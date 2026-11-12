{
  config,
  lib,
  pkgs,
  ...
}:

let
  inherit (config.homelab) nodes;
  baseDomain = config.homelab.domain;
in
{
  # Only the DB password needs to be secret here. Unlike tt-rss's
  # feedCryptKey/passwordFile split, CommaFeed's module has no
  # `environmentFile`-adjacent per-field option — instead the whole
  # module supports one `environmentFile` (a systemd EnvironmentFile),
  # which is the *correct* mechanism: it's read by systemd as root
  # before the service drops to its DynamicUser, entirely at runtime,
  # never touching Nix eval or the store. We render that file with a
  # sops template rather than a bare secret, so it can interpolate the
  # decrypted password into a proper KEY=VALUE line.
  sops.secrets."commafeed-db-password" = {
    sopsFile = ./postgres.enc.yaml; # matches ../commafeed/postgres.enc.yaml expected by the shared postgres module
    key = "password";
    # root-only: systemd reads EnvironmentFile as root before setuid,
    # so the app's DynamicUser never needs direct access to this.
    owner = "root";
    group = "root";
    mode = "0400";
  };

  sops.templates."commafeed.env" = {
    owner = "root";
    group = "root";
    mode = "0400";
    content = ''
      CF_DATABASE_PASSWORD=${config.sops.placeholder."commafeed-db-password"}
    '';
  };

  services.commafeed = {
    enable = true;
    user = "commafeed";
    group = "commafeed";

    environmentFile = config.sops.templates."commafeed.env".path;

    environment = {
      # Public URL users hit; TLS terminates at your edge proxy, which
      # forwards to this container over plain HTTP.
      CF_APP_PUBLICURL = "https://rss.${baseDomain}/";

      # Embedded server listens directly on this port/interface — no
      # local nginx or php-fpm middleman needed, unlike tt-rss.
      CF_SERVER_APPLICATIONCONNECTORS_0_TYPE = "http";
      CF_SERVER_APPLICATIONCONNECTORS_0_PORT = 9070;

      # Point at the shared postgres host instead of the module's
      # embedded H2 default, mirroring the tt-rss createLocally=false
      # setup: the DB/role itself is provisioned by the central
      # postgres.nix's `servicesWithDB` list (make sure "commafeed" is
      # added there, alongside "tt-rss").
      CF_DATABASE_DRIVERCLASS = "org.postgresql.Driver";
      CF_DATABASE_URL = "jdbc:postgresql://${nodes.nix-postgres.ip}:5432/commafeed";
      CF_DATABASE_USER = "commafeed";
    };
  };

}
