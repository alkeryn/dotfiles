{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    steam
  ];
  hardware.graphics.enable32Bit = true;
  hardware.pulseaudio.support32Bit = true;
}
