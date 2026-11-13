# The system NVMe (Samsung PM9A1 512G), whole disk for NixOS.
#
# Only this disk is managed by disko. The data pool on the 4 HDDs
# (threetbpool) is deliberately NOT declared here, so `disko --mode destroy`
# can never touch it; it is imported via boot.zfs.extraPools.
{ params, ... }:
{
  disko.devices.disk.nvme = {
    type = "disk";
    device = params.rootDisk;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
            extraArgs = [
              "-n"
              "NIXBOOT"
            ];
          };
        };
        swap = {
          size = "8G";
          content = {
            type = "swap";
            discardPolicy = "both";
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [ "noatime" ];
            extraArgs = [
              "-L"
              "nixos"
            ];
          };
        };
      };
    };
  };
}
