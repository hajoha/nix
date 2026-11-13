{
  config,
  pkgs,
  lib,
  ...
}:

let
  inherit (config.homelab) nodes;
  flathunter = pkgs.callPackage ./package.nix { };

  # Non-secret configuration. This is rendered through a sops template below
  # rather than pkgs.formats.yaml, because the apprise URL has to carry the
  # Signal number and must not land in the world-readable Nix store.
  settings = {
    verbose = false;

    loop = {
      active = true;
      # Kleinanzeigen will rate-limit your IP below ~600s. 900 is polite.
      sleeping_time = 900;
      random_jitter = true;
    };

    database_location = "/var/lib/flathunter";

    # Configure the search on each portal in your browser, then paste the
    # result URL here. Sort by newest — most crawlers only read page 1.
    urls = [
      # "https://www.wg-gesucht.de/wohnungen-in-Berlin.8.2.1.0.html?..."
      # "https://www.immowelt.de/classified-search?distributionTypes=Rent&..."
      # "https://www.kleinanzeigen.de/s-wohnung-mieten/berlin/..."
    ];

    filters = {
      # min_rooms = 2;
      # max_price = 1400;
      # min_size = 45;
      excluded_titles = [
        "(?i)zwischenmiete"
        "(?i)tausch"
        "(?i)möbliert"
      ];
    };

    message = ''
      {title}
      Zimmer: {rooms}
      Größe: {size}
      Preis: {price}
      Ort: {address}
      {url}
    '';
    title = "{crawler}: {title}";

    notifiers = [ "apprise" ];
    apprise_notify_with_images = true;
    apprise_image_limit = 6;

    captcha = {
      # If you crawl ImmoScout24, add a capmonster secret and splice its
      # placeholder into the template below, next to the apprise URL.
      # Chromium inside an unprivileged LXC cannot use its own sandbox.
      driver_arguments = [
        "--headless=new"
        "--no-sandbox"
        "--disable-dev-shm-usage"
        "--disable-gpu"
      ];
    };
  };

  # JSON is a subset of YAML, so flathunter's yaml.safe_load reads this fine.
  configFile = config.sops.templates."config.yaml".path;
in
{
  imports = [ ./signal.nix ];

  # 1. SOPS Configuration
  # `signal-number` is declared in ./signal.nix
  sops.defaultSopsFile = ./secrets.enc.yaml;

  sops.templates."config.yaml" = {
    owner = "flathunter";
    content = builtins.toJSON (
      settings
      // {
        apprise = [
          "signal://127.0.0.1:9922/${config.sops.placeholder."signal-number"}"
        ];
      }
    );
  };

  users.users.flathunter = {
    isSystemUser = true;
    group = "flathunter";
    home = "/var/lib/flathunter";
  };
  users.groups.flathunter = { };

  systemd.services.flathunter = {
    description = "Flathunter rental listing bot";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [
      "network-online.target"
      "signal-webhook.service"
    ];

    environment = {
      HOME = "/var/lib/flathunter";
      PYTHONUNBUFFERED = "1";
      FLATHUNTER_DATABASE_LOCATION = "/var/lib/flathunter";
      FLATHUNTER_HEADLESS_BROWSER = "1";
    };

    serviceConfig = {
      ExecStart = "${lib.getExe flathunter} --config ${configFile}";

      User = "flathunter";
      Group = "flathunter";
      StateDirectory = "flathunter";
      StateDirectoryMode = "0750";
      WorkingDirectory = "/var/lib/flathunter";

      # It crawls in a loop and dies on transient network errors; just come back.
      Restart = "on-failure";
      RestartSec = 60;

      # Hardening. If Chromium misbehaves, relax MemoryDenyWriteExecute and
      # RestrictNamespaces first — the renderer needs both.
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      SystemCallArchitectures = "native";
    };
  };

  # --- Optional: the Flask web UI -----------------------------------------
  # Only worth it if you want to manage searches from a browser. Its login is
  # the Telegram widget, which needs a public hostname — so it would have to go
  # through nix-nginx, and it is Telegram-bound even though notifications are not.
  #
  # systemd.services.flathunter-web = {
  #   description = "Flathunter web interface";
  #   wantedBy = [ "multi-user.target" ];
  #   after = [ "network-online.target" ];
  #   environment = {
  #     HOME = "/var/lib/flathunter";
  #     FLATHUNTER_WEBSITE_DOMAIN = nodes.nix-flathunter.fqdn;
  #   };
  #   serviceConfig = {
  #     ExecStart = "${flathunter}/bin/flathunter-web --config ${configFile}";
  #     User = "flathunter";
  #     Group = "flathunter";
  #     StateDirectory = "flathunter";
  #     Restart = "on-failure";
  #   };
  # };

  # Firewall ports come from the inventory (tcp/udp in nodes.nix)
  system.stateVersion = "25.11";
}
