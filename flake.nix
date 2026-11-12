{
  description = "Nixos Configuration";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-26.05";
    # Only used for individual packages we want ahead of the stable channel
    # (see the `unstable` overlay in hosts/common/desktop.nix).
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # personal fork, mail client. Follows stable so it shares webkitgtk, gstreamer,
    # glib etc. with the rest of the system instead of dragging in a second set.
    aerion = {
      url = "github:antoniosteiger/aerion";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia-greeter = {
      url = "github:noctalia-dev/noctalia-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets (age, derived from the hosts' ssh keys). Used by the vps and arcticbox only.
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixos-hardware,
      home-manager,
      noctalia-greeter,
      ...
    }@inputs:
    let
      # One NixOS system per machine: hosts/<name>/configuration.nix, optional
      # hardware modules, and the home-manager + greeter setup every host shares.
      # hyprHost selects config/hypr/host-<hyprHost>.conf.
      mkHost =
        {
          name,
          hyprHost,
          hardware ? [ ],
        }:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/${name}/configuration.nix
          ]
          ++ hardware
          ++ [
            home-manager.nixosModules.home-manager
            {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                users.toni = import ./home.nix;
                backupFileExtension = "backup";
                extraSpecialArgs = { inherit hyprHost; };
              };
            }
            noctalia-greeter.nixosModules.default
          ];
        };
      # Headless servers: no home-manager, no greeter. Everything else (sops-nix, modules)
      # is imported by the host config itself, so a host reads as one self-contained unit.
      mkServer =
        { name }:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          specialArgs = { inherit inputs; };
          modules = [ ./hosts/${name}/configuration.nix ];
        };
    in
    {
      nixosConfigurations = {
        lenovo_t14s_gen2 = mkHost {
          name = "lenovo_t14s_gen2";
          hyprHost = "laptop";
          hardware = [ nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen2 ];
        };

        framework_13_pro = mkHost {
          name = "framework_13_pro";
          hyprHost = "framework";
          hardware = [ nixos-hardware.nixosModules.framework-intel-core-ultra-series3 ];
        };

        arcticbox = mkHost {
          name = "arcticbox";
          hyprHost = "desktop";
        };

        # Nextcloud + Vaultwarden + Paperless-ngx. See docs/vps.md.
        vps = mkServer { name = "vps"; };
      };
    };
}
