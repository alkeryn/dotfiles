{ config, pkgs, ... }:

{
    environment.systemPackages = with pkgs; [
      cmake
      gcc
      clang
      nodejs
      python
      python3
    ];
    programs.adb.enable = true;
}
