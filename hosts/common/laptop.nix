{
  pkgs,
  ...
}:

# Shared by the laptop hosts (the desktop does not import this).
{
  powerManagement.enable = true;
  services.power-profiles-daemon.enable = true; # also stops nixos-hardware from enabling TLP
  services.upower.enable = true; # used to get battery info

  # Touchpad behaviour itself lives in config/hypr/host-*.conf (Hyprland, not X11).
  services.libinput.enable = true;

  environment.systemPackages = with pkgs; [
    brightnessctl
  ];
}
