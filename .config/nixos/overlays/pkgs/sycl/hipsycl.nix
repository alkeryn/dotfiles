{
stdenv,
fetchgit,
cmake,
bash,
llvmPackages_latest,
cudatoolkit,
python3,
boost,
}:

stdenv.mkDerivation rec {
  pname = "hipsycl";
  version = "0.8.0";
  src = fetchgit {
    url = "https://github.com/illuhad/hipSYCL";
    rev = "v${version}";
    sha256 = "08hky7wqim4rqrrrr1idx63mszsywmm6gs2fvd2yycklynr1dkvl";
    deepClone = true;
  };
  LLVM_DIR = "${llvmPackages_latest.llvm}";
  cmakeFlags = [
    "-DCLANG_INCLUDE_PATH=${llvmPackages_latest.clang-unwrapped}/include/"
      # "-DCLANG_INCLUDE_PATH=${clang-src}/clang/include/clang"
    #   "-DCLANG_EXECUTABLE_PATH=${llvmPackages_latest.clang}/bin/clang"
  ];
  buildInputs = [ cmake bash llvmPackages_latest.clang cudatoolkit python3 boost];
}
