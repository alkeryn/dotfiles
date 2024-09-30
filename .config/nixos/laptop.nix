{ config, pkgs, lib, ... }:

let
  nvidia-offload = pkgs.writeShellScriptBin "prime" ''
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0 export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    exec "$@"
  '';
in
{
  imports =
    [
      ./hardware-configuration.nix
      ./ath11k.nix
    ]
    ++
    [
      ./configuration.nix
      ./pkgs/list
      ./pkgs/xorg
    ];

    environment.systemPackages = with pkgs; [
      networkmanagerapplet
      unclutter
      xss-lock
      nvidia-offload
    ];

    boot.extraModprobeConfig = "options kvm_amd nested=1";

    # boot.kernelParams = [ "amdgpu.backlight=0" ]; # fix backlight
    services.tlp.enable = true;
    programs.light.enable = true;
    hardware.bluetooth.enable = true;

    systemd.services.lxd.wantedBy = lib.mkForce [];

    services.libinput = {
      enable = true;
      touchpad = {
        naturalScrolling = true;
        accelSpeed = "0.6";
      };
    };
    hardware.nvidia.package = (config.boot.kernelPackages.nvidiaPackages.stable.overrideAttrs {
      src = pkgs.fetchurl {
        url = "https://download.nvidia.com/XFree86/Linux-x86_64/525.147.05/NVIDIA-Linux-x86_64-525.147.05.run";
        sha256 = "1wgyyd53s1ivxccyazpyprlk72km0zd8cyad0kii4zjwakm86la3";
      };
    });

    hardware.openrazer.enable = true;
    hardware.openrazer.users = [ "alkeryn" ];

    services.xserver.videoDrivers = [ "nvidia" ];
    hardware.nvidia.powerManagement.enable = true;
    hardware.nvidia.powerManagement.finegrained = true;

    hardware.nvidia.prime = {
      offload.enable = true;

      # Bus ID of the Amd GPU. You can find it using lspci, either under 3D or VGA
      amdgpuBusId = "PCI:100:0:0";

      # Bus ID of the NVIDIA GPU. You can find it using lspci, either under 3D or VGA
      nvidiaBusId = "PCI:1:0:0";
    };
    services.xserver.screenSection = ''
      Option "TearFree" "true"
    ''; # tearing and 144hz

    networking = {
      hostName = "Blade";
      hostId="8425e349";
      networkmanager.enable = true;
      wireless.enable = false;
    };
    hardware.logitech.wireless.enable = true;
    hardware.logitech.wireless.enableGraphical = true; # for solaar to be included

    users.users.alkeryn.extraGroups = [ "networkmanager" "video" ];
}
