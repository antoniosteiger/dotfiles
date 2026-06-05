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

  environment.systemPackages = with pkgs; [

  ];

  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    dedicatedServer.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
    gamescopeSession.enable = true;
  };
  programs.gamemode.enable = true;
  programs.gamescope.enable = true;
}
