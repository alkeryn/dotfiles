{ config, pkgs, ... }:

let
  overlays = with pkgs; [ ueberzug ];
  qt = with pkgs; [ libsForQt5.qtstyleplugins ];
in
{
  imports = [
    ./apps.nix
    ./fonts.nix
    ./games.nix
    ./utils.nix
    ./media.nix
    ./themes.nix
  ];

  environment.systemPackages = with pkgs; [
    bspwm
    i3lock
    picom
    conky
    feh
    imv
    lxappearance
    maim
    numlockx
    polybar
    rofi
    scrot
    sxhkd
    termite
    xclip
    xorg.xhost
  ]
  ++ qt
  ++ overlays;

  environment.variables = {
    TERMINAL="termite";
  };

  services.xserver = {
    enable = true;
    layout = "fr";
    windowManager.bspwm.enable = true;
    displayManager.startx.enable = true;
  };
}
