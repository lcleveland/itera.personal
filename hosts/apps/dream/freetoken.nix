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
  freetoken,
  config,
  ...
}:
{
  # nixosModules.default, NOT nixosModules.desktop, even though only the GUI is
  # wanted here. The GUI-alone module reads `config.services.freetoken.package`
  # as the default for its `engine` option, and that option only exists in the
  # server module — importing `desktop` on its own dies at eval with
  # "attribute 'freetoken' missing" as soon as programs.freetoken-desktop.enable
  # is set. Importing default declares both option trees; the server itself
  # stays off (see below), so nothing extra is built or run.
  imports = [ freetoken.nixosModules.default ];

  programs.freetoken-desktop.enable = true;

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

  # No extra binary cache here, deliberately. Measured when this was added
  # (2026-09-06), for this nixpkgs rev:
  #   - nix-community.cachix.org — which itera already configures by default —
  #     serves the whole CUDA 12.9 dependency closure (cudnn, the cuda_*
  #     redistributables, ~5.4 GiB). Nothing to add.
  #   - cuda-maintainers.cachix.org, the cache upstream's README recommends, has
  #     nothing for this rev. It only carries the revs its own CI builds, never
  #     channel snapshots, so a rebuild would just pay an extra round trip per
  #     query for a cache that never hits.
  #   - `python3Packages.torch` itself is on NO public cache, in any of the six
  #     nixos-unstable revs sampled back to January. It is built from source, and
  #     it is the bulk of the first rebuild: 23 derivations, of which torch,
  #     flashinfer-python and triton are the expensive ones.
  #
  # If that ever needs to go away, the escape hatch is `python3Packages.torch-bin`
  # (PyTorch's own prebuilt cu130 wheel — no compile at all), but it needs
  # `cudaPackages = cudaPackages_13`, three passthru attributes the source build
  # has and the wheel does not (`cudaSupport`, `cudaPackages`, `cudaCapabilities`,
  # all read by flashinfer-python and freetoken), and it trades the cached 12.9
  # closure for an uncached 13.2 one.

  # If the window comes up blank on the proprietary NVIDIA driver, this is the
  # override upstream asks for on the WebKitGTK nixpkgs ships (the app rejects
  # the more familiar WEBKIT_DISABLE_DMABUF_RENDERER as unsafe on 2.52). Left
  # off until it is actually needed — it forces a slower SHM transport.
  #
  # programs.freetoken-desktop.environment.WEBKIT_DMABUF_RENDERER_FORCE_SHM = "1";
}
