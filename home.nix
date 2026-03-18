{ config, pkgs, ... }:

let
  dotfiles = "${config.home.homeDirectory}/dotfiles/config";
  create_symlink = path: config.lib.file.mkOutOfStoreSymlink path;
in
{
  home.username = "toni";
  home.homeDirectory = "/home/toni";
  home.stateVersion = "25.11";

  # home.packages = with pkgs; [
  # ];

  xdg.configFile."hypr".source = create_symlink "${dotfiles}/hypr";
  xdg.configFile."hyprpanel".source = create_symlink "${dotfiles}/hyprpanel";
  xdg.configFile."zsh/.zshrc".source = create_symlink "${dotfiles}/zsh/.zshrc";
  xdg.configFile.".p10k.zsh".source = create_symlink "${dotfiles}/p10k/.p10k.zsh";
  xdg.configFile."sioyek".source = create_symlink "${dotfiles}/sioyek";
  # xdg.configFile."nvim/init.lua".source = create_symlink "${dotfiles}/neovim/init.lua";

  stylix.fonts = {
    monospace = {
      package = pkgs.nerd-fonts.jetbrains-mono;
      name = "JetBrainsMono Nerd Font Mono";
    };
    sansSerif = {
      package = pkgs.dejavu_fonts;
      name = "DejaVu Sans";
    };
    serif = {
      package = pkgs.dejavu_fonts;
      name = "DejaVu Serif";
    };
  };

  programs.firefox = {
    # only browser where screen sharing works well and can be configured declaratively
    enable = true;
    # Policies
    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      EnableTrackingProtection = {
        Value = true;
        Locked = true;
        Cryptomining = true;
        Fingerprinting = true;
      };
      DisablePocket = true;
      OverrideFirstRunPage = "";
      DisableFirefoxScreenshots = true;
      OverridePostUpdatePage = "";
      DontCheckDefaultBrowser = true;

      # Extensions
      ExtensionSettings = {
        # bitwarden extension
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/{446900e4-71c2-419f-a6a7-df9c091e268b}/latest.xpi";
          installation_mode = "normal_installed";
        };
        # Vimium
        "{d7742d87-e61d-4b78-b8a1-b469842139fa}" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/{d7742d87-e61d-4b78-b8a1-b469842139fa}/latest.xpi";
          installation_mode = "normal_installed";
        };
        # Ghostery Ad and Cookie Blocker
        "firefox@ghostery.com" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/firefox@ghostery.com/latest.xpi";
          installation_mode = "normal_installed";
        };
        # Tab Numbering
        "@tab-numbering.NoorHajDawood" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/@tab-numbering.NoorHajDawood/latest.xpi";
          installation_mode = "normal_installed";
        };
      };

      Preferences = {
        "browser.startup.homepage" = "https://google.com";
      };
    };
  };

  programs.ghostty = {
    # only terminal that is styled by stylix and has image support for yazi. Kitty didnt work.
    enable = true;
    settings = {
      confirm-close-surface = false;
    };
  };

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    vimdiffAlias = true;

    plugins = with pkgs.vimPlugins; [
      # LSP and completion
      nvim-lspconfig
      fidget-nvim
      blink-cmp
      luasnip
      lazydev-nvim

      # File explorer
      neo-tree-nvim
      nvim-web-devicons
      nui-nvim
      plenary-nvim

      # Bufferline (tabs)
      bufferline-nvim

      # Motion
      flash-nvim

      # Utilities
      guess-indent-nvim
      gitsigns-nvim
      which-key-nvim

      # Fuzzy finder
      telescope-nvim
      telescope-fzf-native-nvim
      telescope-ui-select-nvim

      # Formatting
      conform-nvim

      # Theme
      gruvbox-material

      # Todo comments
      todo-comments-nvim

      # Mini.nvim
      mini-nvim

      # Autopairs
      nvim-autopairs

      # Comments
      comment-nvim

      # Treesitter
      (nvim-treesitter.withPlugins (p: [
        p.tree-sitter-nix
        p.tree-sitter-typst
        p.tree-sitter-bash
        p.tree-sitter-python
        p.tree-sitter-json
        p.tree-sitter-yaml
        p.tree-sitter-html
        p.tree-sitter-css
        p.tree-sitter-javascript
        p.tree-sitter-typescript
        p.tree-sitter-just
        p.tree-sitter-markdown
        p.tree-sitter-rust
        p.tree-sitter-lua
        p.tree-sitter-vim
        p.tree-sitter-vimdoc
        p.tree-sitter-diff
        p.tree-sitter-c
      ]))
    ];
    extraLuaConfig = builtins.readFile ./config/neovim/init.lua;
  };

  stylix.targets.neovim.enable = false;

  programs.btop.enable = true;
  programs.yazi.enable = true;
  programs.vicinae = {
    enable = true;
    settings = {
      theme = {
        name = "gruvbox-dark";
      };
    };
  };

  programs.discord.enable = true;

  services.udiskie = {
    # auto mounting external drives
    enable = true;
    tray = "auto"; # only show in tray if device is available
  };
}
