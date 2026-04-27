{ pkgs, config, ... }:
{
  home.packages = with pkgs; [
    ripgrep
    jq
    yq-go
    eza
    fzf
    btop # Generic CLI tools
    zip
    unzip
    p7zip
    ferrishot
    rustdesk
    anydesk
    nautilus
    librepods
    vorta
    opencloud-desktop
    headscale
    _1password-gui
    # mattermost-desktop
    # ... etc
  ];

}
