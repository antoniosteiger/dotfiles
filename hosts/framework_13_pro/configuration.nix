{
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../common/base.nix
    ../common/desktop.nix
    ../common/laptop.nix
  ];

  system.stateVersion = "25.11"; # Never change

  networking.hostName = "tonix-framework";

  # Framework guide, step 5: "select the NOT LTS kernel". Panther Lake (Xe3 GPU,
  # new platform drivers) wants a recent kernel; the nixos-hardware module only
  # forces linuxPackages_latest on kernels older than 6.17.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Panther Lake's Arc B390 (8086:b082) is only driven by xe. nixos-hardware
  # defaults to i915 (which would end up in the initrd and never bind).
  hardware.intelgpu.driver = "xe";
  # Gen12+ only: the media driver (VA-API) + vpl-gpu-rt/compute-runtime that come
  # with it. Skips the legacy intel-vaapi-driver and the unfree intel-ocl.
  hardware.intelgpu.vaapiDriver = "intel-media-driver";
  # nixos-hardware would also install intel-compute-runtime (OpenCL/Level Zero) and
  # its 260 MiB shader compiler. Nothing here uses OpenCL, so keep only video decode.
  # Drop this line if you ever want OpenCL (darktable, local inference, ...).
  hardware.graphics.extraPackages = lib.mkForce (
    with pkgs;
    [
      intel-media-driver
      vpl-gpu-rt
    ]
  );

  # Framework guide, step 8: firmware via fwupdmgr (fwupd itself is enabled in
  # common and by the nixos-hardware module). For Intel models even the stable
  # BIOS releases are still filed under lvfs-testing, so that remote is needed.
  # After flashing the BIOS you can drop this line.
  services.fwupd.extraRemotes = [ "lvfs-testing" ];
  # Guide: "might be necessary once to make the update succeed". Uncomment if
  # `fwupdmgr update` fails to schedule the capsule.
  # services.fwupd.uefiCapsuleSettings.DisableCapsuleUpdateOnDisk = true;
}
