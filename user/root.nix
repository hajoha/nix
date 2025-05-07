{ pkgs, ... }:

{
  mng = {
    description = "Root User";
    home = "/root";
    extraGroups = [ "wheel" ];
    hashedPassword =
      "$y$j9T$8ZMvqBDVPPpxpYJnjLmGj/$i9cecl/Nsoo7fblDwGUDo4s0Ufguv1meIczJkObiAGC";
    packages = with pkgs; [ tree vim nano tmux git ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIocRHpz5SimboTEV6r/YGafvLqNO5qH//VdzcInV/CB hajoha"
    ];
  };
}
