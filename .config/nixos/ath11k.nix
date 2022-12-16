{ config, pkgs, ... }:

let board-2_bin = builtins.fetchurl {
  url = "https://github.com/kvalo/ath11k-firmware/raw/771599eb9b6dfd6c7ccea875b550734fa0fcefc9/WCN6855/hw2.0/board-2.bin";
  sha256 = "06hcgjr7qwfi1vh3rv11m0hkx5qdkbjjhny6yb0d7iyyrgs3zn8v";
};

ath11k_blade = pkgs.runCommandNoCC "ath11k_blade" {} ''
  ath_path=$out/lib/firmware/ath11k/WCN6855
  mkdir -p $ath_path/hw2.0
  mkdir -p $ath_path/hw2.1
  cp ${board-2_bin} $ath_path/hw2.0/board-2.bin
  cp ${board-2_bin} $ath_path/hw2.1/board-2.bin
'';

xz_blacklist = [ ath11k_blade ];
in {
  nixpkgs.overlays = [ (self: super: {
    compressFirmwareXz = firmware: if builtins.elem firmware xz_blacklist
    then firmware
    else super.compressFirmwareXz firmware;
  })];
  hardware.firmware = [ ath11k_blade ];
}

# this file add wifi support for razer blade 14 2022
