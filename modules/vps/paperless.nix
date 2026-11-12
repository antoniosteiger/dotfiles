# Paperless-ngx: OCR + document archive.
#
#   NVMe  dataDir  /var/lib/paperless   search index, classifier model, thumbnails
#   NVMe  scratch  /var/cache/paperless OCR temp files (many small writes)
#   HDD   media    <hdd>/paperless/media  originals + archived PDFs
#   HDD   consume  <hdd>/paperless/consume incoming scans
#
# 2FA: log in, top-right user menu -> "My Profile" -> "Two-factor authentication" ->
# enable TOTP, scan the QR code, store the recovery codes. Paperless-ngx has no setting
# to force it; make it a habit for every user.
{ config, lib, ... }:
let
  cfg = config.vps.paperless;
  hdd = config.vps.storage.hdd;
  domain = config.vps.domains.paperless;
  ncDatadir = config.services.nextcloud.datadir;
  nc = cfg.consumeFromNextcloud;
  ncScanDir = "${ncDatadir}/data/${nc.user}/files/${nc.folder}";
in
{
  options.vps.paperless = {
    exposure = lib.mkOption {
      type = lib.types.enum [
        "public"
        "tailscale"
      ];
      default = "public";
      description = ''
        "public" is hardened (rate limit on login, fail2ban, security headers, use TOTP);
        "tailscale" removes the public attack surface entirely. One line.
      '';
    };

    consumeFromNextcloud = {
      enable = lib.mkEnableOption ''
        one-way ingest: Paperless consumes (and deletes) files that appear in a folder of
        a Nextcloud user, so "scan to Nextcloud" feeds Paperless. Paperless storage is
        never exposed to Nextcloud. Enable only after that Nextcloud user has logged in
        once and created the folder'';
      user = lib.mkOption {
        type = lib.types.str;
        default = "toni";
        description = "Nextcloud user whose folder is watched.";
      };
      folder = lib.mkOption {
        type = lib.types.str;
        default = "Scans";
        description = "Folder (inside the user's files) that is consumed.";
      };
    };

    exporter.enable = lib.mkEnableOption ''
      monthly `document_exporter` run: a version-independent export (original files plus
      JSON manifest) into <hdd>/paperless/export, which the backups include.
      Paperless is stopped for the duration of the export'';
  };

  config = {
    sops.secrets."paperless/admin_password" = { };
    sops.secrets."paperless/secret_key" = { };
    sops.templates."paperless.env".content = ''
      PAPERLESS_SECRET_KEY=${config.sops.placeholder."paperless/secret_key"}
    '';

    services.paperless = {
      enable = true;
      address = "127.0.0.1";
      dataDir = "/var/lib/paperless";
      mediaDir = "${hdd}/paperless/media";
      consumptionDir = if nc.enable then ncScanDir else "${hdd}/paperless/consume";
      passwordFile = config.sops.secrets."paperless/admin_password".path; # user "admin"
      environmentFile = config.sops.templates."paperless.env".path;
      database.createLocally = true; # unix socket + peer auth

      exporter = lib.mkIf cfg.exporter.enable {
        enable = true;
        directory = "${hdd}/paperless/export";
        onCalendar = "*-*-01 02:30:00";
      };

      settings = {
        PAPERLESS_URL = "https://${domain}";
        PAPERLESS_OCR_LANGUAGE = "deu+eng";
        PAPERLESS_SCRATCH_DIR = "/var/cache/paperless";
        # 8 GB box: one OCR job at a time, two threads each.
        PAPERLESS_TASK_WORKERS = 1;
        PAPERLESS_THREADS_PER_WORKER = 2;
        PAPERLESS_WEBSERVER_WORKERS = 1;
        PAPERLESS_CONSUMER_RECURSIVE = true;
        PAPERLESS_ACCOUNT_ALLOW_SIGNUPS = false;
      };
    };

    # Keep OCR from starving Nextcloud / PostgreSQL.
    systemd.slices.system-paperless.sliceConfig = {
      MemoryHigh = "3G";
      MemoryMax = "4G";
      CPUWeight = 50;
    };

    services.nginx.virtualHosts.${domain} = {
      forceSSL = true;
      enableACME = true;
      acmeRoot = null;
      extraConfig =
        config.vps.nginx.securityHeaders
        + ''
          access_log /var/log/nginx/paperless.access.log combined; # read by fail2ban
          client_max_body_size 200M;
        ''
        + lib.optionalString (cfg.exposure == "tailscale") config.vps.nginx.tailscaleOnly;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString config.services.paperless.port}";
        proxyWebsockets = true;
      };
      # Brute-force limiting on both credential endpoints (web login, API token).
      locations."~ ^/(accounts/login|api/token)/?$" = {
        proxyPass = "http://127.0.0.1:${toString config.services.paperless.port}";
        extraConfig = ''
          limit_req zone=paperless_login burst=5 nodelay;
        '';
      };
    };

    services.fail2ban.jails.paperless = lib.mkIf (cfg.exposure == "public") {
      # A failed web login re-renders the form (200); a successful one redirects (302).
      filter.Definition.failregex = ''^<HOST> .* "POST /(accounts/login|api/token)/? HTTP/[0-9.]+" (200|400|401|403) '';
      settings = {
        logpath = "/var/log/nginx/paperless.access.log";
        backend = "auto";
        maxretry = 5;
        findtime = 600;
        bantime = 3600;
      };
    };

    # --- optional one-way ingest from Nextcloud ---------------------------------------
    # Nextcloud creates group-writable (nextcloud:nextcloud) files; the consumer joins that
    # group so it can read and delete them. tmpfiles must not re-own the folder to paperless.
    systemd.services.paperless-consumer.serviceConfig.SupplementaryGroups = lib.mkIf nc.enable [
      "nextcloud"
    ];
    systemd.tmpfiles.settings."10-paperless".${ncScanDir}.d = lib.mkIf nc.enable (
      lib.mkForce {
        user = "nextcloud";
        group = "nextcloud";
        mode = "0770";
      }
    );
    # Paperless deletes consumed files behind Nextcloud's back; refresh its file cache.
    systemd.services.paperless-nextcloud-rescan = lib.mkIf nc.enable {
      description = "Refresh Nextcloud's file cache for the Paperless ingest folder";
      unitConfig.RequiresMountsFor = [ hdd ];
      serviceConfig = {
        Type = "oneshot";
        User = "nextcloud";
        ExecStart = "${lib.getExe config.services.nextcloud.occ} files:scan --path=${nc.user}/files/${nc.folder}";
      };
      startAt = "*:0/10";
    };
  };
}
