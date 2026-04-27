{
  pkgs,
  inputs,
  config,
  ...
}:
{

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-wlr
      pkgs.xdg-desktop-portal-gnome
    ];
    config = {
      common.default = [ "gtk" ];
      niri = {
        default = [ "gtk" ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
        "org.freedesktop.impl.portal.Camera" = [ "gnome" ];
      };
    };
  };
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/mattermost" = [ "mattermost-desktop.desktop" ];
    };
  };

  xdg.desktopEntries = {
    # The key here MUST match the original filename (signal-desktop) to override properly
    signal-desktop = {
      name = "Signal";
      # This points directly to the binary in the nix store
      exec = "nixGLMesa ${pkgs.signal-desktop}/bin/signal-desktop --no-sandbox --enable-features=UseOzonePlatform --ozone-platform=wayland %u";
      icon = "signal-desktop";
      terminal = false;
      categories = [
        "Network"
        "InstantMessaging"
      ];
    };

    mattermost-desktop = {
      name = "Mattermost";
      # This points directly to the binary in the nix store
      exec = "nixGLMesa ${pkgs.mattermost-desktop}/bin/mattermost-desktop --no-sandbox --enable-features=UseOzonePlatform --ozone-platform=wayland %U";
      icon = "mattermost-desktop";
      terminal = false;
      categories = [
        "Network"
        "InstantMessaging"
      ];
      mimeType = [
        "x-scheme-handler/mattermost"
      ];
    };
  };
  home.packages = with pkgs; [
    grim
    slurp
    wl-clipboard
    brightnessctl
    xdg-utils
    libsecret
    awww # Added for high-performance wallpaper management
    # ... other packages
  ];
  programs.hyprlock = {
    enable = true;
    package = pkgs.runCommand "empty" { } "mkdir -p $out";
    settings = {
      general = {
        disable_loading = true;
        grace = 0;
        hide_cursor = true;
      };

      background = [
        {
          blur_passes = 2;
          contrast = 0.8916;
          brightness = 0.8172;
          vibrancy = 0.1696;
          vibrancy_darkness = 0.0;
        }
      ];

      input-field = [
        {
          size = "200, 50";
          outline_thickness = 3;
          dots_size = 0.33;
          dots_spacing = 0.15;
          dots_center = true;
          outer_color = "rgb(151, 151, 151)";
          inner_color = "rgb(200, 200, 200)";
          font_color = "rgb(10, 10, 10)";
          fade_on_empty = true;
          placeholder_text = "<i>Input Password...</i>";
          hide_input = false;
          position = "0, -20";
          halign = "center";
          valign = "center";
        }
      ];
    };
  };
  services.hypridle = {
    enable = true;
    # Again, we tell HM to manage the config but not install the binary
    package = pkgs.runCommand "empty-hypridle" { } "mkdir -p $out";

    settings = {
      general = {
        # This calls the apt-installed hyprlock
        lock_cmd = "pidof hyprlock || hyprlock";
        # Lock the screen before the system goes to sleep
        before_sleep_cmd = "loginctl lock-session";
        # Turn the screen back on when the system wakes up
        after_sleep_cmd = "niri msg action power-on-monitors";
      };

      listener = [
        {
          # timeout = 300; # 5 minutes
          timeout = 300; # 5 minutes
          on-timeout = "loginctl lock-session";
        }
        {
          timeout = 330; # 5.5 minutes
          on-timeout = "niri msg action power-off-monitors";
          on-resume = "niri msg action power-on-monitors";
        }
      ];
    };
  };

  programs.niri = {
    enable = true;
    settings = {
      # --- Visuals & Aesthetics ---
      layout = {
        # Gaps: The secret sauce of a clean desktop
        gaps = 12;

        # Focused window styling
        focus-ring = {
          enable = true;
          width = 2;
          # A clean "Monochrome" friendly accent (Nordic Frost)
          active.color = "rgba(136, 192, 208, 1.0)";
          inactive.color = "rgba(76, 86, 106, 0.5)";
        };

        # Subtle rounding for a modern feel
        border = {
          enable = false; # We use focus-ring instead for a cleaner look
          width = 12;
        };

        # Struts for the bar
        struts = {
          top = 0; # noctalia-shell usually handles its own, but adjust if overlapping
        };
      };

      # --- Smooth Animations ---
      animations = {
        # Makes window opening and workspace switching feel premium
        enable = true;
        slowdown = 1.0;
      };

      # --- Outputs ---
      outputs."eDP-1" = {
        mode = {
          width = 1920;
          height = 1200;
        };
        position = {
          x = 0;
          y = 0;
        };
      };
      outputs."DP-8" = {
        mode = {
          width = 1920;
          height = 1200;
        };
        position = {
          x = 1920;
          y = 0;
        };
      };
      outputs."DP-9" = {
        mode = {
          width = 1920;
          height = 1200;
        };
        position = {
          x = 3840;
          y = 0;
        };
        transform.rotation = 90;
      };

      # --- Autostart ---
      spawn-at-startup = [
        {
          command = [
            "sh"
            "-c"
            ''
              sleep 1
              dbus-update-activation-environment --systemd \
                PATH XDG_DATA_DIRS XDG_CURRENT_DESKTOP \
                XDG_SESSION_TYPE XDG_SESSION_DESKTOP \
                WAYLAND_DISPLAY
              systemctl --user import-environment \
                PATH XDG_DATA_DIRS XDG_CURRENT_DESKTOP \
                XDG_SESSION_TYPE XDG_SESSION_DESKTOP \
                WAYLAND_DISPLAY
              systemctl --user restart xdg-desktop-portal-wlr
              sleep 0.5
              systemctl --user restart xdg-desktop-portal
            ''
          ];
        }
        { command = [ "hypridle" ]; }
        { command = [ "noctalia-shell" ]; }
        # 1. Initialize wallpaper daemon
        # 2. Set the background (Replace path with your actual image)
        { command = [ "swww-daemon" ]; }
        {
          command = [
            "nextcloud"
            "--background"
          ];
        }
        { command = [ "tailscale-systray" ]; }
        { command = [ "opencloud" ]; }
        {
          command = [
            "swww"
            "img"
            "/path/to/your/wallpaper.jpg"
            "--transition-type"
            "outer"
          ];
        }

        {
          command = [
            "gnome-keyring-daemon"
            "--start"
            "--components=ssh"
          ];
        }
        {
          command = [
            "wl-paste"
            "--watch"
            "cliphist"
            "store"
          ];
        }

        # Browser & Messaging
        {
          command = [
            "signal-desktop --no-sandbox --enable-features=UseOzonePlatform --ozone-platform=wayland "
          ];
        }
        {
          command = [
            "mattermost-desktop --no-sandbox --enable-features=UseOzonePlatform --ozone-platform=wayland "
          ];
        }
        {
          command = [
            "thunderbird"
          ];
        }
        { command = [ "MOZ_ENABLE_WAYLAND=1 firefox" ]; }
      ];

      # --- Window Rules ---
      window-rules = [
        {
          matches = [
            { title = "nmtui-floating"; }
            { title = "btop-floating"; }
          ];
          open-floating = true;
          default-column-width = {
            proportion = 0.5;
          };
        }
        {
          matches = [
            { app-id = "signal-desktop"; }
            { app-id = "thunderbird"; }
            { app-id = "mattermost-desktop"; }
          ];
          open-on-workspace = "1";
        }
        {
          matches = [ { app-id = "firefox"; } ];
          open-on-workspace = "2";
        }
      ];

      # --- Keybindings ---
      binds =
        let
          actions = config.lib.niri.actions;
        in
        {
          "Mod+Return".action = actions.spawn "nixGLMesa" "ghostty";
          "Mod+D".action = actions.spawn "nixGLMesa" "wofi" "--show" "drun";
          "Mod+Shift+Q".action = actions."close-window";

          # Navigation (Focus)
          "Mod+H".action = actions."focus-column-left";
          "Mod+L".action = actions."focus-column-right";

          # --- THE NIRI WAY (Dynamic Movement) ---
          # Focus workspaces up/down (since they are stacked vertically)
          "Mod+K".action = actions."focus-workspace-up";
          "Mod+J".action = actions."focus-workspace-down";

          # Move the current window up/down to a different workspace
          "Mod+Shift+K".action = actions."move-column-to-workspace-up";
          "Mod+Shift+J".action = actions."move-column-to-workspace-down";

          # --- THE INDEX WAY (Static-style Movement) ---
          # Focus by number
          "Mod+1".action = actions."focus-workspace" 1;
          "Mod+2".action = actions."focus-workspace" 2;
          "Mod+3".action = actions."focus-workspace" 3;
          "Mod+4".action = actions."focus-workspace" 4;
          "Mod+5".action = actions."focus-workspace" 5;

          "Mod+Ctrl+L".action = actions.spawn "sh" "-c" "hyprlock";
          "Mod+M".action = actions.maximize-column;

          # Fullscreen (covers the whole monitor, hides the bar)
          "Mod+F".action = actions.fullscreen-window;
          "XF86MonBrightnessUp".action = actions.spawn "brightnessctl" "set" "5%+";
          "XF86MonBrightnessDown".action = actions.spawn "brightnessctl" "set" "5%-";
          # Useful addition: Center the window
          "Mod+C".action = actions.center-column;
          "XF86AudioMicMute".action = actions.spawn "wpctl" "set-mute" "@DEFAULT_SOURCE@" "toggle";

          # Move window to workspace by number
          # "Mod+Ctrl+1".action = actions."move-column-to-workspace" 1;
          # "Mod+Ctrl+2".action = actions."move-column-to-workspace" 2;
          # "Mod+Ctrl+3".action = actions."move-column-to-workspace" 3;
          # "Mod+Ctrl+4".action = actions."move-column-to-workspace" 4;
          # "Mod+Ctrl+5".action = actions."move-column-to-workspace" 5;

          # Mouse dragging
          # "Mod+MouseLeft".action = actions."move-window-with-mouse";

          "Mod+Shift+E".action = actions.quit;
          # Screenshots & Audio
          "Print".action = actions.spawn "sh" "-c" "grim -g \"$(slurp)\" - | wl-copy";
          "XF86AudioRaiseVolume".action =
            actions.spawn "wpctl" "set-volume" "-l" "1.5" "@DEFAULT_SINK@"
              "5%+";
          "XF86AudioLowerVolume".action = actions.spawn "wpctl" "set-volume" "@DEFAULT_SINK@" "5%-";
          "XF86AudioMute".action = actions.spawn "wpctl" "set-mute" "@DEFAULT_SINK@" "toggle";
        };
    };
  };

  # Noctalia Shell styling to match the Monochrome theme
  programs.noctalia-shell = {
    enable = true;
    settings = {
      bar = {
        density = "compact";
        position = "top";
        showCapsule = true; # Enabled capsule for a more "pill" like modern look
        widgets = {
          left = [
            {
              id = "ControlCenter";
              useDistroLogo = true;
            }
            { id = "Network"; }
          ];
          center = [
            {
              id = "Workspace";
              hideUnoccupied = false;
              labelMode = "none";
            }
          ];
          right = [
            {
              id = "Tray";
              # This will display Nextcloud, Tailscale, and OpenCloud
              # icons as they register themselves with the shell.
            }
            {
              id = "Battery";
              warningThreshold = 30;
            }
            {
              id = "Clock";
              formatHorizontal = "HH:mm";
              useMonospacedFont = true;
            }
          ];
        };
      };
      colorSchemes.predefinedScheme = "Monochrome";
      general.radiusRatio = 0.4; # Increased roundness for a softer look
    };
  };
}
