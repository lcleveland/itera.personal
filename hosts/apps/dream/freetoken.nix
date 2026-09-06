# FreeToken Desktop — the GUI control panel for FreeToken, FlashML's edge-native
# Mixture-of-Experts serving engine (model library, chat console, engine
# start/stop, live cache/VRAM tuning).
#
# Dream-only, and it has to be: FreeToken is CUDA-only, and dream is the host
# with an NVIDIA GPU (RTX 5090; itera.facter's autoNvidia sees it in the report
# and turns itera.nvidia on by itself, so nothing here has to ask for the
# driver). framework has no NVIDIA and explicitly leaves itera.nvidia off, which
# is why this module is imported from hosts/dream.nix instead of common.nix, and
# why the flake input rides in through specialArgs (same pattern as netskope).
#
# The packaging + module live in github:lcleveland/freetoken: the `ft` CLI built
# from source against nixpkgs' torch/CUDA and wrapped with the CUDA toolchain it
# JITs kernels with, plus the repackaged (closed-source, unfree) desktop .deb
# with a real launcher entry.
#
# What this file does NOT use is that flake's own `packages.x86_64-linux.*`,
# which resolve against a source-built torch. See `ftPkgs` below.
{
  freetoken,
  config,
  pkgs,
  ...
}:
let
  # A private nixpkgs for FreeToken alone. Two deviations from the flake's own
  # package set, and nothing outside this `let` sees either of them:
  #
  #   1. torch comes from `torch-bin`, PyTorch's own prebuilt cu130 wheel (a
  #      526 MB fixed-output download), instead of being compiled. Building
  #      nixpkgs' torch with `cudaSupport` is the single biggest cost in this
  #      closure and it is cached nowhere — not cache.nixos.org, not
  #      nix-community, not cuda-maintainers, in any nixos-unstable rev sampled
  #      back to 2026-01. This is the only way to avoid that compile.
  #
  #   2. cudaPackages is pinned to 13.x. Not a preference: torch 2.13's wheels
  #      want cuda-bindings >= 13.0.3, so against the default 12.9 nixpkgs marks
  #      torch-bin broken outright ("cudaPackages is too old"). The cost is real
  #      — nix-community caches the 12.9 closure and not the 13.2 one, so the
  #      cuda_* redistributables get unpacked locally instead of substituted.
  #      They are unpack-and-patchelf jobs, not compiles.
  #
  # The three passthru attributes below are the seam between the two. The source
  # torch carries them and the wheel does not, and each one is a hard eval
  # failure rather than a fallback: `cudaSupport` and `cudaCapabilities` are read
  # by nixpkgs' flashinfer-python (`meta.broken` and FLASHINFER_CUDA_ARCH_LIST),
  # `cudaPackages` by freetoken's own default for its build toolkit.
  #
  # Everything else still compiles: flashinfer-python, triton, numba,
  # nvidia-cutlass-dsl, freetoken and flashlib — flashinfer against the wheel's
  # bundled libtorch rather than nixpkgs' own.
  ftPkgs = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    config = {
      allowUnfree = true;
      cudaSupport = true;
    };
    overlays = [
      freetoken.overlays.default
      (final: prev: {
        cudaPackages = final.cudaPackages_13;
        pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
          (_pyFinal: pyPrev: {
            torch = pyPrev.torch-bin // {
              cudaSupport = true;
              inherit (final) cudaPackages;
              inherit (final.cudaPackages.flags) cudaCapabilities;
            };
          })
        ];
      })
    ];
  };
in
{
  # nixosModules.default, NOT nixosModules.desktop, even though only the GUI is
  # wanted here. The GUI-alone module reads `config.services.freetoken.package`
  # as the default for its `engine` option, and that option only exists in the
  # server module — importing `desktop` on its own dies at eval with
  # "attribute 'freetoken' missing" as soon as programs.freetoken-desktop.enable
  # is set. Importing default declares both option trees; the server itself
  # stays off (see below), so nothing extra is built or run.
  imports = [ freetoken.nixosModules.default ];

  # `package` and `engine` both come from `ftPkgs`, overriding the flake module's
  # mkDefault (which points at the flake's own source-torch build). The overlay
  # already wires `ftPkgs.freetoken-desktop` to `ftPkgs.freetoken`; setting
  # `engine` too is what the desktop module reads for FREETOKEN_FT_BIN.
  programs.freetoken-desktop = {
    enable = true;
    package = ftPkgs.freetoken-desktop;
    engine = ftPkgs.freetoken;
  };

  # Kept in lockstep even though the service is off, so enabling it later cannot
  # silently pull in a second, source-built torch.
  services.freetoken.package = ftPkgs.freetoken;

  # services.freetoken is deliberately NOT enabled. The GUI starts and stops its
  # own `ft serve` on port 1919, so running the systemd service too means two
  # processes racing for that port (the module warns about exactly this). It
  # would also force a checkpoint path into this repo — `services.freetoken.model`
  # is required — whereas the GUI picks models from its library at run time.
  # If a headless, always-on server is ever wanted, enable it on another port:
  #
  #   services.freetoken = {
  #     enable = true;
  #     model = "/home/lcleveland/.freetoken/models/<checkpoint>";
  #     port = 1920;
  #   };
  #
  # Note the API has NO authentication; keep the default loopback bind.

  # `ft` on PATH for `ft ctl health`, `ft ctl stats`, `ft shell`, `ft bench bw`.
  # The server module only installs it when the service is enabled, so add it
  # here — and take it from the GUI's own `engine` option rather than naming a
  # package, so the CLI in the shell is byte-for-byte the binary the GUI drives
  # (and the two cannot drift). It is already built as the GUI's engine, so this
  # costs nothing beyond the symlink.
  itera.users.lcleveland.packages = [ config.programs.freetoken-desktop.engine ];

  # Impermanence. `~/.freetoken` is FREETOKEN_HOME: the model library
  # (models/ + models.json, tens of GB per checkpoint) and the engine state the
  # GUI writes. It is a top-level dotdir, so none of itera's curated home paths
  # cover it — `.config` (which holds ~/.config/freetoken: models_dir, daemon
  # url/port, hf_endpoint) and `.cache` (~/.cache/huggingface, where downloads
  # land) already are. Same reasoning as itera's own `.steam` entry.
  #
  # Without this every reboot re-downloads the entire model library onto a
  # size-capped tmpfs root. Persisting it also puts the directory on the
  # /persist btrfs subvolume, whose bind mounts are exec-capable — relevant
  # because the app's bundled fallback installer builds a uv venv here and execs
  # out of it, which the noexec /home tmpfs would refuse. (That fallback should
  # never run: the module wires FREETOKEN_FT_BIN to the Nix `ft`.)
  itera.impermanence.users.lcleveland.directories = [ ".freetoken" ];

  # No extra binary cache here, deliberately. Measured 2026-09-06 for this rev:
  # nix-community.cachix.org (which itera configures by default) serves the CUDA
  # 12.9 dependency closure, and cuda-maintainers.cachix.org — the cache
  # upstream's README recommends — has nothing at all for this rev, in any of six
  # nixos-unstable revs sampled back to January. It only carries the revs its own
  # CI builds, never channel snapshots, so adding it would buy nothing but a
  # round trip per query. With `ftPkgs` on cudaPackages 13.x this host is off the
  # 12.9 closure nix-community does have, so the CUDA redistributables are
  # unpacked locally either way.

  # If the window comes up blank on the proprietary NVIDIA driver, this is the
  # override upstream asks for on the WebKitGTK nixpkgs ships (the app rejects
  # the more familiar WEBKIT_DISABLE_DMABUF_RENDERER as unsafe on 2.52). Left
  # off until it is actually needed — it forces a slower SHM transport.
  #
  # programs.freetoken-desktop.environment.WEBKIT_DMABUF_RENDERER_FORCE_SHM = "1";
}
