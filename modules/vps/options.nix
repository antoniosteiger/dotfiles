# Options shared by the vps modules. Per-service options (exposure, ...) live in the
# service's own module; this file only holds what several modules need.
{ lib, ... }:
let
  inherit (lib) mkOption types;

  # Tailscale CGNAT + ULA ranges, plus loopback (Gatus and the VPS itself talk to the
  # vhosts via 127.0.0.1, see networking.hosts in nginx.nix).
  tailscaleOnly = ''
    allow 100.64.0.0/10;
    allow fd7a:115c:a1e0::/48;
    allow 127.0.0.1;
    allow ::1;
    deny all;
  '';
in
{
  options.vps = {
    domains = {
      nextcloud = mkOption {
        type = types.str;
        default = "cloud.example.com"; # TODO
      };
      vaultwarden = mkOption {
        type = types.str;
        default = "vault.example.com"; # TODO
      };
      paperless = mkOption {
        type = types.str;
        default = "docs.example.com"; # TODO
      };
      status = mkOption {
        type = types.str;
        default = "status.example.com"; # TODO (Gatus, Tailscale-only)
      };
    };

    acme.email = mkOption {
      type = types.str;
      default = "admin@example.com"; # TODO
      description = "Let's Encrypt account / expiry notification address.";
    };

    storage = {
      hdd = mkOption {
        type = types.str;
        default = "/mnt/hdd";
        description = ''
          Mount point of the bulk (HDD) volume. Only large, mostly sequential data goes
          here: Nextcloud datadir, Paperless media + consumption. Everything else
          (OS, databases, caches, scratch, app code) is on the NVMe root.
        '';
      };
    };

    ssh.authorizedKeys = mkOption {
      type = types.listOf types.str;
      default = [ "ssh-ed25519 AAAA-TODO-REPLACE-WITH-YOUR-PUBLIC-KEY toni" ];
      description = "Public keys that may log in as toni (the only SSH user).";
    };

    nginx = {
      tailscaleOnly = mkOption {
        type = types.lines;
        readOnly = true;
        default = tailscaleOnly;
        description = "nginx snippet restricting a server/location to the tailnet (and loopback).";
      };
      securityHeaders = mkOption {
        type = types.lines;
        readOnly = true;
        description = ''
          Headers for proxied (non-Nextcloud) vhosts. Hide the upstream's copy first so
          nothing is sent twice. Nextcloud's module sets its own set; HSTS comes from
          services.nextcloud.https.
        '';
        default = ''
          proxy_hide_header X-Content-Type-Options;
          proxy_hide_header Referrer-Policy;
          add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
          add_header X-Content-Type-Options "nosniff" always;
          add_header Referrer-Policy "no-referrer" always;
          add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=()" always;
          add_header X-Robots-Tag "noindex, nofollow" always;
        '';
      };
    };
  };
}
