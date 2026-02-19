{
  config,
  lib,
  pkgs,
  self,
  nodes,
  baseDomain,
  ...
}:

let
  # 1. Internal Services List
  # These names must match the keys in your network.nix nodes set
  backendServices = [
    "nixadguard"
    "nixpostgres"
    "nixzitadel"
    "nixpaperless"
    "nixhedgedoc"
    "nixlms"
    "nixinflux"
    "nixgrafana"
    "nixhomeassistant"
    "nixheadscale"
  ];

  # 2. Generator for backend containers
  mkBackend = name: {
    autoStart = true;
    privateNetwork = true;
    hostBridge = "br-int";

    config =
      { ... }:
      {
        # Inject the shared arguments into the container's evaluation scope
        _module.args = {
          inherit nodes baseDomain;
          inherit (self) inputs;
        };

        # Pull the module definition from the Flake's nixosConfigurations
        imports = self.nixosConfigurations.${name}._module.args.modules;

        boot.isContainer = true;
        networking.useDHCP = false;

        # Dynamically assign the IP from network.nix
        networking.interfaces.eth0.ipv4.addresses = [
          {
            address = nodes.${name}.ip;
            prefixLength = 24;
          }
        ];
      };
  };

in
{
  # --- HOST HARDWARE & CORE ---
  imports = [
    ./hardware-configuration.nix
    ./../../services/ssh/default.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";

  # Restore your user management
  users.users = import ./../../user/mng.nix { inherit pkgs; };

  # --- NETWORKING (Bridges + Physical) ---
  networking = {
    hostName = "nix-nas";

    # Bridges
    bridges."br-lan".interfaces = [ "enp3s0f1np1" ];
    bridges."br-int".interfaces = [ ]; # Virtual bridge for 172.16.0.x

    interfaces = {
      # Physical Management (Static)
      eno1.ipv4.addresses = [
        {
          address = "10.60.0.20";
          prefixLength = 24;
        }
      ];

      # The Bridge IP (The Host's identity on the 10.60.1.x network)
      br-lan.ipv4.addresses = [
        {
          address = "10.60.1.120";
          prefixLength = 24;
        }
      ];

      # The Gateway for your Containers on the internal bridge
      br-int.ipv4.addresses = [
        {
          address = "172.16.0.1";
          prefixLength = 24;
        }
      ];

      # VLAN OOB (Out of Band)
      oob.ipv4.addresses = [
        {
          address = "192.168.0.120";
          prefixLength = 24;
        }
      ];
    };

    vlans = {
      oob = {
        id = 4000;
        interface = "enp3s0f1np1";
      };
    };
  };

  # --- CONTAINER ORCHESTRATION ---
  # Generate all standard backends automatically
  containers = (lib.genAttrs backendServices mkBackend) // {

    # Nginx requires special multi-interface handling
    nixnginx = {
      autoStart = true;
      privateNetwork = true;
      extraFlags = [
        "--network-bridge=br-lan"
        "--network-bridge=br-int"
      ];
      config =
        { ... }:
        {
          _module.args = {
            inherit nodes baseDomain;
            inherit (self) inputs;
          };

          imports = self.nixosConfigurations.nixnginx._module.args.modules;
          boot.isContainer = true;
          networking.interfaces = {
            # eth0 -> br-lan (10.60.1.x)
            eth0.ipv4.addresses = [
              {
                address = "10.60.1.121";
                prefixLength = 24;
              }
            ];
            # eth1 -> br-int (172.16.0.x)
            eth1.ipv4.addresses = [
              {
                address = nodes.nixnginx.ip;
                prefixLength = 24;
              }
            ];
            # eth2 -> oob (192.168.0.x)
            eth2.ipv4.addresses = [
              {
                address = "192.168.0.121";
                prefixLength = 24;
              }
            ];
          };
        };
    };
  };

  # --- SYSTEM UTILS ---
  environment.systemPackages = with pkgs; [
    vim
    wget
    tcpdump
    ethtool
    iperf3
    jq
    git
  ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 2d";
  };

  # Allow the mng user to manage the system
  security.sudo.extraRules = [
    {
      users = [ "mng" ];
      commands = [
        {
          command = "ALL";
          options = [ "NOPASSWD" ];
        }
      ];
    }
  ];

  system.stateVersion = "25.11";
}
