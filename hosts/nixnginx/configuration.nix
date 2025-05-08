{ modulesPath, config, pkgs, ... }:
let
    IP = "192.168.178.102";
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


  networking.hostName = "nixnginx";
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

    services.nginx = {
      enable = true;
      virtualHosts."netbox.nix.fhain" = {
        locations."/" = {
          proxyPass = "http://192.168.178.101:8001";
          proxyWebsockets = true;
        };
      };
    };


  system.stateVersion = "25.05"; # Did you read the comment?
}
