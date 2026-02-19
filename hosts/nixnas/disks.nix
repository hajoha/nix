{
  disko.devices = {
    disk = {
      main = {
        device = "/dev/disk/by-id/ata-INTEL_SSDSC2BB240G6_BTWA526208DP240AGN";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              priority = 1;
              start = "1M";
              size = "2G";
              name = "ESP";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
                # Labeling the disk so the kernel finds it easily
                extraArgs = [
                  "-L"
                  "nixos_root"
                ];
              };
            };
          };
        };
      };
    };
  };
}
