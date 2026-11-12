# Storage policy, memory and housekeeping for a small headless box.
#
#   NVMe (root fs, 240 GB): OS, /nix, PostgreSQL, Redis, PHP opcache/tmp, Nextcloud code
#                           and temp dirs, Paperless data dir + scratch, DB dumps.
#   HDD  (config.vps.storage.hdd): bulk files only, mounted noatime (see
#                           hosts/vps/hardware-configuration.nix).
#
# Services that write to the HDD declare RequiresMountsFor, so nothing starts (or writes
# into the empty mount point of the root fs) while the volume is missing.
{ config, lib, ... }:
let
  hdd = config.vps.storage.hdd;
in
{
  # 8 GB RAM: compressed swap absorbs OCR / PHP spikes instead of the OOM killer.
  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  # OCR scratch must not eat RAM: /tmp stays on the NVMe, emptied at boot.
  boot.tmp = {
    useTmpfs = false;
    cleanOnBoot = true;
  };

  services.journald.extraConfig = ''
    SystemMaxUse=500M
    SystemKeepFree=2G
    MaxRetentionSec=1month
  '';

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
    persistent = true;
  };

  # The HDD is a `nofail` mount, which systemd does not order before
  # systemd-tmpfiles-setup. At boot tmpfiles therefore ran against the still-empty mount
  # point (immutable, so it could not write to the NVMe by mistake), and the service
  # directories on the HDD were never created. This unit re-applies the tmpfiles rules for
  # the HDD paths once the volume is really mounted; everything that writes there orders
  # after it.
  systemd.services =
    {
      vps-hdd-dirs = {
        description = "Create service directories on the HDD once it is mounted";
        wantedBy = [ "multi-user.target" ];
        unitConfig.RequiresMountsFor = [ hdd ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${config.systemd.package}/bin/systemd-tmpfiles --create --prefix=${hdd}";
        };
      };
    }
    // lib.genAttrs (
      [
        "nextcloud-setup"
        "phpfpm-nextcloud"
        "nextcloud-cron"
        "nextcloud-update-db"
        "paperless-scheduler"
        "paperless-consumer"
        "paperless-web"
        "paperless-task-queue"
      ]
      ++ lib.optional config.services.paperless.exporter.enable "paperless-exporter"
    ) (_: {
      # Nextcloud has no RequiresMountsFor of its own for a custom datadir.
      unitConfig.RequiresMountsFor = [ hdd ];
      requires = [ "vps-hdd-dirs.service" ];
      after = [ "vps-hdd-dirs.service" ];
    });
}
