# Data volumes on the HDD pool: container -> paths inside the container.
# On the host each one is the dataset <pool>/containers/<node>/<basename
# path>, mounted at /var/lib/nixos-containers/<node><path>. The container
# roots themselves are plain directories on the NVMe.
{
  nix-opencloud = [ "/var/lib/opencloud/data" ];
  nix-postgres = [ "/var/lib/postgresql" ];
  nix-arr = [ "/data" ];
  nix-immich = [ "/var/lib/immich" ];
}
