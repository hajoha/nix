# Inside every container: services start only once the network is really
# there, i.e. every interface is UP and has its inventory address.
#
#   network-addresses-<iface>   NixOS: link up + address; retried here, as
#                               on a container restart the previous
#                               instance's macvlan (same MAC) can outlive it
#                               until the kernel has torn down its netns,
#                               and until then `ip link set up` fails with
#                               "Address already in use"
#   homelab-network-ready       waits until all addresses are actually set
#                               (up to 5 min), part of network-online.target
#   every service started by multi-user.target (directly or via a target
#   of its own like home-assistant.target)
#                               Requires + After homelab-network-ready,
#                               except early units and the network's own
{
  config,
  lib,
  pkgs,
  ...
}:
let
  ifaces = config.networking.interfaces;
  ready = "homelab-network-ready.service";
  addressUnits = map (i: "network-addresses-${i}") (lib.attrNames ifaces);

  # "<iface> <address/prefix>" for every configured IPv4 address
  expected = lib.concatLists (
    lib.mapAttrsToList (
      i: c: map (a: "${i} ${a.address}/${toString a.prefixLength}") c.ipv4.addresses
    ) ifaces
  );

  # services pulled in by a target of their own, e.g. home-assistant.target
  viaTargets = lib.concatMap (t: t.wants) (
    lib.attrValues (
      lib.filterAttrs (_: t: lib.elem "multi-user.target" t.wantedBy) config.systemd.targets
    )
  );
  isMainService =
    name: unit: lib.elem "multi-user.target" unit.wantedBy || lib.elem "${name}.service" viaTargets;

  # units that bring the network up or run early must not wait for it
  # (only names, wantedBy, before: reading the rendered unit here recurses)
  isEarly =
    name: unit:
    lib.elem name [
      "homelab-network-ready"
      "homelab-ifnames"
      "nscd"
    ]
    || lib.hasPrefix "network-" name
    || lib.hasPrefix "systemd-" name
    || lib.any (t: lib.elem t unit.before) [
      "sysinit.target"
      "basic.target"
      "network-pre.target"
      "network.target"
      "network-online.target"
      "nss-lookup.target"
      "nss-user-lookup.target"
    ];
in
{
  options.systemd.services = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, config, ... }:
        {
          config = lib.mkIf (isMainService name config && !isEarly name config) {
            after = [ ready ];
            requires = [ ready ];
          };
        }
      )
    );
  };

  config.systemd.services =
    lib.genAttrs addressUnits (_: {
      startLimitIntervalSec = 300;
      startLimitBurst = 150;
      serviceConfig = {
        Restart = "on-failure";
        RestartSec = 2;
      };
    })
    // {
      homelab-network-ready = {
        description = "Wait until all interfaces have their addresses";
        wantedBy = [
          "network-online.target"
          "multi-user.target"
        ];
        before = [ "network-online.target" ];
        after = map (u: "${u}.service") addressUnits ++ [ "homelab-ifnames.service" ];
        wants = map (u: "${u}.service") addressUnits;
        # services Require it: a switch must not stop or restart it
        restartIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "6min";
        };
        path = [
          pkgs.iproute2
          pkgs.gnugrep
        ];
        script = ''
          end=$((SECONDS + 300))
          while :; do
            missing=
            ${lib.concatMapStrings (e: ''
              set -- ${e}
              if [ "$(cat /sys/class/net/$1/operstate 2>/dev/null)" != up ] \
                || ! ip -4 -o addr show dev "$1" | grep -qw "inet $2"; then
                missing="$missing $1:$2"
              fi
            '') expected}
            if [ -z "$missing" ]; then
              echo "network ready"
              exit 0
            fi
            if [ "$SECONDS" -ge "$end" ]; then
              echo "still missing after 5 min:$missing" >&2
              exit 1
            fi
            sleep 1
          done
        '';
      };
    };
}
