{
  config,
  lib,
  pkgs,
  nodes,
  ...
}:

{
  # 1. SOPS Configuration
  sops.defaultSopsFile = ./secrets.enc.yaml;
  sops.secrets."hass_secrets" = {
    # Ensure the database URL in secrets.yaml points to the new Postgres IP
    # example: "hass_db_url: postgresql://hass:pass@${nodes.nix-postgres.ip}/hass"
    owner = "hass";
    path = "/var/lib/hass/secrets.yaml";
  };

  services.matter-server.enable = true;

  services.music-assistant = {
    enable = true;
    providers = [
      "tidal"
      "soundcloud"
      "builtin_player"
      "hass"
      "hass_players"
      "dlna"
    ];
  };

  services.home-assistant = {
    enable = true;
    extraPackages = ps: with ps; [ psycopg2 ];

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
    ];

    config = {
      default_config = { };
      homeassistant = {
        name = "XHain";
        unit_system = "metric";
        time_zone = "Europe/Berlin";
      };

      http = {
        use_x_forwarded_for = true;
        trusted_proxies = [
          "127.0.0.1"
          "::1"
          nodes.nix-nginx.ip # Dynamic IP of your Proxy from network.nix
          "10.60.1.0/24" # Your physical LAN range
        ];
      };

      recorder = {
        db_url = "!secret hass_db_url";
      };
    };
  };

  # Permissions for Zigbee/Z-Wave USB sticks passed through from Proxmox
  users.users.hass.extraGroups = [
    "dialout"
    "tty"
  ];

  # Ensure secrets are decrypted before HASS starts
  systemd.services.home-assistant.after = [ "sops-nix.service" ];

  # Networking is now managed by mkLXC and network.nix
  system.stateVersion = "25.11";
}
