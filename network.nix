rec {
  baseDomain = "johann-hackler.com";

  nodes = {
    # --- Edge Proxy ---
    nix-nginx = {
      networking = {
        interfaces.service.ipv4.addresses = [
          {
            address = "10.60.1.17";
            prefixLength = 24;
          }
        ];
        interfaces.service.ipv4.routes = [
          {
            address = "10.60.0.0";
            prefixLength = 24;
            via = "10.60.1.1";
          }
        ];
        interfaces.dmz.ipv4.addresses = [
          {
            address = "10.60.50.17";
            prefixLength = 24;
          }
        ];
        defaultGateway.address = "10.60.50.1";
        defaultGateway.interface = "dmz";
        firewall.allowedTCPPorts = [
          80
          443
        ];
        nameservers = [ nodes.nix-adguard.ip ];
      };
      hostname = "nginx";
      ip = "10.60.1.17";
      port = 443;
    };

    # --- Identity Provider (Zitadel) ---
    nix-grafana = {
      networking = {
        interfaces.service.ipv4.addresses = [
          {
            address = "10.60.1.25";
            prefixLength = 24;
          }
        ];
        defaultGateway.address = "10.60.1.1";
        defaultGateway.interface = "service";
        firewall.allowedTCPPorts = [ 3000 ];
        # This now works because of the 'rec' keyword
        nameservers = [ nodes.nix-adguard.ip ];
      };
      hostname = "grafana";
      ip = "10.60.1.25";
      port = 3000;
    };

    # --- Identity Provider (Zitadel) ---
    nix-influx = {
      networking = {
        interfaces.service.ipv4.addresses = [
          {
            address = "10.60.1.26";
            prefixLength = 24;
          }
        ];
        defaultGateway.address = "10.60.1.1";
        defaultGateway.interface = "service";
        firewall.allowedTCPPorts = [ 8086 ];
        # This now works because of the 'rec' keyword
        nameservers = [ nodes.nix-adguard.ip ];
      };
      hostname = "influxv2";
      ip = "10.60.1.26";
      port = 8086;
    };
    # --- Identity Provider (Zitadel) ---
    nix-zitadel = {
      networking = {
        interfaces.service.ipv4.addresses = [
          {
            address = "10.60.1.21";
            prefixLength = 24;
          }
        ];
        defaultGateway.address = "10.60.1.1";
        defaultGateway.interface = "service";
        firewall.allowedTCPPorts = [ 8081 ];
        # This now works because of the 'rec' keyword
        nameservers = [ nodes.nix-adguard.ip ];
      };
      hostname = "zitadel";
      ip = "10.60.1.21";
      port = 8081;
    };

    # --- Database (Postgres) ---
    nix-postgres = {
      networking = {
        interfaces.service.ipv4.addresses = [
          {
            address = "10.60.1.20";
            prefixLength = 24;
          }
        ];
        defaultGateway.address = "10.60.1.1";
        defaultGateway.interface = "service";
        firewall.allowedTCPPorts = [ 5432 ];
      };
      hostname = "postgres";
      ip = "10.60.1.20";
      port = 5432;
    };

    # --- DNS & Ad-Blocking ---
    nix-adguard = {
      networking = {
        interfaces.service.ipv4.addresses = [
          {
            address = "10.60.1.16";
            prefixLength = 24;
          }
        ];

        defaultGateway.address = "10.60.1.1";
        defaultGateway.interface = "service";
        firewall.allowedTCPPorts = [
          53
          80
          443
          3000
        ];
        firewall.allowedUDPPorts = [ 53 ];
      };
      hostname = "adguard";
      ip = "10.60.1.16";
      port = 3000;
    };

    # --- VPN & Mesh (Headscale) ---
    nix-headscale = {
      networking = {
        interfaces.service.ipv4.addresses = [
          {
            address = "10.60.1.30";
            prefixLength = 24;
          }
        ];
        defaultGateway.address = "10.60.1.1";
        defaultGateway.interface = "service";
        firewall.allowedTCPPorts = [
          8080
          3000
          9090
        ];
        nameservers = [ nodes.nix-adguard.ip ];
        firewall.allowedUDPPorts = [ 3478 ];

      };
      hostname = "headscale";
      ip = "10.60.1.30";
      port = 8080;
    };

    # --- Document Management (Paperless) ---
    nix-paperless = {
      networking = {
        interfaces.service.ipv4.addresses = [
          {
            address = "10.60.1.32";
            prefixLength = 24;
          }
        ];
        nameservers = [ nodes.nix-adguard.ip ];
        defaultGateway.address = "10.60.1.1";
        defaultGateway.interface = "service";
        firewall.allowedTCPPorts = [ 28981 ];
      };
      hostname = "paperless";
      ip = "10.60.1.32";
      port = 28981;
    };

    # --- Smart Home (Home Assistant) ---
    nix-homeassistant = {
      networking = {
        interfaces.service.ipv4.addresses = [
          {
            address = "10.60.1.33";
            prefixLength = 24;
          }
        ];
        interfaces.wireguard.ipv4.addresses = [
          {
            address = "10.60.99.33";
            prefixLength = 24;
          }
        ];
        nameservers = [ nodes.nix-adguard.ip ];
        defaultGateway.address = "10.60.1.1";
        defaultGateway.interface = "service";
        firewall.allowedTCPPorts = [ 8123 ];
      };
      hostname = "homeassistant";
      ip = "10.60.1.33";
      port = 8123;
    };

    # --- Knowledge Base (HedgeDoc) ---
    nix-hedgedoc = {
      networking = {
        interfaces.service.ipv4.addresses = [
          {
            address = "10.60.1.23";
            prefixLength = 24;
          }
        ];
        defaultGateway.address = "10.60.1.1";
        defaultGateway.interface = "service";
        firewall.allowedTCPPorts = [ 3005 ];
      };
      hostname = "hedgedoc";
      ip = "10.60.1.23";
      port = 3005;
    };
  };
}
