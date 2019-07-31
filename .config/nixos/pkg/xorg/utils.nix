{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    xorg.xev
    glxinfo
    megasync
  ];
}
