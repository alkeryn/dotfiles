{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    mpd
    mpc
    mpv
    # pythonPackages.subliminal #subtitle fetcher
    ncmpcpp
    pavucontrol
  ];

}
