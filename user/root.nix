{ pkgs, ... }:

{
  root = {
    description = "Root User";
    home = "/root";
    extraGroups = [ "wheel" ];
    hashedPassword =
      "$y$j9T$svtRQSf0cMYgZncXlokqY.$3rHDLzmvVirnUGJ515R8795Vg09UEkPERvnuP6sRFa6";
    packages = with pkgs; [ tree vim nano tmux git ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIocRHpz5SimboTEV6r/YGafvLqNO5qH//VdzcInV/CB hajoha"
    ];
  };
}
