{
lib,
cmake,
fetchFromGitHub,
ocl-icd,
opencl-clhpp,
opencl-headers,
python3,
spirv-headers,
spirv-llvm-translator,
spirv-tools,
stdenv,
}:

stdenv.mkDerivation rec {
  pname = "llvm";
  version = "2019-10";
  src = builtins.fetchurl {
    url="https://github.com/intel/llvm/archive/${version}.tar.gz";
    sha256="0vnvanxirrigcmkb3fd6sz0rd2xgbyrddzj1y9qcq44h9haz2mb6";
  };
  # src = fetchFromGitHub {
  #   owner = "intel";
  #   repo = "llvm";
  #   sha256 = "0wravn3a3fs4fw8pdm8n568g383hipxyvk1pcjg4zshwfqn802f7";
  #   rev = "d43ee69eb59b606c1181130fb88259da94857fa1";
  # };
  nativeBuildInputs = [ cmake python3 spirv-headers spirv-tools spirv-llvm-translator ];
  buildInputs = [ ocl-icd opencl-headers opencl-clhpp ];

  dontConfigure = true;

  NIX_LDFLAGS = [ "-lOpenCL" ];


  buildPhase = ''
    export SYCL_HOME=$PWD
    export MAKEFLAGS="-j$(nproc)"
    mkdir build
    cd build

    cmake -DCMAKE_BUILD_TYPE=Release -DLLVM_TARGETS_TO_BUILD="X86" \
    -DLLVM_EXTERNAL_PROJECTS="llvm-spirv;sycl" \
    -DLLVM_ENABLE_PROJECTS="clang;llvm-spirv;sycl" \
    -DLLVM_EXTERNAL_SYCL_SOURCE_DIR=$SYCL_HOME/sycl \
    -DLLVM_EXTERNAL_LLVM_SPIRV_SOURCE_DIR=$SYCL_HOME/llvm-spirv \
    -DOpenCL_INCLUDE_DIRS=${opencl-headers}/include \
    -DOpenCL_LIBRARIES=${ocl-icd}/lib \
    -DCMAKE_INSTALL_PREFIX=$out \
    $SYCL_HOME/llvm

    make -j$(nproc) sycl-toolchain
    '';

    meta = with lib; {
      description = "LLVM sycl branch and toolchain";
      longDescription = ''
        sycl is a single source heterogenous computing api that relies on opencl
      '';
      homepage = "https://github.com/intel/llvm";
      license = licenses.gpl3Plus;
      platforms = platforms.linux;
      maintainers = with maintainers; [ alkeryn ];
    };
}
