{
  pkgs,
  inputs,
  config,
  baseDomain,
  ...
}:
{
  programs.firefox = {
    enable = true;

    policies = {
      Cookies = {
        Allow = [
          "https://teams.microsoft.com"
          "https://login.microsoftonline.com"
          "https://login.live.com"
          "https://teams.live.com"
          "https://skype.com"
          "https://teams.skype.com"
          "https://microsoft.com"
          "https://soundcloud.com"
        ];
      };
      Permissions = {
        Autoplay.Default = "block-audio";
        Camera.BlockNewRequests = false;
        Microphone.BlockNewRequests = false;
        Location.BlockNewRequests = false;
        Notifications.BlockNewRequests = false;
        ScreenShare.BlockNewRequests = false;
        VirtualReality.BlockNewRequests = true;
      };
      EnableTrackingProtection = {
        Category = "standard";
        Cryptomining = true;
        Fingerprinting = false;
        Value = true;
      };
      HardwareAcceleration = true;
      DisableTelemetry = true;
      DisableFirefoxAccounts = true;
    };

    profiles.haa = {
      isDefault = true;
      id = 0;

      extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
        ublock-origin
        sponsorblock
        onepassword-password-manager
        youtube-shorts-block
        zotero-connector
      ];

      settings = {
        "sidebar.position_start" = true;
        "sidebar.visible" = true;
        "sidebar.visibility" = "always"; # or "expand-on-hover", or "hide-sidebar"
        "sidebar.verticalTabs.collapsed" = true;
        "sidebar.main.tools" = "tabs,bookmarks";
        "sidebar.revamp" = true;
        "sidebar.verticalTabs" = true;

        "dom.storage_access.enabled" = true;
        "dom.storage.enabled" = true;
        "network.cookie.cookieBehavior" = 0;
        "network.cookie.cookieBehavior.optInPartitioning" = false;
        "network.cookie.CHIPS.enabled" = false;
        "network.cookie.same-site.laxByDefault" = false;
        "privacy.firstparty.isolate" = false;

        "privacy.clearOnShutdown.cookies" = false;
        "privacy.clearOnShutdown.sessions" = false;
        "privacy.clearOnShutdown.cache" = false;
        "privacy.sanitize.sanitizeOnShutdown" = false;

        "media.peerconnection.enabled" = true;
        "media.navigator.enabled" = true;
        "dom.webaudio.enabled" = true;
        "privacy.resistFingerprinting" = false;
        "network.http.referer.XOriginTrimmingPolicy" = 0;
        "browser.tabs.remote.allowLinkedWebInFileUri" = true;
        "browser.toolbars.bookmarks.visibility" = "always";
        "webgl.disabled" = false;
        "webgl.override-unmasked-renderer" = "Intel Iris OpenGL Engine";
        "webgl.override-unmasked-vendor" = "Intel Inc.";
        "layout.css.font-visibility.standard" = 2;
        "layout.css.font-visibility.level" = 2;
        "gfx.webrender.quality.force-subpixel-aa-where-possible" = true;
        "browser.compactmode.show" = true;
        "browser.uidensity" = 1;
        "general.autoScroll" = true;

        "browser.uiCustomization.state" = builtins.toJSON {
          placements = {
            nav-bar = [
              "sidebar-button"
              "back-button"
              "forward-button"
              "stop-reload-button"
              "home-button"
              "urlbar-container"
              "downloads-button"
              "onepassword-password-manager_agilebits_com-browser-action"
              "unified-extensions-button"
              "zotero-connector"
            ];
            TabsToolbar = [
              "tabbrowser-tabs"
              "new-tab-button"
            ];
          };
          currentVersion = 20;
        };
      };
    };
  };
}
