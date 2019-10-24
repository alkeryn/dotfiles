[(

self: super:
{
   bspwm = super.bspwm.overrideAttrs (old: rec {
     src = builtins.fetchGit "https://github.com/baskerville/bspwm";
   });
   ranger = super.ranger.overrideAttrs (old: rec {
     src = builtins.fetchGit "https://github.com/ranger/ranger";
   });
   waifu2x-converter-cpp = (super.waifu2x-converter-cpp.override {
     cudaSupport = true;
   });
   chromium = (super.chromium.override {
     enableWideVine = true;
   });

   neovim = super.neovim.override {
     withNodeJs = true;
     configure = {
       customRC = ''
         source ~/.config/nvim/init.vim
         let g:deoplete#sources#clang#libclang_path = "${super.llvmPackages.libclang}/lib/libclang.so"
         let g:deoplete#sources#clang#clang_header = "${super.llvmPackages.clang-unwrapped}/lib/clang"
       '';
         # let g:deoplete#sources#clang#clang_header = "${super.llvmPackages.clang-unwrapped}/lib/clang/${builtins.elemAt (builtins.split "-" super.llvmPackages.clang-unwrapped.name) 2}/include"
     };
   };

   ueberzug = super.callPackage ./pkgs/ueberzug.nix {};
}

)]
++
[
  (import (fetchGit "https://github.com/nixos-rocm/nixos-rocm" ) [] )
]
