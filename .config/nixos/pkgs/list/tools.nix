{ config, pkgs, ... }:

{
    environment.systemPackages = with pkgs; [
      ethtool
      exfat
      exiftool
      file
      gnupg
      hdparm
      killall
      libressl # for openssl
      mkvtoolnix
      openvpn
      pciutils
      pv
      ripgrep
      screen
      speedtest-cli
      sshfs-fuse
      tree
      unrar
      usbutils
      wget
      youtube-dl
    ];
}
