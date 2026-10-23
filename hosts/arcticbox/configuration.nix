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
    blender
    davinci-resolve # needs the ROCm OpenCL ICD below on AMD
    opencode
  ];

  # Local LLMs on the 7800 XT (16GB VRAM, gfx1101) via ROCm
  services.ollama = {
    enable = true;
    package = pkgs.ollama-rocm;
    loadModels = [ "qwen3:14b" ];
    environmentVariables = {
      OLLAMA_CONTEXT_LENGTH = "65536";
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KV_CACHE_TYPE = "q8_0"; # halves KV cache VRAM so 64k fits next to the 14b weights
    };
  };

  hardware.graphics.extraPackages = [ pkgs.rocmPackages.clr.icd ]; # OpenCL for DaVinci Resolve

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
