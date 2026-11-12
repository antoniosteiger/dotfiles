# Firewall, SSH, fail2ban, Tailscale, kernel knobs. Port policy: 22 (openssh), 80, 443
# (nginx.nix) and the tailscale0 interface; everything else is dropped.
{ config, lib, ... }:
let
  tailnet = [
    "100.64.0.0/10"
    "fd7a:115c:a1e0::/48"
  ];
in
{
  services.tailscale = {
    enable = true;
    openFirewall = true; # UDP 41641 for direct connections
    # First login is interactive: `sudo tailscale up` (docs/vps.md).
  };
  services.resolved.enable = true; # MagicDNS names (tonix-desktop) resolve through it
  networking.firewall.trustedInterfaces = [ "tailscale0" ];

  users.mutableUsers = false;
  users.users.toni.openssh.authorizedKeys.keys = config.vps.ssh.authorizedKeys;
  users.users.root.hashedPassword = "!"; # no root password at all
  security.sudo.wheelNeedsPassword = false; # key-only login, deploys use `--sudo`
  warnings = lib.optional (lib.any (lib.hasInfix "TODO") config.vps.ssh.authorizedKeys) ''
    vps.ssh.authorizedKeys still holds the placeholder: you would be locked out of this host.
  '';

  services.openssh.settings = {
    PermitRootLogin = "no";
    AllowUsers = [ "toni" ];
    MaxAuthTries = 3;
    LoginGraceTime = 30;
    X11Forwarding = false;
    AllowAgentForwarding = false;
  };

  services.fail2ban = {
    enable = true; # sshd jail is on by default
    maxretry = 5;
    bantime = "1h";
    bantime-increment = {
      enable = true;
      maxtime = "48h";
    };
    ignoreIP = tailnet ++ [ "127.0.0.1/8" "::1" ];
    jails.vaultwarden = {
      filter.Definition.failregex = ''^.*Username or password is incorrect\. Try again\. IP: <ADDR>\. Username:.*$'';
      settings = {
        backend = "systemd";
        journalmatch = "_SYSTEMD_UNIT=vaultwarden.service";
        maxretry = 5;
        findtime = 600;
        bantime = 3600;
      };
    };
  };

  nix.settings.allowed-users = [ "@wheel" ];
  environment.defaultPackages = [ ];

  boot.kernel.sysctl = {
    "kernel.kptr_restrict" = 2;
    "kernel.dmesg_restrict" = 1;
    "net.ipv4.tcp_syncookies" = 1;
    "net.ipv4.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.default.accept_redirects" = 0;
    "net.ipv6.conf.all.accept_redirects" = 0;
    "net.ipv4.conf.all.send_redirects" = 0;
  };
}
