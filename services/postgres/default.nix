{
  config,
  pkgs,
  lib,
  ...
}:

{
  services.postgresql = {
    enable = false;
    authentication = lib.mkOverride 10 ''
      # GENERATED
      local all all trust
      host all all 0.0.0.0/0 scram-sha-256

    '';
    initialScript = pkgs.writeText "backend-initScript" ''
      CREATE ROLE demo WITH LOGIN PASSWORD 'password' CREATEDB;
    '';

  };

  networking.firewall.allowedTCPPorts = [
    5432
  ];
}
