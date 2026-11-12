# SSH aliases "home-<node>" for every inventory node (used by nix-build).
{
  config,
  lib,
  ...
}:
{
  programs.ssh.extraConfig = lib.concatStrings (
    lib.mapAttrsToList (name: node: ''
      Host home-${name}
        HostName ${node.ip}
        User root

    '') config.homelab.nodes
  );
}
