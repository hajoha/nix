{
  config,
  pkgs,
  lib,
  nodes,
  keycloakRealm,
  baseDomain,
  ...
}:
{
  users.users.immich.extraGroups = [
    "video"
    "render"
  ];
  # 1. SOPS Configuration
  sops.defaultSopsFile = ./secrets.enc.yaml;

  sops.secrets."immich-oauth-client-secret" = {
    # File should contain: DB_PASSWORD
    owner = "immich";
  };

  sops.secrets."pg-password" = {
    owner = "immich";
    key = "password";
    sopsFile = ./postgres.enc.yaml;
  };

  sops.templates.".env" = {
    owner = "immich";

    content = ''
      DB_PASSWORD=${config.sops.placeholder."pg-password"}
    '';
  };

  services.immich = {
    enable = true;
    host = "0.0.0.0";
    port = nodes.nix-immich.port;
    # Decrypted environment file containing the DB password
    secretsFile = config.sops.templates.".env".path;

    # Media storage location
    mediaLocation = "/var/lib/immich";
    accelerationDevices = [ "/dev/dri/renderD128" ];
    environment.LIBVA_DRIVER_NAME = "iHD";
    # Database Configuration (pointing to your external Postgres node)
    database = {
      enable = false; # Set to false since you use an external nix-postgres node
      host = nodes.nix-postgres.ip;
      port = nodes.nix-postgres.port;
      name = "immich";
      user = "immich";
    };

    # Redis Configuration
    redis = {
      enable = true; # Set to true if you want a local redis, or false to point elsewhere
    };

    # Main System Settings
    settings = {

      logging.enabled = true;
      logging.level = "log";

      server.externalDomain = "https://${nodes.nix-immich.sub}.${baseDomain}";
      newVersionCheck.enabled = true;
      ffmpeg = {
        accel = "vaapi";
        accelDecode = true;
        acceptedAudioCodecs = [
          "aac"
          "mp3"
          "opus"
        ];
        acceptedContainers = [
          "mov"
          "ogg"
          "webm"
        ];
        acceptedVideoCodecs = [ "h264" ];
        bframes = -1;
        cqMode = "auto";
        crf = 23;
        gopSize = 0;
        maxBitrate = "0";
        preferredHwDevice = "auto";
        preset = "ultrafast";
        refs = 0;
        targetAudioCodec = "aac";
        targetResolution = "720";
        targetVideoCodec = "h264";
        temporalAQ = false;
        threads = 0;
        tonemap = "hable";
        transcode = "required";
        twoPass = false;
      };
      machineLearning = {
        enabled = true;
        # In NixOS, the ML service is local, so we use 127.0.0.1
        urls = [ "http://127.0.0.1:3003" ];

        clip = {
          enabled = true;
        };

        facialRecognition = {
          enabled = true;
          minFaces = 3;
          minScore = 0.7;
          maxDistance = 0.5;
        };

        ocr = {
          enabled = true;
          maxResolution = 736;
          minDetectionScore = 0.5;
          minRecognitionScore = 0.8;
        };

        duplicateDetection = {
          enabled = true;
          maxDistance = 0.01;
        };

        availabilityChecks = {
          enabled = true;
          interval = 30000;
          timeout = 2000;
        };
      };
      # Immich OAuth2 (OIDC) Integration
      # Note: Immich uses a specific2 schema for OIDC in its config
      oauth = {
        enabled = true;
        autoRegister = true;
        issuerUrl = "https://${nodes.nix-keycloak.sub}.${baseDomain}/realms/${keycloakRealm}";
        clientId = "immich";
        clientSecret._secret = config.sops.secrets."immich-oauth-client-secret".path;
        scope = "openid email profile";
        buttonText = "SSO";
        defaultStorageQuota = 250;
      };
    };
    environment = {
      IMMICH_TRUSTED_PROXIES = "${nodes.nix-nginx.ip}";
    };

    # Machine Learning Settings
    machine-learning = {
      enable = true;
    };
  };

  system.stateVersion = "25.11";
}
