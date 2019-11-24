{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ]
    ++
    [
      ./configuration.nix
      ./pkgs/list
      ./pkgs/xorg
    ];

    boot.kernelParams = [ "button.lid_init_state=open" ];
    environment.systemPackages = with pkgs; [
      networkmanagerapplet
      unclutter
      xorg.xbacklight
      xss-lock
    ];

    services.tlp.enable = true;
    services.xserver.videoDrivers = [ "intel" ];
    services.xserver.libinput = {
      enable = true;
      naturalScrolling = true;
      accelSpeed = "0.6";
    };

    hardware.cpu.intel.updateMicrocode = true;
    hardware.openrazer.enable = true;

    networking = {
      hostName = "Blade";
      hostId="8425e349";
      networkmanager.enable = true;
      wireless.enable = false;
    };
    users.users.alkeryn.extraGroups = [ "networkmanager" ];
  }
