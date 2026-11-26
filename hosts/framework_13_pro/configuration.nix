{
  lib,
  pkgs,
  ...
}:

let
  # The Level Zero driver (libze_intel_gpu) with the Intel graphics compiler in its RPATH.
  # The compute runtime loads libigc / libigdfcl by name at run time. nixpkgs' postFixup only
  # gives the OpenCL library (libigdrcl.so) a path to intel-graphics-compiler, so a Level Zero
  # program cannot load it. Without the compiler the runtime keeps one-page placeholders for its
  # mid-thread preemption buffers, and the GPU hangs under load ("Fault response: Unsuccessful
  # -EINVAL", "Engine memory CAT error", engine reset). This copy only adds the RPATH; nothing
  # is recompiled.
  levelZeroDriver =
    pkgs.runCommand "intel-compute-runtime-drivers-with-compiler" { nativeBuildInputs = [ pkgs.patchelf ]; }
      ''
        cp -r ${pkgs.intel-compute-runtime.drivers} $out
        chmod -R u+w $out
        for f in $(find $out/lib -type f -name 'libze_intel_gpu.so.*'); do
          patchelf --add-rpath ${pkgs.intel-graphics-compiler}/lib "$f"
        done
      '';
in
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

  # Swap: a file on the LUKS-encrypted ext4 root (no repartitioning needed, and
  # it is encrypted for free). NixOS creates it on activation. Size is in MiB.
  swapDevices = [{ device = "/var/lib/swapfile"; size = 36 * 1024; }]; # >= RAM (32G) so hibernate always fits
  # Hibernate: resume from the swapfile. resume_offset is the file's first
  # physical extent (`filefrag -v /var/lib/swapfile`); it changes if the file is
  # ever recreated, so update it then.
  boot.resumeDevice = "/dev/disk/by-uuid/005c0989-6dd9-4cb9-8685-475043aafe71";
  boot.kernelParams = [ "resume_offset=247083008" ];
  # Lid close: suspend, then hibernate after 1h so the battery doesn't drain.
  services.logind.settings.Login.HandleLidSwitch = "suspend-then-hibernate";
  systemd.sleep.settings.Sleep.HibernateDelaySec = "1h";

  # Compressed RAM swap in front of it; the disk swap only gets the overflow.
  zramSwap.enable = true;

  # Panther Lake's Arc B390 (8086:b082) is only driven by xe. nixos-hardware
  # defaults to i915 (which would end up in the initrd and never bind).
  hardware.intelgpu.driver = "xe";
  # Gen12+ only: the media driver (VA-API) + vpl-gpu-rt/compute-runtime that come
  # with it. Skips the legacy intel-vaapi-driver and the unfree intel-ocl.
  hardware.intelgpu.vaapiDriver = "intel-media-driver";
  # Video decode (media driver, vpl-gpu-rt) plus the compute stack (OpenCL and Level Zero),
  # which costs ~260 MiB for the graphics compiler and is what local inference needs.
  # intel-compute-runtime provides OpenCL (its libigdrcl already finds the compiler);
  # levelZeroDriver is the Level Zero driver with the same fix (see the let block above).
  hardware.graphics.extraPackages = lib.mkForce (
    with pkgs;
    [
      intel-media-driver
      vpl-gpu-rt
      intel-compute-runtime
      levelZeroDriver
      level-zero
    ]
  );

  # Newest Intel GPU firmware. nixpkgs' linux-firmware (20261019) carries GuC 70.72.1
  # for Panther Lake; upstream has had GuC 70.83.0 since 2026-11-14 (linux-firmware
  # commit f51d6d83). This pins the whole linux-firmware tree to upstream main as of
  # 2026-11-17, which contains it. Remove the block once nixpkgs ships a linux-firmware
  # newer than 20261019; check with `journalctl -k -b | grep "GuC firmware"` (>= 70.83.0).
  nixpkgs.overlays = [
    (final: prev: {
      linux-firmware = prev.linux-firmware.overrideAttrs (old: {
        version = "20261019-unstable-2026-11-17";
        src = prev.fetchFromGitLab {
          owner = "kernel-firmware";
          repo = "linux-firmware";
          rev = "6e26a246cf6194dd4b75c5d304013e66ebc0f2ae";
          hash = "sha256-o37Y44aYj90LtlX/IkLIuhrkI4sVZZcdeCBNCBUAD94=";
        };
      });
    })
  ];

  # Framework guide, step 8: firmware via fwupdmgr (fwupd itself is enabled in
  # common and by the nixos-hardware module). For Intel models even the stable
  # BIOS releases are still filed under lvfs-testing, so that remote is needed.
  # After flashing the BIOS you can drop this line.
  services.fwupd.extraRemotes = [ "lvfs-testing" ];
  # Guide: "might be necessary once to make the update succeed". Uncomment if
  # `fwupdmgr update` fails to schedule the capsule.
  # services.fwupd.uefiCapsuleSettings.DisableCapsuleUpdateOnDisk = true;
  services.fprintd.enable = true;
  # NixOS adds fingerprint auth to every PAM service. At the greeter that means a finger
  # logs you in without a password ever reaching PAM, so gnome-keyring cannot unlock
  # ("keyring did not get unlocked"). Password-only at the greeter; sudo and the lock
  # screen keep the fingerprint.
  security.pam.services.greetd.fprintAuth = false;
}
