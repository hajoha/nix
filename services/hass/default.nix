{
  config,
  lib,
  pkgs,
  nodes,
  keycloakRealm,
  baseDomain,
  ...
}:
{
  sops.secrets."hass_db_user" = {
    owner = "hass";
    sopsFile = ./secrets.enc.yaml;
  };
  sops.secrets."client_id" = {
    owner = "hass";
    sopsFile = ./secrets.enc.yaml;
  };

  sops.secrets."pg-password" = {
    owner = "hass";
    key = "password";
    sopsFile = ./postgres.enc.yaml;
  };

  # 2. Create the actual secrets.yaml file for Home Assistant
  sops.templates."hass-secrets.yaml" = {
    owner = "hass";
    path = "/var/lib/hass/secrets.yaml"; # This is the file HA reads

    content = ''
      hass_db_url: postgresql://${config.sops.placeholder.hass_db_user}:${config.sops.placeholder.pg-password}@${nodes.nix-postgres.ip}/${config.sops.placeholder.hass_db_user}
      client_id: ${config.sops.placeholder.client_id}
    '';
  };
  # 2. Kernel & Networking Adjustments
  boot.kernelModules = [ "tun" ];
  boot.kernel.sysctl = {
    "net.ipv6.conf.all.forwarding" = lib.mkForce 1;
    "net.ipv6.conf.default.forwarding" = lib.mkForce 1;
  };
  # 3. Matter & OpenThread Border Router
  services.matterjs-server = {
    enable = true;
    openFirewall = true;
    extraArgs = [
      "--primary-interface=iot"
      # "--web-address=::"
    ];
  };
  systemd.services.matterjs-server.environment.VENDOR_ID = "4939";
  services.openthread-border-router = {
    enable = true;
    backboneInterfaces = [
      "iot"

    ];
    interfaceName = "wpan0";
    logLevel = "info";
    # extraArgs = [
    #   "-B"
    #   "iot"
    # ];
    radio = {
      device = "/dev/serial/by-id/usb-Itead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_V2_90837c5304f4ef11aa21c61b6d9880ab-if00-port0";
      baudRate = 460800;
      flowControl = false;
      # extraDevices = [ "treel://service" ];
    };
    rest = {
      listenAddress = "0.0.0.0"; # or "${nodes.nix-homeassistant.ip}"
      listenPort = 8081;
    };
    web = {
      enable = true;
      listenAddress = "${nodes.nix-homeassistant.ip}";
    };
  };
  systemd.services.otbr-web.serviceConfig = {
    User = lib.mkForce "root";
    Group = lib.mkForce "root";
  };

  services.dbus.enable = true;

  # 4. Declarative Custom Component Injection
  # This links the fetched GitHub source into the HA custom_components directory

  # 5. Home Assistant Configuration
  systemd.tmpfiles.rules = [
    "f /var/lib/hass/automations.yaml 0644 hass hass - []"
    "f /var/lib/hass/scripts.yaml 0644 hass hass - {}"
    "f /var/lib/hass/scenes.yaml 0644 hass hass - []"
  ];

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        port = 1883;
        omitPasswordAuth = true;
        settings = {
          bind_interface = "iot";
          allow_anonymous = true;
        };
        acl = [ "pattern readwrite #" ];
      }
      {
        port = 1883;
        omitPasswordAuth = true;
        settings = {
          bind_interface = "lo";
          allow_anonymous = true;
        };
        acl = [ "pattern readwrite #" ];
      }
    ];
  };

  services.home-assistant = {
    enable = true;
    extraPackages =
      ps: with ps; [
        psycopg2
        universal-silabs-flasher
        pyipp
        python-otbr-api
        home-assistant-chip-clusters
        # Required for OIDC
        authlib
        httpx
      ];

    extraComponents = [
      "analytics"
      "google_translate"
      "met"
      "radio_browser"
      "shopping_list"
      "isal"
      "recorder"
      "matter"
      "dwd_weather_warnings"
      "music_assistant"
      "immich"
      "soundtouch"
      "local_todo"
      "thread"
      "otbr"
      "mqtt"
    ];
    customComponents = [
      pkgs.home-assistant-custom-components.auth_oidc
      pkgs.home-assistant-custom-components.valetudo
      (pkgs.callPackage ./matter-binding-helper.nix { })
    ];
    customLovelaceModules = [
      pkgs.home-assistant-custom-lovelace-modules.valetudo-map-card
    ];

    config = {
      logger = {
        default = "info";
      };
      default_config = { };
      "automation manual" = [ ];
      "automation ui" = "!include automations.yaml";
      "script manual" = { };
      "script ui" = "!include scripts.yaml";
      "scene manual" = [ ];
      "scene ui" = "!include scenes.yaml";
      homeassistant = {
        name = "XHain";
        unit_system = "metric";
        time_zone = "Europe/Berlin";
      };

      auth_oidc = {
        client_id = "!secret client_id";
        discovery_url = "https://${nodes.nix-keycloak.sub}.${baseDomain}/realms/${keycloakRealm}/.well-known/openid-configuration";
      };

      thread = { };
      otbr = { };

      http = {
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "::1"
          nodes.nix-nginx.ip
          "10.60.1.0/24"
          "10.60.60.0/24"
          "100.64.0.0/10"
          "fd00:60:0::/64"
          "fd00:60:1::/64"
        ];
      };

      recorder.db_url = "!secret hass_db_url";
    };
  };

  # 6. Music Assistant & Discovery
  services.music-assistant = {
    enable = true;
    openFirewall = true;
    providers = [
      "tidal"
      "soundcloud"
      "hass"
      "jellyfin"
      "airplay"
      "radiobrowser"
      "radioparadise"
      "hass_players"
      "hass"
      "dlna"
      "sendspin"
      "chromecast"
      "ytmusic"
    ];
  };

  services.avahi = {
    enable = true;
    nssmdns4 = true;
    nssmdns6 = true;
    reflector = true;
    ipv6 = true;
    ipv4 = true;
    publish = {
      enable = true;
      addresses = true;
      userServices = true;
    };
    allowInterfaces = [
      "service"
      "iot"
      "wpan"
    ];

  };

  systemd.services.otbr-agent = {
    after = [
      "avahi-daemon.service"
      "dbus.service"
    ];
    wants = [ "avahi-daemon.service" ];
  };
  # 7. Helper Services & Overrides
  systemd.services.otbr-wpan-up = {
    description = "Bring up wpan0 after OTBR init (LXC fix)";
    after = [ "otbr-agent.service" ];
    requires = [ "otbr-agent.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.iproute2}/bin/ip link set wpan0 up";
      SuccessExitStatus = [
        "0"
        "1"
      ];
    };
  };

  systemd.services.home-assistant.after = [ "sops-nix.service" ];

  users.users.hass.extraGroups = [
    "dialout"
    "tty"
  ];

  # NEW (NixOS Structured Settings)
  services.resolved.settings = {
    Resolve = {
      MulticastDNS = "no";
    };
  };
  system.stateVersion = "25.11";
}
