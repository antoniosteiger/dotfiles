# TODO: replace with the real `nixos-generate-config` output (or `--no-filesystems` if
# you partition with disko / by hand) after booting the installer on the VPS. The values
# below are placeholders so the configuration evaluates and builds.
{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ]; # virtio drivers

  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "sd_mod"
    "nvme"
  ];

  # TODO: BIOS (most VPS) vs UEFI. BIOS/GRUB shown; for UEFI use
  #   boot.loader.systemd-boot.enable = true; boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub = {
    enable = true;
    device = "/dev/vda"; # TODO: the NVMe/root disk as the provider presents it
  };

  # --- 240 GB NVMe: root (OS, /nix, PostgreSQL, Redis, caches, scratch, app code) -------
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos"; # TODO: `mkfs.ext4 -L nixos /dev/vdaN` or uuid
    fsType = "ext4";
    options = [ "noatime" ];
  };

  # --- 8 TB HDD (provider-side RAID 6, shows up as one virtio disk, e.g. /dev/vdb) ------
  # Bulk files only. Format once, by hand, NOT with the provider's defaults (5 % reserved
  # blocks would waste 400 GB; the default inode ratio is wasteful for big files):
  #   parted /dev/vdb -- mklabel gpt mkpart primary 0% 100%
  #   mkfs.ext4 -m 0 -i 65536 -L bulk /dev/vdb1
  # and protect the mount point from writes while the disk is missing:
  #   mkdir -p ${config.vps.storage.hdd} && chattr +i ${config.vps.storage.hdd}
  fileSystems.${config.vps.storage.hdd} = {
    device = "/dev/disk/by-label/bulk"; # TODO: or by-uuid
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
