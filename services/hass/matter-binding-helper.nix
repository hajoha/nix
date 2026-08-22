{
  lib,
  fetchFromGitHub,
  buildHomeAssistantComponent,
  home-assistant,
}:

buildHomeAssistantComponent rec {
  owner = "cedricziel";
  domain = "matter_binding_helper";
  version = "0.1.0"; # pin to a tag/commit, check the repo for latest release

  src = fetchFromGitHub {
    owner = "cedricziel";
    repo = "ha-matter-binding-helper";
    rev = "v${version}"; # or a commit sha
    hash = ""; # leave empty first, nix build will tell you the correct hash
  };

  # add any extra python deps the component needs, if not already in home-assistant.python.pkgs
  # dependencies = with home-assistant.python.pkgs; [ ... ];
}
