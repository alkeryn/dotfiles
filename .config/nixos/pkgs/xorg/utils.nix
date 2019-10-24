{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    xorg.xev
    glxinfo
    virtmanager
    megasync
  ];
}
