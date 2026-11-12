# VPS: Nextcloud + Vaultwarden + Paperless-ngx. Headless, minimal, hardened.
# Everything service-related is in modules/vps/*; this file only holds identity and the
# few host-specific values. Walkthrough: docs/vps.md.
{
  inputs,
  modulesPath,
  pkgs,
  ...
}:

{
  imports = [
    (modulesPath + "/profiles/minimal.nix")
    (modulesPath + "/profiles/headless.nix")
    ./hardware-configuration.nix
    ../common/base.nix # shared with the PCs: nix settings, locale, ssh, firewall, user
    inputs.sops-nix.nixosModules.sops
    ../../modules/vps
  ];

  # Set once, never change. 26.05 = the release this host was first installed with.
  system.stateVersion = "26.05";

  networking.hostName = "tonix-vps";
  sopsHost.name = "vps";

  vps = {
    domains = {
      nextcloud = "cloud.steiger.ing";
      vaultwarden = "vault.steiger.ing";
      paperless = "docs.steiger.ing";
      status = "status.steiger.ing";
    };
    acme.email = "it@steiger.ing";
    ssh.authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICWVaVODpS04sqUnEXu7+m194XOntKi8AQY7OdZEGd7O antonio@steiger.ing"
    ];

    # One-line exposure switches ("public" | "tailscale"). See docs/vps.md for tradeoffs.
    nextcloud.exposure = "public";
    vaultwarden.exposure = "public"; # /admin is Tailscale-only regardless
    paperless.exposure = "public";
    # Gatus is Tailscale-only, not configurable.

    # paperless.consumeFromNextcloud.enable = true;
    # paperless.exporter.enable = true;
    # nextcloud.previewsToNvme.instanceId = "ocXXXXXXXX"; # after first install

    # Backups. Secondary repo in Cloudflare R2 (the account id is the hex label in the
    # S3 endpoint URL, not a secret). Arcticbox is the primary target.
    backup.r2 = {
      accountId = "fde7ed6154c8cd39952d5f931e6e45a8";
      bucket = "vps-backup";
    };

    # Alert mail via Infomaniak SMTP. The password is `smtp/password` in secrets/vps.yaml.
    monitoring.email = {
      enable = true;
      host = "mail.infomaniak.com";
      port = 587; # STARTTLS
      username = "it@steiger.ing";
      from = "it@steiger.ing"; # must match the account
      to = "antonio@steiger.ing";
    };
  };

  # Only what this box needs; no environment.defaultPackages (see hardening.nix).
  environment.systemPackages = with pkgs; [
    git # flake fetching, editing this repo on the box in an emergency
    restic # manual restores
    sqlite
    htop
    ncdu
  ];

  # HostBRR does not run DHCP: static addressing (values from the provider panel).
  networking = {
    useDHCP = false;
    interfaces.ens3.ipv4.addresses = [
      {
        address = "5.175.211.138";
        prefixLength = 24;
      }
    ];
    defaultGateway = {
      address = "5.175.211.1";
      interface = "ens3";
    };
    nameservers = [
      "1.1.1.1"
      "9.9.9.9"
    ];
    # IPv6 (2a0c:4ac1:4:302::a, gateway 2a0c:4ac1:4::1) is added once tested by hand,
    # see docs/vps.md: the gateway is outside the /64, so it needs an on-link route.
  };
}
