{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    mpd
    mpc_cli
    mpv
    pythonPackages.subliminal #subtitle fetcher
    ncmpcpp
    pavucontrol
  ];

}
