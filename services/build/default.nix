{
  inputs,
  config,
  nodes,
  ...
}:

{
  imports = [
    inputs.self.nixosModules.ssh-client
  ];
  nix.settings = {
    secret-key-files = [ "/etc/nix/signing-key.sec" ];
    trusted-users = [ "root" ];
  };
}
