{ config, pkgs, ... }:

{
  networking.firewall.allowedTCPPorts = [ 8001 ];

  services.hedgedoc = {
    enable = true;
    environmentFile = config.sops.secrets."env".path;
    settings = {

      port = 8001;
      protocolUseSSL = true;
      useSSL = false;
      allowEmailRegister = false;
      allowGravatar = false;
      allowAnonymous = true;
      allowAnonymousEdits = true;
      allowFreeURL = true;
      disableNoteCreation = false;
      defaultPermission = "freely";

      allowOrigin = [
        "localhost"
        "hedgedoc.johann-hackler.com"
      ];

      db = {
        database = "hedgedoc";
        dialect = "postgresql";
        host = "10.60.1.20";
        port = 5432;
        username = "hedgedoc";
      };

      debug = true;
      domain = "hedgedoc.johann-hackler.com";
      email = false;
      host = "10.60.1.23";

      oauth2 = {
        authorizationURL = "https://zitadel.johann-hackler.com/oauth/v2/authorize";
        baseURL = "https://zitadel.johann-hackler.com";
        enabled = true;
        provider = "generic";
        scope = "openid email profile";
        tokenURL = "https://zitadel.johann-hackler.com/oauth/v2/token";
        userProfileDisplayNameAttr = "preferred_username";
        userProfileEmailAttr = "email";
        userProfileURL = "https://zitadel.johann-hackler.com/oidc/v1/userinfo";
        userProfileUsernameAttr = "preferred_username";
      };

    };

  };
}
