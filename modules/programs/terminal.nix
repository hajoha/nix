{ pkgs, config, ... }: {

  # Essential packages for the visual upgrades
  home.packages = with pkgs; [
    fzf            # Fuzzy finder for history/files
    zoxide         # Smarter 'cd' (jump to directories)
    eza            # Modern 'ls' with icons
    ghostty.terminfo
  ];

  # --- Terminal: Ghostty ---
  programs.ghostty = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      theme = "Catppuccin Mocha"; # One of the cleanest themes available
      font-family = "JetBrainsMono Nerd Font";
      font-size = 11;
      window-padding-x = 10;
      window-padding-y = 10;
      cursor-style = "block";
    };
  };

  # --- Prompt: Starship (The "Beautiful" Part) ---
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    # Customizing the look to be minimal yet informative
    settings = {
      add_newline = true;
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[➜](bold red)";
      };
      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
      };
    };
  };

  # --- Shell: Zsh ---
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;      # Ghost-text completions
    syntaxHighlighting.enable = true;  # Colors commands as you type
    shellAliases = {
      # Modern replacements
      ls = "eza --icons --group-directories-first";
      ll = "eza -l --icons --git --group-directories-first";
      la = "eza -a --icons --group-directories-first";
      tree = "eza --tree --icons";
      
      # Navigation & Workflow
      cd = "z"; # Use zoxide jump instead of manual cd
      update = "home-manager switch --flake ~/.config/home-manager#haa";
      ".." = "cd ..";
    };

    history = {
      size = 10000;
      ignoreDups = true;
      path = "${config.xdg.dataHome}/zsh/history";
    };

    # Oh My Zsh for backend plugin support
    oh-my-zsh = {
      enable = true;
      plugins = [ 
        "git" 
        "sudo" 
        "fzf" 
      ];
      # Theme is set to null because Starship handles the prompt
      theme = ""; 
    };

    # Extra init for interactive features
    initExtra = ''
      if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
        exec nixGLMesa sway
      fi
      # Bind arrow keys for prefix-based history search
      bindkey '^[[A' up-line-or-search
      bindkey '^[[B' down-line-or-search
    '';
  };

  # --- Smarter Directory Jumping ---
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # --- File Manager: Yazi ---
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      manager = {
        ratio = [ 1 4 3 ];
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
        ueberzug_offset = [ 0 0 0 0 ];
      };
    };

    plugins = {
          "bypass"      = pkgs.yaziPlugins.bypass;
          "chmod"       = pkgs.yaziPlugins.chmod;
          "full-border" = pkgs.yaziPlugins.full-border;
          "lazygit"     = pkgs.yaziPlugins.lazygit;
          "mediainfo"   = pkgs.yaziPlugins.mediainfo;
          "no-status"   = pkgs.yaziPlugins.no-status;
          "ouch"        = pkgs.yaziPlugins.ouch;
          "restore"     = pkgs.yaziPlugins.restore;
          "smart-enter" = pkgs.yaziPlugins.smart-enter;
          "toggle-pane" = pkgs.yaziPlugins.toggle-pane;
        };
  };
  
  programs.wofi = {
    enable = true;
    settings = {
      allow_images = true;
      image_size = 24;
      width = 450;
      height = 500;
      location = "center";
      hide_scroll = true;
      prompt = "Run Applications";
      insensitive = true;
    };
    style = ''
      window {
        font-family: "Geist Mono";
        background-color: #11111b;
        color: #cdd6f4;
      }
      #entry:selected {
        background-color: #313244;
      }
      #img {
        margin-right: 10px;
      }
    '';
  };
}