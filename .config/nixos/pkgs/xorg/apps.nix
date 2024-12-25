{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    brave
    discord
    epiphany
    evince
    nautilus
    imagemagick
    qbittorrent
    spotify
    xorg.xeyes
    zathura
  ];
}
