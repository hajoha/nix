{
  pkgs,
  lib,
  config,
  ...
}:
{
  programs.nvf = {
    enable = true;
    settings = {

      vim.viAlias = true;
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

}
