{
  config,
  pkgs,
  modulesPath,
  ...
}:

{
  networking.hostName = "nix-headscale";
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ./../../services/headscale/default.nix
    ./../../services/ssh/root.nix
  ];
  users.users = import ./../../user/root.nix { inherit pkgs; };
  virtualisation.lxc.enable = true;
  boot.isContainer = true;
  fileSystems."/".device = "/dev/root";
  boot.loader.grub.enable = false;
  systemd.services."sys-kernel-debug.mount".enable = false;
  nix.settings.trusted-users = [ "root" ];
  environment.systemPackages = [
    pkgs.unixtools.netstat

  ];

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ./secrets/creds.enc.yaml;
  sops.secrets."headplane/OIDC_CLIENT_SECRET" = {
    owner = "headscale";
  };
  sops.secrets."headplane/serverCookieSecret" = {
    owner = "headscale";
  };
  sops.secrets."headplane/integrationAgentPreAuthkeyPath" = {
    owner = "headscale";
  };
  sops.secrets."headplane/oidcHeadscaleApiKey" = {
    owner = "headscale";
  };

  services.headplane = {
    enable = true;
    debug = true;
    settings = {
      server = {
        host = "0.0.0.0";
        port = 3000;
        cookie_secure = false;

        # Using `sops-nix` as an example, can be a path to any file with a secret.
        cookie_secret_path = config.sops.secrets."headplane/serverCookieSecret".path;
      };
      headscale = {
         url = "https://headscale.johann-hackler.com";
#        url = "localhost:8080";
#        url = http://10.60.0.22:8080;
        #        config_path = "${headscaleConfig}";
      };
      integration.agent = {
        enabled = false;
        # Using `sops-nix` as an example, can be a path to any file with a secret.
        pre_authkey_path = config.sops.secrets."headplane/integrationAgentPreAuthkeyPath".path;
      };
      oidc = {
        issuer = "https://zitadel.johann-hackler.com";
        client_id = "343314794796875797";
        # Using `sops-nix` as an example, can be a path to any file with a secret.
        client_secret_path = config.sops.secrets."headplane/OIDC_CLIENT_SECRET".path;
        disable_api_key_login = false;
        # Might needed when integrating with Authelia.
        token_endpoint_auth_method = "client_secret_basic";
        # Using `sops-nix` as an example, can be a path to any file with a secret.
        headscale_api_key_path = config.sops.secrets."headplane/oidcHeadscaleApiKey".path;
        redirect_uri = "https://headscale.johann-hackler.com/admin/oidc/callback";
      };
    };
  };
  networking.firewall.allowedTCPPorts = [
    3000
    8080
  ];
  system.stateVersion = "24.05";
}
