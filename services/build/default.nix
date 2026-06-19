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
}
