{
  description = "Nixos Configuration";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-26.05";
    nur = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia-greeter = {
      url = "github:noctalia-dev/noctalia-greeter";
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
    {
      nixosConfigurations.lenovo_t14s_gen2 = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/lenovo_t14s_gen2/configuration.nix
          nixos-hardware.nixosModules.lenovo-thinkpad-t14-amd-gen2
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.toni = import ./home.nix;
              backupFileExtension = "backup";
              extraSpecialArgs = {
                hostType = "laptop";
              };
            };
          }
          noctalia-greeter.nixosModules.default
        ];
      };

      nixosConfigurations.arcticbox = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./hosts/arcticbox/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.toni = import ./home.nix;
              backupFileExtension = "backup";
              extraSpecialArgs = {
                hostType = "desktop";
              };
            };
          }
          noctalia-greeter.nixosModules.default
        ];
      };
    };
}
