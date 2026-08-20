{
  config,
  lib,
  pkgs,
  nodes,
  baseDomain,
  ...
}:
{

  # Only the feed-crypt key stays as a tt-rss-specific secret.
  # The DB password itself now comes from the shared postgres module's
  # per-service secret (../postgres/default.nix expects
  # ../tt-rss/postgres.enc.yaml, key "password", owned by "postgres" for
  # the sync service). We add a second read of that same file/key here,
  # owned by tt_rss, so the app itself can authenticate.
  sops.secrets."tt-rss-feed-crypt-key" = {
    sopsFile = ./secrets.enc.yaml;
    owner = "tt_rss";
    group = "tt_rss";
    mode = "0440";
  };

  sops.secrets."tt-rss-db-password" = {
    sopsFile = ./postgres.enc.yaml; # same file the postgres module reads via ../tt-rss/postgres.enc.yaml
    key = "password";
    owner = "tt_rss";
    group = "tt_rss";
    mode = "0440";
  };

  services.tt-rss = {
    enable = true;

    virtualHost = null;
    selfUrlPath = "https://rss.${baseDomain}/";

    database = {
      type = "pgsql";

      # Don't let the module manage its own DB/user — the shared
      # postgres.nix already creates "tt-rss" as both DB name and
      # owning role via `servicesWithDB` / `ensureDatabases` / `ensureUsers`.
      createLocally = false;

      # If tt-rss runs on the same host as postgresql, leave host = null
      # to go over the unix socket, which hits the "local ... trust" rule
      # in your pg_hba config (no password needed).
      # If tt-rss runs on a different node, point this at the postgres
      # host's address on the 10.60.1.0/24 subnet instead, e.g.:
      host = nodes.nix-postgres.address;
      # host = null;

      name = "tt-rss";
      user = "tt-rss";
      passwordFile = config.sops.secrets."tt-rss-db-password".path;
    };

    auth = {
      autoCreate = false;
      autoLogin = false;
    };

    feedCryptKey = builtins.readFile config.sops.secrets."tt-rss-feed-crypt-key".path;

    sessionCookieLifetime = 86400;
    simpleUpdateMode = false;
    forceArticlePurge = 0;
    enableGZipOutput = true;

    registration.enable = false;

    email = {
      server = "localhost:25";
      fromName = "Tiny Tiny RSS";
      fromAddress = "tt-rss@${baseDomain}";
      digestSubject = "[tt-rss] New headlines for last 24 hours";
    };

    plugins = [
      "auth_internal"
      "note"
      # "auth_remote"  # uncomment + add via pluginPackages if you wire up SSO
    ];

    logDestination = "sql";

    updateDaemon.commandFlags = "--quiet";
  };
}
