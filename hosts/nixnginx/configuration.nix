{
  config,
  pkgs,
  modulesPath,
  ...
}:

{
  networking.hostName = "nix-nginx";
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ./../../services/nginx/default.nix
    ./../../services/ssh/root.nix
  ];
  users.users = import ./../../user/root.nix { inherit pkgs; } // {
    nginx = {
      extraGroups = [ "acme" ];
    };
  };
  virtualisation.lxc.enable = true;
  boot.isContainer = true;
  fileSystems."/".device = "/dev/root";
  boot.loader.grub.enable = false;
  systemd.services."sys-kernel-debug.mount".enable = false;
  environment.systemPackages = [
    pkgs.tshark
    pkgs.unixtools.netstat
    pkgs.nginx
    pkgs.openssl

  ];

  networking = {
    interfaces.service.ipv4 = {
      routes = [
        {
          address = "10.60.0.0";
          prefixLength = 24;
          via = "10.60.1.1";
        }
      ];
      addresses = [
        {
          address = "10.60.1.17";
          prefixLength = 24;
        }
      ];
    };
  };
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ./secrets/inwx-creds.enc.yaml;
  sops.secrets."INWX_USERNAME" = { };
  sops.secrets."INWX_PASSWORD" = { };
  system.stateVersion = "24.05";
}
