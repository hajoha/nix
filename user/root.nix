{ pkgs, ... }:

{
  root = {
    home = "/root";
    extraGroups = [ "wheel" ];
    hashedPassword = "$y$j9T$KoJZYdUoVmcHtV2WqGGDC.$w.j2Nsk3il2ynwxdYprCAU5TlN0yn70fC5qp6Rsn1H/";
    packages = with pkgs; [
      tree
      vim
      nano
      tmux
      git
    ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIocRHpz5SimboTEV6r/YGafvLqNO5qH//VdzcInV/CB hajoha"
    ];
  };
}
