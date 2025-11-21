{ pkgs ? import <nixpkgs> {} }:

pkgs.stdenv.mkDerivation rec {
  pname = "wloc";
  version = "0.1.0"; # you can pin to a tag or commit if you want

  src = pkgs.fetchFromGitHub {
    owner = "acheong08";
    repo = "apple-corelocation-experiments";
    rev = "main"; # or a specific commit hash
    sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; # replace with actual hash
  };

  nativeBuildInputs = [ pkgs.go ];

  buildPhase = ''
    export GOPATH=$(pwd)/go
    mkdir -p $GOPATH/src/github.com/acheong08
    ln -s ${src} $GOPATH/src/github.com/acheong08/apple-corelocation-experiments

    cd $GOPATH/src/github.com/acheong08/apple-corelocation-experiments/cmd/wloc
    go build -o $out/wloc
  '';

  installPhase = ''
    mkdir -p $out/bin
    mv $out/wloc $out/bin/
  '';

  meta = with pkgs.lib; {
    description = "Command-line tool to work with Apple CoreLocation experiments";
    homepage = "https://github.com/acheong08/apple-corelocation-experiments";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
  };
}
