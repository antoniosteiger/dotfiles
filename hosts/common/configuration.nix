{
  # config,
  # lib,
  pkgs,
  ...
}:

{
  system.stateVersion = "25.11"; # Never change

  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.grub = {
    enable = true;
    device = "nodev";
    efiSupport = true;
  };

  boot.plymouth = {
    enable = true;
  };

  boot = {
    # Enable "Silent boot"
    consoleLogLevel = 3;
    initrd.verbose = false;
    kernelParams = [
      "quiet"
      "splash"
      "boot.shell_on_fail"
      "udev.log_priority=3"
      "rd.systemd.show_status=auto"
    ];
    # Hide the OS choice for bootloaders.
    # It's still possible to open the bootloader list by pressing any key
    # It will just not appear on screen unless a key is pressed
    loader.timeout = 0;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 10d";
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

  services.displayManager.gdm = {
    enable = true;
    wayland = true;
  };

  services.gvfs.enable = true;

  security.pam.services.hyprlock = { };

  xdg.portal = {
    enable = true;
    wlr.enable = true; # Needed for proper screen sharing, screenshots, file pickers
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-wlr
    ];
    config.common.default = [
      "gtk"
      "wlr"
    ];
  };

  programs.zsh = {
    enable = true;
    syntaxHighlighting.enable = true;
    autosuggestions.enable = true;
  };

  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  environment.sessionVariables = {
    ZDOTDIR = "$HOME/.config/zsh";
  };

  services.printing.enable = true;

  services.pipewire = {
    enable = true;
    pulse.enable = true;
  };

  users.defaultUserShell = pkgs.zsh;
  users.users.toni = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
      "input"
    ]; # Enable 'sudo' for the user.
  };

  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [
    wget
    git
    git-lfs
    pulseaudio
    hyprpanel # bar
    hyprlock # locking
    hypridle # screen locking on idle
    hyprpaper # wallpaper
    hyprpicker # color pipette
    capitaine-cursors-themed # replace hyprland cursor with gruvbox themed cursor.
    zsh-powerlevel10k # Shell prompt. Supports transient prompts. Starship didn't work with transient.
    imagemagick
    ghostscript # to convert pdf to images using imagemagick
    ffmpeg
    bitwarden-desktop
    wl-clipboard
    typst
    tinymist
    sioyek
    pdfcpu # pdf manipulation, e.g. extract a page
    mpv # media viewer/player: images, video, audio
    curl
    calcurse # calendar
    aerc # mail
    neofetch
    onlyoffice-desktopeditors
    mattermost-desktop
    gimp2 # for image editing
    spotify
    inkscape # for svg editing
    zotero
    vscode
    gaphor # for quick SysML diagrams
    nix-search-cli # for quick nix pckgs search in cli
    grimblast # Needed because grim puts gray border around screenshots
    slurp
    pdfpc # presenter view with speaker notes and timer for PDFs
    polylux2pdfpc # Extract pdfpc data from polylux based typst projects
    usbutils # lsusb & co.
    unzip
    gcc
    ripgrep
    fd
    gnumake
    nil # nix language server
    nixfmt # nix formatter
    stylua # lua formatter
    ruff # python formatter and linter
    pyrefly # python language server
    rust-analyzer # rust language server
    rustfmt # Rust formatter
    nodejs_24 # JS runtime old for compatibility
    bun # JS runtime
    biome # css, ts/js, html, json linter
    typescript
    typescript-language-server
    lua-language-server
    marksman # markdown lsp
    vscode-langservers-extracted
    buf
    protoc-gen-es
    cameractrls-gtk4
    google-chrome # for compatibility and lighthouse
    playerctl # loaded by many media-control apps
    docker-compose
    xhost # let containers open windows
    claude-code
    ltex-ls-plus # spell checking in nvim
  ];

  virtualisation.docker.enable = true;
  programs.xwayland.enable = true;

  programs.zsh.promptInit = "source ${pkgs.zsh-powerlevel10k}/share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
  programs.vim.enable = true;
  programs.vim.defaultEditor = true;

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

  stylix = {
    enable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/gruvbox-material-dark-medium.yaml";
    image = ../../backgrounds/artemis2_lunar_flyby_eclipse_integrity.jpg;
    autoEnable = true;
  };

  xdg.mime.defaultApplications = {
    "application/pdf" = "sioyek.desktop";
  };
}
