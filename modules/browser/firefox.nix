{ pkgs, inputs, ... }:
{
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (pkgs.lib.getName pkg) [
      "onepassword-password-manager"
    ];
  programs.firefox = {
    enable = true;
    profiles.hajoha = {

      search.engines = {
        "Nix Packages" = {
          urls = [{
            template = "https://search.nixos.org/packages";
            params = [
              { name = "type"; value = "packages"; }
              { name = "query"; value = "{searchTerms}"; }
            ];
          }];

          icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
          definedAliases = [ "@np" ];
        };
      };
      search.force = true;
      #bookmarks = [];
      settings = {
        "dom.security.https_only_mode" = true;
        "browser.download.panel.shown" = true;
        "identity.fxaccounts.enabled" = false;
        "signon.rememberSignons" = false;
      };

      userChrome = ''                         
        /* some css */                        
      '';

      extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
        ublock-origin
        sponsorblock
        onepassword-password-manager
        youtube-shorts-block
      ];

    };
  };
}
