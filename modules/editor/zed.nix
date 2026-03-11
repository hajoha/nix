{ pkgs, lib, ... }:
{

  home.packages = with pkgs; [
    nixd
    nixfmt
  ];
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
      autosave = {
        after_delay = {
          milliseconds = 200;
        };
      };
      assistant = {
        enabled = false;
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
        pyright = {
          binary = {
            path_lookup = true;
          };
        };
        ruff = {
          binary = {
            path_lookup = true;
          };
          # Optional: tell Ruff to fix all auto-fixable rules on save
          settings = {
            fixAll = true;
            organizeImports = true;
          };
        };

        nil = {
          binary = {
            path_lookup = true; # Tells Zed to find the 'nil' you just installed
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
          format_on_save = "on"; # Fixed: simplified to "on"
          formatter = {
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
          format_on_save = "on"; # Fixed: simplified to "on"
          formatter = {
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
        "Nix" = {
          language_servers = [
            "nixd"
          ];
          format_on_save = "on";
          formatter = {
            external = {
              command = "nixfmt"; # Matches the package added above
            };
          };
        };

        "Python" = {
          language_servers = [
            "pyright"
            "ruff"
            "!pylsp"
          ];
          format_on_save = "on"; # Fixed: simplified to "on"
          formatter = {
            language_server = {
              name = "ruff";
            };
          };
        };
      };

      vim_mode = false;

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

}
