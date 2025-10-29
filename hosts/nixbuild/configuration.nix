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
    ./../../services/ssh/root.nix
  ];
  users.users = import ./../../user/root.nix { inherit pkgs; };
  virtualisation.lxc.enable = true;
  boot.isContainer = true;
  fileSystems."/".device = "/dev/root";
  boot.loader.grub.enable = false;
  systemd.services."sys-kernel-debug.mount".enable = false;
  nix.settings.trusted-users = [
    "haa"
    "hajoha"
  ];
  nix.settings.sandbox = false;
  system.stateVersion = "24.05";
}
