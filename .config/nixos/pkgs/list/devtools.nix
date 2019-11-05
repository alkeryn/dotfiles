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
      llvmPackages_latest.clang
      clang-tools
      cmake
      debootstrap
      gcc
      gdb
      git
      gnumake
      nodejs yarn
      qemu
    ] ++ languages;
    programs.adb.enable = true;
}
