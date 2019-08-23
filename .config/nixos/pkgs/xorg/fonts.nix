{ config, pkgs, ... }:

{
  fonts.fonts = with pkgs; [
    dejavu_fonts
    hack-font
    noto-fonts
    noto-fonts-emoji
    noto-fonts-extra
    siji
  ];
}
