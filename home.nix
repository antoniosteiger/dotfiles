{
  config,
  pkgs,
  hostType ? "desktop",
  ...
}:

let
  dotfiles = "${config.home.homeDirectory}/dotfiles/config";
  create_symlink = path: config.lib.file.mkOutOfStoreSymlink path;

  # Determine which host-specific Hyprland config to use
  hyprHostConfig = if hostType == "laptop" then "host-laptop.conf" else "host-desktop.conf";
in
{
  home.username = "toni";
  home.homeDirectory = "/home/toni";
  home.stateVersion = "25.11";

  # home.packages = with pkgs; [
  # ];

  xdg.configFile."hypr/hypridle.conf".source = create_symlink "${dotfiles}/hypr/hypridle.conf";
  xdg.configFile."hypr/hyprland.conf".source = create_symlink "${dotfiles}/hypr/hyprland.conf";
  xdg.configFile."hypr/hyprlock.conf".source = create_symlink "${dotfiles}/hypr/hyprlock.conf";
  xdg.configFile."hypr/host-specific.conf".source =
    create_symlink "${dotfiles}/hypr/${hyprHostConfig}";
  xdg.configFile."wayle/config.toml".source = create_symlink "${dotfiles}/wayle/config.toml";
  xdg.configFile."xdg-desktop-portal-termfilechooser/config".source =
    create_symlink "${dotfiles}/xdg-desktop-portal-termfilechooser/config";
  xdg.configFile."xdg-desktop-portal-termfilechooser/yazi-wrapper.sh".source =
    create_symlink "${dotfiles}/xdg-desktop-portal-termfilechooser/yazi-wrapper.sh";
  xdg.configFile."zsh/.zshrc".source = create_symlink "${dotfiles}/zsh/.zshrc";
  xdg.configFile."sioyek".source = create_symlink "${dotfiles}/sioyek";
  # xdg.configFile."nvim/init.lua".source = create_symlink "${dotfiles}/neovim/init.lua";

  # pi coding agent — managed config. Uses home.file (not xdg.configFile) because pi
  # reads from ~/.pi/agent/ and ~/.agents/, not ~/.config/. auth.json and runtime
  # caches (models-store.json, npm/, sessions/, ~/.agents/.skill-lock.json) stay in
  # place, unmanaged.
  home.file.".pi/agent/settings.json".source = create_symlink "${dotfiles}/pi/settings.json";
  home.file.".pi/agent/extensions".source = create_symlink "${dotfiles}/pi/extensions";
  home.file.".agents/skills".source = create_symlink "${dotfiles}/pi/skills";

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
    configPath = "${config.xdg.configHome}/mozilla/firefox";
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
        # 1Password:
        "{d634138d-c276-4fc8-924b-40a0ea21d284}" = {
          install_url = "https://addons.mozilla.org/firefox/downloads/latest/{d634138d-c276-4fc8-924b-40a0ea21d284}/latest.xpi";
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
        "dom.webgpu.enabled" = true;
        "gfx.webgpu.force-enabled" = true;
        "gfx.webrender.all" = true;
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

  programs.starship = {
    enable = true;
    settings = builtins.fromTOML (builtins.readFile ./config/starship/starship.toml);
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
      ccc-nvim

      # Fuzzy finder
      telescope-nvim
      telescope-fzf-native-nvim
      telescope-ui-select-nvim
      # Replace
      grug-far-nvim

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
    initLua = builtins.readFile ./config/neovim/init.lua;
    withPython3 = false;
    withRuby = false;
  };

  stylix.targets.neovim.enable = false;
  stylix.targets.starship.enable = false;
  stylix.targets.firefox.profileNames = [ "Default" ];

  programs.btop.enable = true;
  programs.yazi = {
    enable = true;
    shellWrapperName = "y";

    plugins = with pkgs.yaziPlugins; {
      smart-enter.package = smart-enter;
      compress.package = compress;
      clipboard.package = clipboard;
    };

    settings = {
      # general yazi.toml config goes here (empty for now, unless you have other settings)
    };

    keymap = {
      mgr.prepend_keymap = [
        {
          on = [
            "c"
            "a"
            "a"
          ];
          run = "plugin compress";
          desc = "Archive selected files";
        }
        {
          on = [
            "c"
            "a"
            "p"
          ];
          run = "plugin compress -p";
          desc = "Archive selected files (password)";
        }
        {
          on = [
            "c"
            "a"
            "l"
          ];
          run = "plugin compress -l";
          desc = "Archive selected files (compression level)";
        }

        {
          on = "y";
          run = [
            "yank"
            "plugin clipboard -- --action=copy"
          ];
          desc = "Yank selected files (copy)";
        }
        {
          on = "x";
          run = [
            "yank --cut"
            "plugin clipboard -- --action=copy"
          ];
          desc = "Yank selected files (cut)";
        }
        {
          on = "<C-p>";
          run = [ "plugin clipboard -- --action=paste" ];
          desc = "Paste yanked system clipboard files";
        }

        {
          on = "l";
          run = "plugin smart-enter";
          desc = "Enter the child directory, or open the file";
        }
      ];
    };
  };

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
