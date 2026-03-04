{
  pkgs,
  inputs,
  config,
  ...
}:
{
  programs.firefox = {
    enable = true;
    package = config.lib.nixGL.wrap pkgs.firefox;

    policies = {
      AutofillAddressEnabled = false;
      AutofillCreditCardEnabled = false;
      Cookies.Behavior = "reject-tracker-and-partition-foreign";
      DisableBuiltinPDFViewer = false;
      DisableFirefoxAccounts = true;
      DisableFirefoxStudies = true;
      DisableFormHistory = true;
      DisableMasterPasswordCreation = true;
      DisableProfileImport = true;
      DisableSetDesktopBackground = true;
      DisableTelemetry = true;
      DisplayBookmarksToolbar = "never";
      DisplayMenuBar = "default-off";
      DNSOverHTTPS.Enabled = false;
      EnableTrackingProtection = {
        Category = "strict";
        Cryptomining = true;
        EmailTracking = true;
        Fingerprinting = true;
        SuspectedFingerprinting = true;
        Value = true;
      };
      EncryptedMediaExtensions.Enabled = true;
      FirefoxHome = {
        Highlights = false;
        Search = false;
        SponsoredStories = false;
        SponsoredTopSites = false;
        Stories = false;
        TopSites = true;
      };
      FirefoxSuggest = {
        ImproveSuggest = false;
        SponsoredSuggestions = false;
        WebSuggestions = false;
      };
      GenerativeAI.Enabled = false;
      HardwareAcceleration = true;
      HttpsOnlyMode = "enabled";
      NoDefaultBookmarks = true;
      OfferToSaveLogins = false;
      OverrideFirstRunPage = "";
      OverridePostUpdatePage = "";
      PasswordManagerEnabled = false;
      Permissions = {
        Autoplay.Default = "block-audio";
        Camera.BlockNewRequests = true;
        Location.BlockNewRequests = true;
        Microphone.BlockNewRequests = true;
        Notifications.BlockNewRequests = true;
        ScreenShare.BlockNewRequests = true;
        VirtualReality.BlockNewRequests = true;
      };
      PictureInPicture.Enabled = true;
      PopupBlocking.Default = true;
      PrimaryPassword = false;
      RequestedLocales = "en-US";
      SearchBar = "unified";
      SearchSuggestEnabled = false;
      ShowHomeButton = true;
      SkipTermsOfUse = true;
      TranslateEnabled = true;

      # Search Engine Declarations
      SearchEngines = {
        Add = [
          
          {
            Name = "GitHub";
            Alias = "@gh";
            URLTemplate = "https://github.com/search?q={searchTerms}";
            IconURL = "https://github.com/favicon.ico";
          }
          {
            Name = "GitHub Nix";
            Alias = "@gn";
            URLTemplate = "https://github.com/search?q=language%3ANix+NOT+is%3Afork+{searchTerms}&type=code";
            IconURL = "https://github.com/favicon.ico";
          }
          {
            Name = "Home Manager";
            Alias = "@hm";
            URLTemplate = "https://home-manager-options.extranix.com/?query={searchTerms}&release=release-25.11";
            IconURL = "https://home-manager-options.extranix.com/images/favicon.png";
          }
          {
            Name = "NixOS Options";
            Alias = "@no";
            URLTemplate = "https://search.nixos.org/options?channel=25.11&query={searchTerms}";
            IconURL = "https://search.nixos.org/favicon.png";
          }
          {
            Name = "NixOS Packages";
            Alias = "@np";
            URLTemplate = "https://search.nixos.org/packages?channel=25.11&query={searchTerms}";
            IconURL = "https://search.nixos.org/favicon.png";
          }
          {
            Name = "NixOS Wiki";
            Alias = "@nw";
            URLTemplate = "https://wiki.nixos.org/w/index.php?search={searchTerms}";
            IconURL = "https://wiki.nixos.org/favicon.ico";
          }
          
          {
            Name = "Stack Overflow";
            Alias = "@so";
            URLTemplate = "https://stackoverflow.com/search?q={searchTerms}";
            IconURL = "https://stackoverflow.com/favicon.ico";
          }
          {
            Name = "Wikipedia";
            Alias = "@wk";
            URLTemplate = "https://en.wikipedia.org/wiki/Special:Search?search={searchTerms}";
            IconURL = "https://en.wikipedia.org/static/favicon/wikipedia.ico";
          }
          {
            Name = "YouTube";
            Alias = "@yt";
            URLTemplate = "https://www.youtube.com/results?search_query={searchTerms}";
            IconURL = "https://www.youtube.com/favicon.ico";
          }
        ];
        Remove = [
          "Amazon.com"
          "Bing"
          "eBay"
          "Perplexity"
          "Wikipedia (en)"
        ];
      };
    };

    # 2. USER PROFILE
    profiles.haa = {
      isDefault = true;
      id = 0;

      # Keep your existing extensions
      extensions.packages = with pkgs.nur.repos.rycee.firefox-addons; [
        ublock-origin
        sponsorblock
        onepassword-password-manager
        youtube-shorts-block
      ];

      settings = {
        # --- 1. THE "CROWD" LOGIC (Resist Fingerprinting) ---
        "privacy.resistFingerprinting" = true;
        "privacy.resistFingerprinting.letterboxing" = false;

        # --- 2. FONT HARDENING (Fixes the 1033 font leak) ---
        # This is likely why you are still "Unique"
        "layout.css.font-visibility.standard" = 1;
        "layout.css.font-visibility.trackingprotection" = 1;
        "layout.css.font-visibility.private" = 1;

        "dom.webaudio.enabled" = true;
        # --- 3. UI & COMPACT MODE ---
        "browser.compactmode.show" = true;
        "browser.uidensity" = 1;
        "browser.tabs.firefox-view" = false;
        "browser.tabs.tabmanager.enabled" = false;

        # --- 4. PERFORMANCE & HW ---
        "layers.acceleration.force-enabled" = true;
        "webgl.disabled" = false; # RFP will spoof the vendor to "Mozilla" automatically
        "media.hardware-video-decoding.force-enabled" = true;
        "general.autoScroll" = true;

        # --- 5. NETWORK & PRIVACY ---
        "privacy.trackingprotection.fingerprinting.enabled" = true;
        "privacy.resistFingerprinting.reduceTimerPrecision" = true;
        "network.http.referer.XOriginPolicy" = 2;

        # --- 6. PINNED SITES & UI STATE ---
        "browser.newtabpage.activity-stream.system.showWeather" = false;
        "browser.newtabpage.activity-stream.topSitesRows" = 2;
        "browser.newtabpage.pinned" = builtins.toJSON [
          {
            label = "YouTube";
            url = "https://youtube.com/feed/subscriptions";
          }
          {
            label = "GitHub";
            url = "https://github.com";
          }
        ];

        "browser.uiCustomization.state" = builtins.toJSON {
          placements = {
            nav-bar = [
              "back-button"
              "forward-button"
              "stop-reload-button"
              "home-button"
              "urlbar-container"
              "downloads-button"
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
