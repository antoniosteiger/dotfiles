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

    previewsToNvme.instanceId = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "ocabc123def4";
      description = ''
        Nextcloud's instanceid (`sudo nextcloud-occ config:system:get instanceid`), known
        only after the first install. When set, appdata_<id>/preview (the thumbnail cache:
        thousands of tiny random writes) is bind-mounted from the NVMe instead of living
        on the HDD. It is a cache, regenerated on demand and excluded from backups.
        Worth it if you keep photo libraries; pointless for documents only.
      '';
    };
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
      };
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

    # Optional: thumbnail cache on the NVMe. Mounted over a directory inside the HDD
    # datadir; the HDD mount is its parent, so systemd orders it correctly.
    fileSystems = lib.mkIf (cfg.previewsToNvme.instanceId != null) {
      "${datadir}/data/appdata_${cfg.previewsToNvme.instanceId}/preview" = {
        device = "/var/lib/nextcloud-previews";
        options = [
          "bind"
          "nofail"
        ];
      };
    };
    systemd.tmpfiles.settings."20-nextcloud-previews" = lib.mkIf (cfg.previewsToNvme.instanceId != null) {
      "/var/lib/nextcloud-previews".d = {
        user = "nextcloud";
        group = "nextcloud";
        mode = "0750";
      };
    };
  };
}
