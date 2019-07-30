{ config, pkgs, ... }:

{
    environment.systemPackages = with pkgs; [
      cmake
      gcc
      git
      clang
      nodejs
      python
      python3
    ];
    programs.adb.enable = true;
}
