# Settings shared by every host. itera's opinionated defaults are already on
# (opt-out via mkDefault); this file only sets what deviates from them plus the
# single user.
{ ... }:
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
      # First-boot password. Defaults to the username ("lcleveland"); CHANGE IT
      # after the first login with `passwd`. (A secrets-managed password can be
      # added later — e.g. agenix + users.users.lcleveland.hashedPasswordFile.)
      initialPassword = "lcleveland";
    };
  };
}
