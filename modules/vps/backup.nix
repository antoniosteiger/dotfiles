# Backups. Sync is not backup; RAID is not backup.
#
#   Primary    restic -> restic REST server on Arcticbox (append-only, Tailscale only).
#              Hourly timers, skipped quietly while Arcticbox is off. Pruning/`restic check`
#              run on Arcticbox (modules/restic-server.nix), the VPS cannot delete history.
#   Secondary  restic -> Cloudflare R2: DB dumps, Vaultwarden, config, Paperless media.
#              Daily. No Nextcloud files (too big), see docs/vps.md for the gap this leaves.
#
# Consistency without snapshots (the HDD is a provider-side virtual disk, plain ext4):
# the databases are dumped FIRST (vps-db-dump, pg_dump + sqlite3 .backup), the files are
# read AFTER. The only possible skew is "file newer than the DB dump", which
# `occ files:scan --all` repairs on restore. Putting Nextcloud in maintenance mode hourly
# (or for the days the first 8 TB run takes) is not an option.
{ config, lib, pkgs, ... }:
let
  cfg = config.vps.backup;
  hdd = config.vps.storage.hdd;
  ncDatadir = config.services.nextcloud.datadir;
  pl = config.services.paperless;
  push = lib.getExe config.vps.monitoring.pushBin;
  restic = lib.getExe pkgs.restic;

  dumpDir = "/var/backup/db";
  dbDump = pkgs.writeShellScript "vps-db-dump" ''
    set -euo pipefail
    umask 077
    for db in nextcloud paperless; do
      # Plain SQL, uncompressed on purpose: restic dedups and compresses it itself.
      pg_dump --clean --if-exists "$db" > "${dumpDir}/$db.sql.tmp"
      mv "${dumpDir}/$db.sql.tmp" "${dumpDir}/$db.sql"
    done
  '';

  # Small, fast-changing state: dumps, Vaultwarden backup copy, Nextcloud config.php,
  # Paperless media (<20 GB) and the optional document_exporter output.
  statePaths = [
    "/var/backup"
    "${ncDatadir}/config"
  ]
  ++ lib.optional (cfg.paperlessMedia) pl.mediaDir
  ++ lib.optional (pl.exporter.enable) pl.exporter.directory;

  reachable = pkgs.writeShellScript "arcticbox-reachable" ''
    # Any HTTP answer (even 401) proves the REST server is up; 000 means no connection.
    code=$(${lib.getExe pkgs.curl} -s -o /dev/null -w '%{http_code}' --max-time 10 \
      "http://${cfg.arcticbox.host}:${toString cfg.arcticbox.port}/" || true)
    if [ -z "$code" ] || [ "$code" = 000 ]; then
      echo "Arcticbox (${cfg.arcticbox.host}) not reachable, skipping this run"
      exit 1 # ExecCondition: 1-254 = skip quietly, not a failure
    fi
  '';

  arcticboxRepo = "rest:http://${cfg.arcticbox.host}:${toString cfg.arcticbox.port}/${cfg.arcticbox.user}/";

  # Shared systemd tuning for every restic job.
  jobUnit = endpoint: extra: lib.recursiveUpdate {
    requires = [ "vps-db-dump.service" ];
    after = [ "vps-db-dump.service" ];
    unitConfig = {
      OnFailure = [ "gatus-push-failure@${endpoint}.service" ];
      RequiresMountsFor = [ hdd ];
    };
    serviceConfig = {
      # Interrupted (reboot, Arcticbox going to sleep, SIGTERM) -> the next timer tick
      # simply runs again; restic's dedup means finished packs are not uploaded twice.
      # No Restart=: it would also hide failures from OnFailure.
      TimeoutStartSec = "infinity";
      TimeoutStopSec = "5min"; # let restic finish the current pack and release its lock
      Nice = 15;
      IOSchedulingClass = "idle";
      ExecStartPost = "-${push} ${endpoint} success";
      PrivateTmp = true;
      ProtectHome = true;
      NoNewPrivileges = true;
    };
  } extra;

  # `unlock` removes only stale locks (dead process / >30 min old), the single thing an
  # interrupted run leaves behind. Allowed on an append-only server.
  unlockOnStart = "${restic} unlock || true";
in
{
  options.vps.backup = {
    arcticbox = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "tonix-desktop"; # MagicDNS name of Arcticbox on the tailnet
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 8000;
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = "vps";
        description = "REST server user; with --private-repos it is also the repository path.";
      };
      dataSchedule = lib.mkOption {
        type = lib.types.str;
        default = "*:35";
        description = "OnCalendar of the Nextcloud datadir job (hourly by default).";
      };
      stateSchedule = lib.mkOption {
        type = lib.types.str;
        default = "*:05";
        description = "OnCalendar of the dumps/config/Paperless job (hourly by default).";
      };
    };

    paperlessMedia = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Include Paperless media in the state job and in R2 (expected < 20 GB).";
    };

    r2 = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      accountId = lib.mkOption {
        type = lib.types.str;
        default = "0123456789abcdef0123456789abcdef"; # TODO Cloudflare account id
      };
      bucket = lib.mkOption {
        type = lib.types.str;
        default = "vps-backup"; # TODO
      };
      schedule = lib.mkOption {
        type = lib.types.str;
        default = "*-*-* 03:30:00";
      };
      retention = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "--keep-daily 7"
          "--keep-weekly 4"
          "--keep-monthly 3"
        ];
        description = "Small on purpose. Pruned by the VPS itself (it holds R2 credentials).";
      };
    };
  };

  config = lib.mkMerge [
    {
      sops.secrets."restic/arcticbox_password" = { };
      sops.secrets."restic/arcticbox_rest_password" = { };
      sops.templates."restic-arcticbox.env".content = ''
        RESTIC_REST_USERNAME=${cfg.arcticbox.user}
        RESTIC_REST_PASSWORD=${config.sops.placeholder."restic/arcticbox_rest_password"}
      '';

      systemd.tmpfiles.rules = [
        "d /var/backup 0755 root root - -"
        "d ${dumpDir} 0700 postgres postgres - -"
      ];

      # Dump order matters (see header): this always completes before any file is read.
      systemd.services.vps-db-dump = {
        description = "Dump PostgreSQL databases; refresh the Vaultwarden SQLite backup";
        requires = [
          "postgresql.target"
          "backup-vaultwarden.service"
        ];
        after = [
          "postgresql.target"
          "backup-vaultwarden.service"
        ];
        path = [ config.services.postgresql.package ];
        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          ExecStart = dbDump;
          ReadWritePaths = [ dumpDir ];
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
        };
      };

      services.restic.backups = {
        arcticbox-state = {
          repository = arcticboxRepo;
          passwordFile = config.sops.secrets."restic/arcticbox_password".path;
          environmentFile = config.sops.templates."restic-arcticbox.env".path;
          initialize = true;
          paths = statePaths;
          extraBackupArgs = [
            "--tag=state"
            "--retry-lock=30m"
          ];
          backupPrepareCommand = unlockOnStart;
          timerConfig = {
            OnCalendar = cfg.arcticbox.stateSchedule;
            Persistent = true;
            RandomizedDelaySec = "3min";
          };
        };

        arcticbox-data = {
          repository = arcticboxRepo;
          passwordFile = config.sops.secrets."restic/arcticbox_password".path;
          environmentFile = config.sops.templates."restic-arcticbox.env".path;
          initialize = true;
          paths = [ "${ncDatadir}/data" ];
          # The thumbnail cache is regenerated on demand; backing it up is pure churn.
          exclude = [ "${ncDatadir}/data/appdata_*/preview" ];
          extraBackupArgs = [
            "--tag=nextcloud-data"
            "--retry-lock=30m"
            "--one-file-system"
          ];
          backupPrepareCommand = unlockOnStart;
          timerConfig = {
            OnCalendar = cfg.arcticbox.dataSchedule;
            Persistent = true;
            RandomizedDelaySec = "3min";
          };
        };
      };

      systemd.services.restic-backups-arcticbox-state = jobUnit "restic-arcticbox-state" {
        serviceConfig.ExecCondition = reachable;
      };
      systemd.services.restic-backups-arcticbox-data = jobUnit "restic-arcticbox-data" {
        # Never both at once on first start (both would `restic init`).
        after = [
          "vps-db-dump.service"
          "restic-backups-arcticbox-state.service"
        ];
        serviceConfig.ExecCondition = reachable;
      };
    }

    (lib.mkIf cfg.r2.enable {
      sops.secrets."restic/r2_password" = { };
      sops.secrets."r2/access_key_id" = { };
      sops.secrets."r2/secret_access_key" = { };
      sops.templates."restic-r2.env".content = ''
        AWS_ACCESS_KEY_ID=${config.sops.placeholder."r2/access_key_id"}
        AWS_SECRET_ACCESS_KEY=${config.sops.placeholder."r2/secret_access_key"}
        AWS_DEFAULT_REGION=auto
      '';

      services.restic.backups.r2 = {
        repository = "s3:https://${cfg.r2.accountId}.r2.cloudflarestorage.com/${cfg.r2.bucket}";
        passwordFile = config.sops.secrets."restic/r2_password".path;
        environmentFile = config.sops.templates."restic-r2.env".path;
        initialize = true;
        paths = statePaths;
        extraBackupArgs = [
          "--tag=state"
          "--retry-lock=30m"
        ];
        backupPrepareCommand = unlockOnStart;
        pruneOpts = cfg.r2.retention;
        checkOpts = [ "--read-data-subset=2%" ];
        timerConfig = {
          OnCalendar = cfg.r2.schedule;
          Persistent = true;
          RandomizedDelaySec = "30min";
        };
      };
      systemd.services.restic-backups-r2 = jobUnit "restic-r2" { };
    })
  ];
}
