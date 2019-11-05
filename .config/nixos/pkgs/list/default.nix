{ config, pkgs, ... }:

{
  imports =
    [
      ./devtools.nix
      ./hacking.nix
      ./sdr.nix
      ./tools.nix
    ];
  environment.systemPackages = with pkgs; [
    man-pages
    weechat
    wine-staging winetricks
  ];
}
