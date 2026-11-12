{
  # config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  # capitaine-cursors-themed ships eight prebuilt variants; only Gruvbox is used.
  gruvboxCursor = pkgs.capitaine-cursors-themed.overrideAttrs (_: {
    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/icons
      cp -r "Capitaine Cursors (Gruvbox)" $out/share/icons/
      runHook postInstall
    '';
  });
in
{
  # Shared base (nix settings, locale, ssh, firewall, user) is in base.nix; this file is
  # PC-only. system.stateVersion is set per host.
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

  # Man pages stay; the HTML/info/NixOS manuals are never read here and cost ~100 MiB.
  documentation = {
    doc.enable = false;
    info.enable = false;
    nixos.enable = false;
  };

  # Generation retention is count-based. nix.gc can only express age
  # ("--delete-older-than"), which bounds nothing if you rebuild several times
  # a day; nh keeps the N newest across system, user and home-manager profiles.
  nix.gc.automatic = false; # must not run alongside nh-clean
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

  networking.networkmanager.enable = true;
  networking.modemmanager.enable = false; # no WWAN modem; on by default and pulls libqmi/libmbim/libqrtr

  services.xserver.xkb.layout = "de";

  services.displayManager.noctalia-greeter = {
    enable = true;
    settings = {
      # Same cursor as the Hyprland session, so the pointer does not change at handover.
      cursor = {
        theme = "Capitaine Cursors (Gruvbox)";
        size = 24;
        path = gruvboxCursor; # the greeter looks in <path>/share/icons
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

  environment.variables.EDITOR = "nvim";

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
    # isNormalUser and "wheel" come from base.nix.
    extraGroups = [
      "networkmanager"
      "dialout"
      "tty"
    ];
  };

  nixpkgs.config.allowUnfree = true;
  nixpkgs.overlays = [
    inputs.nur.overlays.default
    # Exposes the unstable channel as pkgs.unstable.* for the few packages that
    # should track upstream instead of the stable release.
    (final: prev: {
      unstable = import inputs.nixpkgs-unstable {
        inherit (prev.stdenv.hostPlatform) system;
        inherit (prev) config;
      };
    })
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
    imagemagick
    ffmpeg
    wl-clipboard
    typst
    tinymist
    sioyek
    pdfcpu # pdf manipulation, e.g. extract a page
    # video/audio player. youtubeSupport = false drops yt-dlp and its deno runtime (~170 MiB).
    # The mpris script (tiny) makes audio-only playback (no window) show up in the Noctalia
    # media player, where it can be paused/stopped.
    (mpv.override {
      youtubeSupport = false;
      scripts = [ mpvScripts.mpris ];
    })
    swayimg # image viewer (mpv is poor at photos); images only, videos at most as thumbnails
    curl
    fastfetch
    onlyoffice-desktopeditors
    # gst_all_1.gstreamer # all gst_all stuff is for videos in onlyoffice
    # gst_all_1.gst-plugins-base
    # gst_all_1.gst-plugins-good
    # gst_all_1.gst-plugins-bad
    # gst_all_1.gst-plugins-ugly
    # gst_all_1.gst-libav
    zulip
    gimp3 # for image editing
    spotify-player # TUI; needs Spotify Premium
    discordo # Discord TUI
    inkscape # for svg editing
    zotero
    pdfpc # presenter view with speaker notes and timer for PDFs
    usbutils # lsusb & co.
    unzip
    unrar
    ripgrep
    fd
    nil # nix language server
    nixfmt # nix formatter
    stylua # lua formatter
    ruff # python formatter and linter
    pyrefly # python language server
    typescript-language-server
    lua-language-server
    vscode-langservers-extracted
    cameractrls-gtk4
    gruvboxCursor # replace hyprland cursor with gruvbox themed cursor.
    xhost # let containers open windows
    unstable.claude-code
    (callPackage ../../pkgs/anytype-bin/package.nix { }) # official prebuilt .deb, see the file header
    gcr # for anytype
    inputs.aerion.packages.${pkgs.stdenv.hostPlatform.system}.default # mail (personal fork)
    hunspellDicts.en_US # system spellcheck dictionaries (Aerion, other Hunspell/Enchant apps)
    hunspellDicts.de_DE
    openvpn
    ncdu
  ];

  # for gstreamer for onlyoffice
  # environment.sessionVariables.GST_PLUGIN_PATH_1_0 = "/run/current-system/sw/lib/gstreamer-1.0";
  # environment.pathsToLink = [ "/lib/gstreamer-1.0" ];

  #1password:
  programs._1password.enable = true;
  programs.gpu-screen-recorder.enable = true; # recording backend for the noctalia screen_recorder plugin; sets up the capability wrapper for KMS capture
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "toni" ];
  };

  # For anytype:
  services.gnome.gnome-keyring.enable = true;
  services.gnome.gcr-ssh-agent.enable = false;

  # No Nerd Font here on purpose: Ghostty embeds JetBrains Mono and Symbols Nerd Font
  # itself (verified with an empty fontconfig), which saves ~220 MiB. Add
  # nerd-fonts.symbols-only (5 MiB) if another terminal or app ever needs the icons.
  fonts.packages = with pkgs; [
    dejavu_fonts
    (google-fonts.override { fonts = [ "HostGrotesk" ]; })
  ];

  services.udisks2.enable = true; # auto mounting external drives

  programs.gnupg.agent = {
    enable = true;
  };

  programs.ssh.startAgent = true;

  xdg.mime.defaultApplications = {
    "application/pdf" = "sioyek.desktop";
  };
}
