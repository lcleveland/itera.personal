# Settings shared by every host. itera's opinionated defaults are already on
# (opt-out via mkDefault); this file only sets what deviates from them plus the
# single user and the agenix-stored password.
{ config, ... }:
{
  itera = {
    # Pin the NixOS release the stateful data matches. Set ONCE at install time.
    nix.stateVersion = "25.11";

    # `nh` is itera's rebuild front-end. Point it at the persisted checkout of
    # this repo so `sudo nh os switch` (no args) works. Home dirs are persisted
    # under impermanence, so a checkout in $HOME is a valid target.
    nix.nh.flake = "/home/lcleveland/Documents/itera.personal";

    # Both machines are AMD; a host may override.
    hardware.cpu = "amd";

    # Desktop: mango (dwl/wlroots) + DankMaterialShell. mango is opt-in.
    desktop.mango.enable = true;

    # agenix password secret. Decrypts to /run/agenix/lcleveland-password at
    # activation via the host ed25519 key (persisted by impermanence). Inert
    # until secrets/lcleveland-password.age exists — see the bootstrap steps in
    # the plan / README before the file is committed.
    secrets.secrets.lcleveland-password.file = ../secrets/lcleveland-password.age;

    users.lcleveland = {
      description = "Lyle Cleveland";
      extraGroups = [
        "wheel"
        "networkmanager"
        "video"
        "audio"
        "libvirtd"
        "docker"
        "input"
      ];
      # initialPassword defaults to the username and only applies at first account
      # creation; hashedPasswordFile below takes over once the secret exists.
    };
  };

  # Password sourced from the decrypted agenix secret. The account fields
  # itera.users creates are mkDefault, so this plain assignment wins.
  users.users.lcleveland.hashedPasswordFile = config.age.secrets.lcleveland-password.path;
}
