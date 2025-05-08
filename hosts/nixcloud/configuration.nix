{ modulesPath, config, pkgs, ... }:
let
    IP = "192.168.178.103";
in
{
  imports =
    [
      "${modulesPath}/virtualisation/lxc-container.nix"
      ./../../services/ssh/root.nix
    ];
  boot.isContainer = true;

  # I had to suppress these units, since they do not work inside LXC
  systemd.suppressedSystemUnits = [
    "dev-mqueue.mount"
    "sys-kernel-debug.mount"
    "sys-fs-fuse-connections.mount"
  ];


  networking.hostName = "nixcloud";
  networking.domain = "lan";

  networking.interfaces.eth0.ipv4.addresses = [{
    address = IP;
    prefixLength = 24;
  }];
  networking.defaultGateway = "192.168.178.1";
  networking.nameservers = [ "9.9.9.9"];

  # A few packages I like to have around
  environment.systemPackages = with pkgs; [
    openssh
    openssl
  ];
  users.users = import ./../../user/root.nix { inherit pkgs; };



  services = {
    nginx.virtualHosts = {
      "nixcloud.fhain" = {
        forceSSL = false;
        enableACME = false;
      };

      "nixoffice.fhain" = {
        forceSSL = false;
        enableACME = false;
      };
    };

    nextcloud = {
      enable = true;
      hostName = "nixcloud.fhain";

       # Need to manually increment with every major upgrade.
      package = pkgs.nextcloud28;

      # Let NixOS install and configure the database automatically.
      database.createLocally = true;

      # Let NixOS install and configure Redis caching automatically.
      configureRedis = true;

      # Increase the maximum file upload size to avoid problems uploading videos.
      maxUploadSize = "16G";
      https = false;

      autoUpdateApps.enable = true;
      extraAppsEnable = true;
      extraApps = with config.services.nextcloud.package.packages.apps; {
        # List of apps we want to install and are already packaged in
        # https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/nextcloud/packages/nextcloud-apps.json
        inherit calendar contacts mail notes onlyoffice tasks;

      };

      config = {
        overwriteProtocol = "https";
        defaultPhoneRegion = "PT";
        dbtype = "pgsql";
        adminuser = "admin";
        adminpassFile = import ./../../passw/nextcloud.txt;
      };
    };
    onlyoffice = {
      enable = true;
      hostname = "nixoffice.fhain";
    };
  };








  system.stateVersion = "25.05"; # Did you read the comment?
}
