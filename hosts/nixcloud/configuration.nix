{ config, pkgs, modulesPath, ... }:

{
  networking.hostName = "nix-cloud";
  imports = [
     (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ./../../services/opencloud/default.nix
    ./../../services/ssh/root.nix
  ];
  users.users = import ./../../user/root.nix { inherit pkgs; };
  virtualisation.lxc.enable = true;
  boot.isContainer = true;
  fileSystems."/".device = "/dev/root";
  boot.loader.grub.enable = false;
  systemd.services."sys-kernel-debug.mount".enable = false;

  system.stateVersion = "24.05";
}