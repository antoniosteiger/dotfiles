# Nextcloud on nginx + PHP-FPM + PostgreSQL + Redis.
#
# Layout:
#   NVMe  services.nextcloud.home      = /var/lib/nextcloud   code, apps, store-apps, tmp/
#   HDD   services.nextcloud.datadir   = <hdd>/nextcloud      config/config.php + data/
#
# The module ties config/ to datadir, so config.php is on the HDD too; it is a few KB read
# once per PHP worker start (opcache), not a real IO load.
{ config, lib, pkgs, ... }:
let
  cfg = config.vps.nextcloud;
  mail = config.vps.monitoring.email;
  hdd = config.vps.storage.hdd;
  domain = config.vps.domains.nextcloud;
  datadir = "${hdd}/nextcloud";
  home = "/var/lib/nextcloud";
  tmp = "${home}/tmp";
in
{
  options.vps.nextcloud = {
    exposure = lib.mkOption {
      type = lib.types.enum [
        "public"
        "tailscale"
      ];
      default = "public";
      description = ''
        "public": reachable from the internet (needed for public share links, mobile
        clients away from the tailnet). "tailscale": only from the tailnet; point the DNS
        record at the VPS's Tailscale IP. Switching is this one line.
      '';
    };

    maxUploadSize = lib.mkOption {
      type = lib.types.str;
      default = "16G";
    };

    previewsToNvme.enable = lib.mkEnableOption ''
      thumbnail cache on the NVMe: appdata_<instanceid>/preview (thousands of tiny random
      writes) is bind-mounted from /var/lib/nextcloud-previews instead of living on the
      HDD. The instance id is only known after the first install, so a small service reads
      it at boot (after nextcloud-setup) and mounts. It is a cache, regenerated on demand
      and excluded from backups. Worth it if you keep photo libraries'';
  };

  config = {
    sops.secrets."nextcloud/admin_password" = { };

    services.nextcloud = {
      enable = true;

      # Pinned explicitly (not the module default) so a nixpkgs update can never pick
      # the major for us. Nextcloud only upgrades ONE major at a time: bump 34 -> 35,
      # let nextcloud-setup finish (check `journalctl -u nextcloud-setup`), only then
      # go 35 -> 36. Never skip a major. nixpkgs 26.05 offers 32 (EOL), 33, 34, 35.
      package = pkgs.nextcloud34;

      hostName = domain;
      https = true;
      inherit home datadir;
      maxUploadSize = cfg.maxUploadSize;

      config = {
        dbtype = "pgsql";
        adminuser = "admin";
        adminpassFile = config.sops.secrets."nextcloud/admin_password".path;
      };
      database.createLocally = true; # unix socket + peer auth, no DB password
      configureRedis = true; # unix socket

      # Apps are declarative; app-store installs/updates are off while extraApps is set.
      extraApps = {
        inherit (config.services.nextcloud.package.packages.apps)
          calendar
          contacts
          memories
          notes
          tasks
          ;
      };
      extraAppsEnable = true;
      autoUpdateApps.enable = false;

      # Sized for 8 GB shared with PostgreSQL, Redis and Paperless OCR.
      poolSettings = {
        "pm" = "dynamic";
        "pm.max_children" = "12";
        "pm.start_servers" = "3";
        "pm.min_spare_servers" = "2";
        "pm.max_spare_servers" = "5";
        "pm.max_requests" = "500";
        "pm.status_path" = "/status";
      };
      phpOptions = {
        "opcache.interned_strings_buffer" = "16";
        "opcache.memory_consumption" = "128";
        # PHP's own upload/temp files stay on the NVMe.
        upload_tmp_dir = tmp;
        sys_temp_dir = tmp;
      };

      settings = {
        default_phone_region = "DE";
        maintenance_window_start = 1; # UTC hour; heavy background jobs run here
        tempdirectory = tmp; # NVMe: assembled uploads, zip downloads
        log_type = "systemd"; # not nextcloud.log in the datadir on the HDD
        loglevel = 2;
        serverid = 1; # single PHP server; silences the admin-page hint

        # Memories: the app's bundled exiftool / go-vod binaries are prebuilt for FHS
        # distros and do not run on NixOS, so use the Nix one and skip video transcoding
        # (originals stream directly). Places/map view needs a separate planet database: off.
        "memories.exiftool" = lib.getExe pkgs.exiftool;
        "memories.exiftool_no_local" = true;
        "memories.vod.disable" = true;
      }
      # Outgoing mail (password resets, share notifications) through the same SMTP account
      # as the Gatus alerts. STARTTLS is negotiated automatically on port 587.
      // lib.optionalAttrs mail.enable {
        mail_smtpmode = "smtp";
        mail_smtphost = mail.host;
        mail_smtpport = mail.port;
        mail_smtpauth = true;
        mail_smtpname = mail.username;
        mail_from_address = lib.head (lib.splitString "@" mail.from);
        mail_domain = lib.last (lib.splitString "@" mail.from);
      };
      # Only the SMTP password; merged into config.php at runtime, never in the store.
      secretFile = lib.mkIf mail.enable config.sops.templates."nextcloud-secrets.json".path;
    };

    sops.secrets."smtp/password" = lib.mkIf mail.enable { };
    sops.templates."nextcloud-secrets.json" = lib.mkIf mail.enable {
      owner = "nextcloud";
      content = builtins.toJSON { mail_smtppassword = config.sops.placeholder."smtp/password"; };
    };

    # nextcloud-cron.timer (every 5 min, systemd) is created by the module: background
    # jobs run via cron.php, not on page loads / AJAX.

    systemd.tmpfiles.rules = [ "d ${tmp} 0750 nextcloud nextcloud - -" ];

    services.nginx.virtualHosts.${domain} = {
      forceSSL = true;
      enableACME = true;
      acmeRoot = null; # DNS-01, see nginx.nix
      extraConfig = lib.optionalString (cfg.exposure == "tailscale") config.vps.nginx.tailscaleOnly;
    };

    # Optional: thumbnail cache on the NVMe, bind-mounted over a directory inside the HDD
    # datadir. Done by a service (not fileSystems) because the path contains the instance
    # id, which Nextcloud generates at install. Wants (not Requires) nextcloud-setup so a
    # setup restart during a switch does not bounce the mount. Existing previews on the
    # HDD are hidden by the mount and regenerate on the NVMe.
    systemd.services.nextcloud-previews-nvme = lib.mkIf cfg.previewsToNvme.enable {
      description = "Bind-mount Nextcloud's preview cache from the NVMe";
      wantedBy = [ "multi-user.target" ];
      wants = [ "nextcloud-setup.service" ];
      after = [ "nextcloud-setup.service" ];
      before = [
        "phpfpm-nextcloud.service"
        "nextcloud-cron.service"
      ];
      unitConfig.RequiresMountsFor = [ hdd ];
      path = [
        pkgs.coreutils
        pkgs.util-linux
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        id=$(${lib.getExe config.services.nextcloud.occ} config:system:get instanceid)
        [ -n "$id" ] || { echo "no instanceid yet" >&2; exit 1; }
        app=${datadir}/data/appdata_$id
        install -d -o nextcloud -g nextcloud -m 0750 /var/lib/nextcloud-previews "$app" "$app/preview"
        mountpoint -q "$app/preview" || mount --bind /var/lib/nextcloud-previews "$app/preview"
      '';
    };
  };
}
