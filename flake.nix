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
  };

  outputs =
    { nixpkgs, itera, ... }:
    let
      # A single import (itera.nixosModules.default) pulls in hjem and wires
      # itera's whole opinionated layer: disko + tmpfs-root impermanence, agenix,
      # the mango/DMS desktop, hardening, etc. Every default is a mkDefault.
      mkHost =
        hostModule:
        nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            itera.nixosModules.default
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
    };
}
