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
  # TODO please change the username & home directory to your own
  home.username = "hajoha";
  home.homeDirectory = "/home/hajoha";
  
  #home.pointerCursor.gtk.enable = true;

  # link the configuration file in current directory to the specified location in home directory
  # home.file.".config/i3/wallpaper.jpg".source = ./wallpaper.jpg;

  # link all files in `./scripts` to `~/.config/i3/scripts`
  # home.file.".config/i3/scripts" = {
  #   source = ./scripts;
  #   recursive = true;   # link recursively
  #   executable = true;  # make all files executable
  # };

  # encode the file content in nix configuration file directly
  # home.file.".xxx".text = ''
  #     xxx
  # '';

  # set cursor size and dpi for 4k monitor
  #xresources.properties = {
  #  "Xcursor.size" = 16;
  #  "Xft.dpi" = 172;
  #};
#  services.flatpak.enable = true;
  # Packages that should be installed to the user profile.
  home.packages = with pkgs; [
    # here is some command line tools I use frequently
    # feel free to add your own or remove some of them
    thefuck
    zsh
    inkscape
    #3d-stuff
    freecad
    orca-slicer
    #cura
    ausweisapp
    spice-gtk
    solaar
    gcc
    # archives
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
    #python312Packages.pip

    # utils
    ripgrep # recursively searches directories for a regex pattern
    jq # A lightweight and flexible command-line JSON processor
    yq-go # yaml processor https://github.com/mikefarah/yq
    eza # A modern replacement for ‘ls’
    fzf # A command-line fuzzy finder

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
