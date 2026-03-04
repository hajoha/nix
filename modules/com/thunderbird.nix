{ pkgs, config, ... }:
{
  programs.thunderbird = {
    enable = true;
    #  package = pkgs.thunderbird;

    # Change the profile name from "haa" to your actual old folder name:
    profiles."lbmpfe0j.default-release" = {
      isDefault = true;
      # Ensure this matches the folder name exactly

      settings = {
        "mail.openpgp.allow_external_gnupg" = true;
      };
    };
  };

}
