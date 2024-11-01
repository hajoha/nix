{
  description = "A simple NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixpkgs-unstable = {
        url = "github:NixOS/nixpkgs/nixos-unstable";
    };
    nur.url = "github:nix-community/nur";
  };


  outputs = { self, nixpkgs, home-manager,... }@inputs:
    {
        nixosConfigurations = {
        nixmaschine = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/nixmaschine/configuration.nix
              home-manager.nixosModules.home-manager
              {
                home-manager.useUserPackages = true;

                home-manager.users.hajoha = import ./home.nix;

                home-manager.extraSpecialArgs = {
                    inherit inputs;
                };

              }
          ];
        };
    };
  };
}
