{ pkgs, config, ... }: {
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

home.packages = with pkgs; [
    ripgrep jq yq-go eza fzf btop # Generic CLI tools
    zip unzip p7zip
    # ... etc
  ];
  
  }