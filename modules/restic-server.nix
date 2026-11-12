# Append-only restic REST server (the primary backup target) + the maintenance the
# append-only mode forces onto this side: retention (`forget --prune`) and `restic check`.
#
# Machines that are not always on are fine: clients skip quietly while this one is off,
# and the prune timer is Persistent (runs after the next boot if it was missed).
#
# Safety: storage may not be bought/mounted yet. Server, socket and prune jobs only start
# when dataDir is a real MOUNT POINT (ConditionPathIsMountPoint), so enabling this can
# neither fail a rebuild nor fill the root disk by accident.
{ config, lib, pkgs, ... }:
let
  cfg = config.services.resticBackupServer;
  inherit (lib) mkOption types;
  mount = {
    RequiresMountsFor = [ cfg.dataDir ];
    ConditionPathIsMountPoint = cfg.dataDir;
  };
in
{
  options.services.resticBackupServer = {
    enable = lib.mkEnableOption "the append-only restic REST server (Tailscale only) and its prune/check timer";

    dataDir = mkOption {
      type = types.str;
      default = "/srv/restic";
      description = "Repository storage. Must be its own mount (see header).";
    };

    port = mkOption {
      type = types.port;
      default = 8000;
    };

    htpasswdFile = mkOption {
      type = types.str;
      description = "htpasswd file (bcrypt) with one user per client; with --private-repos user X owns <dataDir>/X.";
    };

    repos = mkOption {
      type = types.attrsOf (
        types.submodule {
          options.passwordFile = mkOption {
            type = types.str;
            description = "restic repository password (needed for forget/prune/check).";
          };
        }
      );
      default = { };
      description = "Repositories (= REST users) to maintain, keyed by repo directory name.";
    };

    retention = {
      daily = mkOption { type = types.ints.unsigned; default = 7; };
      weekly = mkOption { type = types.ints.unsigned; default = 4; };
      monthly = mkOption { type = types.ints.unsigned; default = 12; };
    };

    schedule = mkOption {
      type = types.str;
      default = "Sun 03:00";
      description = "OnCalendar of forget/prune + check.";
    };

    checkReadDataSubset = mkOption {
      type = types.str;
      default = "5%";
      description = "Share of pack data re-read and verified per run (bit-rot detection; the HDD has no checksums).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.restic.server = {
      enable = true;
      appendOnly = true;
      privateRepos = true;
      dataDir = cfg.dataDir;
      listenAddress = toString cfg.port;
      htpasswd-file = cfg.htpasswdFile;
    };

    # Reachable over the tailnet only: no other interface opens the port.
    services.tailscale.enable = lib.mkDefault true;
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ cfg.port ];

    systemd.sockets.restic-rest-server.unitConfig = mount;
    systemd.services = {
      restic-rest-server.unitConfig = mount;
    }
    // lib.mapAttrs' (
      name: repo:
      lib.nameValuePair "restic-prune-${name}" {
        description = "restic retention + integrity check for repository ${name}";
        unitConfig = mount;
        path = [ pkgs.restic ];
        environment = {
          RESTIC_REPOSITORY = "${cfg.dataDir}/${name}";
          RESTIC_PASSWORD_FILE = repo.passwordFile;
          RESTIC_CACHE_DIR = "/var/cache/restic-prune-${name}";
        };
        serviceConfig = {
          Type = "oneshot";
          User = "restic";
          Group = "restic";
          CacheDirectory = "restic-prune-${name}";
          ReadWritePaths = [ cfg.dataDir ];
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
          Nice = 15;
          IOSchedulingClass = "idle";
        };
        script = ''
          [ -f "$RESTIC_REPOSITORY/config" ] || { echo "repository not initialised yet"; exit 0; }
          restic unlock # only removes stale locks
          restic forget --prune \
            --keep-daily ${toString cfg.retention.daily} \
            --keep-weekly ${toString cfg.retention.weekly} \
            --keep-monthly ${toString cfg.retention.monthly}
          restic check --read-data-subset=${cfg.checkReadDataSubset}
        '';
      }
    ) cfg.repos;

    systemd.timers = lib.mapAttrs' (
      name: _:
      lib.nameValuePair "restic-prune-${name}" {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.schedule;
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
      }
    ) cfg.repos;
  };
}
