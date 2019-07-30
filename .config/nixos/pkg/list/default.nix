{ config, pkgs, ... }:

{
  imports =
    [
      ./devtools.nix
      ./tools.nix
      ./hacking.nix
    ];
}
