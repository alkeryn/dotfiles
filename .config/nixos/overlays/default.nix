[(

self: super:
{
   bspwm = super.bspwm.overrideAttrs (old: rec {
     src = builtins.fetchGit "https://github.com/baskerville/bspwm";
   });

   netbird = super.netbird.overrideAttrs (old: rec {
     version = "0.45.1";
     src = super.fetchFromGitHub {
       owner = "netbirdio";
       repo = "netbird";
       rev = "v${version}";
       hash = "sha256-55Vyhzt0WtJRq9CcH7mXw7cklAce/lvC1S+MBMDnMbo=";
     };
     vendorHash = "sha256-EVhtxYDinmid5C/3N8UGmCzWw1qIE3m0rXes4uFpcOM=";
     ldflags = old.ldflags or [] ++ [
       "-X github.com/netbirdio/netbird/version.version=${version}"
       ];
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

   openai-whisper = (super.openai-whisper.overrideAttrs (old: rec {
      src = builtins.fetchGit "https://github.com/openai/whisper";
   })).override {
      torch = super.python3.pkgs.torch-bin;
   };

}

)]
# ++
# [
#   (import (fetchGit "https://github.com/nixos-rocm/nixos-rocm" ) )
# ]
