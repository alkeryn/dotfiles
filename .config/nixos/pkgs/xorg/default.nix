{ config, pkgs, ... }:

let
  overlays = with pkgs; [ ueberzug ];
  qt = with pkgs; [ libsForQt512.qtstyleplugins ];
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
    compton
    conky
    feh
    imv
    lxappearance-gtk3
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
    autorun = true;
    layout = "fr";
    desktopManager.default = "none";
    windowManager.bspwm.enable = true;
    windowManager.default = "bspwm";
    displayManager.auto.enable = true;
    displayManager.auto.user = "alkeryn";
    # displayManager.startx.enable = true;
  };

}
