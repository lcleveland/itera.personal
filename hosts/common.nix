# Settings shared by every host. itera's opinionated defaults are already on
# (opt-out via mkDefault); this file only sets what deviates from them plus the
# single user.
{ ... }:
{
  itera = {
    # Pin the NixOS release the stateful data matches. Set ONCE at install time.
    nix.stateVersion = "25.11";

    # The `itera` command's rebuild/update verbs (and a bare `nh os switch`)
    # build from this flake. Point it at the GitHub remote so rebuilds need no
    # checkout on disk: `itera rebuild` builds the pushed revision, and being a
    # remote ref, `itera update` uses `--refresh` (fetch the newest pushed
    # revision) rather than bumping a local flake.lock. `itera.update.configuration`
    # is per-host (see hosts/*.nix) because the flake attribute (dream/framework)
    # differs from the hostname.
    update.flake = "github:lcleveland/itera.personal";

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
