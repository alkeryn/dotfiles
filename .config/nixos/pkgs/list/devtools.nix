{ config, pkgs, ... }:

let
  languages = with pkgs;[
    # clisp
    dart
    go
    nodejs yarn
    python3
    python3.pkgs.pip
  ];
in
{
    environment.systemPackages = with pkgs; [
      bear
      binutils
      ccls
      clang-tools
      cmake
      debootstrap
      direnv
      gcc
      gdb
      git
      gnumake
      llvmPackages_latest.clang
      pandoc
      qemu
      stdman
    ] ++ languages;
    programs.adb.enable = true;
}
