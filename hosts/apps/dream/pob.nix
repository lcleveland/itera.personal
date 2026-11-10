# Path of Building (rusty port) — Path of Exile character/build planner.
{ pkgs, ... }:
{
  itera.users.lcleveland.packages = [
    # shortcut: zstd-sys/aws-lc now link system libs and nixpkgs' 0.3.3 lacks
    # them (backport of nixpkgs PR 585127); drop once nixos-unstable has it.
    (pkgs.rusty-path-of-building.overrideAttrs (o: {
      buildInputs = o.buildInputs ++ [
        pkgs.aws-lc
        pkgs.zstd
      ];
    }))
  ];
}
