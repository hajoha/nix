# ─────────────────────────────────────────────────────────────────────────────
# Everything about the physical box that the rest of the config needs
# (Fujitsu D3417-A, Xeon E3-1275 v5, 32 GB).
# ─────────────────────────────────────────────────────────────────────────────
{
  hostName = "homelab";

  # 8 hex chars, required by ZFS; the pool was last imported with this id.
  hostId = "c78d3ae7";

  # The NVMe that disko partitions (hosts/homelab/disko.nix), Samsung PM9A1
  # 512G. by-id so no other disk can be picked; the system mounts its
  # partitions by label, this is only used when (re)installing.
  rootDisk = "/dev/disk/by-id/nvme-SAMSUNG_MZVL4512HBLU-00BL7_S67VNF1TB39494";

  # false keeps all containers off, e.g. after a reinstall until the secrets
  # are re-encrypted for the new keys (README).
  startContainers = true;

  # ZFS data pool on the 4 HDDs (stays as it is, gets imported at boot).
  pool = "threetbpool";

  # The NIC that carries the VLAN trunk (onboard I219-LM), named by MAC.
  trunk = "nic0";
  trunkMac = "90:1b:0e:fc:1f:0a";

  # VLAN id for every network a container sits on. The attribute name is the
  # interface name the services use ("service", "iot", ...); the container
  # sees exactly that name.
  vlans = {
    service = 3001; # 10.60.1.0/24
    dmz = 3050; # 10.60.50.0/24 (nginx)
    iot = 3060; # 10.60.60.0/24 (homeassistant)
  };

  # The host's own address (management). Containers are not reachable from
  # the host over their macvlans; go through the router or use
  # `nixos-container root-login <name>`.
  management = {
    vlan = null; # untagged on `trunk`
    address = "10.60.0.4";
    prefixLength = 24;
    gateway = "10.60.0.1";
    nameservers = [
      "10.60.1.16" # adguard (a container on this host)
      "9.9.9.9"
    ];
  };

  # "intel", "amd" or null. Used for /dev/dri (immich ML / jellyfin transcode).
  gpu = "intel"; # HD Graphics P530

  # Device of the Thread/Zigbee radio for homeassistant (by-id path is stable).
  radio = "/dev/serial/by-id/usb-Itead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_V2_90837c5304f4ef11aa21c61b6d9880ab-if00-port0";
}
