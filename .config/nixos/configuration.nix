# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

let
  rangertools = with pkgs; [
    atool
    highlight
    mediainfo
  ];
  nixtools = with pkgs; [
    nix-prefetch-git
    nixpkgs-review
    patchelf
  ];
in
{
  nixpkgs.overlays = import ./overlays;
  nixpkgs.config.allowUnfree = true;

  system.autoUpgrade.channel = "https://nixos.org/channels/nixos-unstable";

  environment.systemPackages = with pkgs; [
    bind
    fzf
    htop
    lsof
    mosh
    neofetch
    neovim
    pulseaudio # for pactl and whatnot
    ranger
    unzip
  ]
  ++ rangertools
  ++ nixtools;

  environment.variables = {
    LIBVIRT_DEFAULT_URI="qemu:///system";
    _JAVA_AWT_WM_NONREPARENTING="1";
    QT_STYLE_OVERRIDE="gtk2";
    GTK2_RC_FILES="$HOME/.gtkrc-2.0";
  };

  # nix.nixPath = [
  #   "nixpkgs=/home/alkeryn/.nixpkgs"
  # ];

  boot.tmp.useTmpfs = true;

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.supportedFilesystems = ["zfs"];
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;

  virtualisation.libvirtd = {
    enable = true;
    qemu.ovmf.enable = true;
    qemu.swtpm.enable = true;
  };
  programs.dconf.enable = true; # needed for virt manager to remember connection

  virtualisation.incus.enable = true;
  virtualisation.incus.socketActivation = true;

  systemd.enableUnifiedCgroupHierarchy = lib.mkForce true;
  # networking.hostName = "nixos"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  console.keyMap = "fr";
  i18n = {
    # consoleFont = "Lat2-Terminus16";
    defaultLocale = "fr_FR.UTF-8";
  };

  # Set your time zone.
  time.timeZone = "Europe/Paris";
  services.geoclue2.enable = true;
  services.localtimed.enable = true;

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
  networking.nameservers = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];

  services.resolved = {
    enable = true;
    dnssec = "true";
    dnsovertls = "true";
    domains = [ "~." ];
    fallbackDns = [ "1.1.1.1#one.one.one.one" "1.0.0.1#one.one.one.one" ];
  };

  # Enable CUPS to print documents.
  # services.printing.enable = true;

  # Enable sound.
  sound.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.root.shell = pkgs.zsh;
  users.users.alkeryn = {
    isNormalUser = true;
    extraGroups = [ "wheel" "adbusers" "libvirtd" "systemd-journald" "incus-admin" ]; # Enable ‘sudo’ for the user.
    uid = 1000;
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  # This value determines the NixOS release with which your system is to be
  # compatible, in order to avoid breaking some software such as database
  # servers. You should change this only after NixOS release notes say you
  # should.
  system.stateVersion = "24.05"; # Did you read the comment?
}
