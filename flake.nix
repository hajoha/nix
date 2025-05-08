{
  description = "A simple NixOS flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nur.url = "github:nix-community/nur";

  };



  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    {
        nixosConfigurations = {
            nixmaschine = nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                #./modules/home-manager/open-webui/open-webui.nix
                ./hosts/nixmaschine/configuration.nix
                home-manager.nixosModules.home-manager
                  {
                    home-manager.useUserPackages = true;
                    home-manager.users.hajoha = import ./hosts/nixmaschine/home.nix;
                    home-manager.extraSpecialArgs = {inherit inputs;};
                  }
              ];

            };
            nixserver = nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                #./modules/home-manager/open-webui/open-webui.nix
                ./hosts/nixserver/configuration.nix
                home-manager.nixosModules.home-manager
                  {
                    home-manager.useUserPackages = true;
                    home-manager.users.mng = import ./hosts/nixserver/home.nix;
                    home-manager.extraSpecialArgs = {inherit inputs;};
                  }
              ];

            };
            nixlxc = nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                #./modules/home-manager/open-webui/open-webui.nix
                ./hosts/nixlxc/configuration.nix
                home-manager.nixosModules.home-manager
                  {
                    home-manager.useUserPackages = true;
                    home-manager.users.root = import ./hosts/nixlxc/home.nix;
                    home-manager.extraSpecialArgs = {inherit inputs;};
                  }
              ];

            };
            nixnetbox = nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                ./hosts/nixnetbox/configuration.nix
              ];

            };
            nixnginx = nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                ./hosts/nixnginx/configuration.nix
              ];

            };
            nixcloud = nixpkgs.lib.nixosSystem {
              system = "x86_64-linux";
              modules = [
                ./hosts/nixcloud/configuration.nix
              ];

            };
    };
  };
}
