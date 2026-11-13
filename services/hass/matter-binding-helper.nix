{
  lib,
  fetchzip,
  buildHomeAssistantComponent,
  home-assistant,
}:

buildHomeAssistantComponent rec {
  owner = "cedricziel";
  domain = "matter_binding_helper";
  version = "0.35.3";
  src = fetchzip {
    url = "https://github.com/cedricziel/ha-matter-binding-helper/releases/download/v${version}/matter_binding_helper.zip";
    stripRoot = false;
    hash = "sha256-MHPFyP1MJr8sonwe2+/0U9fMi7E5kDq80I8RRcpMhso="; # nix build will report the correct one — paste it in
  };

  # Generated automations carry `initial_state: false`, which makes Home
  # Assistant switch them off on every start (ignoring the restored state).
  # Without it HA keeps whatever on/off state they had before the restart.
  postPatch = ''
    substituteInPlace automation_generator.py \
      --replace-fail '"initial_state": False,  # Disabled by default per user preference' ""
  '';
}
