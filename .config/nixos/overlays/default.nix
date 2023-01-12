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

   neovim = super.neovim.override {
     withNodeJs = true;
   };

   rofi = super.rofi.override {
      plugins = with super; [
         rofi-calc
         rofi-emoji
      ];
   };

}

)]
++
[
  (import (fetchGit "https://github.com/nixos-rocm/nixos-rocm" ) )
]
