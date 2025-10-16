{
  lib,
  config,
  system,
  pkgs,
  inputs,
  ...
}:
let
  firefox-config = import ./../../modules/browser/firefox.nix {
    inherit pkgs;
    inherit inputs;
  };
in
{

  nixpkgs = {
    overlays = [
      inputs.nur.overlays.default
    ];
    config = {
      allowUnfree = true;
    };

  };
  imports = [
    firefox-config
    inputs.nvf.homeManagerModules.default
  ];
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
    extraConfig = ''

      set $left h
      set $down j
      set $up k
      set $right l

      for_window [title="nmtui-floating"] floating enable, move position center, focus
      for_window [title="btop-floating"] floating enable, move position center, focus

      assign [class="Signal"] workspace 1
      assign [app_id="thunderbird"] workspace 1
      assign [app_id="firefox"] workspace 2


      exec firefox
      exec thunderbird
      exec signal-desktop

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
        "${config.wayland.windowManager.sway.config.modifier}+f" = "fullscreen toggle";

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
        {
          command = "pgrep waybar > /dev/null || waybar &";
          always = true;
        }
        {
          command = "exec dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=sway";
        }
        {
          command = "exec systemctl --user restart pipewire-media-session xdg-desktop-portal xdg-desktop-portal-wlr xdg-desktop-portal-gtk swaync";
        }
        { command = "sh -c 'swaymsg workspace 1; swaymsg layout tabbed'"; }

      ];

    };
  };

  programs.swaylock.enable = true;

  home.packages = with pkgs; [
    # 3D-stuff
    freecad
    ferrishot
    way-displays
    #orca-slicer
    #cura
    ffmpeg
    libqmi
    tmux
    zsh
    inkscape
    ausweisapp
    spice-gtk
    poppler-utils
    solaar
    pdfpc
    gcc
    inetutils
    zip
    tio
    nextcloud-client
    vlc
    xz
    unzip
    p7zip
    tor-browser
    anydesk
    chromium
    gimp
    python312Full
    python312Packages.pyudev
    python312Packages.systemd
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
    noto-fonts-emoji
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
    thunderbird
    killall
    #jetbrains.pycharm-professional
    #jetbrains.clion
    (jetbrains.plugins.addPlugins pkgs.jetbrains.clion [ "github-copilot" ])
    (jetbrains.plugins.addPlugins pkgs.jetbrains.pycharm-professional [
      "github-copilot"
      "nixidea"
    ])
    android-studio
    nixfmt-rfc-style
    ollama
    wdisplays
    alacritty
    #    xdg-desktop-portal
    #    xdg-desktop-portal-wlr
    #    xdg-desktop-portal-gtk
    #    xdg-desktop-portal-hyprland

    socat

    pavucontrol
    pipewire
    wireplumber
    wofi
    swaylock
    swayidle
    wl-clipboard
    swaynotificationcenter
    waybar # status bar
    noto-fonts-emoji # Best overall support
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
  };
  fonts.fontconfig.enable = false;

  programs.git = {
    enable = true;
    userName = "hajoha";
    userEmail = "hajoha1@proton.me";
  };

  programs.zsh = {
    enable = true;
    enableCompletion = true;

    shellAliases = {
      ll = "ls -l";
      update = "sudo nixos-rebuild switch";
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
    QT_QPA_PLATFORMTHEME = "qt5ct";
    QT_STYLE_OVERRIDE = "kvantum";
  };

  programs.waybar = {
    enable = true;
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
          #          "tray"
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
          icon-size = 13;
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
