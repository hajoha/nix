{ pkgs, ... }:
{
  home.packages = with pkgs; [
    gcc
    gnumake
    nixfmt
    (pkgs.jetbrains.plugins.addPlugins pkgs.jetbrains.clion [
      #  pkgs.jetbrains.plugins.github-copilot
    ])
    (pkgs.jetbrains.plugins.addPlugins pkgs.jetbrains.pycharm [
      #  pkgs.jetbrains.plugins.github-copilot
      #  pkgs.jetbrains.plugins.nixidea
    ])

  ];
}
