{
  config,
  pkgs,
  modulesPath,
  ...
}:

{
  networking.hostName = "nix-zitadel";
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ./../../services/influxv2/default.nix
    ./../../services/ssh/root.nix
  ];
  users.users = import ./../../user/root.nix { inherit pkgs; };
  virtualisation.lxc.enable = true;
  boot.isContainer = true;
  fileSystems."/".device = "/dev/root";
  boot.loader.grub.enable = false;
  systemd.services."sys-kernel-debug.mount".enable = false;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ./secrets/influx-creds.enc.yaml;

  networking.firewall.allowedTCPPorts = [ 8086 ];
  system.stateVersion = "24.05";
}
