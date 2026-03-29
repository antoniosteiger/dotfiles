{
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../common/configuration.nix
  ];

  networking.hostName = "tonix-desktop";

  # Desktop-specific: No power management needed
  powerManagement.enable = false;
}
