[(

self: super:
{
   bspwm = super.bspwm.overrideAttrs (old: rec {
     src = builtins.fetchGit "https://github.com/baskerville/bspwm";
   });

   netbird = super.netbird.overrideAttrs (old: rec {
     version = "0.42.0";
     src = super.fetchFromGitHub {
       owner = "netbirdio";
       repo = "netbird";
       rev = "v${version}";
       hash = "sha256-xVk5vAU9G4HTaHmK1i8HvvYUxN0B2T2w+Vj4Ypg7N4s=";
     };
     vendorHash = "sha256-vy725OvkYLyCDYEmnPpXJWqyofb29GiP4GkLn1GInm0=";
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
