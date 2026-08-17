# OBS Studio (screen recording + streaming), shared by both hosts.
#
# Uses the NixOS program module rather than a bare package (like zoom.nix) so we
# get the wrapped OBS — `programs.obs-studio.plugins` builds a wrapper with the
# plugin search path set, which a plain `pkgs.obs-studio` in
# `itera.users.lcleveland.packages` cannot do.
#
# Screen capture needs no extra setup here: itera's mango session already ships
# PipeWire plus xdg-desktop-portal-wlr (with itera's own screencast chooser), so
# OBS's built-in "Screen Capture (PipeWire)" source works through the portal.
# That is why there is no `wlrobs` plugin below — wlrobs talks wlr-screencopy
# directly and is only for compositors without a working portal.
#
# Impermanence: nothing to persist. Root is tmpfs, but /home is a bind mount
# onto /persist, so ~/.config/obs-studio (scene collections, profiles, encoder
# settings) survives a reboot on its own.
{ pkgs, ... }:
{
  programs.obs-studio = {
    enable = true;

    plugins = [
      # Per-application audio capture. OBS's built-in audio sources can only
      # bind whole PipeWire devices (a sink or a source); this plugin adds
      # "Application Audio Capture", which is how you record one program's audio
      # — e.g. a Teams/Zoom call or a game — without also recording everything
      # else on the same sink.
      pkgs.obs-studio-plugins.obs-pipewire-audio-capture
    ];

    # Virtual camera (`Start Virtual Camera` → /dev/video1, "OBS Cam"), so an
    # OBS scene can be used as the webcam in Teams/Zoom. This pulls in the
    # out-of-tree v4l2loopback module and loads it at boot; unlike the mt76
    # rebuild on dream it is a stock nixpkgs kernel module (cached upstream), so
    # a kernel bump carries no maintenance work here.
    enableVirtualCamera = true;
  };
}
