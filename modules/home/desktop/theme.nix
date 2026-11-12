{ pkgs, ... }:
{
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

  xdg.configFile."fontconfig/conf.d/10-nix-fonts.conf".text = ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
    <fontconfig>
      <dir>/usr/share/fonts</dir>
      <dir>/usr/local/share/fonts</dir>
      <dir>~/.local/share/fonts</dir>
    </fontconfig>
  '';

  home.packages = with pkgs; [
    noto-fonts-color-emoji # Best overall support
    twemoji-color-font
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

    inter
    nerd-fonts.arimo
    nerd-fonts.tinos
    nerd-fonts.cousine

  ];
}
