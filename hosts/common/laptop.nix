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

  # Tailscale: tailscaled is started at boot (multi-user.target) and keeps its login in
  # /var/lib/tailscale. One-time, per machine: `sudo tailscale up`. Add
  # `--operator=$USER` to use `tailscale` without sudo afterwards.
  services.tailscale = {
    enable = true;
    openFirewall = true; # UDP 41641, lets peers connect directly instead of via relays
    useRoutingFeatures = "client"; # exit nodes / subnet routes; sets the rp_filter this needs
  };
  # MagicDNS names (tonix-vps, ...) need a resolver Tailscale can configure; with
  # NetworkManager alone it would fight over /etc/resolv.conf.
  services.resolved.enable = true;

  environment.systemPackages = with pkgs; [
    brightnessctl
  ];
}
