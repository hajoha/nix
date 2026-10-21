# Flathunter is not in nixpkgs, so we build it ourselves.
#
# Upstream ships a Pipfile rather than usable packaging metadata, so instead of
# fighting buildPythonApplication we drop the source tree into
# $out/share/flathunter and wrap it with a python3.withPackages interpreter.
#
# BEFORE FIRST BUILD:
#   1. Replace `rev` with a real commit hash (do not track a branch).
#   2. Run `nix build`, copy the "got:" hash into `hash`.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  makeWrapper,
  python3,
  chromium,
  chromedriver,
  # Set to false if you only crawl WG-Gesucht / Immowelt / Idealista, which need
  # no browser. Saves ~2GB of closure.
  withBrowser ? true,
}:
let
  # Not in nixpkgs at the time of writing. Flathunter imports this at module
  # level in its crawlers, so it is not optional.
  # Look up the current version at https://pypi.org/project/requests-random-user-agent/
  requests-random-user-agent = python3.pkgs.buildPythonPackage rec {
    pname = "requests-random-user-agent";
    version = "2022.6.4";
    format = "setuptools";
    src = python3.pkgs.fetchPypi {
      pname = "requests_random_user_agent";
      inherit version;
      hash = "sha256-KmKgRelNWlR+EhgANSTPhWNWX2vMUVNe5e7L74I1+e4=";
    };
    propagatedBuildInputs = [ python3.pkgs.requests ];
    doCheck = false;
    pythonImportsCheck = [ "requests_random_user_agent" ];
  };

  python = python3.withPackages (
    ps:
    with ps;
    [
      # core
      pyyaml
      requests
      urllib3
      lxml
      beautifulsoup4
      jsonpath-ng
      backoff
      pytz
      python-dotenv
      certifi
      jinja2
      cryptography
      pydantic
      setuptools
      requests-random-user-agent

      # notifiers
      apprise

      # config_wizard.py
      prompt-toolkit
      ruamel-yaml

      # only needed for the optional Flask web UI (main.py)
      flask
      werkzeug
      gunicorn
    ]
    ++ lib.optionals withBrowser [
      selenium
      undetected-chromedriver
      # webdriver-manager  # add if your nixpkgs has it and startup complains
    ]
  );
in
stdenvNoCC.mkDerivation {
  pname = "flathunter";
  version = "0-unstable-2026-09-08";

  src = fetchFromGitHub {
    owner = "flathunters";
    repo = "flathunter";
    rev = "6a078d7c65cb84b4a8333893341e189c455c7a6b";
    hash = "sha256-OZGfP4SHu/QaPpSb5gZphfi5ydD25S7UsGC9GdQZFAY="; # replaced after the next build
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/flathunter
    cp -r ./* $out/share/flathunter/

    makeWrapper ${python}/bin/python $out/bin/flathunter \
      --add-flags $out/share/flathunter/flathunt.py \
      --set PYTHONPATH $out/share/flathunter \
      ${lib.optionalString withBrowser ''
        --prefix PATH : ${
          lib.makeBinPath [
            chromium
            chromedriver
          ]
        } \
        --set SE_CHROMEDRIVER ${chromedriver}/bin/chromedriver \
      ''}

    # Optional Flask web UI, see the notes in default.nix
    makeWrapper ${python}/bin/python $out/bin/flathunter-web \
      --add-flags $out/share/flathunter/main.py \
      --set PYTHONPATH $out/share/flathunter

    runHook postInstall
  '';

  meta = {
    description = "Bot that scrapes rental listing sites and notifies you about new offers";
    homepage = "https://github.com/flathunters/flathunter";
    license = lib.licenses.mit;
    mainProgram = "flathunter";
    platforms = lib.platforms.linux;
  };
}
