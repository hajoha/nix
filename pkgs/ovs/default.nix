{ pkgs, python39 }:

python39.pkgs.buildPythonPackage rec {
  pname = "ovs";
  version = "2.6.0";

  src = pkgs.fetchPypi {
    inherit pname version;
    sha256 = "sha256-8w18S/BjmPWw1ZktBGDpDvsbgzQzf9JweOwopcnjTYk="; # from PyPI listing :contentReference[oaicite:2]{index=2}
  };

  propagatedBuildInputs = with python39.pkgs; [
    six
    cffi
    sortedcontainers
    formencode
    pylint
    pycodestyle
    nose
    mock
    autopep8
    # any other dependencies required
  ];

  doCheck = false;

  meta = with pkgs.lib; {
    description = "Python bindings for Open vSwitch (pre‐release v2.6.0.dev2)";
    license = licenses.asl20;
    homepage = "https://pypi.org/project/ovs/";
  };
}
