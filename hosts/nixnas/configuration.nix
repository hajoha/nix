{ config, lib, pkgs, self, ... }:

let
  # 1. Internal Services List
  backendServices = [
    "nixadguard" "nixpostgres" "nixzitadel" "nixpaperless"
    "nixhedgedoc" "nixlms" "nixinflux" "nixgrafana"
    "nixhomeassistant" "nixheadscale"
  ];

  # 2. Generator for backend containers
mkBackend = name: {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br-int";

    config = { ... }: {
      imports = self.nixosConfigurations.${name}._module.args.modules;
      boot.isContainer = true;
      networking.useDHCP = false;

      # Logic: find the position of the name in the list and add 10
      # (e.g., first item = 0 + 10 = .10, second = 1 + 10 = .11)
      networking.interfaces.eth0.ipv4.addresses = [{
        address = let
          index = lib.lists.findFirstIndex (x: x == name) (throw "not found") backendServices;
        in "172.16.0.${toString (index + 10)}";
        prefixLength = 24;
      }];
    };
  };

in {
  # --- RESTORED HOST HARDWARE & CORE ---
  imports = [
    ./hardware-configuration.nix        # Your physical drive/CPU config
    ./../../services/ssh/default.nix    # Your SSH access
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  # Restore your user
  users.users = import ./../../user/mng.nix { inherit pkgs; };

  # --- NETWORKING (Bridges + Physical) ---
  networking = {
    hostName = "nix-nas";

    # Bridges
    bridges."br-lan".interfaces = [ "enp3s0f1np1" ];
    bridges."br-int".interfaces = []; # Virtual only

    interfaces = {
      # Physical Management
      eno1.ipv4.addresses = [{ address = "10.60.0.20"; prefixLength = 24; }];

      # The Bridge IP (The Host's identity on the 10.60.1.x network)
      br-lan.ipv4.addresses = [{ address = "10.60.1.120"; prefixLength = 24; }];

      # The Gateway for your Containers
      br-int.ipv4.addresses = [{ address = "172.16.0.1"; prefixLength = 24; }];

      # VLAN OOB
      oob.ipv4.addresses = [{ address = "192.168.0.120"; prefixLength = 24; }];
    };

    vlans = {
        oob = { id = 4000; interface = "enp3s0f1np1"; };
    };
  };

  # --- CONTAINER ORCHESTRATION ---
  containers = (lib.genAttrs backendServices mkBackend) // {
    nixnginx = {
      autoStart = true;
      privateNetwork = true;
      extraFlags = [
        "--network-bridge=br-lan"
        "--network-bridge=br-int"
        "--network-vlan=oob"
      ];
      config = { ... }: {
        imports = self.nixosConfigurations.nixnginx._module.args.modules;
        boot.isContainer = true;
        networking.interfaces = {
          eth0.ipv4.addresses = [{ address = "10.60.1.121"; prefixLength = 24; }];
          eth1.ipv4.addresses = [{ address = "172.16.0.2"; prefixLength = 24; }];
          eth2.ipv4.addresses = [{ address = "192.168.0.121"; prefixLength = 24; }];
        };
      };
    };
  };

  # --- RESTORED SYSTEM UTILS ---
  environment.systemPackages = with pkgs; [
    vim wget tcpdump ethtool iperf3
  ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 2d";
  };

  security.sudo.extraRules = [{
    users = [ "mng" ];
    commands = [{ command = "ALL"; options = [ "NOPASSWD" ]; }];
  }];

  system.stateVersion = "25.11";
}