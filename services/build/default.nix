{
  inputs,
  config,
  ...
}:

{
  imports = [
    inputs.self.nixosModules.ssh-client
  ];
  nix.settings = {
    secret-key-files = [ "/etc/nix/signing-key.sec" ];
    trusted-users = [ "root" ];

    max-jobs = 1;
    cores = 4;
    keep-outputs = false;
    keep-derivations = false;
  };

  # The daemon owns the build processes, not your shell.
  systemd.services.nix-daemon.serviceConfig = {
    MemoryHigh = "8G";
    MemoryMax = "10G";
  };

  # Builds in /tmp on tmpfs is RAM you don't have.
  systemd.services.nix-daemon.environment.TMPDIR = "/var/tmp";
}
