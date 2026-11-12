# Hardware of the HostBRR VPS: virtio-scsi disks, AMD host, BIOS boot.
# Kernel module list comes from `nixos-generate-config --no-filesystems` run in the
# installer; the filesystems are declared here by label.
{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ]; # virtio drivers

  boot.initrd.availableKernelModules = [
    "ata_piix"
    "uhci_hcd"
    "virtio_pci"
    "virtio_scsi"
    "ahci"
    "sd_mod"
    "sr_mod"
  ];
  boot.kernelModules = [ "kvm-amd" ];

  # BIOS boot (no /sys/firmware/efi in the installer): GRUB into the MBR of the root disk.
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  # --- 120 GB root disk (sda): OS, /nix, PostgreSQL, Redis, caches, scratch, app code ----
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
    options = [ "noatime" ];
  };

  # --- 8 TB HDD (sdb; provider-side RAID 6, one virtual disk) ----------------------------
  # Bulk files only. Created once, by hand (NOT with the provider's defaults: 5 % reserved
  # blocks would waste 400 GB):
  #   parted /dev/sdb -- mklabel gpt mkpart primary 0% 100%
  #   mkfs.ext4 -m 0 -i 65536 -L bulk /dev/sdb1
  # The mount point carries `chattr +i`, so nothing can write into it while the disk is missing.
  fileSystems.${config.vps.storage.hdd} = {
    device = "/dev/disk/by-label/bulk";
    fsType = "ext4";
    options = [
      "noatime" # no atime writes on bulk files
      "nofail" # a dead HDD must not stop the boot (and with it SSH/Tailscale)
      "x-systemd.device-timeout=30s"
    ];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  # Swap lives in RAM (zram, see modules/vps/storage.nix); no swap partition.
}
