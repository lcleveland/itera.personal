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
{
  config,
  freetoken,
  ...
}:
{
  # The GUI alone. `nixosModules.desktop` stands on its own — it does not import
  # the server module, and supplies both its own package and the `ft` engine it
  # drives from the flake's CUDA-enabled build. Switch this to
  # `freetoken.nixosModules.default` if the headless server is ever wanted too;
  # that adds `services.freetoken.*` and nothing else.
  #
  # No overlay and no `nixpkgs.config.cudaSupport` here: the flake builds its own
  # CUDA-enabled instance of OUR nixpkgs (we `follows` it), so nothing else on
  # this system is rebuilt with CUDA.
  imports = [ freetoken.nixosModules.desktop ];

  programs.freetoken-desktop.enable = true;

  # NOTE — this import also turns on a third-party substituter system-wide:
  # `services.freetoken.binaryCache` adds cache.nixos-cuda.org (the CUDA
  # maintainers' cache, which replaced cuda-maintainers.cachix.org in November
  # 2025) to nix.settings.extra-substituters and trusts its key. That is
  # deliberate and it is the whole build story here. cache.nixos.org carries no
  # unfree CUDA — hydra will not build it — so a `cudaSupport` torch is cached
  # nowhere public except this. With it, installing FreeToken fetches ~11 GiB
  # and builds only the flake's own small derivations (flashlib, FreeToken's two
  # C++ extensions, two symlinkJoins, the wrapper). Without it, this is hours of
  # torch and flashinfer.
  #
  # Verified 2026-09-06 against our locked nixpkgs (c043004): the cache has both
  # python3.14-torch-2.13.0 and python3.14-flashinfer-python-0.6.4 for this exact
  # rev. It only has what its CI has built, so a very fresh `nix flake update`
  # can land off it — `nix build --dry-run` on the desktop package says which,
  # before committing to the rebuild.
  #
  # To opt out (and build the closure locally):
  #   services.freetoken.binaryCache.enable = false;
  #
  # Deliberately NOT done here: swapping in torch's own cu130 wheel
  # (`freetoken.overlays.binary-torch`, or a private nixpkgs on cudaPackages_13).
  # An earlier version of this file did exactly that, before the cache existed —
  # it is the off-cache path, it trades the download for an NCCL + flashinfer
  # build, and it needs `triton = triton-bin` on top or the whole thing dies on a
  # withPackages name collision after every compile has already run.

  # `ft` on PATH for `ft ctl health`, `ft ctl stats`, `ft shell`, `ft bench bw`.
  # The GUI's own `engine` option, not a package named again, so the CLI in the
  # shell is byte-for-byte the binary the GUI drives and the two cannot drift.
  # It is already built as the GUI's engine, so this costs nothing but a symlink.
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

  # If the window comes up blank on the proprietary NVIDIA driver, this is the
  # override upstream asks for on the WebKitGTK nixpkgs ships (the app rejects
  # the more familiar WEBKIT_DISABLE_DMABUF_RENDERER as unsafe on 2.52). Left
  # off until it is actually needed — it forces a slower SHM transport.
  #
  # programs.freetoken-desktop.environment.WEBKIT_DMABUF_RENDERER_FORCE_SHM = "1";
}
