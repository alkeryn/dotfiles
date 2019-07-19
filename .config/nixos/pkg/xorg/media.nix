{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    mpd
    mpc_cli
    mpv
    ncmpcpp
    pavucontrol
  ];

}
