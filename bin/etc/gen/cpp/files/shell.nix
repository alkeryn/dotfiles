with import <nixpkgs> {};
mkShell rec {
  nativeBuildInputs = [
    llvmPackages_latest.clang
  ];
  buildInputs = [
    # glew
    # SDL2
    # nlohmann_json
    # curl
  ];
  # LD_LIBRARY_PATH = "${ocl-icd}/lib";
}
