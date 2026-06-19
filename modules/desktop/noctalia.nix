{
  pkgs,
  inputs,
  config,
  ...
}:
{
  systemd.user.services.xdg-desktop-portal = {
    Service.ExecStart = [
      "" # clear the ubuntu default
      "${pkgs.xdg-desktop-portal}/libexec/xdg-desktop-portal"
    ];
  };

  systemd.user.services.xdg-desktop-portal-gtk = {
    Service.ExecStart = [
      ""
      "${pkgs.xdg-desktop-portal-gtk}/libexec/xdg-desktop-portal-gtk"
    ];
  };

  systemd.user.services.xdg-desktop-portal-wlr = {
    Service.ExecStart = [
      ""
      "${pkgs.xdg-desktop-portal-wlr}/libexec/xdg-desktop-portal-wlr"
    ];
  };
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-wlr
    ];
    config = {
      common.default = [ "gtk" ];
      niri = {
        default = [ "gtk" ];
        "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
        "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
      };
    };
  };
  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "x-scheme-handler/http" = [ "firefox.desktop" ];
      "x-scheme-handler/https" = [ "firefox.desktop" ];
      "x-scheme-handler/chrome" = [ "firefox.desktop" ];
      "text/html" = [ "firefox.desktop" ];
      "application/x-extension-htm" = [ "firefox.desktop" ];
      "application/x-extension-html" = [ "firefox.desktop" ];
      "application/x-extension-shtml" = [ "firefox.desktop" ];
      "application/xhtml+xml" = [ "firefox.desktop" ];
      "application/x-extension-xhtml" = [ "firefox.desktop" ];
      "application/x-extension-xht" = [ "firefox.desktop" ];
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
    libcamera
    libgtop
    playerctl
    cliphist
    sqlite

    awww # Added for high-performance wallpaper management
    # ... other packages
  ];
  programs.hyprlock = {
    enable = true;
    # Keeping your existing "empty" package hack if you are installing via apt/outside Nix
    package = pkgs.runCommand "empty" { } "mkdir -p $out";

    settings = {
      general = {
        disable_loading = true;
        grace = 0;
        hide_cursor = true;
        no_fade_in = false;
      };

      # Background - Matching your swww wallpaper or a solid dark theme
      background = [
        {
          path = "screenshot"; # Update this to your actual path
          color = "rgba(25, 20, 20, 1.0)";
          blur_passes = 5; # 0 disables blurring
          blur_size = 4;
          noise = 0.02;
          contrast = 0.8916;
          brightness = 0.8172;
          vibrancy = 0.1696;
          vibrancy_darkness = 0.0;
        }
      ];

      label = [
        {
          text = "$TIME"; # Hyprlock native variable is more efficient than a cmd
          color = "rgba(255, 255, 255, 1.0)";
          font_size = 90;
          font_family = "Inter Bold"; # Or your preferred font
          position = "-30, 0";
          halign = "right";
          valign = "top";
        }
        # Date (Sub-label)
        {
          text = "cmd[update:43200000] echo \"$(date +'%A, %d %B')\"";
          color = "rgba(255, 255, 255, 0.7)";
          font_size = 24;
          position = "-35, -120";
          halign = "right";
          valign = "top";
        }
      ];
      input-field = [
        {
          size = "250, 50";
          outline_thickness = 2;
          dots_size = 0.2;
          dots_spacing = 0.6;
          dots_center = true;
          outer_color = "rgba(136, 192, 208, 0.6)"; # Your Niri Frost color
          inner_color = "rgba(0, 0, 0, 0)"; # Completely transparent
          font_color = "rgb(255, 255, 255)";
          fade_on_empty = false;
          placeholder_text = "Password";
          hide_input = false;
          rounding = -1; # Circle

          # Feedback colors (optional but helpful since inner is transparent)
          check_color = "rgba(136, 192, 208, 1.0)";
          fail_color = "rgba(191, 97, 106, 1.0)"; # Nord Red for errors

          position = "0, -100";
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
      input = {
        keyboard.repeat-delay = 300;
        keyboard.repeat-rate = 25;

        # Ensures your mouse behaves like a modern desktop
        touchpad = {
          tap = true;
          dwt = true; # disable-while-typing
          natural-scroll = true;
        };

        mouse.natural-scroll = false;

        # Allows focus to change as you move the mouse
        focus-follows-mouse = {
          enable = true;
          # This prevents the 'focus' from jumping monitors just because
          # the mouse is at the edge.
          max-scroll-amount = "0%";
        };
        warp-mouse-to-focus = true;
        workspace-auto-back-and-forth = false;
      };
      layout = {
        # Gaps: The secret sauce of a clean desktop
        gaps = 20;
        center-focused-column = "never";

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
      # outputs."DP-8" = {
      #   mode = {
      #     width = 1920;
      #     height = 1200;
      #   };
      #   position = {
      #     x = 1536;
      #     y = 0;
      #   };
      # };
      # outputs."DP-9" = {
      #   mode = {
      #     width = 1920;
      #     height = 1200;
      #   };
      #   position = {
      #     x = 3456;
      #     y = 0;
      #   };
      #   transform.rotation = 270;
      # };

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
              sleep 0.5
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
        { command = [ "tailscalnm-ae systray" ]; }
        { command = [ "nm-applet" ]; }
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
          # "Mod+D".action = actions.spawn "nixGLMesa" "wofi" "--show" "drun";
          "Mod+D".action = actions.spawn "noctalia-shell" "ipc" "call" "launcher" "toggle";
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
          "Mod+WheelScrollDown" = {
            action = actions.focus-workspace-down;
            cooldown-ms = 250;
          };
          "Mod+WheelScrollUp" = {
            action = actions.focus-workspace-up;
            cooldown-ms = 250;
          };
          "Mod+Alt+WheelScrollDown".action = actions.focus-column-right;
          "Mod+Alt+WheelScrollUp".action = actions.focus-column-left;
          # Keybindings written exactly how the Niri module expects them
          "Mod+V".action.spawn = [
            "noctalia-shell"
            "ipc"
            "call"
            "plugin:clipboard"
            "toggle"
          ];

          "Mod+Z".action.spawn = [
            "noctalia-shell"
            "ipc"
            "call"
            "plugin:zed-provider"
            "toggle"
          ];
        };
    };
  };

  # Noctalia Shell styling to match the Monochrome theme
  programs.noctalia-shell = {
    enable = true;

    # --- Plugin Configuration ---
    plugins = {
      version = 2;
      sources = [
        {
          enabled = true;
          name = "Official Noctalia Plugins";
          url = "https://github.com/noctalia-dev/noctalia-plugins";
        }
      ];
      states = {
        # This tells the shell to download and enable the tailscale plugin
        #
        tailscale = {
          enabled = true;
          sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
        };
        zed-provider = {
          enabled = true;
          sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
        };
        privacy-indicator = {
          enabled = true;
          sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
        };
        clipboard = {
          enabled = true;
          sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
        };
        latency-monitor = {
          enabled = true;
          sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
        };
        network-manager-vpn = {
          enabled = true;
          sourceUrl = "https://github.com/noctalia-dev/noctalia-plugins";
        };
      };
    };

    # If the tailscale plugin has specific settings, they go here
    pluginSettings = {
      tailscale = {
        # Add any plugin-specific options here if needed
      };
      clipboard = {
        maxHistorySize = 100;
        showImagePreviews = true;
        density = "comfortable";
      };
      privacy-indicator = {
        hideInactive = false;
        enableToast = true;
        removeMargins = false;
        iconSpacing = 4;
        activeColor = "primary";
        inactiveColor = "none";
        micFilterRegex = "";
        camFilterRegex = "";
      };
      latency-monitor = {
        hosts = [
          {
            name = "xhain";
            address = "johann-hackler.com";
          }
        ];
        intervalSeconds = 5;
        thresholdGood = 20;
        thresholdWarning = 70;
        showHostName = true;
        barHost = "worst";
        colorGood = "#00ff7f";
        colorWarning = "#f1fa8c";
        colorCritical = "#ff5555";
        animations = false;
      };
    };

    # --- Shell Settings ---
    settings = {
      bar = {
        density = "default";
        position = "top";
        showCapsule = true;
        widgets = {
          left = [
            {
              id = "ControlCenter";
              useDistroLogo = false;
            }
            # {
            #   id = "Network";
            #   showLabel = true;
            # }
            { id = "plugin:network-manager-vpn"; }
            { id = "SystemMonitor"; }
            # Add the Tailscale widget to the bar
            # { id = "plugin:tailscale"; }
            # { id = "plugin:latency-monitor"; }
          ];
          center = [
            {
              id = "Workspace";
              labelMode = "none";
              showApplications = true;
              showWorkspaceBadge = false;
              hideUnoccupied = false;
              showLabelsOnlyWhenOccupied = false;
              iconScaling = 80;
              unfocusedIconsOpacity = 100;
            }
          ];
          right = [
            { id = "plugin:clipboard"; }
            # { id = "AudioVisualizer"; }
            {
              id = "Tray";
              pinned = [
                "nm-applet"
                "tailscale"
              ];
            }
            { id = "Battery"; }
            {
              id = "Clock";
              formatHorizontal = "HH:mm - dd.MM.yyyy";
            }
            { id = "Bluetooth"; }
            { id = "KeepAwake"; }
            { id = "plugin:privacy-indicator"; }
            { id = "NotificationHistory"; }
          ];
        };
      };
      colorSchemes.predefinedScheme = "Monochrome";
      general.radiusRatio = 0.2;
    };
  };
}
