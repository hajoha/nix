# Data volumes that stay on the HDD pool (they were mpN subvolumes on
# Proxmox): container -> { path inside the container = old Proxmox subvol }.
# On the host each one is <pool>/containers/<node>/<basename path>, mounted
# at /var/lib/nixos-containers/<node><path>. The container roots themselves
# are plain directories on the NVMe.
{
  nix-opencloud."/var/lib/opencloud/data" = "subvol-101-disk-0";
  nix-postgres."/var/lib/postgresql" = "subvol-105-disk-0";
  nix-arr."/data" = "subvol-106-disk-0";
  nix-immich."/var/lib/immich" = "subvol-113-disk-0";
}
