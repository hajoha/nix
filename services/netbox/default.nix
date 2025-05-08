{ config, ... }: {
  system.stateVersion = "25.05";

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  services.netbox = {
    enable = true;
    secretKeyFile = "/var/lib/netbox/secret-key-file";
  };

    services.nginx = {
    enable = true;
    user = "netbox";
    recommendedTlsSettings = true;
    clientMaxBodySize = "25m";

    virtualHosts."192.168.178.101" = {
      locations = {
        "/" = {
          proxyPass = "http://[::1]:8001";
          # proxyPass = "http://${config.services.netbox.listenAddress}:${config.services.netbox.port}";
        };
        "/static/" = { alias = "${config.services.netbox.dataDir}/static/"; };
      };
      forceSSL = false;
      enableACME = false;
      sslCertificate = "";
      sslCertificateKey = "";
      serverName = "${config.networking.fqdn}";
    };
  };

  security.acme = {
    defaults.email = "acme@${config.networking.domain}";
    acceptTerms = true;
  };

}