{ lib
, stdenv
, fetchurl
, system
}:

# This derivation fetches the pre-built openFrameworks third-party libraries
# from the apothecary project. These are libraries that are either:
# - not available in nixpkgs (tess2, svgtiny, kiss)
# - header-only libs bundled by OF (utf8)
# - or need to match OF's exact expected layout (FreeImage, glm, etc.)
#
# On Linux, we only extract the small/niche libs that aren't in nixpkgs.
# On Darwin, we extract more since many libs need the apothecary builds.

let
  sources = {
    x86_64-linux = fetchurl {
      url = "https://github.com/openframeworks/apothecary/releases/download/v12.1.0/openFrameworksLibs_v12.1.0_linux_64_gcc14.tar.bz2";
      hash = "sha256-oZIOgZkVCEj/dgIq3HJuBwVG9rTQjMgT79Y0WkcRrvY=";
    };
    aarch64-linux = fetchurl {
      url = "https://github.com/openframeworks/apothecary/releases/download/latest/openFrameworksLibs_latest_linux_arm64_gcc14.tar.bz2";
      hash = lib.fakeHash;
    };
    # Darwin uses the macOS builds which are universal (arm64 + x86_64)
    x86_64-darwin = fetchurl {
      url = "https://github.com/openframeworks/apothecary/releases/download/latest/openFrameworksLibs_latest_macos_1.tar.bz2";
      hash = lib.fakeHash;
    };
    aarch64-darwin = fetchurl {
      url = "https://github.com/openframeworks/apothecary/releases/download/latest/openFrameworksLibs_latest_macos_1.tar.bz2";
      hash = lib.fakeHash;
    };
  };

  platformLibPath = if stdenv.hostPlatform.isLinux then
    (if stdenv.hostPlatform.isx86_64 then "linux/64"
     else if stdenv.hostPlatform.isAarch64 then "linux/64"  # aarch64 uses same path in newer bundles
     else throw "Unsupported Linux architecture")
  else if stdenv.hostPlatform.isDarwin then "macos"
  else throw "Unsupported platform";

in stdenv.mkDerivation {
  pname = "openframeworks-apothecary-libs";
  version = "12.1.0";

  src = sources.${system} or (throw "Unsupported system: ${system}");

  sourceRoot = ".";

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
    runHook preInstall

    # Install each library into its own subdirectory under $out
    # preserving the OF-expected layout: libs/{name}/include and libs/{name}/lib/{platform}

    for lib in tess2 svgtiny kiss utf8 glm json fmt; do
      if [ -d "$lib" ]; then
        echo "Installing $lib"
        mkdir -p "$out/$lib"
        cp -r "$lib"/* "$out/$lib/"
      fi
    done

    # Also install FreeImage from the bundle (pre-built, as fallback)
    if [ -d "FreeImage" ]; then
      mkdir -p "$out/FreeImage"
      cp -r FreeImage/* "$out/FreeImage/"
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "Pre-built third-party libraries for openFrameworks from the apothecary project";
    homepage = "https://github.com/openframeworks/apothecary";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
  };
}
