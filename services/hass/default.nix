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
      hass_db_url: "postgresql://${config.sops.placeholder.hass_db_user}:${config.sops.placeholder.pg-password}@${nodes.nix-postgres.ip}/${config.sops.placeholder.hass_db_user}"
      client_id: "${config.sops.placeholder.client_id}"
    '';
  };
  # 2. Kernel & Networking Adjustments
  boot.kernelModules = [ "tun" ];

  # 3. Matter & OpenThread Border Router
  services.matter-server = {
    enable = true;
    logLevel = "debug";
    openFirewall = true;
    extraArgs = {
      primary-interface = "iot";
    };
  };

  services.openthread-border-router = {
    enable = true;
    backboneInterfaces = [ "iot" ];
    logLevel = "info";
    radio = {
      device = "/dev/serial/by-id/usb-Itead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_V2_90837c5304f4ef11aa21c61b6d9880ab-if00-port0";
      baudRate = 460800;
      flowControl = false;
      # extraDevices = [ "treel://service" ];
    };
    web = {
      enable = true;
      listenAddress = "0.0.0.0";
    };
  };

  services.dbus.enable = true;

  # 4. Declarative Custom Component Injection
  # This links the fetched GitHub source into the HA custom_components directory

  # 5. Home Assistant Configuration
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
      "soundtouch"
      "thread"
      "otbr"
    ];
    customComponents = [
      pkgs.home-assistant-custom-components.auth_oidc
    ];

    config = {
      default_config = { };
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
    providers = [
      "tidal"
      "soundcloud"
      "hass"
      "jellyfin"
      "hass_players"
      "hass"
      "dlna"
      "sendspin"
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
      "wpan0"
    ];
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

  system.stateVersion = "25.11";
}
