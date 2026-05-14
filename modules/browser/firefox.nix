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
    package = config.lib.nixGL.wrap pkgs.firefox;

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
      ];

      settings = {
        # --- 1. NATIVE VERTICAL TABS FIX ---
        # Note: These require Firefox 131+ or Nightly to function correctly.
        #"sidebar.revamp" = true; # Enable new sidebar system
        #"sidebar.verticalTabs" = true; # Enable native vertical tabs
        "sidebar.position_start" = true; # Sidebar on the LEFT
        "sidebar.visible" = true; # Force visibility so tabs don't "disappear"
        "sidebar.verticalTabs.collapsed" = true; # Icons-only mode
        "sidebar.expandOnHover" = true; # Set to true initially to ensure you can see titles
        "sidebar.main.tools" = "tabs"; # Focus sidebar on tabs

        # --- 2. STORAGE & COOKIE FIXES (Teams/SoundCloud) ---
        "dom.storage_access.enabled" = true;
        "dom.storage.enabled" = true;
        "network.cookie.cookieBehavior" = 0;
        "network.cookie.cookieBehavior.optInPartitioning" = false;
        "network.cookie.CHIPS.enabled" = false;
        "network.cookie.same-site.laxByDefault" = false;
        "privacy.firstparty.isolate" = false;

        # --- 3. PERSIST SESSIONS ---
        "privacy.clearOnShutdown.cookies" = false;
        "privacy.clearOnShutdown.sessions" = false;
        "privacy.clearOnShutdown.cache" = false;
        "privacy.sanitize.sanitizeOnShutdown" = false;

        # --- 4. AUTH & WEBRTC (Teams Calls) ---
        "media.peerconnection.enabled" = true;
        "media.navigator.enabled" = true;
        "dom.webaudio.enabled" = true;
        "privacy.resistFingerprinting" = false;
        "network.http.referer.XOriginTrimmingPolicy" = 0;
        "browser.tabs.remote.allowLinkedWebInFileUri" = true;

        # --- 5. PERFORMANCE & UI ---
        "webgl.disabled" = false;
        "webgl.override-unmasked-renderer" = "Intel Iris OpenGL Engine";
        "webgl.override-unmasked-vendor" = "Intel Inc.";
        "layout.css.font-visibility.standard" = 2;
        "layout.css.font-visibility.level" = 2;
        "gfx.webrender.quality.force-subpixel-aa-where-possible" = true;
        "browser.compactmode.show" = true;
        "browser.uidensity" = 1;
        "general.autoScroll" = true;

        # --- 6. PINNED 1PASSWORD & TOOLBAR ---
        "browser.uiCustomization.state" = builtins.toJSON {
          placements = {
            nav-bar = [
              "back-button"
              "forward-button"
              "stop-reload-button"
              "home-button"
              "urlbar-container"
              "downloads-button"
              "onepassword-password-manager_agilebits_com-browser-action"
              "unified-extensions-button"
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
