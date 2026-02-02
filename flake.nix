{
  description = "tankbusta nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    ida-pro-overlay = {
      url = "github:msanft/ida-pro-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      inherit (self) outputs;

      overlays = [
        inputs.ida-pro-overlay.overlays.default
      ];

      # Helper function to create NixOS system configurations
      mkNixosConfig = { hostname, system }: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs outputs; };
        modules = [
          { nixpkgs.overlays = overlays; }

          # Global configuration shared across all hosts
          ./hosts/global

          # Host-specific configuration
          ./hosts/${hostname}

          # Home-manager NixOS module
          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs outputs; };
              users.cschmitt = import ./hosts/${hostname}/home.nix;
            };
          }
        ];
      };
    in
    {
      # Host Configurations
      nixosConfigurations = {
        "daedalus" = mkNixosConfig {
          # Dev Laptop
          hostname = "daedalus";
          system = "x86_64-linux";
        };
      };
    };
}
