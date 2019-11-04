with import <nixpkgs> {};
mkShell rec {
  nativeBuildInputs = [
    clang_9
  ];
  buildInputs = [
    # glew
    # SDL2
    # nlohmann_json
    # curl
  ];
  # LD_LIBRARY_PATH = "${ocl-icd}/lib";
}
