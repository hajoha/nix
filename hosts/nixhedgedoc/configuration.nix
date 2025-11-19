{
  config,
  pkgs,
  modulesPath,
  ...
}:

{
  networking.hostName = "nix-hedgedoc";
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ./../../services/hedgedoc/default.nix
    ./../../services/ssh/root.nix
  ];
  users.users = import ./../../user/root.nix { inherit pkgs; };
  virtualisation.lxc.enable = true;
  boot.isContainer = true;
  fileSystems."/".device = "/dev/root";
  boot.loader.grub.enable = false;
  systemd.services."sys-kernel-debug.mount".enable = false;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ./secrets/hedgedoc-creds.enc.yaml;
  sops.secrets."env" = {
    owner = "hedgedoc";
    restartUnits = [ "hedgedoc.service" ];
  };

  networking.nameservers = [ "10.60.1.16"];
  system.stateVersion = "24.05";
}
