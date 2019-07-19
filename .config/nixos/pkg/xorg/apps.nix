{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    chromium
    discord
    i3lock
    imagemagick
    gnome3.nautilus
  ];
}
