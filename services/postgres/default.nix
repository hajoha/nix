{ config, pkgs, lib, nodes, ... }:

{
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
      "netbox" # Added NetBox as well
    ];

    # Automated user creation
    ensureUsers = [
      { name = "zitadel";  ensureDBOwnership = true; }
      { name = "hass";     ensureDBOwnership = true; }
      { name = "hedgedoc"; ensureDBOwnership = true; }
      { name = "paperless"; ensureDBOwnership = true; }
      { name = "netbox";    ensureDBOwnership = true; }
      { name = "admin";    ensureClauses.superuser = true; }
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

  # Port management is now handled by mkLXC and network.nix
  # (No manual networking.firewall block needed here)

  system.stateVersion = "25.11";
}