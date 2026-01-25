{ config, pkgs, modulesPath, nodes, baseDomain, ... }:

{
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ./../../user/root.nix # Standardize your root/admin user
  ];

  # Proxmox LXC Essentials
  boot.isContainer = true;
  networking.useDHCP = false; # Proxmox usually assigns IP via DHCP/Static via UI

  # Optimization for containers
  services.getty.autologinUser = "root";
  systemd.services."sys-kernel-debug.mount".enable = false;

  # Shared Nix Settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Common tools for debugging
  environment.systemPackages = with pkgs; [
    vim wget curl htop tcpdump dnsutils
  ];

  system.stateVersion = "25.11";
}