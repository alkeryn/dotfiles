# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, ... }:

let
  rangertools = with pkgs; [
    atool
    highlight
    mediainfo
  ];
  nixtools = with pkgs; [
    nix-prefetch-git
    patchelf
  ];
in
{
  imports =
    [ # Include the results of the hardware scan.
    /etc/nixos/hardware-configuration.nix
  ];
  nixpkgs.overlays = [ (import ./overlays/default.nix) ];

  system.autoUpgrade.channel = "https://nixos.org/channels/nixos-unstable";

  environment.systemPackages = with pkgs; [
    bind
    fzf
    htop
    lsof
    mosh
    neofetch
    neovim
    ranger
    unzip
    zsh
  ]
  ++ rangertools
  ++ nixtools;

  environment.variables = {
    LIBVIRT_DEFAULT_URI="qemu:///system";
    _JAVA_AWT_WM_NONREPARENTING="1";
    QT_STYLE_OVERRIDE="gtk2";
    GTK2_RC_FILES="$HOME/.gtkrc-2.0";
  };

  boot.tmpOnTmpfs = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = ["zfs"];
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n = {
    # consoleFont = "Lat2-Terminus16";
    consoleKeyMap = "fr";
    defaultLocale = "fr_FR.UTF-8";
  };

  # Set your time zone.
  time.timeZone = "Europe/Paris";
  services.localtime.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  # programs.gnupg.agent = { enable = true; enableSSHSupport = true; };

  # List services that you want to enable:

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;
  networking.nameservers = [ "8.8.8.8" "8.8.4.4" ];

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.root.shell = pkgs.zsh;
  users.users.alkeryn = {
    isNormalUser = true;
    extraGroups = [ "wheel" "adbusers" ]; # Enable ‘sudo’ for the user.
    uid = 1000;
    shell = pkgs.zsh;
  };

  # This value determines the NixOS release with which your system is to be
  # compatible, in order to avoid breaking some software such as database
  # servers. You should change this only after NixOS release notes say you
  # should.
  system.stateVersion = "19.03"; # Did you read the comment?

}
