{
  description = "A simple NixOS flake";
         

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };


   nur.url = "github:nix-community/nur";
  };


  outputs = { self, nixpkgs, home-manager,... }@inputs: 
{	# Please replace my-nixos with your hostname
    nixosConfigurations = {
nixmaschine = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        # Import the previous configuration.nix we used,
        # so the old configuration file still takes effect
        ./configuration.nix
          home-manager.nixosModules.home-manager
          {
#            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;

            home-manager.users.hajoha = import ./home.nix;

            # Optionally, use home-manager.extraSpecialArgs to pass arguments to home.nix
            home-manager.extraSpecialArgs = { inherit inputs; };

          }
      ];
    };
};
  };
}
