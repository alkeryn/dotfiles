{ config, pkgs, ... }:

{
    environment.systemPackages = with pkgs; [
      gqrx
      limesuite
      # gr-limesdr
      # gnuradio-with-packages
    ];
    boot.blacklistedKernelModules = [ "dvb_usb_rtl28xxu" ];
    services.udev = {
      packages = [ pkgs.rtl-sdr ];
      extraRules = ''
        SUBSYSTEM=="usb", ATTR{idVendor}=="04b4", ATTR{idProduct}=="8613", SYMLINK+="stream-%k", MODE="666"
        SUBSYSTEM=="usb", ATTR{idVendor}=="04b4", ATTR{idProduct}=="00f1", SYMLINK+="stream-%k", MODE="666"
        SUBSYSTEM=="usb", ATTR{idVendor}=="0403", ATTR{idProduct}=="601f", SYMLINK+="stream-%k", MODE="666"
        SUBSYSTEM=="usb", ATTR{idVendor}=="1d50", ATTR{idProduct}=="6108", SYMLINK+="stream-%k", MODE="666"
        SUBSYSTEM=="xillybus", MODE="666", OPTIONS="last_rule"
      '';
    };
  }
