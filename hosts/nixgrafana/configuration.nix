{
  config,
  pkgs,
  modulesPath,
  ...
}:

{
  networking.hostName = "nix-zitadel";
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ./../../services/grafana/default.nix
    ./../../services/ssh/root.nix
  ];
  users.users = import ./../../user/root.nix { inherit pkgs; };
  virtualisation.lxc.enable = true;
  boot.isContainer = true;
  fileSystems."/".device = "/dev/root";
  boot.loader.grub.enable = false;
  systemd.services."sys-kernel-debug.mount".enable = false;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ./secrets/grafana-creds.enc.yaml;
  networking.firewall.allowedTCPPorts = [ 3000 ];
  sops.secrets.dsp25-ssh = {
    sopsFile = ./secrets/ssh-creds.enc.yaml;
  };
  services.autossh.sessions = [
    {
      extraArguments = "-N -T -F /etc/ssh/ssh_config dsp25-main-influx";
      monitoringPort = 20000;
      name = "dsp25-main-influx";
      user = "root";
    }
  ];
  programs.ssh.extraConfig = "
Include ${config.sops.secrets.dsp25-ssh.path}
  ";
programs.ssh.startAgent = true;
  networking = {
    defaultGateway = {
      address = "10.60.1.1";
      interface = "service";
    };
    interfaces.service = {
      ipv4 = {
        addresses = [
          {
            address = "10.60.1.25";
            prefixLength = 24;
          }
        ];
        routes = [
#          {
#            address = "141.23.28.221";
#            prefixLength = 32;
#            via = "10.60.1.25";
#          }
          {
            address = "10.60.1.0";
            prefixLength = 24;
            via = "10.60.1.25";
          }
        ];
      };
    };
  };

  system.stateVersion = "24.05";

}
