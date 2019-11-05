{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    glxinfo
    megasync
    virtmanager
    xorg.xev
    xsel
    xwinwrap
  ];
}
