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
    ./../../services/lms/default.nix
    ./../../services/ssh/root.nix
  ];
  users.users = import ./../../user/root.nix { inherit pkgs; };
  virtualisation.lxc.enable = true;
  boot.isContainer = true;
  fileSystems."/".device = "/dev/root";
  boot.loader.grub.enable = false;
  systemd.services."sys-kernel-debug.mount".enable = false;
    environment.systemPackages = [
    pkgs.socat
  ];
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc
      glibc
      zlib
      openssl
      libogg
      libvorbis
      ffmpeg
      alsa-lib
    ];
  };
networking.firewall.enable = false;

#  networking.firewall.allowedTCPPorts = [
#    9000
#    9090
#    3483
#    49152
#    58251
#    57881
#  ];
#  networking.firewall.allowedUDPPorts = [
#    3483
#    49837
#    50119
#    50119
#    59110
#    1900
#    5353
#  ];
  system.stateVersion = "24.05";
}
