{
  config,
  pkgs,
  lib,
  nodes,
  ...
}:
let
  servicesWithDB = [
    "keycloak"
  ];

  # Helper: Maps a service name to its specific sops secret configuration
  mkSopsSecret = name: {
    # The physical file on disk
    sopsFile = ../${name}/postgres.enc.yaml;

    # The KEY inside the encrypted YAML file
    key = "password";

    owner = "postgres";
  };
in
{

  sops.secrets = lib.genAttrs (map (svc: "users/${svc}") servicesWithDB) (
    path:
    let
      svc = lib.last (lib.splitString "/" path);
    in
    mkSopsSecret svc
  );

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    enableTCPIP = true;

    # Automated database creation
    ensureDatabases = [
      "zitadel"
      "hass"
      "hedgedoc"
      "paperless"
      "keycloak"
      "netbox" # Added NetBox as well
    ];

    #    ensureDatabases = servicesWithDB;
    #    ensureUsers = map (svc: {
    #      name = svc;
    #      ensureDBOwnership = true;
    #    }) servicesWithDB ++ [
    #      { name = "admin"; ensureClauses.superuser = true; }
    #    ];

    # Automated user creation
    ensureUsers = [
      {
        name = "zitadel";
        ensureDBOwnership = true;
      }
      {
        name = "hass";
        ensureDBOwnership = true;
      }
      {
        name = "hedgedoc";
        ensureDBOwnership = true;
      }
      {
        name = "paperless";
        ensureDBOwnership = true;
      }
      {
        name = "keycloak";
        ensureDBOwnership = true;
      }
      {
        name = "netbox";
        ensureDBOwnership = true;
      }
      {
        name = "admin";
        ensureClauses.superuser = true;
      }
    ];

    # Security: Subnet-based access control
    authentication = lib.mkOverride 10 ''
      # Type  Database        User            Address                 Method

      # 1. Local connections
      local   all             all                                     trust

      # 2. Unified LAN Subnet (All LXCs and Management)
      # Allows your other containers (Hass, Paperless, etc.) to connect
      host    all             all             10.60.1.0/24            scram-sha-256

      # Allow local loopback for the container itself
      host    all             all             127.0.0.1/32            scram-sha-256
    '';

    settings = {
      max_connections = 100;
      shared_buffers = "256MB";
      # Ensure it listens on the eth0 interface
      listen_addresses = "*";
    };
  };
  systemd.services.postgresql-password-sync = {
    description = "Sync Postgres passwords from per-service SOPS files";
    after = [
      "postgresql.service"
      "sops-nix.service"
    ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      RemainAfterExit = true;
    };
    script = lib.concatMapStringsSep "\n" (svc: ''
            SECRET_PATH="${config.sops.secrets."users/${svc}".path}"
            if [ -f "$SECRET_PATH" ]; then
              PASSWORD=$(cat "$SECRET_PATH")

              # Removed 'c' from -tAc. -tA makes it quiet/unaligned.
              ${config.services.postgresql.package}/bin/psql -tA <<EOF
                ALTER USER ${svc} WITH PASSWORD '$PASSWORD';
      EOF
            fi
    '') servicesWithDB;
  };
  system.stateVersion = "25.11";
}
