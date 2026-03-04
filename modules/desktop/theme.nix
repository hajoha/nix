{ pkgs, ... }: {
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark"; # or "Catppuccin-Mocha", "Gruvbox-Dark", etc.
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };

  dconf.settings = {
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = [ "qemu:///system" ];
      uris = [ "qemu:///system" ];

    };
    "org/gnome/desktop/interface".color-scheme = "prefer-dark";
  };

    fonts.fontconfig.enable = true;
  home.packages = with pkgs; [
    noto-fonts-color-emoji # Best overall support
    twemoji-color-font
    fontconfig
    nerd-fonts.symbols-only
    dejavu_fonts
    liberation_ttf
    noto-fonts
    noto-fonts-cjk-sans
    twemoji-color-font
    nerd-fonts.symbols-only
    nerd-fonts.fira-code
    material-icons
    fira-code

    # ... other fonts ...
  ];
}