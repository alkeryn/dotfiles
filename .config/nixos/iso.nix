{config, pkgs, ...}:
{
  imports = [
    ./configuration.nix
    ./pkgs/list
    ./pkgs/xorg
    <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix>

    # Provide an initial copy of the NixOS channel so that the user
    # doesn't need to run "nix-channel --update" first.
    <nixpkgs/nixos/modules/installer/cd-dvd/channel.nix>
  ];

  services.xserver.libinput.enable = true;
  networking = {
    hostName = "Blade";
    networkmanager.enable = true;
    wireless.enable = false;
  };
  users.users.alkeryn.extraGroups = [ "networkmanager" ];

  services.xserver = {
    enable = true;
    autorun = false;
    layout = "fr";
    desktopManager.default = "none";
    windowManager.bspwm.enable = true;
    windowManager.default = "bspwm";
    displayManager.auto.enable = false;
    displayManager.auto.user = "alkeryn";
    # displayManager.startx.enable = true;
  };
}
