{ config, pkgs, ... }:

{
  services.nginx = {
    enable = true;

    virtualHosts = {
      "bar0.foo" = {
        forceSSL = true;
        enableACME = true;
        locations = {
          "/" = {
            root = "/var/www";
          };
        };
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    certs = {
      "bar0.foo".email = "joh.hackler@gmail.com";
    };
  };

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
