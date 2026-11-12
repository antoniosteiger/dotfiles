# Shared by EVERY host (PCs and the VPS): only what is true for all of them.
# Desktop-only software lives in desktop.nix, which the PCs import in addition.
{
  # Default-deny inbound. Hosts open what they need; SSH is opened by services.openssh.
  networking.firewall.enable = true;

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nix.optimise.automatic = true; # nightly hardlink dedup of identical files

  # Language and Timezone
  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "de";

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false; # keys only
      KbdInteractiveAuthentication = false; # PAM password prompts count as passwords too
    };
  };

  users.users.toni = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # Enable 'sudo' for the user.
  };
}
