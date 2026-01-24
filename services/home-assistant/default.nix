{
  config,
  lib,
  pkgs,
  ...
}:

{
  services.matter-server.enable = true;
  services.music-assistant.enable = true;
  services.music-assistant.providers = [
    "tidal"
    "soundcloud"
    "builtin_player"
    "hass"
    "hass_players"
    "dlna"
  ];
  services.home-assistant = {
    enable = true;

    extraPackages =
      ps: with ps; [
        psycopg2
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
    ];

    config = {
      default_config = { };
      http = {
        use_x_forwarded_for = true;
        trusted_proxies = [
          "10.60.1.17"
          "127.0.0.1"
          "::1"
        ];
      };
      recorder = {
        db_url = "!secret hass_db_url";
      };
      homeassistant = {
        name = "XHain";
        time_zone = "Europe/Berlin";
      };
    };

  };
  users.users.hass.extraGroups = [
    "dialout"
    "tty"
  ];
  systemd.services.home-assistant.after = [ "sops-nix.service" ];

}
