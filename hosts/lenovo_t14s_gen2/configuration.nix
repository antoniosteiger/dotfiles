{
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../common/configuration.nix
  ];

  networking.hostName = "tonix-laptop";

  # Laptop-specific: Enable power management
  powerManagement.enable = true;

  # Laptop-specific: ThinkPad button remapping
  services.udev.extraHwdb = ''
    evdev:name:ThinkPad Extra Buttons:dmi:bvn*:bvr*:bd*:svnLENOVO*:pn*
     KEYBOARD_KEY_1bd=phone
     KEYBOARD_KEY_9c=favorites
  '';

  # Laptop-specific: Workaround for fprintd suspend bug
  powerManagement.powerDownCommands = ''
    ${pkgs.systemd}/bin/systemctl stop fprintd.service 2>/dev/null || true
  '';

  services.power-profiles-daemon.enable = true;

  # Laptop-specific: Battery and power management
  services.upower.enable = true; # used to get battery info

  # Laptop-specific: Touchpad support
  services.libinput.enable = true;
  services.libinput.touchpad.tapping = true;

  # Laptop-specific: Brightness control
  environment.systemPackages = with pkgs; [
    brightnessctl
    steam
    (prismlauncher.override {
      jdks = with pkgs; [
        jdk25
      ];
    })
  ];
}
