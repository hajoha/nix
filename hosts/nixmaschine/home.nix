{ lib, config, system, pkgs, inputs, ... }:
    let
      firefox-config = import ./../../modules/browser/firefox.nix {inherit pkgs; inherit inputs; };
      pkgs-unstable = import inputs.nixpkgs-unstable {system="x86_64-linux"; config.allowUnfree = true;};
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
  imports = [
    firefox-config
  ];


  home.packages = with pkgs; [
    # 3D-stuff
    freecad
    orca-slicer
    #cura
    ffmpeg
    libqmi
    tmux
    thefuck
    zsh
    inkscape
    ausweisapp
    spice-gtk
    solaar
    gcc
    zip
    tio
    nextcloud-client
    vlc
    xz
    unzip
    p7zip
    jetbrains.pycharm-professional
    jetbrains.clion
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
    signal-desktop
    mtr
    iperf3
    dnsutils
    ldns
    aria2
    socat
    nmap
    ipcalc
    nix-output-monitor
    firefox
    hugo
    glow
    btop
    iotop
    iftop
    strace
    ltrace
    lsof
    sysstat
    lm_sensors
    ethtool
    pciutils
    usbutils
    android-tools
  ] ++ [
    pkgs-unstable.android-studio
    pkgs-unstable.ollama
  ];

  programs.firefox = {
    enable = true;
  };

  programs.git = {
    enable = true;
    userName = "hajoha";
    userEmail = "hajoha1@proton.me";
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;

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

  home.stateVersion = "23.11";

  # Let home Manager install and manage itself.
  programs.home-manager.enable = true;
}
