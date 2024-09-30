{ config, pkgs, ... }:

let
  overlays = with pkgs; [ ueberzug ];
  qt = with pkgs; [ libsForQt5.qtstyleplugins ];
  xtty = "7";
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
    xkb.layout = "fr";
    windowManager.bspwm.enable = true;
    displayManager.startx.enable = true;
  };

  systemd.defaultUnit = "graphical.target";
  systemd.services.xlogin = {
    enable = true;
    description = "X11 for alkeryn";
    after = [ "graphical.target" "systemd-user-sessions.service" ];
    wantedBy = [ "graphical.target" ];
    serviceConfig = {
      User = "alkeryn";
      Restart = "no";
      WorkingDirectory = "~";
      PAMName = "login";
      Environment = [ "XDG_SESSION_TYPE=x11" ];
      TTYPath = "/dev/tty${xtty}";
      StandardInput = "tty";
      UnsetEnvironment = "TERM";
      UtmpIdentifier = "tty${xtty}";
      UtmpMode = "user";
      StandardOutput = "tty";
      ExecStartPre = "${pkgs.kbd}/bin/chvt ${xtty}";
      ExecStart = "${pkgs.xorg.xinit}/bin/startx";
    };
  };
}
