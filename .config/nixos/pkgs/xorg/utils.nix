{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    mesa-demos
    virt-manager
    xorg.xev
    xsel
    xwinwrap
  ];
}
