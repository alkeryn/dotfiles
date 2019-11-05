{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    nmap
    pythonPackages.binwalk
    radare2
    socat
    tcpdump
    whois
    xxd
  ];
}
