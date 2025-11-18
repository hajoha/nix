{
  python39,
  lib,
  fetchFromGitHub,
}:

python39.pkgs.buildPythonPackage rec {
  pname = "ryu";
  version = "4.34";

  src = fetchFromGitHub {
    owner = "faucetsdn";
    repo = "ryu";
    rev = "v${version}";
    sha256 = "sha256-ywv4MvY45vENVRcdKP+54FY0+9+rsc4RW8eTK2ds9nk=";
  };
  doCheck = false;
  propagatedBuildInputs = with python39.pkgs; [
    netaddr
    oslo-serialization
    oslo-utils
    oslo-log
    oslo-config
    requests
    eventlet
    routes
    six
    #    (import ./../eventlet/default.nix { inherit python39 lib fetchPypi; })
    webob
    (import ./../tinyrpc/default.nix {
      inherit pkgs python39;
      lib = pkgs.lib;
      fetchPypi = pkgs.fetchPypi;
    })
    (import ./../ovs/default.nix {
      inherit pkgs python39;
    })
  ];

  meta = with lib; {
    description = "Ryu SDN Framework";
    license = licenses.asl20;
    maintainers = [ ];
  };
}
