{
  pkgs,
  python39,
  lib,
  fetchPypi,
}:

python39.pkgs.buildPythonPackage rec {
  pname = "tinyrpc";
  version = "1.0.4";
  src = fetchPypi {
    inherit pname version;
    sha256 = "sha256-S0H6uWf7HJePVzvw1gmjsSzDtu1ivTEI9D9XVWN0Y5Y="; # replace with nix-prefetch-url
  };

  propagatedBuildInputs = with python39.pkgs; [
    six
    gevent
    gevent-websocket
    msgpack
    pika
    pytest
    pytest-cov
    pyzmq
    requests
    werkzeug
  ];

  meta = with lib; {
    description = "A tiny RPC library";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
}
