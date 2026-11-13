# Container ssh host keys generated on the laptop (`nix run .#new-node-key
# <node>`) instead of on the host. The private keys are in
# ./container-keys.enc.json (host + admins can decrypt); the node's age key is
# known before the first deploy, so its secrets work right away.
#
# Nodes whose key is not in the file keep the key the host generated for them
# (homelab-container-prepare).
{
  lib,
  pkgs,
  ...
}:
let
  file = ./container-keys.enc.json;
  keyRoot = "/var/lib/homelab/keys";

  # sops keeps the JSON keys in plain text; only the values are encrypted.
  nodes =
    if builtins.pathExists file then
      lib.attrNames (removeAttrs (builtins.fromJSON (builtins.readFile file)) [ "sops" ])
    else
      [ ];

  secretName = node: "container-key-${node}";
in
{
  sops.secrets = lib.genAttrs (map secretName nodes) (
    name:
    let
      node = lib.removePrefix "container-key-" name;
    in
    {
      sopsFile = file;
      format = "json";
      key = node;
    }
  );

  # Runs before the generation step of homelab-container-prepare, which then
  # finds the key in place.
  systemd.services.homelab-container-prepare = {
    path = [ pkgs.diffutils ];
    preStart = lib.concatMapStrings (node: ''
      src=/run/secrets/${secretName node}
      dst=${keyRoot}/${node}/ssh_host_ed25519_key
      if ! cmp -s "$src" "$dst"; then
        echo "installing ssh host key for ${node} from the repo"
        install -d -m 700 ${keyRoot} ${keyRoot}/${node}
        install -m 600 "$src" "$dst"
        ssh-keygen -y -f "$dst" > "$dst.pub"
      fi
    '') nodes;
  };
}
