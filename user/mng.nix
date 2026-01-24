{ pkgs, ... }:

{
  mng = {
    isNormalUser = true;
    description = "Default User";
    home = "/home/mng";
    extraGroups = [ "wheel" ];
    hashedPassword = "$6$z8fny9TfC1DlKjUb$M17rvaZ4gfMBYmsjkjDPuMIfEguhzN84Xp4h/zLGw9itbFKiB7JuvP4G9id7MWvsAu7rmYeuoLPuZSMoywBwB1";
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
