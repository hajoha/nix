{
  config,
  pkgs,
  lib,
  nodes,
  ...
}:
let
  # Single source of truth for services requiring a DB and a Secret
  servicesWithDB = [
    "hass"
    "hedgedoc"
    "paperless"
    "immich"
    "keycloak"
    "listmonk"
  ];

  # Helper: Maps a service name to its specific sops secret configuration
  mkSopsSecret = name: {
    sopsFile = ../${name}/postgres.enc.yaml;
    key = "password";
    owner = "postgres";
  };
in
{
  # 1. SOPS Configuration
  sops.secrets = lib.genAttrs (map (svc: "users/${svc}") servicesWithDB) (
    path:
    let
      svc = lib.last (lib.splitString "/" path);
    in
    mkSopsSecret svc
  );

  # 2. PostgreSQL Configuration
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    enableTCPIP = true;

    # Automatically create all databases defined in our list
    ensureDatabases = servicesWithDB;

    # Automatically create all users and assign ownership
    ensureUsers =
      (map (svc: {
        name = svc;
        ensureDBOwnership = true;
      }) servicesWithDB)
      ++ [
        {
          name = "admin";
          ensureClauses.superuser = true;
        }
      ];

    extensions =
      ps: with ps; [
        pgvector
        vectorchord
      ];

    authentication = lib.mkOverride 10 ''
      # Type  Database        User            Address                Method
      local   all             all                                    trust
      host    all             all             10.60.1.0/24           scram-sha-256
      host    all             all             127.0.0.1/32           scram-sha-256
    '';

    settings = {
      max_connections = 100;
      shared_buffers = "256MB";
      listen_addresses = "*";
      shared_preload_libraries = "vchord.so";
    };
  };

  # 3. Password Sync Service
  # This service waits for Postgres to start, then applies passwords from SOPS
  systemd.services.postgresql-password-sync = {
    description = "Sync Postgres passwords from per-service SOPS files";
    after = [
      "postgresql.service"
      "sops-nix.service"
    ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      ExecStartPre = "${config.services.postgresql.package}/bin/pg_isready";
      RemainAfterExit = true;
    };

    script = lib.concatMapStringsSep "\n" (svc: ''
            SECRET_PATH="${config.sops.secrets."users/${svc}".path}"
            if [ -f "$SECRET_PATH" ]; then
              PASSWORD=$(cat "$SECRET_PATH")
              # Use a DO block to safely update password only if user exists
              ${config.services.postgresql.package}/bin/psql -d postgres -tA <<EOF
                DO \$$
                BEGIN
                  IF EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${svc}') THEN
                    EXECUTE format('ALTER USER %I WITH PASSWORD %L', '${svc}', '$PASSWORD');
                  END IF;
                END
                \$$;
      EOF
            fi
    '') servicesWithDB;
  };

  # 4. Immich Specific Extensions
  systemd.services.postgresql-immich-setup = {
    description = "Setup Immich extensions";
    after = [
      "postgresql.service"
      "postgresql-password-sync.service"
    ];
    requires = [ "postgresql.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      ExecStartPre = "${config.services.postgresql.package}/bin/pg_isready";
      RemainAfterExit = true;
    };

    script = ''
            ${config.services.postgresql.package}/bin/psql -d postgres <<EOF
              -- Give immich temporary superuser to manage its own extensions
              ALTER USER immich WITH SUPERUSER;
      EOF

            ${config.services.postgresql.package}/bin/psql -d immich -U immich <<EOF
              -- These will now be OWNED by immich because immich is running them
              CREATE EXTENSION IF NOT EXISTS "unaccent";
              CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
              CREATE EXTENSION IF NOT EXISTS "pg_trgm";
              CREATE EXTENSION IF NOT EXISTS "cube";
              CREATE EXTENSION IF NOT EXISTS "earthdistance";
              CREATE EXTENSION IF NOT EXISTS "vector";
              CREATE EXTENSION IF NOT EXISTS "vchord";

              -- If they already existed, we force an update to make sure
              ALTER EXTENSION vchord UPDATE;
              ALTER EXTENSION vector UPDATE;
      EOF

            ${config.services.postgresql.package}/bin/psql -d postgres <<EOF
              -- Revoke superuser now that setup is done (Security First!)
              ALTER USER immich WITH NOSUPERUSER;
              -- Ensure schema ownership is correct
              \c immich
              ALTER SCHEMA public OWNER TO immich;
      EOF
    '';
  };

  system.stateVersion = "25.11";
}
