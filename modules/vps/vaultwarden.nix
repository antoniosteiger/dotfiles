# Vaultwarden (SQLite). Login is public; /admin is Tailscale-only, always.
# Data lives on the NVMe (/var/lib/vaultwarden), it is tiny and latency-sensitive.
{ config, lib, ... }:
let
  domain = config.vps.domains.vaultwarden;
  port = 8222;
in
{
  options.vps.vaultwarden.exposure = lib.mkOption {
    type = lib.types.enum [
      "public"
      "tailscale"
    ];
    default = "public";
    description = "Whole vhost public or Tailscale-only. /admin is Tailscale-only either way.";
  };

  config = {
    sops.secrets."vaultwarden/admin_token" = { };
    # ADMIN_TOKEN must be an argon2 PHC hash (`vaultwarden hash`); you log in to /admin
    # with the plaintext you hashed. Single quotes: the hash contains `$`.
    sops.templates."vaultwarden.env".content = ''
      ADMIN_TOKEN='${config.sops.placeholder."vaultwarden/admin_token"}'
    '';

    services.vaultwarden = {
      enable = true;
      dbBackend = "sqlite";
      environmentFile = config.sops.templates."vaultwarden.env".path;
      # The module's own backup unit uses `sqlite3 .backup` (never a raw copy of the live
      # file). vps-db-dump (backup.nix) triggers it right before every backup run.
      backupDir = "/var/backup/vaultwarden";
      config = {
        DOMAIN = "https://${domain}";
        ROCKET_ADDRESS = "127.0.0.1";
        ROCKET_PORT = port;

        # First account: set to true, rebuild, register, set back to false, rebuild.
        SIGNUPS_ALLOWED = false;
        INVITATIONS_ALLOWED = false;
        SHOW_PASSWORD_HINT = false;
        # nginx (recommendedProxySettings) sets X-Real-IP; fail2ban reads the log line.
        IP_HEADER = "X-Real-IP";
        LOG_LEVEL = "warn";
        EXTENDED_LOGGING = true;
      };
    };

    services.nginx.virtualHosts.${domain} = {
      forceSSL = true;
      enableACME = true;
      acmeRoot = null;
      extraConfig =
        config.vps.nginx.securityHeaders
        + lib.optionalString (config.vps.vaultwarden.exposure == "tailscale") config.vps.nginx.tailscaleOnly;
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        proxyWebsockets = true;
      };
      # Admin panel: tailnet only, whatever the vhost exposure is.
      locations."/admin" = {
        proxyPass = "http://127.0.0.1:${toString port}";
        extraConfig = config.vps.nginx.tailscaleOnly;
      };
    };
  };
}
