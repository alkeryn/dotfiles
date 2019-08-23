{ config, pkgs, ... }:

{
  imports =
    [
      ./configuration.nix
      ./pkgs/list
      ./pkgs/xorg
    ];

    environment.systemPackages = with pkgs; [
      tlp
      xorg.xbacklight
    ];

    services.xserver.libinput.enable = true;
    networking = {
      hostName = "Blade";
      networkmanager.enable = true;
    }
    users.users.alkeryn.extraGroups = [ "networkmanager" ];
  }
