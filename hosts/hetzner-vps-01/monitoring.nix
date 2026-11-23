# Alloy on the VPS: its journal and node metrics go to nix-loki /
# nix-thanos at home over WireGuard (home-openwrt routes 10.60.1.27/.28,
# see wireguard-peers.json), and it probes the public vhosts from outside,
# i.e. what the internet sees (label prober="hetzner-vps-01").
#
# While the tunnel is down Alloy buffers (metrics up to 8h in its WAL, the
# journal by cursor) and sends the backlog with the original timestamps.
{
  lib,
  inventory,
  publicVhosts,
  ...
}:
let
  inherit (inventory) nodes;
in
{
  imports = [ ../../modules/nixos/alloy-agent.nix ];

  homelab.alloy = {
    enable = true;
    instance = "hetzner-vps-01";
    lokiUrl = "http://${nodes.nix-loki.ip}:${toString nodes.nix-loki.port}/loki/api/v1/push";
    remoteWriteUrl = "http://${nodes.nix-thanos.ip}:19291/api/v1/receive";

    probes = lib.genAttrs publicVhosts (h: {
      address = "https://${h}";
      module = "http_up";
    });
  };
}
