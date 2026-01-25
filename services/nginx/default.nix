{
  config,
  pkgs,
  nodes,
  baseDomain,
  ...
}:

let
  commonProxy = {
    proxyWebsockets = true;
    extraConfig = ''
      proxy_set_header Host ''$host;
      proxy_set_header X-Real-IP ''$remote_addr;
      proxy_set_header X-Forwarded-For ''$proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto ''$scheme;
      proxy_set_header X-Forwarded-Host ''$host;
    '';
  };

  lanOnly = ''
    if (''$remote_addr !~ ^(10\.60\.|172\.16\.0\.)) {
      return 444;
    }
  '';
in
{

  sops.defaultSopsFile = ./secrets.enc.yaml;

  # 2. Tell sops-nix which keys to decrypt
  sops.secrets = {
    "INWX_USERNAME" = {
      owner = "nginx";
    };
    "INWX_PASSWORD" = {
      owner = "nginx";
    };
  };
  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedTlsSettings = true;

    appendHttpConfig = ''
      map ''$http_upgrade ''$connection_upgrade {
          default upgrade;
          # Escaped empty string for Nginx
          '''       close;
      }
    '';

    virtualHosts = {
      # --- Root Domain (Webfinger for Zitadel) ---
      "${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        locations."/.well-known/webfinger".extraConfig = ''
          add_header Content-Type application/jrd+json;
          return 200 '{"subject":"acct:info@${baseDomain}","links":[{"rel":"http://openid.net/specs/connect/1.0/issuer","href":"https://${nodes.nix-zitadel.hostname}"}]}';
        '';
      };

      # --- AdGuard ---
      "${nodes.nix-adguard.hostname}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        extraConfig = lanOnly;
        locations."/".proxyPass = "http://${nodes.nix-adguard.ip}:${toString nodes.nix-adguard.port}";
      };

      # --- Zitadel ---
      "${nodes.nix-zitadel.hostname}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        http2 = true;
        locations."/" = commonProxy // {
          proxyPass = "http://${nodes.nix-zitadel.ip}:8081";
          # Notice the ''$ to escape Nginx variables from Nix interpolation
          extraConfig = commonProxy.extraConfig + "proxy_set_header X-Forwarded-Port 443;";
        };
      };

      # --- HedgeDoc ---
      "${nodes.nix-hedgedoc.hostname}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        http2 = true;
        locations."/" = commonProxy // {
          proxyPass = "http://${nodes.nix-hedgedoc.ip}:${toString nodes.nix-hedgedoc.port}";
        };
        locations."/socket.io/" = commonProxy // {
          proxyPass = "http://${nodes.nix-hedgedoc.ip}:${toString nodes.nix-hedgedoc.port}";
          extraConfig = commonProxy.extraConfig + ''
            proxy_set_header Upgrade ''$http_upgrade;
            proxy_set_header Connection ''$connection_upgrade;
          '';
        };
      };

      # --- Paperless ---
      "${nodes.nix-paperless.hostname}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        extraConfig = lanOnly;
        locations."/" = commonProxy // {
          proxyPass = "http://${nodes.nix-paperless.ip}:${toString nodes.nix-paperless.port}";
        };
      };

      # --- Home Assistant ---
      "${nodes.nix-homeassistant.hostname}.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        extraConfig = lanOnly;
        locations."/" = commonProxy // {
          proxyPass = "http://${nodes.nix-homeassistant.ip}:${toString nodes.nix-homeassistant.port}";
        };
      };

      # --- Headscale ---
      "headscale.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        locations."/" = commonProxy // {
          proxyPass = "http://${nodes.nix-headscale.ip}:8080";
          extraConfig = commonProxy.extraConfig + ''
            proxy_buffering off;
            add_header Strict-Transport-Security "max-age=15552000; includeSubDomains" always;
          '';
        };
        locations."/admin/" = commonProxy // {
          proxyPass = "http://${nodes.nix-headscale.ip}:3000/admin/";
        };
        locations."/admin".extraConfig = "return 301 /admin/ ;";
      };

      # --- External Hosts (Non-Containers) ---
      "pve1.${baseDomain}" = {
        useACMEHost = baseDomain;
        forceSSL = true;
        extraConfig = lanOnly;
        locations."/".proxyPass = "https://10.60.0.3:8006/";
      };
    };
  };

  # ... (ACME and Firewall remain the same) ...
  security.acme = {
    acceptTerms = true;
    defaults.group = "nginx"; # This allows the nginx group to read the certs

    certs."${baseDomain}" = {
      extraDomainNames = [ "*.${baseDomain}" ];
      dnsProvider = "inwx";
      email = "joh.hackler@gmail.com";

      # This ensures Nginx reloads whenever the certificate is renewed
      reloadServices = [ "nginx.service" ];

      credentialFiles = {
        "INWX_USERNAME_FILE" = config.sops.secrets."INWX_USERNAME".path;
        "INWX_PASSWORD_FILE" = config.sops.secrets."INWX_PASSWORD".path;
      };
      dnsPropagationCheck = false;
    };
  };
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
