# Points sops-nix at secrets/<name>.yaml (a sops-encrypted file, see .sops.yaml).
#
# Until that file exists AND is tracked by git (flakes only see tracked files) the
# plaintext placeholder secrets/<name>.example.yaml is used so the configuration still
# evaluates and builds. It is not decryptable: activation fails loudly, it never
# silently deploys placeholder secrets. Builds warn while it is missing.
{ config, lib, ... }:
let
  cfg = config.sopsHost;
  real = ../secrets + "/${cfg.name}.yaml";
  exists = builtins.pathExists real;
in
{
  options.sopsHost.name = lib.mkOption {
    type = lib.types.str;
    description = "Basename of the host's secrets file in secrets/.";
  };

  config = {
    sops.defaultSopsFile = if exists then real else ../secrets + "/${cfg.name}.example.yaml";
    sops.validateSopsFiles = exists;
    warnings = lib.optional (!exists && config.sops.secrets != { }) ''
      secrets/${cfg.name}.yaml does not exist (or is not `git add`ed): using the undecryptable
      placeholder secrets/${cfg.name}.example.yaml. See docs/vps.md ("Secrets").
    '';
  };
}
