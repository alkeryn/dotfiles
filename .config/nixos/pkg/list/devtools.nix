{ config, pkgs, ... }:

let
  languages = with pkgs;[
    clisp
    python
    python3
  ];
in
{
    environment.systemPackages = with pkgs; [
      binutils
      clang
      cmake
      debootstrap
      gcc
      gdb
      git
      gnumake
      nodejs
      qemu
    ] ++ languages;
    programs.adb.enable = true;
}
