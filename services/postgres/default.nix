{
  config,
  pkgs,
  lib,
  ...
}:
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    enableTCPIP = true;
    ensureDatabases = [
      "zitadel"
      "hass"
    ];
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
        name = "admin";
      }
    ];
    authentication = lib.mkOverride 10 ''
      # GENERATED
      local all all trust
      host all all 10.60.1.0/24 scram-sha-256

    '';

  };

  networking.firewall.allowedTCPPorts = [
    5432
  ];
}
