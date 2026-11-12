# Gatus status page (Tailscale-only), declaratively configured.
#
#  * HTTP checks (status + response time + certificate expiry) for the three apps.
#  * "External endpoints": things that cannot be polled push their own result with
#    `gatus-push <endpoint> success|failure [message]`. Gatus marks an endpoint failed
#    when no push arrives within its heartbeat interval. Used by the backups, autoUpgrade
#    and the 5-minute vps-health check (disk, HDD mount, PostgreSQL, Redis).
#  * Alerting is OFF. vps.monitoring.email.enable turns on email via an SMTP relay.
{ config, lib, pkgs, ... }:
let
  cfg = config.vps.monitoring;
  d = config.vps.domains;
  hdd = config.vps.storage.hdd;
  port = 8080;

  # name -> { group, token (secret name), interval (heartbeat) }
  push = {
    restic-arcticbox-data = {
      group = "backups";
      token = "restic_arcticbox_data";
      interval = cfg.heartbeat.backup;
    };
    restic-arcticbox-state = {
      group = "backups";
      token = "restic_arcticbox_state";
      interval = cfg.heartbeat.backup;
    };
    restic-r2 = {
      group = "backups";
      token = "restic_r2";
      interval = cfg.heartbeat.r2;
    };
    nixos-autoupgrade = {
      group = "system";
      token = "autoupgrade";
      interval = cfg.heartbeat.autoUpgrade;
    };
  }
  // lib.genAttrs [ "disk-nvme" "disk-hdd" "hdd-mount" "postgresql" "redis" ] (_: {
    group = "health";
    token = "health";
    interval = cfg.heartbeat.health;
  });

  tokenNames = lib.unique (lib.mapAttrsToList (_: e: e.token) push);
  envVar = t: "GATUS_TOKEN_${lib.toUpper t}";
  secret = t: "gatus/token_${t}";

  alerts = lib.optional cfg.email.enable {
    type = "email";
    failure-threshold = 3;
    success-threshold = 2;
    send-on-resolved = true;
  };

  http =
    {
      name,
      url,
      time,
    }:
    {
      inherit name url alerts;
      group = "services";
      interval = "2m";
      # Hide what is being probed and how (harmless, but no reason to publish it).
      ui = {
        hide-url = true;
        hide-hostname = true;
        hide-conditions = true;
      };
      conditions = [
        "[STATUS] == 200"
        "[RESPONSE_TIME] < ${toString time}"
        "[CERTIFICATE_EXPIRATION] > 336h" # alarm 14 days before expiry
      ];
    };

  pushBin = pkgs.writeShellApplication {
    name = "gatus-push";
    runtimeInputs = [
      pkgs.curl
      pkgs.coreutils
    ];
    text = ''
      endpoint="$1"; status="$2"; msg="''${3:-}"
      case "$endpoint" in
      ${lib.concatStrings (
        lib.mapAttrsToList (n: e: ''
          ${n}) group=${e.group}; tokenfile=${config.sops.secrets.${secret e.token}.path} ;;
        '') push
      )}
        *) echo "gatus-push: unknown endpoint '$endpoint'" >&2; exit 2 ;;
      esac
      case "$status" in success) ok=true ;; failure) ok=false ;; *) exit 2 ;; esac
      curl -fsS --max-time 15 -X POST -G \
        -H "Authorization: Bearer $(cat "$tokenfile")" \
        --data-urlencode "success=$ok" --data-urlencode "error=$msg" \
        "http://127.0.0.1:${toString port}/api/v1/endpoints/''${group}_$endpoint/external"
    '';
  };

  healthBin = pkgs.writeShellApplication {
    name = "vps-health";
    runtimeInputs = [
      pushBin
      pkgs.coreutils
      pkgs.util-linux
      pkgs.gnugrep
      config.services.postgresql.package
      config.services.redis.package
    ];
    text = ''
      report() { # endpoint ok(0|1) message
        if [ "$2" = 1 ]; then gatus-push "$1" success || true
        else gatus-push "$1" failure "$3" || true; fi
      }
      used() { df --output="$2" "$1" | tail -1 | tr -dc 0-9; } # path pcent|ipcent

      limit=${toString cfg.diskUsageLimitPercent}

      u=$(used / pcent); i=$(used / ipcent)
      if [ "$u" -lt "$limit" ] && [ "$i" -lt 90 ]; then report disk-nvme 1
      else report disk-nvme 0 "NVMe: $u% space, $i% inodes used"; fi

      if mountpoint -q ${hdd} && findmnt -no OPTIONS ${hdd} | grep -qw rw \
         && touch ${hdd}/.vps-health && rm -f ${hdd}/.vps-health; then
        report hdd-mount 1
        u=$(used ${hdd} pcent); i=$(used ${hdd} ipcent)
        if [ "$u" -lt "$limit" ] && [ "$i" -lt 90 ]; then report disk-hdd 1
        else report disk-hdd 0 "HDD: $u% space, $i% inodes used"; fi
      else
        report hdd-mount 0 "${hdd} not mounted, read-only or not writable"
        report disk-hdd 0 "${hdd} unavailable"
      fi

      if pg_isready -q -h /run/postgresql; then report postgresql 1
      else report postgresql 0 "pg_isready failed"; fi

      if [ "$(redis-cli -s ${config.services.redis.servers.nextcloud.unixSocket} ping 2>/dev/null)" = PONG ]
      then report redis 1; else report redis 0 "redis ping failed"; fi
    '';
  };
in
{
  options.vps.monitoring = {
    pushBin = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = pushBin;
      description = "gatus-push, for other modules to report their result.";
    };

    heartbeat = lib.mkOption {
      type = lib.types.submodule {
        options = lib.genAttrs [ "backup" "r2" "autoUpgrade" "health" ] (_: lib.mkOption { type = lib.types.str; });
      };
      default = {
        backup = "36h"; # Arcticbox is not always on: hourly runs, but only one success per 36 h is required
        r2 = "36h";
        autoUpgrade = "36h";
        health = "30m";
      };
      description = "Gatus durations: an external endpoint is failed if nothing was pushed within this time.";
    };

    exposure = lib.mkOption {
      type = lib.types.enum [
        "public"
        "tailscale"
      ];
      default = "public";
      description = ''
        "public": anyone can read the status page (read-only; Gatus has no login, and the
        push API is blocked at nginx). It then shows service names, uptime, response
        times, disk state and backup freshness; endpoint URLs are hidden. "tailscale":
        only from the tailnet; point the DNS record at the Tailscale IP.
      '';
    };

    diskUsageLimitPercent = lib.mkOption {
      type = lib.types.ints.between 1 99;
      default = 85;
    };

    email = {
      enable = lib.mkEnableOption "email alerts via an SMTP relay (off: status page only)";
      host = lib.mkOption {
        type = lib.types.str;
        default = "smtp.example.com"; # TODO provider
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 587;
      };
      username = lib.mkOption {
        type = lib.types.str;
        default = "smtp-user"; # TODO
      };
      from = lib.mkOption {
        type = lib.types.str;
        default = "status@example.com"; # TODO
      };
      to = lib.mkOption {
        type = lib.types.str;
        default = "you@example.com"; # TODO
      };
    };
  };

  config = {
    sops.secrets =
      lib.genAttrs (map secret tokenNames) (_: { })
      // lib.optionalAttrs cfg.email.enable { "smtp/password" = { }; };

    sops.templates."gatus.env".content =
      lib.concatMapStrings (t: "${envVar t}=${config.sops.placeholder.${secret t}}\n") tokenNames
      + lib.optionalString cfg.email.enable "GATUS_SMTP_PASSWORD=${config.sops.placeholder."smtp/password"}\n";

    services.gatus = {
      enable = true;
      environmentFile = config.sops.templates."gatus.env".path;
      settings = {
        web = {
          address = "127.0.0.1"; # reached through nginx (see vps.monitoring.exposure)
          inherit port;
        };
        ui.title = "vps status";
        storage = {
          type = "sqlite";
          path = "/var/lib/gatus/data.db";
        };

        endpoints = [
          (http { name = "nextcloud"; url = "https://${d.nextcloud}/status.php"; time = 3000; })
          (http { name = "vaultwarden"; url = "https://${d.vaultwarden}/alive"; time = 2000; })
          (http { name = "paperless"; url = "https://${d.paperless}/accounts/login/"; time = 3000; })
        ];

        external-endpoints = lib.mapAttrsToList (name: e: {
          inherit name alerts;
          inherit (e) group;
          token = "\${${envVar e.token}}";
          heartbeat.interval = e.interval;
        }) push;
      }
      // lib.optionalAttrs cfg.email.enable {
        alerting.email = {
          inherit (cfg.email) host port from username;
          to = cfg.email.to;
          password = "\${GATUS_SMTP_PASSWORD}";
        };
      };
    };

    systemd.services.gatus.serviceConfig = {
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictNamespaces = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
    };

    services.nginx.virtualHosts.${d.status} = {
      forceSSL = true;
      enableACME = true;
      acmeRoot = null;
      extraConfig =
        config.vps.nginx.securityHeaders
        + lib.optionalString (cfg.exposure == "tailscale") config.vps.nginx.tailscaleOnly;
      locations."/".proxyPass = "http://127.0.0.1:${toString port}";
      # The push API (backups, autoUpgrade, health) is never reachable through nginx, in
      # either mode: the pushers talk to 127.0.0.1:${toString port} directly. Tokens would
      # protect it anyway; this removes it from the public surface altogether.
      locations."~ ^/api/v1/endpoints/[^/]+/external$".return = "403";
    };

    # Failure side of the push: units point OnFailure= here (restic jobs, autoUpgrade).
    systemd.services."gatus-push-failure@" = {
      description = "Report failure of %i to Gatus";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "-${lib.getExe pushBin} %i failure \"job failed, see journalctl\"";
      };
    };

    systemd.services.vps-health = {
      description = "Disk / HDD / PostgreSQL / Redis health, pushed to Gatus";
      after = [ "gatus.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = lib.getExe healthBin;
        PrivateTmp = true;
        ProtectHome = true;
        NoNewPrivileges = true;
      };
      startAt = "*:0/5";
    };
  };
}
