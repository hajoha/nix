# Raw disk image of the whole host (layout from ./disko.nix), built by disko
# in a VM and written to the NVMe with dd:
#
#   nix build .#homelab-image        -> result/nvme.raw  (sparse, imageSize)
#
# The image is smaller than the NVMe; on first boot the root partition (the
# last one) and its ext4 grow to fill the disk.
#
# No secrets end up in the image: the host and every container get fresh ssh
# keys, and the secrets are re-encrypted for them afterwards (README).
{
  disko.devices.disk.nvme.imageSize = "64G";
  disko.memSize = 4096;

  boot.growPartition = true;
  fileSystems."/".autoResize = true;
}
