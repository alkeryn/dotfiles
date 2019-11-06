{ config, pkgs, ... }:

{
  imports =
    [
      /etc/nixos/hardware-configuration.nix
    ]
    ++
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
      wireless.enable = false;
    };
    users.users.alkeryn.extraGroups = [ "networkmanager" ];
  }
