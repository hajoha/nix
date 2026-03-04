{ pkgs, ... }: {
  home.packages = with pkgs; [
    ripgrep jq yq-go eza fzf tmux zsh
    btop iotop iftop strace ltrace lsof
    zip unzip p7zip xz
    killall usbutils pciutils ethtool lm_sensors
  ];
}