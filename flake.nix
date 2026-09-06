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

    # FreeToken — FlashML's edge-native MoE serving engine (the `ft` CLI) and its
    # desktop GUI, packaged for NixOS. A flake exposing nixosModules.default
    # (services.freetoken.* + programs.freetoken-desktop.*) and
    # nixosModules.desktop (the GUI alone, which is what dream takes). CUDA-only,
    # so like netskope this is NOT imported for every host: it is dream-only (the
    # NVIDIA box) and comes in via specialArgs, through
    # hosts/apps/dream/freetoken.nix.
    #
    # Following our nixpkgs is free here, not just tidy: the CUDA torch this
    # resolves to is the same derivation under our rev and the one this flake
    # pins, so sharing nixpkgs costs no extra build. It still builds its own
    # package set with `cudaSupport = true`; nothing else on the system is
    # rebuilt with CUDA because of it.
    #
    # What keeps that cheap is the substituter the module turns on
    # (cache.nixos-cuda.org — see hosts/apps/dream/freetoken.nix), which carries
    # nixpkgs built with cudaSupport. It only has what its CI has built, so
    # `follows` puts the build cost of this input on OUR nixpkgs rev: a very
    # fresh flake update can land off the cache and turn a download into a torch
    # compile. `nix build --dry-run` on
    # nixosConfigurations.dream.config.programs.freetoken-desktop.package says
    # which, before the rebuild (as root, or it silently ignores the cache —
    # extra-substituters is a trusted-user setting).
    freetoken = {
      url = "github:lcleveland/freetoken";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, itera, ninjarmm-ncplayer, netskope, freetoken, ... }:
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
          # only), which `imports` can't gate on config — as does `freetoken`,
          # which is dream-only for the mirror-image reason (it needs the NVIDIA
          # GPU that only dream has).
          specialArgs = { inherit itera netskope freetoken; };
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
