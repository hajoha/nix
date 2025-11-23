{
  config,
  pkgs,
  modulesPath,
  old-nixpkgs,
  ...
}:
let
  python39 = old-nixpkgs.python39;

  myPython = python39.withPackages (
    ps: with ps; [
      pip
      setuptools
      mininet-python
      (import ./../../pkgs/ryu/pypi.nix {
        inherit
          pkgs
          python39
          lib
          fetchPypi
          ;
      })
    ]
  );
in
{

  networking.hostName = "nix-mininet";

  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ./../../services/ssh/root.nix

  ];
  services.openssh.settings.PermitRootLogin = pkgs.lib.mkForce "yes";
  users.users = import ./../../user/root.nix {
    inherit pkgs;
    hashedPassword = "$6$FhHHCctDLMQVH7If$o5iW.2rN9Ncmoyt/hOmuTwH4/ykQnzZh3QHFyXFEPP40lcWSO0uNdeVyWpG4pnDR7hkHfWM8grglXlksZ8aTs0";
  };

  virtualisation.lxc.enable = true;
  boot.isContainer = true;

  fileSystems."/".device = "/dev/root";
  boot.loader.grub.enable = false;
  systemd.services."sys-kernel-debug.mount".enable = false;

  networking.interfaces.eth0.ipv4.addresses = [
    {
      address = "10.0.3.2";
      prefixLength = 24;
    }
  ];

  networking.defaultGateway = {
    address = "10.0.3.1";
    interface = "eth0";
  };

  virtualisation.vswitch.enable = true;

  environment.systemPackages =
    with pkgs;
    [
      mininet
      xterm
      inetutils
      iperf3
      iperf2
      btop
      uv
      wget
    ]
    ++ [ myPython ];

  system.stateVersion = "24.05";
}
