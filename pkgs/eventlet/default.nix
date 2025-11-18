{
  python39,
  lib,
  fetchPypi,
}:

python39.pkgs.buildPythonPackage rec {
  pname = "eventlet";
  version = "0.31.1";

  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-uekSYwT6483yA/HxdmC7p5q3xIjgXWAzEnfK5CR/jXY=";
  };

  propagatedBuildInputs = with python39.pkgs; [
    greenlet
    six
    dnspython
    monotonic
    (import ./../dnspython/default.nix { inherit python39 lib fetchPypi; })
  ];
  doCheck = true;

  meta = with lib; {
    description = "Concurrent networking library for Python";
    license = lib.licenses.mit;
    homepage = "https://eventlet.net";
    maintainers = [ ];
  };
}
