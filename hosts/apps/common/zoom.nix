# Zoom. Uses the NixOS program module (Wayland wrapper etc.) rather than a bare
# package, matching the personal source config.
{ ... }:
{
  programs.zoom-us.enable = true;
}
