{ config, pkgs, ... }:

{
  imports =
    [
      ./devtools.nix
      ./hacking.nix
      ./sdr.nix
      ./tools.nix
    ];
}
