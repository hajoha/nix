{
  pkgs,
  python39,
  lib,
  fetchPypi,
}:

python39.pkgs.buildPythonPackage rec {
  pname = "ryu";
  version = "4.34";

  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-oxBB61Ou4MNspChkWtJgcWPKXhOQ9aPW7yAlt4Kc6T4=";
  };

  postPatch = ''
    # Remove setup_requires=['pbr'], which triggers pip at build time
    sed -i "/setup_requires/d" setup.py

    # Patch out deprecated Eventlet API: ALREADY_HANDLED
    sed -i "s/from eventlet.wsgi import ALREADY_HANDLED/ALREADY_HANDLED = object()/" \
      ryu/app/wsgi.py
  '';

  propagatedBuildInputs = with python39.pkgs; [
    eventlet
    greenlet
    oslo-serialization
    oslo-utils
    oslo-log
    oslo-config
    routes
    webob
    six
    msgpack
    netaddr

    # your local modules
    (import ./../tinyrpc/default.nix {
      inherit pkgs python39;
      lib = pkgs.lib;
      fetchPypi = pkgs.fetchPypi;
    })
    (import ./../ovs/default.nix {
      inherit pkgs python39;
    })
  ];

  # Disable pbr versioning (we removed pbr)
  PBR_VERSION = version;
  SETUPTOOLS_SCM_PRETEND_VERSION = version;

  doCheck = false;
}
