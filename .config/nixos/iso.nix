# This module defines a small NixOS installation CD.  It does not
# contain any graphical stuff.
{ config, pkgs, lib, ... }:
{
  imports = [
    <nixpkgs/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix>

    # Provide an initial copy of the NixOS channel so that the user
    # doesn't need to run "nix-channel --update" first.
    <nixpkgs/nixos/modules/installer/cd-dvd/channel.nix>
    ./ath11k.nix
  ];

  isoImage.squashfsCompression = "gzip -Xcompression-level 1";
  boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
  console.keyMap = "fr";

  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable=true;
  environment.noXlibs = lib.mkForce false;

  services.openssh = {
    enable = true;
    # require public key authentication for better security
    passwordAuthentication = false;
    kbdInteractiveAuthentication = false;
    permitRootLogin = "yes";
  };

  services.getty.autologinUser = lib.mkForce "root";

  users.users."root".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFcfSzUZ++WTpW1zICgHcBnZsTVDrqvUMIPna9mu9e7u alkeryn@Alkeryn-PC"
    # content of authorized_keys file
  ];
}
