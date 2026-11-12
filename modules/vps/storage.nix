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

  # Nextcloud has no RequiresMountsFor of its own for a custom datadir.
  systemd.services = lib.genAttrs [
    "nextcloud-setup"
    "phpfpm-nextcloud"
    "nextcloud-cron"
    "nextcloud-update-db"
  ] (_: { unitConfig.RequiresMountsFor = [ hdd ]; });
}
