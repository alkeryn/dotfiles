{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    brave
    discord
    epiphany
    evince
    gnome3.nautilus
    imagemagick
    qbittorrent
    spotify
    xorg.xeyes
    zathura
  ];
}
