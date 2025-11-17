{
  config,
  pkgs,
  modulesPath,
  ...
}:

{
  networking.hostName = "nix-mininet";
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
  networking = {
    interfaces.eth0 = {
      ipv4.addresses = [
        {
          address = "10.0.3.2";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "10.0.3.1";
      interface = "eth0";
    };
  };
  virtualisation.vswitch.enable = true;
  environment.systemPackages = with pkgs; [
    mininet
    xterm
    inetutils
    iperf3
    iperf2
    btop
    uv
    (pkgs.python3.withPackages (
      p: with p; [
        distutils
        mininet-python
      ]
    ))
  ];

  system.stateVersion = "24.05";
}
