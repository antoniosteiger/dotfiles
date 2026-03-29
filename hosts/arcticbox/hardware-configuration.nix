{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  # NOTE: These values are placeholders and will need to be updated after installation
  # Run `nixos-generate-config` on the arcticbox to get the correct values
  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ "amdgpu" ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # IMPORTANT: Update these filesystem paths after running nixos-generate-config on arcticbox
  # These are placeholder values - replace with actual UUIDs from your system
  fileSystems."/" =
    { device = "/dev/disk/by-uuid/REPLACE-WITH-ROOT-UUID";
      fsType = "ext4";
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/REPLACE-WITH-BOOT-UUID";
      fsType = "vfat";
      options = [ "fmask=0077" "dmask=0077" ];
    };

  swapDevices =
    [ { device = "/dev/disk/by-uuid/REPLACE-WITH-SWAP-UUID"; }
    ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Desktop-specific: Enable AMD GPU support
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  # Desktop-specific: AMD GPU drivers
  services.xserver.videoDrivers = [ "amdgpu" ];

  # Desktop-specific: Bluetooth (optional for desktop)
  hardware.bluetooth.enable = true;
}
