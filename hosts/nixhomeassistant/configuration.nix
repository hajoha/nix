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
    ./../../services/home-assistant/default.nix
    ./../../services/ssh/root.nix
  ];
  users.users = import ./../../user/root.nix { inherit pkgs; };
  virtualisation.lxc.enable = true;
  boot.isContainer = true;
  fileSystems."/".device = "/dev/root";
  boot.loader.grub.enable = false;
  systemd.services."sys-kernel-debug.mount".enable = false;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ./secrets/home-assistant-creds.enc.yaml;

  sops.secrets."hass_db_url" = {
    owner = "hass";
    path = "/var/lib/hass/secrets.yaml";
    sopsFile = ./secrets/home-assistant-creds.enc.yaml;
  };

  system.stateVersion = "24.05";

  networking.firewall.allowedTCPPorts = [
    8123
    8095
  ];

}
