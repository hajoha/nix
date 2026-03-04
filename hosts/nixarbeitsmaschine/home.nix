{
  lib,
  config,
  system,
  pkgs,
  inputs,
  nixgl,
  ...
}:
let
  scinterface = pkgs.stdenv.mkDerivation {
    pname = "scinterface";
    version = "8.3.4";

    src = pkgs.fetchurl {
      url = "https://www.cc-pki.fraunhofer.de/images/stories/files/downloads/treiber/middleware/linux/cv/SCinterface_8_3_4_Ubuntu.zip";
      sha256 = "sha256-fqim4yvWLHoUbzD4m4Jsgo6q4PFISXy5xtQUYkQL0ic=";
    };

    nativeBuildInputs = [
      pkgs.unzip
      pkgs.dpkg
      pkgs.autoPatchelfHook
    ];

    buildInputs = [
      pkgs.stdenv.cc.cc.lib
      pkgs.pcsclite
      pkgs.openssl
      pkgs.zlib
    ];

    unpackPhase = ''
      unzip $src
      DEBFILE=$(find . -name "*Ubuntu24.04-x86_64.deb" | head -n 1)
      mkdir -p extracted
      dpkg-deb -x "$DEBFILE" extracted/
    '';

    installPhase = ''
      mkdir -p $out/lib
      # Copy the libraries
      find extracted -name "*.so*" -exec cp -v {} $out/lib/ \;

      # Copy the configuration file (Crucial for Cryptovision)
      cp -v SCinterface_8_3_4/support/cvP11.ini $out/lib/cvP11.ini

      # Force the symlink for pcsc-lite
      ln -sf ${pkgs.lib.getLib pkgs.pcsclite}/lib/libpcsclite.so.1 $out/lib/libpcsclite.so.1
    '';
  };
in
{

  xdg.portal.enable = false;
  nixpkgs = {
    overlays = [
      inputs.nur.overlays.default
    ];
    config = {
      allowUnfree = true;
    };

  };
  imports = [
    inputs.nvf.homeManagerModules.default
  ];
  targets.genericLinux.enable = true;
  fonts.fontconfig.enable = true;
  systemd.user.startServices = "sd-switch";
  services.gnome-keyring = {
    enable = false;
    components = [
      "secrets"
      "ssh"
    ];
  };
  home.file.".config/opensc/opensc.conf".text = ''
    app default {
      # Try all drivers that might support an Infineon chip
      card_drivers = starcos, cardos, asepcos;
      # Increase log level so we can see WHY it fails
      debug = 3;
      debug_file = /tmp/opensc.log;
    }
  '';
  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    pinentry.package = pkgs.pinentry-gnome3;
    # This helps ensure the agent finds the right socket path
    enableExtraSocket = true;
    extraConfig = ''
      disable-ccid
      allow-loopback-pinentry
    '';
  };

  programs.zed-editor = {
    enable = true;

    # This populates the userSettings "auto_install_extensions"
    extensions = [
      "nix"
      "toml"
      "elixir"
      "make"
      "json"
      "latex"
      "python"
      "typescript"
    ];

    # Everything inside of these brackets are Zed options
    userSettings = {
      assistant = {
        enabled = true;
        version = "2";
        default_open_ai_model = null;

        # Provider options:
        # - zed.dev models (claude-3-5-sonnet-latest) requires GitHub connected
        # - anthropic models (claude-3-5-sonnet-latest, claude-3-haiku-latest, claude-3-opus-latest) requires API_KEY
        # - copilot_chat models (gpt-4o, gpt-4, gpt-3.5-turbo, o1-preview) requires GitHub connected
        default_model = {
          provider = "zed.dev";
          model = "claude-3-5-sonnet-latest";
        };

        # inline_alternatives = [
        #   {
        #     provider = "copilot_chat";
        #     model = "gpt-3.5-turbo";
        #   }
        # ];
      };

      node = {
        path = lib.getExe pkgs.nodejs;
        npm_path = lib.getExe' pkgs.nodejs "npm";
      };

      hour_format = "hour24";
      auto_update = false;

      terminal = {
        alternate_scroll = "off";
        blinking = "off";
        copy_on_select = false;
        dock = "bottom";
        detect_venv = {
          on = {
            directories = [
              ".env"
              "env"
              ".venv"
              "venv"
            ];
            activate_script = "default";
          };
        };
        env = {
          TERM = "alacritty";
        };
        font_family = "FiraCode Nerd Font";
        font_features = null;
        font_size = null;
        line_height = "comfortable";
        option_as_meta = false;
        button = false;
        shell = "system";
        # shell = {
        #   program = "zsh";
        # };
        toolbar = {
          title = true;
        };
        working_directory = "current_project_directory";
      };

      lsp = {
        rust-analyzer = {
          binary = {
            # path = lib.getExe pkgs.rust-analyzer;
            path_lookup = true;
          };
        };

        nix = {
          binary = {
            path_lookup = true;
          };
        };

        elixir-ls = {
          binary = {
            path_lookup = true;
          };
          settings = {
            dialyzerEnabled = true;
          };
        };
      };

      languages = {
        "Elixir" = {
          language_servers = [
            "!lexical"
            "elixir-ls"
            "!next-ls"
          ];
          format_on_save = {
            external = {
              command = "mix";
              arguments = [
                "format"
                "--stdin-filename"
                "{buffer_path}"
                "-"
              ];
            };
          };
        };

        "HEEX" = {
          language_servers = [
            "!lexical"
            "elixir-ls"
            "!next-ls"
          ];
          format_on_save = {
            external = {
              command = "mix";
              arguments = [
                "format"
                "--stdin-filename"
                "{buffer_path}"
                "-"
              ];
            };
          };
        };
      };

      vim_mode = true;

      # Tell Zed to use direnv and direnv can use a flake.nix environment
      load_direnv = "shell_hook";
      base_keymap = "JetBrains";

      theme = {
        mode = "system";
        light = "One Light";
        dark = "One Dark";
      };

      show_whitespaces = "all";
      ui_font_size = 16;
      buffer_font_size = 16;
    };
  };

  programs.gpg = {
    enable = true;
    settings = {
      # Standard hardening for smartcards
      use-agent = true;
    };
  };
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
  programs.nvf = {
    enable = true;
    settings = {

      vim.viAlias = false;
      vim.vimAlias = true;
      vim.languages = {
        nix = {
          enable = true;
          format.enable = true;
          lsp.enable = true;
          treesitter.enable = true;
        };

        python = {
          enable = true;
          format.enable = true;
          lsp.enable = true;
          treesitter.enable = true;
        };

      };
      vim.lsp = {
        enable = true;
        formatOnSave = true;
      };
      vim.dashboard.dashboard-nvim = {
        enable = true;
        setupOpts = {
          theme = "doom";
          config = {
            header = [ ];
            center = [
              {
                icon = " ";
                desc = "Open latest session";
                key = "s";
                keymap = "SPC s l";
                key_format = " %s";
                action = "lua require('persistence').load()";
                highlight = "Function";
              }
              {
                icon = " ";
                desc = "Recently opened files";
                key = "r";
                keymap = "SPC s r";
                key_format = " %s";
                action = "lua require('fzf-lua').oldfiles()";
                highlight = "Identifier";
              }
              {
                icon = " ";
                desc = "Find File";
                key = "f";
                keymap = "SPC f f";
                key_format = " %s";
                action = "lua require('fzf-lua').files()";
                highlight = "Function";
              }
              {
                icon = " ";
                desc = "File Browser";
                key = "b";
                keymap = "SPC f b";
                key_format = " %s";
                action = "lua require('fzf-lua').files({ cwd = vim.fn.getcwd() })";
                highlight = "Type";
              }
              {
                icon = " ";
                desc = "Find Word";
                key = "w";
                keymap = "SPC f w";
                key_format = " %s";
                action = "lua require('fzf-lua').live_grep()";
                highlight = "Keyword";
              }
            ];
            footer = [
            ];
          };
        };
      };

      vim.startPlugins = [
        "nvim-treesitter"
        "telescope"
        "nvim-cursorline"
        #        "dashboard-nvim"
        "nvim-colorizer-lua"
        "nui-nvim"
        "plenary-nvim"
        "neo-tree-nvim"
        "fzf-lua"
      ];
      vim.keymaps = [
        {
          key = "<leader>e";
          mode = "n";
          silent = true;
          action = ":Neotree toggle<CR>";
        }
        {
          key = "<leader>p";
          mode = "n";
          silent = true;
          action = ":FzfLua files<CR>";
        }
        {
          key = "<leader>f";
          mode = "n";
          silent = true;
          action = ":FzfLua live_grep<CR>";
        }
        {
          key = "K";
          mode = "n";
          silent = true;
          action = "lua vim.lsp.buf.hover()<CR>";
        }
      ];
    };
  };
  wayland.windowManager.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    systemd.enable = true;
    extraConfig = ''
      output DP-8 transform 90
      set $left h
      set $down j
      set $up k
      set $right l

      for_window [title="nmtui-floating"] floating enable, move position center, focus
      for_window [title="btop-floating"] floating enable, move position center, focus

      assign [app_id="signal-desktop"] workspace number 1
      assign [app_id="thunderbird"] workspace number 1
      assign [app_id="mattermost-desktop"] workspace number 1
      assign [app_id="firefox"] workspace number 2

      # Autostart
      exec signal-desktop --password-store=gnome-libsecret --enable-features=UseOzonePlatform --ozone-platform=wayland
      exec mattermost-desktop
      exec thunderbird

      exec firefox

      exec swayidle -w \
        timeout 600 'swaylock -f -c 000000' \
        timeout 630 'swaymsg "output * dpms off"' \
        resume 'swaymsg "output * dpms on"' \
        before-sleep 'swaylock -f -c 000000'
      exec cliphist wipe
      exec wl-paste --watch cliphist store


    '';
    config = {
      modifier = "Mod4"; # Super/Windows key
      terminal = "alacritty";
      defaultWorkspace = "workspace number 1";
      menu = "wofi --show drun"; # You can replace this with bemenu, fuzzel, etc.
      keybindings = {
        "${config.wayland.windowManager.sway.config.modifier}+Return" =
          "exec ${config.wayland.windowManager.sway.config.terminal}";
        "${config.wayland.windowManager.sway.config.modifier}+d" =
          "exec ${config.wayland.windowManager.sway.config.menu}";
        "${config.wayland.windowManager.sway.config.modifier}+Shift+q" = "kill";
        "${config.wayland.windowManager.sway.config.modifier}+Shift+c" = "reload";
        "${config.wayland.windowManager.sway.config.modifier}+Shift+r" = "restart";
        "${config.wayland.windowManager.sway.config.modifier}+h" = "focus left";
        "${config.wayland.windowManager.sway.config.modifier}+j" = "focus down";
        "${config.wayland.windowManager.sway.config.modifier}+k" = "focus up";
        "${config.wayland.windowManager.sway.config.modifier}+l" = "focus right";
        "${config.wayland.windowManager.sway.config.modifier}+f" = "fullscreenV toggle";

        "${config.wayland.windowManager.sway.config.modifier}+Shift+v" = ''
          exec cliphist list | sed -E "s/^([0-9]+)\t/\1 /" | wofi --dmenu | sed -E "s/^([0-9]+) /\1\t/" | cliphist decode | wl-copy
        '';

        "${config.wayland.windowManager.sway.config.modifier}+1" = "workspace 1";
        "${config.wayland.windowManager.sway.config.modifier}+2" = "workspace 2";
        "${config.wayland.windowManager.sway.config.modifier}+3" = "workspace 3";
        "${config.wayland.windowManager.sway.config.modifier}+4" = "workspace 4";
        "${config.wayland.windowManager.sway.config.modifier}+5" = "workspace 5";
        "${config.wayland.windowManager.sway.config.modifier}+6" = "workspace 6";
        "${config.wayland.windowManager.sway.config.modifier}+7" = "workspace 7";
        "${config.wayland.windowManager.sway.config.modifier}+8" = "workspace 8";
        "${config.wayland.windowManager.sway.config.modifier}+9" = "workspace 9";
        "${config.wayland.windowManager.sway.config.modifier}+0" = "workspace 10";

        "${config.wayland.windowManager.sway.config.modifier}+Shift+1" =
          "move container to workspace number 1";
        "${config.wayland.windowManager.sway.config.modifier}+Shift+2" =
          "move container to workspace number 2";
        "${config.wayland.windowManager.sway.config.modifier}+Shift+3" =
          "move container to workspace number 3";
        "${config.wayland.windowManager.sway.config.modifier}+Shift+4" =
          "move container to workspace number 4";
        "${config.wayland.windowManager.sway.config.modifier}+Shift+5" =
          "move container to workspace number 5";
        "${config.wayland.windowManager.sway.config.modifier}+Shift+6" =
          "move container to workspace number 6";
        "${config.wayland.windowManager.sway.config.modifier}+Shift+7" =
          "move container to workspace number 7";
        "${config.wayland.windowManager.sway.config.modifier}+Shift+8" =
          "move container to workspace number 8";
        "${config.wayland.windowManager.sway.config.modifier}+Shift+9" =
          "move container to workspace number 9";
        "${config.wayland.windowManager.sway.config.modifier}+Shift+0" =
          "move container to workspace number 10";
        "${config.wayland.windowManager.sway.config.modifier}+Control+f" = "exec ferrishot";
        "${config.wayland.windowManager.sway.config.modifier}+Control+l" =
          "exec swaylock -f -c 000000 --indicator-radius 100 --indicator-thickness 8 --text-color ffffff";

        "${config.wayland.windowManager.sway.config.modifier}+Shift+e" = "layout toggle split";

        "${config.wayland.windowManager.sway.config.modifier}+b" = "splith";
        "${config.wayland.windowManager.sway.config.modifier}+v" = "splitv";

        "${config.wayland.windowManager.sway.config.modifier}+s" = "layout stacking";
        "${config.wayland.windowManager.sway.config.modifier}+w" = "layout tabbed";
        "${config.wayland.windowManager.sway.config.modifier}+e" = "layout toggle split";

        "${config.wayland.windowManager.sway.config.modifier}+a" = "focus parent";

        "XF86AudioRaiseVolume" = "exec pactl set-sink-volume @DEFAULT_SINK@ +5%";
        "XF86AudioLowerVolume" = "exec pactl set-sink-volume @DEFAULT_SINK@ -5%";
        "XF86AudioMute" = "exec pactl set-sink-mute @DEFAULT_SINK@ toggle";
        "XF86MonBrightnessUp" = "exec brightnessctl set +5%";
        "XF86MonBrightnessDown" = "exec brightnessctl set 5%-";
        "XF86AudioPause" = "exec playerctl play-pause";
        "XF86AudioNext" = "exec playerctl next";
        "XF86AudioPrev" = "exec playerctl previous";

        "${config.wayland.windowManager.sway.config.modifier}+Shift+space" = "floating toggle";

        "${config.wayland.windowManager.sway.config.modifier}+Control+Shift+Right" =
          "move workspace to output right";
        "${config.wayland.windowManager.sway.config.modifier}+Control+Shift+Left" =
          "move workspace to output left";
        "${config.wayland.windowManager.sway.config.modifier}+Control+Shift+Down" =
          "move workspace to output down";
        "${config.wayland.windowManager.sway.config.modifier}+Control+Shift+Up" =
          "move workspace to output up";

      };

      input = {
        "type:keyboard" = {
          xkb_layout = "us";
          xkb_options = "compose:ralt";
        };
        "type:touchpad" = {
          natural_scroll = "enabled";
          accel_profile = "adaptive";
          tap = "enabled";
          scroll_method = "two_finger";
          dwt = "disabled";
          click_method = "button_areas";
        };
      };
      fonts = {
        names = [ "Fira Code" ];
        size = 10.0;

      };

      gaps = {
        inner = 0;
        outer = 0;
      };
      bars = [ ];
      startup = [
        # 1. Clear previous environment hangs
        { command = "systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP"; }
        {
          command = "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway";
        }
        { command = "dbus-update-activation-environment --all"; }

        { command = "systemctl --user restart pipewire wireplumber swaync"; }

        { command = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"; }
        {
          command = "sh -c 'sleep 5; nm-applet --indicator & 1password --silent & opencloud & blueman-applet &'";
        }
        {
          command = "dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway DISPLAY";
        }
      ];

    };
  };
  #xdg.desktopEntries.FreeCAD = {
  #  name = "FreeCAD";
  #  genericName = "CAD Modeler";
  #  # This prepends the env var to the execution command
  #  exec = "env QT_QPA_PLATFORM=xcb FreeCAD %F";
  #  categories = [ "Graphics" "Engineering" ];
  #  mimeType = [ "application/x-extension-fcstd" ];
  #  settings = {
  #    StartupWMClass = "FreeCAD";
  #  };
  #};
  targets.genericLinux.nixGL.packages = import nixgl { inherit pkgs; };
  targets.genericLinux.nixGL.defaultWrapper = "mesa";
  targets.genericLinux.nixGL.installScripts = [ "mesa" ];

  home.packages = with pkgs; [
    # 3D-stuff
    nix-ld
    freecad
    opensc
    ferrishot
    uv
    way-displays
    #orca-slicer
    #cura
    ffmpeg
    libqmi
    libsecret
    tmux
    zsh
    inkscape
    ausweisapp
    spice-gtk
    poppler-utils
    solaar
    pdfpc
    gcc
    zip
    tio
    nextcloud-client
    vlc
    xz
    unzip
    p7zip
    anydesk
    chromium
    gimp
    udev
    libvirt
    kvmtool
    ripgrep
    jq
    yq-go
    eza
    fzf
    slurp
    signal-desktop
    dejavu_fonts
    liberation_ttf
    noto-fonts
    noto-fonts-cjk-sans
    twemoji-color-font
    nerd-fonts.symbols-only
    nerd-fonts.fira-code
    material-icons
    fira-code
    mtr
    iperf3
    dnsutils
    ldns
    aria2
    socat
    ueberzugpp
    papers
    nmap
    ipcalc
    nix-output-monitor
    hugo
    glow
    pulseaudio
    btop
    iotop
    iftop
    strace
    ltrace
    lsof
    sysstat
    lm_sensors
    openssl
    ethtool
    pciutils
    pamixer
    usbutils
    android-tools
    tuigreet
    killall
    #jetbrains.pycharm-professional
    #jetbrains.clion
    (pkgs.jetbrains.plugins.addPlugins pkgs.jetbrains.clion [
      #  pkgs.jetbrains.plugins.github-copilot
    ])
    (pkgs.jetbrains.plugins.addPlugins pkgs.jetbrains.pycharm [
      #  pkgs.jetbrains.plugins.github-copilot
      #  pkgs.jetbrains.plugins.nixidea
    ])
    android-studio
    nixfmt
    ollama
    wdisplays
    alacritty
    opencloud-desktop
    scinterface
    #    xdg-desktop-portal
    #    xdg-desktop-portal-wlr
    #    xdg-desktop-portal-gtk
    #    xdg-desktop-portal-hyprland

    socat

    pavucontrol
    pipewire
    wireplumber
    wofi
    #    swaylock
    swaybg
    swayidle
    glib
    wl-clipboard
    swaynotificationcenter
    waybar # status bar
    noto-fonts-color-emoji # Best overall support
    twemoji-color-font # Twitter-style emojis (optional)
    fontconfig # Ensures font configuration
    nerd-fonts.symbols-only
    nerdfix
    brightnessctl
    anydesk
    wtype
    chromium
    cliphist
  ];

  programs.firefox = {
    enable = true;
    package = config.lib.nixGL.wrap pkgs.firefox;

    # 1. ENTERPRISE POLICIES (Global settings)
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
            Name = "Arch Wiki";
            Alias = "@aw";
            URLTemplate = "https://wiki.archlinux.org/index.php?search={searchTerms}";
            IconURL = "https://wiki.archlinux.org/favicon.ico";
          }
          {
            Name = "Docker Hub";
            Alias = "@dh";
            URLTemplate = "https://hub.docker.com/search?q={searchTerms}";
            IconURL = "https://hub.docker.com/favicon.ico";
          }
          {
            Name = "Flathub";
            Alias = "@fh";
            URLTemplate = "https://flathub.org/apps/search?q={searchTerms}";
            IconURL = "https://flathub.org/favicon.png";
          }
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
            Name = "ProtonDB";
            Alias = "@pd";
            URLTemplate = "https://www.protondb.com/search?q={searchTerms}";
            IconURL = "https://www.protondb.com/favicon.ico";
          }
          {
            Name = "Reddit";
            Alias = "@rd";
            URLTemplate = "https://www.reddit.com/search/?q={searchTerms}";
            IconURL = "https://www.reddit.com/favicon.ico";
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

  programs.zsh = {
    enable = true;
    enableCompletion = true;

    shellAliases = {
      ll = "ls -l";
      update = "home-manager switch --flake ~/.config/home-manager#haa";
    };

    history = {
      size = 10000;
      path = "${config.xdg.dataHome}/zsh/history";
    };

    oh-my-zsh = {
      enable = true;
      plugins = [ "git" ];
      theme = "rkj-repos";
    };
  };
  xdg.desktopEntries."signal-desktop" = {
    name = "Signal";
    genericName = "Messaging and Video Chat";
    exec = "signal-desktop --password-store=gnome-libsecret --enable-features=UseOzonePlatform --ozone-platform=wayland %U";
    icon = "signal";
    terminal = false;
    categories = [
      "Network"
      "InstantMessaging"
    ];
    # Adding this ensures it takes precedence
    settings = {
      Keywords = "chat;messaging;talk;";
    };
  };
  dconf.settings = {
    "org/virt-manager/virt-manager/connections" = {
      autoconnect = [ "qemu:///system" ];
      uris = [ "qemu:///system" ];

    };
    "org/gnome/desktop/interface".color-scheme = "prefer-dark";
  };

  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      manager = {
        ratio = [
          1
          4
          3
        ];
        sort_by = "natural";
        sort_sensitive = true;
        sort_reverse = false;
        sort_dir_first = true;
        linemode = "none";
        show_hidden = true;
        show_symlink = true;
      };

      preview = {
        image_filter = "lanczos3";
        image_quality = 90;
        tab_size = 1;
        max_width = 600;
        max_height = 900;
        cache_dir = "";
        ueberzug_scale = 1;
        ueberzug_offset = [
          0
          0
          0
          0
        ];
      };
      plugins = {
        "bypass.yazi" = pkgs.yaziPlugins.bypass;
        "chmod.yazi" = pkgs.yaziPlugins.chmod;
        "full-border.yazi" = pkgs.yaziPlugins.full-border;
        "lazygit.yazi" = pkgs.yaziPlugins.lazygit;
        "mediainfo.yazi" = pkgs.yaziPlugins.mediainfo;
        "no-status.yazi" = pkgs.yaziPlugins.no-status;
        "ouch.yazi" = pkgs.yaziPlugins.ouch;
        "restore.yazi" = pkgs.yaziPlugins.restore;
        "smart-enter.yazi" = pkgs.yaziPlugins.smart-enter;
        "toggle-pane.yazi" = pkgs.yaziPlugins.toggle-pane;
      };
      tasks = {
        micro_workers = 5;
        macro_workers = 10;
        bizarre_retry = 5;
      };
    };
  };

  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark"; # or "Catppuccin-Mocha", "Gruvbox-Dark", etc.
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };

  home.sessionVariables = {
    GTK_THEME = "Adwaita:dark";
    QT_QPA_PLATFORM = "wayland;xcb";
    QT_QPA_PLATFORMTHEME = "qt5ct";
    QT_STYLE_OVERRIDE = "kvantum";
    XDG_CURRENT_DESKTOP = "sway";
    OPENSC_CONF = "$HOME/.config/opensc/opensc.conf";
    NIX_LD_LIBRARY_PATH = "/usr/lib/x86_64-linux-gnu:${pkgs.stdenv.cc.cc.lib}/lib";
    NIX_LD = "${pkgs.stdenv.cc.cc.lib}/lib/ld-linux-x86-64.so.2";
    LD_LIBRARY_PATH = "${pkgs.stdenv.cc.cc.lib}/lib:${pkgs.pcsclite}/lib:${config.home.profileDirectory}/lib";
    XDG_SESSION_TYPE = "wayland";
    # Add this line to stop Waybar from hanging on portal timeouts
    GTK_USE_PORTAL = "0";
    MOZ_ENABLE_WAYLAND = "1";
    XDG_DATA_DIRS = lib.mkForce "$HOME/.nix-profile/share:$HOME/.local/share:$XDG_DATA_DIRS:/usr/local/share:/usr/share";
  };
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    systemd.target = "sway-session.target"; # Ensures it starts with Sway

    style = builtins.readFile ./style.css;
    settings = [
      {
        layer = "top";
        position = "top";
        mod = "dock";
        exclusive = true;
        passtrough = false;
        #        gtk-layer-shell = true;
        height = 10;
        modules-left = [
          "sway/workspaces"
          "custom/divider"
          "cpu"
          "custom/divider"
          "memory"
        ];
        modules-center = [ "sway/window" ];
        modules-right = [

          "network"
          "custom/divider"
          "backlight"
          "custom/divider"
          "pulseaudio"
          "custom/divider"
          "battery"
          "custom/divider"
          "clock"
          "custom/divider"
          "custom/notification"
          "custom/divider"
          "tray"
        ];
        "sway/window" = {
          format = "{}";
        };
        "wlr/workspaces" = {
          on-scroll-up = "hyprctl dispatch workspace e+1";
          on-scroll-down = "hyprctl dispatch workspace e-1";
          all-outputs = true;
          on-click = "activate";
        };
        "sway/workspaces" = {
          all-outputs = true;
          on-click = "activate";
          # Remove the hyprctl command since you are in Sway
        };
        battery = {
          # Show an icon that varies with capacity + percentage
          format = "{icon} {capacity}%";
          # When charging or plugged in, swap to a bolt/plug icon
          format-charging = "󰂄 {capacity}%"; # lightning bolt
          format-plugged = "󰚥 {capacity}%"; # same as charging (or use 󰂄 for a plug)
          format-full = "󰁹 {capacity}%"; # full battery icon if you like

          format-icons = [
            "󰁺"
            "󰁻"
            "󰁼"
            "󰁽"
            "󰁾"
            "󰁿"
            "󰂀"
            "󰂁"
            "󰂂"
            "󰁹"
          ];
          interval = 2;
          states = {
            warning = 30;
            critical = 15;
          };
        };
        cpu = {
          interval = 10;
          format = "󰻠 {}%";
          max-length = 10;
          on-click = "swaymsg exec 'alacritty --title btop-floating -e btop'";
        };
        memory = {
          interval = 30;
          format = "  {}%";
          format-alt = " {used:0.1f}G";
          max-length = 10;
        };
        backlight = {
          format = "󰖨 {}";
          device = "acpi_video0";
        };
        tray = {
          icon-size = 15;
          tooltip = false;
          spacing = 3;
        };
        network = {
          format = "{ifname}";
          format-disconnected = "󰖪 disconnected";
          interval = 10;
          format-wifi = "󰖩 {essid} {signaldBm} [dbm]";
          format-ethernet = "󰖠 {ipaddr}/{cidr}";
          tooltip-format-wifi = "{ifname} | {ipaddr}/{cidr}\n{signaldBm} [dBm] | {frequency} [GHz] \n↑{bandwidthUpBits} | ↓{bandwidthDownBits}\n{essid} - {bssid}";
          tooltip-format-ethernet = "{ifname}\n{ipaddr}/{cidr}\n↑{bandwidthUpBits} | ↓{bandwidthDownBits}\n";
          on-click = "swaymsg exec 'alacritty --title nmtui-floating -e nmtui'";
        };
        clock = {
          format = "{:%H:%M - %d/%m/%y}";
          tooltip-format = ''
            <big>{:%Y %B}</big>
            <tt><small>{calendar}</small></tt>'';
        };
        pulseaudio = {
          format = "{icon} {volume}%";
          tooltip = false;
          format-muted = "🔇 Muted";
          on-click = "pavucontrol";
          on-scroll-up = "pamixer -i 5";
          on-scroll-down = "pamixer -d 5";
          scroll-step = 5;
          format-icons = {
            headphone = "";
            hands-free = "";
            headset = "";
            phone = "";
            portable = "";
            car = "";
            default = [
              ""
              ""
              ""
            ];
          };
        };
        "custom/divider" = {
          format = " | ";
          interval = "once";
          tooltip = false;
        };
        "custom/endright" = {
          format = "_";
          interval = "once";
          tooltip = false;
        };
        "custom/notification" = {
          tooltip = false;
          format = "{icon}";
          "format-icons" = {
            notification = " <span foreground='red'><sup></sup></span> ";
            none = "";
            "dnd-notification" = " <span foreground='red'><sup></sup></span> ";
            "dnd-none" = "  ";
            "inhibited-notification" = " <span foreground='red'><sup></sup></span> ";
            "inhibited-none" = "";
            "dnd-inhibited-notification" = " <span foreground='red'><sup></sup></span> ";
            "dnd-inhibited-none" = "  ";
          };
          "return-type" = "json";
          "exec-if" = "which swaync-client";
          exec = "swaync-client -swb";
          "on-click" = "swaync-client -t -sw";
          "on-click-right" = "swaync-client -d -sw";
          escape = true;
        };
      }
    ];
  };

  home.stateVersion = "23.11";

  # Let home Manager install and manage itself.
  programs.home-manager = {
    enable = true;
  };

}
