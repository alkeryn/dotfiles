{
callPackage,
wrapCCWith,
llvmPackages_latest,
stdenv,
libstdcxxHook,
}:
let
  llvm = callPackage ./llvm.nix {};
  mkExtraBuildCommands = cc: ''
      rsrc="$out/resource-root"
      mkdir "$rsrc"
      ln -s "${cc}/lib/clang/10/include" "$rsrc"
      ln -s "${llvmPackages_latest.compiler-rt.out}/lib" "$rsrc/lib"
      echo "-resource-dir=$rsrc" >> $out/nix-support/cc-cflags
      echo "--gcc-toolchain=${llvmPackages_latest.clang-unwrapped.gcc}" >> $out/nix-support/cc-cflags
  '';
in
{
  clang = wrapCCWith rec {
    cc = llvm;
    extraPackages = [
      libstdcxxHook
      llvmPackages_latest.compiler-rt
    ];
    extraBuildCommands = mkExtraBuildCommands cc;
  };
  # clang = wrapCCWith rec {
  #   cc = llvm;
  #   libcxx = llvmPackages_latest.libcxx;
  #   extraPackages = [
  #     llvmPackages_latest.libcxx
  #     llvmPackages_latest.libcxxabi
  #     llvmPackages_latest.compiler-rt
  #   ];
  #   extraBuildCommands = mkExtraBuildCommands cc;
  # };

  hipsycl = callPackage ./hipsycl.nix {};
}

