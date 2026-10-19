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

  xdg.configFile."hypr/hyprland.conf".source = create_symlink "${dotfiles}/hypr/hyprland.conf";
  xdg.configFile."hypr/host-specific.conf".source =
    create_symlink "${dotfiles}/hypr/${hyprHostConfig}";
  xdg.configFile."noctalia/config.toml".source = create_symlink "${dotfiles}/noctalia/config.toml";
  xdg.configFile."xdg-desktop-portal-termfilechooser/config".source =
    create_symlink "${dotfiles}/xdg-desktop-portal-termfilechooser/config";
  xdg.configFile."xdg-desktop-portal-termfilechooser/yazi-wrapper.sh".source =
    create_symlink "${dotfiles}/xdg-desktop-portal-termfilechooser/yazi-wrapper.sh";
  xdg.configFile."zsh/.zshrc".source = create_symlink "${dotfiles}/zsh/.zshrc";
  xdg.configFile."sioyek".source = create_symlink "${dotfiles}/sioyek";

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

  # Open folders in yazi from GUI apps. yazi.desktop has Terminal=true, which xdg-open
  # ignores on Hyprland: it runs a bare `yazi` without a tty, which dies silently.
  # This entry launches ghostty itself, so it works via xdg-open, gio and portals.
  xdg.desktopEntries.yazi-ghostty = {
    name = "Yazi";
    genericName = "File Manager";
    exec = "ghostty -e yazi %f";
    terminal = false;
    icon = "yazi";
    mimeType = [ "inode/directory" ];
    categories = [
      "System"
      "FileManager"
    ];
  };

  xdg.mimeApps = {
    enable = true;
    defaultApplications = {
      "inode/directory" = "yazi-ghostty.desktop";
      "x-scheme-handler/claude-cli" = "claude-code-url-handler.desktop";
    };
  };

  # Terminal for apps that launch Terminal=true entries through GLib/gio.
  home.packages = [
    pkgs.xdg-terminal-exec
    pkgs.glib # `gio` CLI: the yazi devices plugin uses it to list/unmount drives and phones
  ];
  xdg.configFile."xdg-terminals.list".text = "com.mitchellh.ghostty.desktop\n";

  programs.starship = {
    enable = true;
    settings = builtins.fromTOML (builtins.readFile ./config/starship/starship.toml);
  };

  programs.neovim = {
    enable = true;
    defaultEditor = true;
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

  programs.btop.enable = true;
  programs.yazi =
    let
      # Put files on the clipboard as file:// URIs, so they paste as files into Slack, browsers, etc.
      yaziCopy = pkgs.writeShellApplication {
        name = "yazi-copy";
        runtimeInputs = [ pkgs.wl-clipboard ];
        text = ''
          encode() {
            # LC_ALL=C: walk bytes, so non-ASCII names get UTF-8 percent-encoding
            local LC_ALL=C s="$1" out="" c i
            for ((i = 0; i < ''${#s}; i++)); do
              c="''${s:i:1}"
              case "$c" in
                [A-Za-z0-9/._~-]) out+="$c" ;;
                *) out+=$(printf '%%%02X' "'$c") ;;
              esac
            done
            printf '%s' "$out"
          }
          for f in "$@"; do
            printf 'file://%s\r\n' "$(encode "$(realpath "$f")")"
          done | wl-copy -t text/uri-list
        '';
      };

      # Mail files with Aerion; folders are zipped first (one <name>.zip each).
      yaziMail = pkgs.writeShellApplication {
        name = "yazi-mail";
        runtimeInputs = [ pkgs.zip ];
        text = ''
          # Aerion reads attachments only once the composer opens, so archives
          # stay around; $XDG_RUNTIME_DIR is tmpfs and old runs are swept here.
          base="''${XDG_RUNTIME_DIR:-/tmp}/yazi-mail"
          mkdir -p "$base"
          find "$base" -mindepth 1 -maxdepth 1 -mmin +60 -exec rm -rf {} +
          dir=$(mktemp -d "$base/XXXXXX")
          files=()
          for f in "$@"; do
            if [ -d "$f" ]; then
              path=$(realpath "$f")
              name=$(basename "$path")
              (cd "$(dirname "$path")" && zip -qr "$dir/$name.zip" "$name")
              files+=("$dir/$name.zip")
            else
              files+=("$f")
            fi
          done
          exec aerion --attach -- "''${files[@]}"
        '';
      };

      # Print through CUPS; asks for a printer when there is more than one.
      yaziPrint = pkgs.writeShellApplication {
        name = "yazi-print";
        runtimeInputs = [ pkgs.cups ];
        text = ''
          mapfile -t printers < <(lpstat -e 2>/dev/null)
          if [ "''${#printers[@]}" -eq 0 ]; then
            echo "No printers configured. Add one at http://localhost:631"
            read -rp "Press enter to close" _
            exit 1
          fi
          if [ "''${#printers[@]}" -eq 1 ]; then
            dest="''${printers[0]}"
          else
            default=$(lpstat -d 2>/dev/null | sed -n 's/^system default destination: //p')
            echo "Printer (default: ''${default:-none}):"
            select dest in "''${printers[@]}"; do [ -n "$dest" ] && break; done
          fi
          printf 'Print %s file(s) on %s? [Y/n] ' "$#" "$dest"
          read -r answer
          case "$answer" in [nN]*) exit 0 ;; esac
          lp -d "$dest" "$@"
          read -rp "Press enter to close" _
        '';
      };
    in
    {
      enable = true;
      shellWrapperName = "y";

      plugins = with pkgs.yaziPlugins; {
        smart-enter.package = smart-enter;
        compress.package = compress;
        clipboard.package = clipboard;
        # Own plugin: one menu for every mounted drive/phone/camera (via gvfs).
        devices = ./config/yazi/plugins/devices.yazi;
      };

      settings = {
        # Extra openers, offered in the `open --interactive` menu (<S-Enter>).
        # The default openers (edit/open/play/reveal/extract) stay as they are.
        opener = {
          gimp = [
            {
              run = "gimp %s";
              desc = "GIMP";
              for = "unix";
              orphan = true;
            }
          ];
          inkscape = [
            {
              run = "inkscape %s";
              desc = "Inkscape";
              for = "unix";
              orphan = true;
            }
          ];
          mpv = [
            {
              run = "mpv %s";
              desc = "mpv";
              for = "unix";
              orphan = true;
            }
          ];
          browser = [
            {
              run = "google-chrome-stable %s";
              desc = "Chrome";
              for = "unix";
              orphan = true;
            }
            {
              run = "firefox %s";
              desc = "Firefox";
              for = "unix";
              orphan = true;
            }
          ];
          sioyek = [
            {
              run = "sioyek %s1";
              desc = "Sioyek";
              for = "unix";
              orphan = true;
            }
          ];

          # File actions, listed at the end of the <S-Enter> menu.
          copy = [
            {
              run = "${yaziCopy}/bin/yazi-copy %s";
              desc = "Copy to clipboard";
              for = "unix";
            }
          ];
          print = [
            {
              run = "${yaziPrint}/bin/yazi-print %s";
              desc = "Print";
              for = "unix";
              block = true;
            }
          ];
          share = [
            {
              # Hands the files to the running (tray) instance and opens its Send tab.
              run = "localsend_app %s";
              desc = "Share (LocalSend)";
              for = "unix";
              orphan = true;
            }
          ];
          mail = [
            {
              # New message with the files attached (Aerion fork's --attach flag)
              run = "${yaziMail}/bin/yazi-mail %s";
              desc = "Mail (Aerion)";
              for = "unix";
              orphan = true;
            }
          ];
        };

        # First entry of each rule is what plain <Enter> uses;
        # <S-Enter> shows the whole list to pick from.
        # Only the first matching rule applies, so this replaces yazi's preset rules
        # (copied below the custom ones) to get the file actions onto every file type.
        open.rules =
          let
            withActions =
              use:
              use
              ++ [
                "copy"
                "mail"
                "share"
              ];
            withPrint =
              use:
              use
              ++ [
                "copy"
                "print"
                "mail"
                "share"
              ];
          in
          [
            {
              url = "*.svg";
              use = withActions [
                "inkscape"
                "open"
                "gimp"
                "browser"
                "edit"
                "reveal"
              ];
            }
            {
              mime = "image/*";
              use = withPrint [
                "mpv"
                "open"
                "gimp"
                "inkscape"
                "browser"
                "reveal"
              ];
            }
            {
              mime = "{audio,video}/*";
              use = withActions [
                "mpv"
                "play"
                "browser"
                "reveal"
              ];
            }
            {
              mime = "application/pdf";
              use = withPrint [
                "sioyek"
                "open"
                "browser"
                "reveal"
              ];
            }
            {
              mime = "text/html";
              use = withActions [
                "browser"
                "edit"
                "reveal"
              ];
            }

            # yazi preset rules
            {
              mime = "folder/*";
              use = withActions [
                "edit"
                "open"
                "reveal"
              ];
            }
            {
              mime = "text/*";
              use = withPrint [
                "edit"
                "reveal"
              ];
            }
            {
              mime = "application/{json,ndjson,javascript,wine-extension-ini}";
              use = withActions [
                "edit"
                "reveal"
              ];
            }
            {
              mime = "application/{zip,rar,7z*,tar,gzip,xz,zstd,bzip*,lzma,compress,archive,cpio,arj,xar,ms-cab*}";
              use = withActions [
                "extract"
                "reveal"
              ];
            }
            {
              mime = "inode/empty";
              use = [
                "edit"
                "reveal"
              ];
            }
            {
              mime = "vfs/{absent,stale}";
              use = "download";
            }
            {
              mime = "trash/**";
              use = [
                "open"
                "trash"
              ];
            }
            {
              url = "*";
              use = withActions [
                "open"
                "reveal"
              ];
            }
          ];
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

          {
            on = "M";
            run = "plugin devices";
            desc = "Mounted devices: jump to one, or u to unmount";
          }
        ];
      };
    };

  programs.discord.enable = true;

  # Automount drives, phones (MTP) and cameras on plug-in. udiskie only handles
  # drives; PCManFM's windowless daemon mounts anything gvfs sees.
  systemd.user.services.pcmanfm-automount = {
    Unit = {
      Description = "PCManFM daemon: automount removable media";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.pcmanfm}/bin/pcmanfm --daemon-mode";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
  xdg.configFile."pcmanfm/default/pcmanfm.conf".text = ''
    [volume]
    mount_on_startup=1
    mount_removable=1
    autorun=0
  '';
}
