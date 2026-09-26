{
  # config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  system.stateVersion = "25.11"; # Never change

  boot = {
    loader.efi.canTouchEfiVariables = true;
    loader.grub = {
      enable = true;
      device = "nodev";
      efiSupport = true;
      # No NixOS splash: GRUB draws it unscaled in the top-left corner.
      splashImage = null;
    };
    # Hide the bootloader menu; any keypress still brings it up.
    loader.timeout = 0;

    plymouth.enable = false; # takes too much boot time

    # Enable "Silent boot"
    consoleLogLevel = 3;
    initrd.verbose = false;
    kernelParams = [
      "quiet"
      "boot.shell_on_fail"
      "udev.log_priority=3"
      "rd.systemd.show_status=auto"
    ];
  };

  systemd.services.NetworkManager-wait-online.enable = false;
  services.fwupd.enable = true;

  # Generation retention is count-based. nix.gc can only express age
  # ("--delete-older-than"), which bounds nothing if you rebuild several times
  # a day; nh keeps the N newest across system, user and home-manager profiles.
  nix.gc.automatic = false; # must not run alongside nh-clean
  nix.optimise.automatic = true; # nightly hardlink dedup of identical files

  programs.nh = {
    enable = true;
    flake = "/home/toni/dotfiles";
    clean = {
      enable = true;
      dates = "weekly";
      # Union, not intersection: at least 4 generations AND at least 7 days.
      extraArgs = "--keep 4 --keep-since 7d";
    };
  };

  networking.firewall = {
    enable = false;
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking.networkmanager.enable = true;

  # Language and Timezone
  time.timeZone = "Europe/Berlin";

  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "de";

  services.xserver.xkb.layout = "de";

  services.displayManager.noctalia-greeter = {
    enable = true;
    # Same cursor as the Hyprland session, so the pointer does not change at handover.
    cursorTheme.package = pkgs.capitaine-cursors-themed;
    settings = {
      cursor = {
        theme = "Capitaine Cursors (Gruvbox)";
        size = 24;
      };
      keyboard.layout = "de";
    };
  };

  services.displayManager.defaultSession = "hyprland-uwsm";

  services.gvfs.enable = true;

  xdg.portal = {
    enable = true;
    # xdg-desktop-portal-hyprland is added automatically by programs.hyprland.enable.
    # Do NOT add xdg-desktop-portal-wlr as well: both implement ScreenCast, and wlr
    # has no window/output picker under Hyprland.
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-termfilechooser # yazi-based file picker (multi-monitor safe)
    ];
    config.common = {
      default = [
        "hyprland"
        "gtk"
      ];
      # Route only the file-chooser to termfilechooser (yazi); hyprland/gtk keep the rest.
      "org.freedesktop.impl.portal.FileChooser" = [ "termfilechooser" ];
    };
  };

  programs.zsh = {
    enable = true;
    syntaxHighlighting.enable = true;
    autosuggestions.enable = true;
  };

  programs.hyprland = {
    enable = true;
    withUWSM = true; # returns to GDM immediately otherwise
    xwayland.enable = true;
  };

  environment.sessionVariables = {
    ZDOTDIR = "$HOME/.config/zsh";
  };

  services.printing.enable = true;

  # Off by default here: it is a NixOS default-on service that pulls in
  # espeak -> mbrola -> mbrola-voices (~645 MiB) for screen-reader TTS we never use.
  services.speechd.enable = false;

  services.pipewire = {
    enable = true;
    pulse.enable = true;
    wireplumber.enable = true; # noctalia
  };
  security.rtkit.enable = true; # for real-time audio

  users.defaultUserShell = pkgs.zsh;
  users.users.toni = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "input"
      "dialout"
      "tty"
    ]; # Enable 'sudo' for the user.
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    inputs.nur.overlays.default
  ];
  environment.systemPackages = with pkgs; [
    wget
    git
    git-lfs
    pulseaudio
    noctalia # desktop shell: launcher, bar, notifs, ...
    noctalia-greeter
    accountsservice # user avatar in lockscreen
    hyprpicker # color pipette
    capitaine-cursors-themed # replace hyprland cursor with gruvbox themed cursor.
    imagemagick
    ghostscript # to convert pdf to images using imagemagick
    ffmpeg
    wl-clipboard
    typst
    tinymist
    sioyek
    pdfcpu # pdf manipulation, e.g. extract a page
    mpv # media viewer/player: images, video, audio
    curl
    fastfetch
    onlyoffice-desktopeditors
    # gst_all_1.gstreamer # all gst_all stuff is for videos in onlyoffice
    # gst_all_1.gst-plugins-base
    # gst_all_1.gst-plugins-good
    # gst_all_1.gst-plugins-bad
    # gst_all_1.gst-plugins-ugly
    # gst_all_1.gst-libav
    mattermost-desktop
    gimp3 # for image editing
    spotify
    inkscape # for svg editing
    zotero
    pdfpc # presenter view with speaker notes and timer for PDFs
    polylux2pdfpc # Extract pdfpc data from polylux based typst projects
    usbutils # lsusb & co.
    unzip
    unrar
    gcc
    ripgrep
    fd
    gnumake
    nil # nix language server
    nixfmt # nix formatter
    stylua # lua formatter
    ruff # python formatter and linter
    pyrefly # python language server
    bun # JS runtime
    biome # css, ts/js, html, json linter
    typescript
    typescript-language-server
    lua-language-server
    marksman # markdown lsp
    vscode-langservers-extracted
    cameractrls-gtk4
    google-chrome # for compatibility and lighthouse
    xhost # let containers open windows
    claude-code
    ltex-ls-plus # spell checking in nvim
    localsend # local network file sharing
    anytype
    gcr # for anytype
    nur.repos.lonerOrz.aerion # mail
  ];

  environment.sessionVariables.GST_PLUGIN_PATH_1_0 = "/run/current-system/sw/lib/gstreamer-1.0";
  environment.pathsToLink = [ "/lib/gstreamer-1.0" ];

  #1password:
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "toni" ];
  };

  # For anytype:
  services.gnome.gnome-keyring.enable = true;
  services.gnome.gcr-ssh-agent.enable = false;

  programs.vim.enable = true; # a system editor for root; toni gets neovim via home-manager

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    dejavu_fonts
  ];

  services.udisks2.enable = true; # auto mounting external drives

  programs.gnupg.agent = {
    enable = true;
  };

  services.openssh.enable = true;
  programs.ssh.startAgent = true;

  xdg.mime.defaultApplications = {
    "application/pdf" = "sioyek.desktop";
  };
}
