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
    vorta
    # ... etc
  ];

}
