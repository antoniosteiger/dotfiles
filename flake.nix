{
  description = "Nixos Configuration";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-26.05";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    llm-agents.url = "github:numtide/llm-agents.nix";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      # self,
      nixpkgs,
      nixos-hardware,
      home-manager,
      stylix,
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
          stylix.nixosModules.stylix
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
          stylix.nixosModules.stylix
        ];
      };
    };

}
