{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    nmap
    radare2
  ];
}
