{
  nodes,
  lib,
  ...
}:
{
  programs.ssh.extraConfig = lib.concatStrings (
    lib.mapAttrsToList (name: node: ''
      Host home-${name}
        HostName ${node.ip}
        User root

    '') nodes
  );
}
