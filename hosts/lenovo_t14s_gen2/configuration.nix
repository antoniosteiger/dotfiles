{
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../common/configuration.nix
    ../common/laptop.nix
  ];

  networking.hostName = "tonix-laptop";

  # ThinkPad button remapping
  services.udev.extraHwdb = ''
    evdev:name:ThinkPad Extra Buttons:dmi:bvn*:bvr*:bd*:svnLENOVO*:pn*
     KEYBOARD_KEY_1bd=phone
     KEYBOARD_KEY_9c=favorites
  '';

  # Workaround for fprintd suspend bug
  powerManagement.powerDownCommands = ''
    ${pkgs.systemd}/bin/systemctl stop fprintd.service 2>/dev/null || true
  '';

  environment.systemPackages = with pkgs; [
    (prismlauncher.override {
      jdks = with pkgs; [
        jdk25
      ];
    })
    tigervnc
  ];
}
