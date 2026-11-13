# Fujitsu D3417-A, Xeon E3-1275 v5, NVMe Samsung PM9A1 512G (whole disk NixOS, see disko.nix),
# 4x WD Red 3TB raidz2 (threetbpool).
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

  # File systems + swap: ./disko.nix

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
  hardware.enableRedistributableFirmware = true;
}
