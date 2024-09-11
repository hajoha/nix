{
  description = "A simple NixOS flake";
         

  inputs = {
    # NixOS official package source, using the nixos-23.11 branch here
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.11";
    home-manager = {
      url = "github:nix-community/home-manager/release-23.11";  # this selects the release-branch and needs to match Nixpkgs
      inputs.nixpkgs.follows = "nixpkgs";
    };

#    firefox-addons = {
#      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
#      inputs.nixpkgs.follows = "nixpkgs";
#    };

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
	   
            # TODO replace ryan with your own username
            home-manager.users.hajoha = import ./home.nix;

            # Optionally, use home-manager.extraSpecialArgs to pass arguments to home.nix
            home-manager.extraSpecialArgs = { inherit inputs; };

          }
      ];
    };
};
  };
}
