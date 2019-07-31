{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    chromium
    discord
    epiphany
    evince
    gnome3.nautilus
    i3lock
    imagemagick
    qbittorrent
    spotify
    xorg.xeyes
  ];
}
