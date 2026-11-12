{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../common/base.nix
    ../common/desktop.nix
    inputs.sops-nix.nixosModules.sops
    ../../modules/sops-host.nix
    ../../modules/restic-server.nix
  ];

  system.stateVersion = "25.11"; # Never change

  networking.hostName = "tonix-desktop";

  # Receives the VPS backups (append-only restic REST server, Tailscale only). Shipped OFF so
  # a rebuild changes nothing until the storage exists. To switch on (docs/vps.md, "Arcticbox"):
  # mount the big disk at dataDir, create secrets/arcticbox.yaml, set enable = true.
  sopsHost.name = "arcticbox";
  services.resticBackupServer = {
    enable = false; # TODO: flip once /srv/restic is a real mount and the secrets exist
    dataDir = "/srv/restic";
    htpasswdFile = config.sops.secrets."restic/server_htpasswd".path;
    repos.vps.passwordFile = config.sops.secrets."restic/vps_password".path;
  };
  sops.secrets = lib.mkIf config.services.resticBackupServer.enable {
    "restic/vps_password".owner = "restic";
    "restic/server_htpasswd".owner = "restic";
  };

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
