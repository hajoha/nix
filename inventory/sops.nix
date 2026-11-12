# Generates .sops.yaml from the inventory, so who can decrypt what follows
# the same data as everything else:
#
#   services/<svc>/*.enc.yaml        the node's `age` key + its `sopsReaders`
#   services/<svc>/postgres.enc.yaml  ... + nix-postgres   (nodes with db = true)
#   hosts/<host>/*.enc.yaml          that host's key from keys.nix
#   secrets/pve2.enc.yaml            pve2
#   everything else                  admins only
#
# Admin keys (keys.nix) can always decrypt.
#
#   nix run .#sops-config     rewrite .sops.yaml
#   nix flake check           fails if .sops.yaml is out of date
#   sops updatekeys <file>    re-encrypt an existing file after a change
{ lib }:
let
  inherit (lib)
    concatMapStrings
    concatStringsSep
    filterAttrs
    mapAttrsToList
    ;
  inherit (import ./default.nix { inherit lib; }) nodes;
  keys = import ./keys.nix;
  raw = import ./nodes.nix;

  # recipients are { name, key } so the YAML can say whose key it is
  named = name: key: { inherit name key; };
  admins = mapAttrsToList named keys.admins;
  ageOf = name: named name raw.${name}.age;

  rule = regex: recipients: {
    inherit regex;
    recipients = lib.unique (recipients ++ admins);
  };

  withKey = filterAttrs (_: n: n ? age && nodes.${n.name}.service != null) (
    lib.mapAttrs (name: n: n // { inherit name; }) raw
  );

  nodeRules = lib.concatLists (
    mapAttrsToList (
      name: n:
      let
        dir = "services/${nodes.${name}.service}";
        readers = [ (ageOf name) ] ++ map ageOf (n.sopsReaders or [ ]);
      in
      lib.optional (n.db or false) (
        rule "${dir}/postgres\\.enc\\.yaml$" ([ (ageOf "nix-postgres") ] ++ readers)
      )
      ++ [ (rule "${dir}/.*\\.enc\\.yaml$" readers) ]
    ) withKey
  );

  hostRules = mapAttrsToList (host: key: rule "hosts/${host}/.*\\.enc\\.yaml$" [ (named host key) ]) (
    removeAttrs keys.hosts [ "pve2" ]
  );

  fallbackRules = [
    (rule "secrets/pve2\\.enc\\.yaml$" [ (named "pve2" keys.hosts.pve2) ])
    # Any other service file (incl. postgres.enc.yaml of nodes without a key)
    (rule "services/.*/postgres\\.enc\\.yaml$" [ (ageOf "nix-postgres") ])
    (rule ".*\\.enc\\.(yaml|toml|json|env|ini)$" [ ])
  ];

  rules = nodeRules ++ hostRules ++ fallbackRules;

  renderRule = r: ''
    - path_regex: ${r.regex}
      key_groups:
        - age:
    ${concatMapStrings (k: "      - ${k.key} # ${k.name}\n") r.recipients}'';
in
''
  # GENERATED from inventory/ by `nix run .#sops-config` — do not edit.
  # Change inventory/nodes.nix (age, sopsReaders, db) or inventory/keys.nix.
  creation_rules:
  ${concatStringsSep "" (map renderRule rules)}''
