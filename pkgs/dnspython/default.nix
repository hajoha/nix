{
  python39,
  lib,
  fetchPypi,
}:

python39.pkgs.buildPythonPackage rec {
  pname = "dnspython";
  version = "v1.16.0";

  src = fetchPypi {
    inherit pname version;
    sha256 = ""; # use `nix-prefetch-pypi dnspython==1.16.0`
  };

  doCheck = false;

  meta = with lib; {
    description = "DNS toolkit for Python";
    #    license = lib.licenses.psf;
    homepage = "https://www.dnspython.org/";
  };
}
