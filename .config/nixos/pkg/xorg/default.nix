{ config, pkgs, ... }:

let
  overlays = with pkgs; [ ueberzug ];
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
  ] ++ overlays;

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
