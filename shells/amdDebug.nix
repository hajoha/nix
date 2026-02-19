{
  pkgs ? import <nixpkgs> { },
}:

pkgs.mkShell {
  name = "amd_s2idle-shell";

  buildInputs = [
    pkgs.python312
    pkgs.python312Packages.requests
    pkgs.python312Packages.pyyaml
    pkgs.python312Packages.distro
    pkgs.python312Packages.pyudev
    pkgs.python312Packages.systemd
    pkgs.python312Packages.setuptools
    pkgs.python312Packages.packaging
    pkgs.ethtool
    pkgs.acpica-tools
  ];

  shellHook = ''
    echo "Activating Nix shell for amd_s2idle.py"
    echo "You can now run 'python3 amd_s2idle.py'"
  '';
}
