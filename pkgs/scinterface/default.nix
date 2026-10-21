{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "scinterface";
  version = "8.3.4";

  src = pkgs.fetchurl {
    url = "https://www.pki.fraunhofer.de/images/stories/files/downloads/treiber/middleware/linux/cv/SCinterface_8_3_13_Ubuntu.zip";
    sha256 = "sha256-MyjknT4243Pzl6C0xwJUxXrqGt0PXx/dPikb41ummnQ=";
  };

  nativeBuildInputs = [
    pkgs.unzip
    pkgs.dpkg
    pkgs.autoPatchelfHook
  ];

  buildInputs = [
    pkgs.stdenv.cc.cc.lib
    pkgs.pcsclite
    pkgs.openssl
    pkgs.zlib
  ];

  unpackPhase = ''
    unzip $src
    DEBFILE=$(find . -name "*Ubuntu24.04-x86_64.deb" | head -n 1)
    mkdir -p extracted
    dpkg-deb -x "$DEBFILE" extracted/
  '';

  installPhase = ''
    mkdir -p $out/lib
    # Copy the libraries
    find extracted -name "*.so*" -exec cp -v {} $out/lib/ \;

    # Copy the configuration file (Crucial for Cryptovision)
    cp -v SCinterface_8_3_13/support/cvP11.ini $out/lib/cvP11.ini

    # Force the symlink for pcsc-lite
    ln -sf ${pkgs.lib.getLib pkgs.pcsclite}/lib/libpcsclite.so.1 $out/lib/libpcsclite.so.1
  '';
}
