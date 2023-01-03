[(

self: super:
{
   bspwm = super.bspwm.overrideAttrs (old: rec {
     src = builtins.fetchGit "https://github.com/baskerville/bspwm";
   });
   # ranger = super.ranger.overrideAttrs (old: rec {
   #   src = builtins.fetchGit "https://github.com/ranger/ranger";
   # });
   waifu2x-converter-cpp = (super.waifu2x-converter-cpp.override {
     cudaSupport = true;
   });
   chromium = (super.chromium.override {
     enableWideVine = true;
   });

   neovim = super.neovim.override {
     withNodeJs = true;
   };

   ueberzug = super.callPackage ./pkgs/ueberzug.nix {};
   sycl = super.callPackage ./pkgs/sycl {};

}

)]
++
[
  (import (fetchGit "https://github.com/nixos-rocm/nixos-rocm" ) )
]
