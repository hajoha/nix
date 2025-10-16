{
  config,
  pkgs,
  modulesPath,
  ...
}:
let
in
{
  networking.hostName = "nix-zitadel";
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ./../../services/netbird/default.nix
    ./../../services/ssh/root.nix
  ];
  users.users = import ./../../user/root.nix { inherit pkgs; };
  virtualisation.lxc.enable = true;
  boot.isContainer = true;
  fileSystems."/".device = "/dev/root";
  boot.loader.grub.enable = false;
  systemd.services."sys-kernel-debug.mount".enable = false;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ./secrets/creds.enc.yaml;

  sops.secrets."PASSWORD_COTURN" = {};
  sops.secrets."TURN_SECRET" = {};
  sops.secrets."NETBIRD_ZITADEL_PASSWORD" = {};
  sops.secrets."NETBIRD_IDP_MGMT_CLIENT_SECRET" = {};
  sops.secrets."NETBIRD_ENCRYPTION_KEY" = {};
  sops.secrets."COTURN" = {owner = "turnserver";};

  system.stateVersion = "24.05";
}
