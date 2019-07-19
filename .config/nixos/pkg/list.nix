{ config, pkgs, ... }:

{
  imports =
    [
      ./list/devtools.nix
      ./list/tools.nix
      ./list/hacking.nix
    ];
}
