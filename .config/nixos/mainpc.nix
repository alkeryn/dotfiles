{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ]
    ++
    [
      ./configuration.nix
      ./pkgs/list
      ./pkgs/xorg
    ];

    environment.systemPackages = with pkgs; [
      zfs
    ];
    hardware.ckb-next.enable = true;
    hardware.bluetooth.enable = true;
    hardware.steam-hardware.enable = true;
    hardware.pulseaudio.daemon.config = {
      default-sample-rate = "96000";
      default-sample-format = "s32le";
      resample-method = "src-sinc-best-quality";
    };

    services.openssh = {
      enable = true;
      listenAddresses = [ { addr = "0.0.0.0"; } ];
      passwordAuthentication = false;
      permitRootLogin = "no";
    };

    networking.hostName = "Alkeryn-PC";
    networking.hostId = "8fddb2a7";

    # networking.interfaces.eth0.ipv4.addresses = [ {
        # address = "192.168.1.2";
        # prefixLength = 24;
    # } ];

    boot.extraModprobeConfig =''
    options bluetooth disable_ertm=1
'';

    services.xserver.wacom.enable = true;
    services.xserver.videoDrivers = [ "nvidia" ];
    services.xserver.screenSection = ''
    Option         "metamodes" "DVI-D-0: 1920x1080_144 +1920+0 {ForceCompositionPipeline=On, ForceFullCompositionPipeline=On}, HDMI-0: nvidia-auto-select +0+0 {ForceCompositionPipeline=On, ForceFullCompositionPipeline=On}"
  ''; # tearing and 144hz
    # boot.blacklistedKernelModules = [ "i915" "intel_agp" ];
    # boot.extraModprobeConfig =''
# install i915 /usr/bin/env false
# install intel_agp /usr/bin/env false

# '';


}
