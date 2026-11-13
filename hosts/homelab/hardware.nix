# pve2: Xeon E3-1275 v5, NVMe WD SN770 1TB (Proxmox keeps p1-p3; NixOS gets
# its own ESP + root in the free space), 4x WD Red 3TB raidz2 (threetbpool).
# Compare with `nixos-generate-config --show-hardware-config` from the
# installer and adjust if it differs.
{
  lib,
  modulesPath,
  ...
}:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.initrd.availableKernelModules = [
    "ahci"
    "xhci_pci"
    "nvme"
    "usbhid"
    "sd_mod"
  ];
  boot.kernelModules = [ "kvm-intel" ];

  # Partitions created during the install (labels, see README).
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/NIXBOOT";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
  hardware.enableRedistributableFirmware = true;
}
