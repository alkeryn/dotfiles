{ config, pkgs, ... }:

{
  imports = [
    ./list.nix
    ./xorg/apps.nix
    ./xorg/fonts.nix
    ./xorg/games.nix
    ./xorg/utils.nix
    ./xorg/media.nix
    ./xorg/themes.nix
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
  ];

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
