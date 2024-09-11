{ lib, config, pkgs, inputs,  ... }:
let
  firefoxConfig  = import ./firefox.nix {inherit pkgs; inherit inputs; };
in
{
  nixpkgs = {
    overlays = [
      inputs.nur.overlay
    ];
    config = {
      allowUnfree = true;
    };
  };
  imports = [ firefoxConfig ];

  home.username = "hajoha";
  home.homeDirectory = "/home/hajoha";
  

  home.packages = with pkgs; [

    #3D-stuff
    freecad
    orca-slicer
    #cura

    thefuck
    zsh
    inkscape
    ausweisapp
    spice-gtk
    solaar
    gcc
    zip
    nextcloud-client
    vlc
    xz
    unzip
    p7zip
    jetbrains.pycharm-professional
    android-studio
    tor-browser
    anydesk
    chromium
    gimp
    python312Full
    python312Packages.pyudev
    python312Packages.systemd
    udev
    libvirt
    kvmtool
    ripgrep
    jq
    yq-go
    eza
    fzf

    # networking tools
   mtr # A network diagnostic tool
    iperf3
    dnsutils  # `dig` + `nslookup`
    ldns # replacement of `dig`, it provide the command `drill`
    aria2 # A lightweight multi-protocol & multi-source command-line download utility
    socat # replacement of openbsd-netcat
    nmap # A utility for network discovery and security auditing
    ipcalc  # it is a calculator for the IPv4/v6 addresses

      # nix related
    #
    # it provides the command `nom` works just like `nix`
    # with more details log output
    nix-output-monitor
    firefox

    # productivity
    hugo # static site generator
    glow # markdown previewer in terminal

    btop  # replacement of htop/nmon
    iotop # io monitoring
    iftop # network monitoring

    # system call monitoring
    strace # system call monitoring
    ltrace # library call monitoring
    lsof # list open files

    # system tools
    sysstat
    lm_sensors # for `sensors` command
    ethtool
    pciutils # lspci
    usbutils # lsusb
  ];
  programs.firefox = {
   enable = true; 
  };
  # basic configuration of git, please change to your own
  programs.git = {
    enable = true;
    userName = "hajoha";
    userEmail = "hajoha1@proton.me";
  };
 
  programs.zsh = {
  	enable = true;
  	enableCompletion = true;
  	
	#autosuggestion = true;
  	
	#syntaxHighlighting.enable = true;

  	shellAliases = {
    		ll = "ls -l";
    		update = "sudo nixos-rebuild switch";
  	};
  	
	history = {
    		size = 10000;
    		path = "${config.xdg.dataHome}/zsh/history";
  	};

	oh-my-zsh = {
    		enable = true;
    		plugins = [ "git" "thefuck" ]; 
    		theme = "rkj-repos";
  	};
  };



  dconf.settings = {
  "org/virt-manager/virt-manager/connections" = {
    autoconnect = ["qemu:///system"];
    uris = ["qemu:///system"];
   };
  };
  
  #programs.ausweisapp = {
  # enable = true;
  # openFirewall = true;
  #};
  home.stateVersion = "23.11";

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}
