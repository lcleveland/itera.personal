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

    # netskope-mcp — an MCP server over the Netskope REST API v2 (Private Access
    # publishers and apps, NPA + inline policy, URL lists, event and alert search,
    # SCIM), so Claude Code can read the tenant instead of clicking through the admin
    # UI. A flake exposing nixosModules.default (option: services.netskope-mcp.*) and
    # the Go binary built from source — MIT, nothing unfree, no vendor blob.
    #
    # Unlike the `netskope` input below this IS imported for every host (the `modules`
    # list further down) rather than through specialArgs: it is a *client* of the
    # tenant API, not a tenant endpoint agent — nothing in it is laptop- or
    # model-specific, it hooks nothing in the kernel, and the only thing the host it
    # runs on needs is the token. Enabled in hosts/apps/common/netskope-mcp.nix.
    # Share nixpkgs.
    netskope-mcp = {
      url = "github:lcleveland/netskope-mcp";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Netskope Client for Linux (the corporate SASE/SSE endpoint agent).
    # A flake exposing nixosModules.default (option: services.netskope.*) plus the
    # unfree, tenant-specific NSClient.run packaging. Unlike ninjarmm-ncplayer this
    # is NOT imported for every host — the tenant is work-only, so the module is
    # imported by hosts/apps/work/netskope.nix (shared by the work laptops
    # `framework` and `x1yoga`) via specialArgs. Share nixpkgs.
    netskope = {
      url = "github:lcleveland/netskope-client";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # CrowdStrike Falcon sensor — the corporate EDR agent. A flake exposing
    # nixosModules.default (option: services.falcon-sensor.*) plus the unfree,
    # non-redistributable .deb packaging. Work-laptops-only for the same reason as
    # netskope (it is the work tenant's agent), so it comes in through
    # specialArgs rather than the every-host `modules` list, and is imported by
    # hosts/apps/work/falcon-sensor.nix. Share nixpkgs.
    #
    # The installer sits behind an authenticated CrowdStrike API and can never be
    # fetched during a build, so the sensor is NOT packaged: this host downloads
    # its own copy at runtime, authenticating with an API client id + secret kept
    # in /persist/secrets. Consequences worth knowing at this level:
    #
    #   - Nothing here is built from the sensor, so `nixos-rebuild` never needs
    #     the .deb and never tells you which sensor is deployed. What pins it is
    #     `services.falcon-sensor.hash` in the host module — the SHA-256 the
    #     download endpoint is itself keyed by. Bumping that is the upgrade path.
    #   - The sensor cannot come from a binary cache, and there is no offline
    #     install.
    #   - Sensor Download API credentials therefore live on the endpoint. That is
    #     inherent to this design, not a configuration choice; see the scoping
    #     note in hosts/apps/work/falcon-sensor.nix.
    falcon-sensor = {
      url = "github:lcleveland/falcon-sensor";
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
    { nixpkgs, itera, ninjarmm-ncplayer, netskope, netskope-mcp, falcon-sensor, freetoken, ... }:
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
          # along for the same reason: it is a host-scoped module import (the work
          # laptops only), which `imports` can't gate on config — as does
          # `falcon-sensor`, the other work-tenant agent, and `freetoken`, which is
          # dream-only for the mirror-image reason (it needs the NVIDIA GPU that
          # only dream has).
          specialArgs = { inherit itera netskope falcon-sensor freetoken; };
          modules = [
            itera.nixosModules.default
            ninjarmm-ncplayer.nixosModules.default
            netskope-mcp.nixosModules.default
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
        x1yoga = mkHost ./hosts/x1yoga.nix;
      };

      # One installer covering every host in this flake, from itera's upstream
      # `mkInstaller` builder — this replaces the hand-maintained install.sh
      # (which was the prototype itera upstreamed as its own cli/install.sh).
      # Run it from a live ISO; it picks a host + disk, confirms the wipe, and
      # hands off to disko-install. All FDE behaviour is read from the chosen
      # host's EVALUATED config, so the hands-free path is fully driven by
      # `itera.disko.encryption.*` in hosts/*.nix: on the encrypted hosts
      # (`framework`, `x1yoga`) it prompts for the LUKS passphrase, then enrolls
      # the TPM2 keyslot in the same pass so the first boot is already
      # passwordless — no post-install step, no duplicated encryption policy in a
      # script here.
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
