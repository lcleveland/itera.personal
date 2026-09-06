{
  description = "lcleveland's NixOS configuration (itera + hjem)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # hjem manages $HOME. itera's home modules are class-`hjem` submodules, so
    # itera MUST share this exact hjem (see `follows` below) or evaluation breaks.
    hjem = {
      url = "github:feel-co/hjem";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    itera = {
      url = "github:lcleveland/itera";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.hjem.follows = "hjem"; # CRITICAL: share one hjem
    };

    # NinjaOne remote session player (ncplayer) + the ninjarmm:// URL handler.
    # A flake exposing nixosModules.default (option: programs.ninjarmm-ncplayer.*);
    # enabled in hosts/common.nix so every host gets it. Share our nixpkgs.
    ninjarmm-ncplayer = {
      url = "github:lcleveland/ninjarmm-ncplayer";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Netskope Client for Linux (the corporate SASE/SSE endpoint agent).
    # A flake exposing nixosModules.default (option: services.netskope.*) plus the
    # unfree, tenant-specific NSClient.run packaging. Unlike ninjarmm-ncplayer this
    # is NOT imported for every host — the tenant is work-only, so the module is
    # imported by hosts/apps/framework/netskope.nix via specialArgs. Share nixpkgs.
    netskope = {
      url = "github:lcleveland/netskope-client";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, itera, ninjarmm-ncplayer, netskope, ... }:
    let
      # A single import (itera.nixosModules.default) pulls in hjem and wires
      # itera's whole opinionated layer: disko + tmpfs-root impermanence, agenix,
      # the mango/DMS desktop, hardening, etc. Every default is a mkDefault.
      mkHost =
        hostModule:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          # Expose the itera flake to host modules so they can select a
          # nixos-hardware board via `itera.hardwareModules.<board>` (an
          # import-time choice, not a `config.itera.*` option). `netskope` rides
          # along for the same reason: it is a host-scoped module import (framework
          # only), which `imports` can't gate on config.
          specialArgs = { inherit itera netskope; };
          modules = [
            itera.nixosModules.default
            ninjarmm-ncplayer.nixosModules.default
            { nixpkgs.overlays = [ itera.overlays.default ]; }
            ./hosts/common.nix
            hostModule
          ];
        };
    in
    {
      nixosConfigurations = {
        dream = mkHost ./hosts/dream.nix;
        framework = mkHost ./hosts/framework.nix;
      };

      # One installer covering every host in this flake, from itera's upstream
      # `mkInstaller` builder — this replaces the hand-maintained install.sh
      # (which was the prototype itera upstreamed as its own cli/install.sh).
      # Run it from a live ISO; it picks a host + disk, confirms the wipe, and
      # hands off to disko-install. All FDE behaviour is read from the chosen
      # host's EVALUATED config, so the hands-free path is fully driven by
      # `itera.disko.encryption.*` in hosts/*.nix: on `framework` it prompts for
      # the LUKS passphrase, then enrolls the TPM2 keyslot in the same pass so
      # the first boot is already passwordless — no post-install step, no
      # duplicated encryption policy in a script here.
      #
      #   sudo nix run github:lcleveland/itera.personal#installer            # menus
      #   sudo nix run github:lcleveland/itera.personal#installer -- framework /dev/nvme0n1
      #   sudo ITERA_INSTALL_FLAKE=. nix run .#installer                     # local clone
      packages.x86_64-linux.installer =
        itera.lib.mkInstaller (import nixpkgs { system = "x86_64-linux"; }) {
          flake = "github:lcleveland/itera.personal";
        };
    };
}
