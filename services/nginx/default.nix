{ config, ... }: {
  system.stateVersion = "25.05";

  services.nginx = {
    enable = true;
    virtualHosts."nixnetbox" = {
      serverName = "nixnetbox";
      listen = [
        { addr = "0.0.0.0"; port = 80; }
      ];
      forceSSL = false;
      enableACME = false;
        locations = {
          "/" = {
            proxyPass = "http://192.168.178.101:8001";
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
            '';
          };
        };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "foo@bar.com";
  };
}
