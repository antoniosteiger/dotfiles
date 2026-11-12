{
  imports = [
    ../sops-host.nix
    ./options.nix
    ./storage.nix
    ./database.nix
    ./nginx.nix
    ./nextcloud.nix
    ./vaultwarden.nix
    ./paperless.nix
    ./backup.nix
    ./gatus.nix
    ./updates.nix
    ./hardening.nix
  ];
}
