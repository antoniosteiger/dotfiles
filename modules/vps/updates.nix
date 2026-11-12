# Unattended updates from the flake. Rollback: every switch is a boot entry
# (`nixos-rebuild switch --rollback` or pick the previous generation in GRUB).
{ config, lib, ... }:
let
  cfg = config.vps.autoUpgrade;
  push = lib.getExe config.vps.monitoring.pushBin;
in
{
  options.vps.autoUpgrade = {
    flake = lib.mkOption {
      type = lib.types.str;
      default = "github:antoniosteiger/dotfiles#vps";
      description = ''
        Flake the box upgrades itself from. Must be reachable without credentials (public
        repo) or use a git+ssh URL with a deploy key.
      '';
    };
    followChannel = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        true: every run re-resolves nixpkgs to the tip of nixos-26.05 (security fixes
        arrive within a day, flake.lock is only the fallback). false: only what is
        committed in flake.lock is deployed, i.e. updates happen when you push a bumped lock.
        Bump the channel name below when you move to the next NixOS release.
      '';
    };
    channelRef = lib.mkOption {
      type = lib.types.str;
      default = "github:NixOS/nixpkgs/nixos-26.05";
    };
  };

  config = {
    system.autoUpgrade = {
      enable = true;
      inherit (cfg) flake;
      flags = lib.optionals cfg.followChannel [
        "--override-input"
        "nixpkgs"
        cfg.channelRef
      ];
      dates = "03:30";
      randomizedDelaySec = "30min";
      persistent = true;
      # Reboots only for a new kernel/initrd, and only inside this window (otherwise the
      # new generation is staged and applied on the next night / manual reboot).
      allowReboot = true;
      rebootWindow = {
        lower = "03:00";
        upper = "05:00";
      };
    };

    systemd.services.nixos-upgrade = {
      unitConfig.OnFailure = [ "gatus-push-failure@nixos-autoupgrade.service" ];
      serviceConfig.ExecStartPost = "-${push} nixos-autoupgrade success";
    };
  };
}
