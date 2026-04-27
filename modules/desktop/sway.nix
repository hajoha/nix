{
  pkgs,
  inputs,
  config,
  ...
}:
{
  # xdg.portal = {
  #   enable = true;
  #   # Use gtk for file pickers and wlr for screen sharing
  #   extraPortals = [
  #     pkgs.xdg-desktop-portal-wlr
  #     pkgs.xdg-desktop-portal-gtk
  #     pkgs.xdg-desktop-portal

  #   ];
  #   xdgOpenUsePortal = false;
  #   config = {
  #     common = {
  #       default = [ "gtk" ];
  #       "org.freedesktop.impl.portal.Screenshot" = [ "wlr" ];
  #       "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
  #     };
  #   };
  # };
  # systemd.user.enable = true;

  # home.file.".config/systemd/user/xdg-desktop-portal-wlr.service".source =
  #   "${pkgs.xdg-desktop-portal-wlr}/lib/systemd/user/xdg-desktop-portal-wlr.service";

  # home.file.".config/systemd/user/xdg-desktop-portal.service".source =
  #   "${pkgs.xdg-desktop-portal}/lib/systemd/user/xdg-desktop-portal.service";

  # home.file.".config/systemd/user/xdg-desktop-portal-gtk.service".source =
  #   "${pkgs.xdg-desktop-portal-gtk}/lib/systemd/user/xdg-desktop-portal-gtk.service";

  home.packages = with pkgs; [
    adwaita-icon-theme
    gnome-themes-extra
    brightnessctl
    wl-clipboard
    # pipewire
    cliphist
    #   pavucontrol
    nerd-fonts.fira-code # Modern way to include Fira Code Nerd Font
    nerd-fonts.symbols-only # Great fallback for all icons
  ];

  services.swaync = {
    enable = true;
    settings = {
      positionX = "right";
      positionY = "top";
      layer = "top";
      control-center-margin-top = 10;
      control-center-margin-bottom = 10;
      control-center-margin-right = 10;
      control-center-margin-left = 10;
      notification-icon-size = 64;
      notification-body-image-height = 100;
      notification-body-image-width = 200;
    };
  };

  programs.waybar = {
    enable = true;
    systemd.enable = true;
    systemd.target = "graphical-session.target"; # Ensures it starts with Sway

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
          "idle_inhibitor"
          "custom/divider"
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
        "idle_inhibitor" = {
          format = "{icon}";
          format-icons = {
            activated = ""; # Eye open icon
            deactivated = ""; # Eye closed icon
          };
        };
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
        "pulseaudio" = {
          # {format_source} pulls in the microphone status
          format = "{icon} {volume}% | {format_source}";
          format-bluetooth = "{icon} {volume}% | {format_source}";
          format-muted = "󰝟 Muted | {format_source}";

          # Microphone specific formatting
          format-source = " {volume}%";
          format-source-muted = "";

          tooltip = false;
          on-click = "pavucontrol";
          on-scroll-up = "wpctl set-volume @DEFAULT_SINK@ 5%+";
          on-scroll-down = "wpctl set-volume @DEFAULT_SINK@ 5%-";

          format-icons = {
            headphone = "";
            hands-free = "";
            headset = "";
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
          tooltip = true;
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

  wayland.windowManager.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    systemd.enable = true;
    package = config.lib.nixGL.wrap pkgs.sway;
    extraConfig = ''
      # 1. Laptop Screen (eDP-1)
        # Starting at the origin (0,0)
        output eDP-1 pos 0 0 res 1920x1200

        # 2. Main External Monitor (DP-8)
        # Positioned exactly after the laptop width (1920)
        output DP-8 pos 1920 0 res 1920x1200

        # 3. Vertical Monitor (DP-9)
        # Positioned after laptop + main width (1920 + 1920 = 3840)
        # It is 1200 units wide logically because of the transform.
        output DP-9 pos 3840 0 res 1920x1200 transform 90
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
              before-sleep 'swaylock -f -c 000000' \
              timeout 5 'if pgrep -x swaylock; then swaymsg "output * dpms off"; fi' \
              resume 'swaymsg "output * dpms on"' \
              switch:on:Lid\ Input 'swaylock -f -c 000000'
      exec cliphist wipe
      exec wl-paste --watch cliphist store
      exec gnome-keyring-daemon --start --components=ssh


    '';
    config = {
      modifier = "Mod4"; # Super/Windows key
      terminal = "nixGLMesa ghostty";
      defaultWorkspace = "workspace number 1";
      menu = "nixGLMesa wofi --show drun"; # You can replace this with bemenu, fuzzel, etc.
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
        "${config.wayland.windowManager.sway.config.modifier}+f" = "fullscreen toggle";

        "${config.wayland.windowManager.sway.config.modifier}+Shift+v" = ''
          exec nixGLMesa cliphist list | sed -E "s/^([0-9]+)\t/\1 /" | wofi --dmenu | sed -E "s/^([0-9]+) /\1\t/" | cliphist decode | wl-copy
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

        "XF86AudioRaiseVolume" = "exec wpctl set-volume -l 1.5 @DEFAULT_SINK@ 5%+";
        "XF86AudioLowerVolume" = "exec wpctl set-volume @DEFAULT_SINK@ 5%-";
        "XF86AudioMute" = "exec wpctl set-mute @DEFAULT_SINK@ toggle";
        "XF86AudioMicMute" = "exec wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";

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
        names = [
          "FiraCode Nerd Font"
          "Font Awesome 6 Free"
        ];
        size = 10.0;
      };

      gaps = {
        inner = 0;
        outer = 0;
      };
      bars = [ ];
      startup = [
        # 1. Force the DBus session to pick up ALL Nix environment variables
        { command = "dbus-update-activation-environment --systemd --all"; }
        { command = "systemctl --user import-environment PATH SSH_AUTH_SOCK"; }

        # 2. Kill any existing portal processes (Ubuntu's or hung Nix ones)
        { command = "pkill -f xdg-desktop-portal"; }

        # 3. Start the Nix-managed portals explicitly
        {
          command = "systemctl --user start xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk";
        }

        # 4. Standard services
        { command = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"; }
        { command = "systemctl --user restart pipewire wireplumber swaync"; }
        { command = "systemctl --user stop waybar && systemctl --user start waybar"; }
        {
          command = "sh -c 'sleep 5; nm-applet --indicator & 1password --silent & opencloud & blueman-applet &'";
        }
      ];
    };
  };

}
