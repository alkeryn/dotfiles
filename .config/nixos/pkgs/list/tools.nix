{ config, pkgs, ... }:

{
    environment.systemPackages = with pkgs; [
      file
      hdparm
      killall
      exiftool
      sshfs-fuse
      usbutils
      youtube-dl
    ];
}
