{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    glxinfo
    megasync
    virt-manager
    xorg.xev
    xsel
    xwinwrap
  ];
}
