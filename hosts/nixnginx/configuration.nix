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
    ./../../services/zitadel-proxy/default.nix
  ];
  users.users = import ./../../user/root.nix { inherit pkgs; };
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

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ./secrets/inwx-creds.enc.yaml;
  sops.secrets."INWX_USERNAME" = { };
  sops.secrets."INWX_PASSWORD" = { };
  system.stateVersion = "24.05";
}
