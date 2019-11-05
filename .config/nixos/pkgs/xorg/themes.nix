{ config, pkgs, ... }:

{
    environment.systemPackages = with pkgs; [
      adapta-gtk-theme
      arc-icon-theme
      capitaine-cursors
      paper-icon-theme
      paper-icon-theme
    ];
}
