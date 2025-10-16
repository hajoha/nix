{
  config,
  pkgs,
  modulesPath,
  ...
}:

{
  networking.hostName = "nix-postgres";
  imports = [
    (modulesPath + "/virtualisation/proxmox-lxc.nix")
    ./../../services/postgres/default.nix
    ./../../services/ssh/root.nix
  ];
  users.users = import ./../../user/root.nix { inherit pkgs; };
  virtualisation.lxc.enable = true;
  boot.isContainer = true;
  fileSystems."/".device = "/dev/root";
  boot.loader.grub.enable = false;
  systemd.services."sys-kernel-debug.mount".enable = false;
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.defaultSopsFile = ./secrets/postgres-creds.enc.yaml;
  services.postgresql = {
    enable = true;
    enableTCPIP = true;
    package = pkgs.postgresql_17;
    ensureDatabases = [ "zitadel" ];
    ensureUsers = [
      {
        name = "zitadel";
        ensureDBOwnership = true;
      }
      {
        name = "admin";
      }
    ];
  };
  system.stateVersion = "24.05";
}
