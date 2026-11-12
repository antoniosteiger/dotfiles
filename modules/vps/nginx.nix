# nginx + ACME (DNS-01 via Cloudflare).
#
# Why nginx and not Caddy: services.nextcloud ships a complete nginx vhost (PHP-FPM
# socket, .well-known, headers, upload limits) and nginx plugs into security.acme
# (enableACME/forceSSL, reload on renewal). Caddy would mean a second ACME client plus
# hand-written PHP-FPM/Nextcloud config, for no gain here.
#
# DNS-01 means certificates need no inbound connection, so Tailscale-only vhosts get
# real certificates too. The Cloudflare records must be DNS-only (grey cloud): proxied
# records cap uploads at 100 MB and would break large Nextcloud files.
{ config, lib, ... }:
let
  cfg = config.vps;
in
{
  sops.secrets."cloudflare/dns_api_token" = { };
  # Needs Zone:Zone:Read + Zone:DNS:Edit on the one zone only.
  sops.templates."acme-cloudflare.env".content = ''
    CLOUDFLARE_DNS_API_TOKEN=${config.sops.placeholder."cloudflare/dns_api_token"}
  '';

  security.acme = {
    acceptTerms = true;
    defaults = {
      inherit (cfg.acme) email;
      dnsProvider = "cloudflare";
      environmentFile = config.sops.templates."acme-cloudflare.env".path;
      dnsResolver = "1.1.1.1:53"; # lego checks propagation against this, not the local resolver
      group = "nginx";
    };
  };

  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    recommendedBrotliSettings = true;
    recommendedProxySettings = true;
    serverTokens = false;
    sslProtocols = "TLSv1.2 TLSv1.3";

    # 6 requests/min per IP on login endpoints (Paperless uses zone paperless_login).
    commonHttpConfig = ''
      limit_req_zone $binary_remote_addr zone=paperless_login:10m rate=6r/m;
      limit_req_status 429;
    '';

    virtualHosts."_" = {
      default = true;
      rejectSSL = true; # no certificate leak for requests by IP / unknown name
      locations."/".return = "444";
    };
  };

  # Local lookups of our own names (Gatus checks, Nextcloud/Paperless talking to
  # themselves) go to loopback: independent of Cloudflare, and works when a vhost is
  # Tailscale-only (the ACL allows 127.0.0.1).
  networking.hosts."127.0.0.1" = lib.attrValues cfg.domains;

  # 80 stays open for the http->https redirect nginx generates for forceSSL.
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
