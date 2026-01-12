{
  config,
  pkgs,
  modulesPath,
  ...
}:

{
  networking.hostName = "nix-paperless";
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ./../../services/ssh/root.nix
    ./../../services/paperless/default.nix
  ];
  users.users = import ./../../user/root.nix { inherit pkgs; };
  virtualisation.lxc.enable = true;
  boot.isContainer = true;
  fileSystems."/".device = "/dev/root";
  boot.loader.grub.enable = false;
  systemd.services."sys-kernel-debug.mount".enable = false;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ./secrets/paperless-creds.enc.yaml;

  sops.secrets."paperless-creds/oidcSecret" = {
    owner = "paperless";
  };
  sops.secrets."paperless-creds/env" = {
    owner = "paperless";
  };

  networking.nameservers = [ "10.60.1.16" ];
  system.stateVersion = "24.05";
}
