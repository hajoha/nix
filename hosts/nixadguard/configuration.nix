{
  config,
  pkgs,
  modulesPath,
  ...
}:

{
  networking.hostName = "nix-adguard";
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ./../../services/adguardhome/default.nix
    ./../../services/ssh/root.nix
  ];
  users.users = import ./../../user/root.nix { inherit pkgs; };
  virtualisation.lxc.enable = true;
  boot.isContainer = true;
  fileSystems."/".device = "/dev/root";
  boot.loader.grub.enable = false;
  systemd.services."sys-kernel-debug.mount".enable = false;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ./secrets/adguard-creds.enc.yaml;
  sops.secrets."ADGUARD_PASSWORD" = {
#    owner = "adguardhome";
   };
  environment.systemPackages = [
    pkgs.dnslookup
    pkgs.dig
  ];

  system.stateVersion = "24.05";
}
