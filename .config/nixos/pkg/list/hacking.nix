{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    nmap
    whois
    socat
    radare2
    xxd
  ];
}
