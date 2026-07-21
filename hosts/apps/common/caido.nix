# Caido web security auditing proxy. Work-only in the old config; now shared to
# both hosts. Upstream `pkgs.caido` (the desktop app) was split into
# `caido-desktop` (GUI) + `caido-cli` (headless server); pin the desktop app
# explicitly to match the old config and avoid the deprecation alias warning.
{ pkgs, ... }:
{
  itera.users.lcleveland.packages = [ pkgs.caido-desktop ];
}
