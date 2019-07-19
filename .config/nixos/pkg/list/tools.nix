{ config, pkgs, ... }:

{
    environment.systemPackages = with pkgs; [
      killall
      hdparm
    ];
}
