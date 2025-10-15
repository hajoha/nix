{ config, pkgs, ... }:

{
  services.zitadel = {
    enable = true;
    domain = "zitadel.bar0.foo";
    settings = {
      ZITADEL_UI_ASSETS_URL = "https://zitadel.bar0.foo";
      ZITADEL_API_URL = "https://api.zitadel.bar0.foo";
      ZITADEL_ISSUER = "https://zitadel.bar0.foo";
      ZITADEL_AUTHENTICATION_METHODS = "external,internal";
    };
  };

  networking.firewall.allowedTCPPorts = [
    443
    80
  ];
}
