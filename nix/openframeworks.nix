{ lib
, stdenv
, fetchurl
, pkg-config
, gnumake

# Graphics / OpenGL
, libGL
, libGLU
, glew
, freeglut
, glfw
, glm

# X11 / Windowing (Linux only)
, libX11 ? null
, libXrandr ? null
, libXxf86vm ? null
, libXi ? null
, libXcursor ? null
, libXinerama ? null
, libXmu ? null

# Wayland (Linux only)
, wayland ? null
, wayland-protocols ? null
, libxkbcommon ? null
, libdecor ? null

# Fonts / 2D Graphics
, cairo
, freetype
, fontconfig
, pixman

# Audio
, openal
, libsndfile
, rtaudio
, alsa-lib ? null
, libjack2 ? null
, libpulseaudio ? null

# Video (Linux only)
, gstreamer ? null
, gst-plugins-base ? null
, gst-plugins-good ? null
, gst-plugins-bad ? null
, gst_all_1 ? null

# Networking
, curl
, openssl
, brotli

# Data / Parsing
, pugixml
, uriparser
, nlohmann_json
, libxml2
, zlib
, fmt

# System
, udev ? null
, libusb1
, libdrm ? null

# Misc
, poco
, opencv
, assimp
, mpg123 ? null
, harfbuzz
, gtk3 ? null

# Darwin frameworks
, darwin ? null

# Custom dependencies
, apothecaryLibs
}:

let
  version = "0.12.1";

  isDarwin = stdenv.hostPlatform.isDarwin;
  isLinux = stdenv.hostPlatform.isLinux;

  platformLibSubpath =
    if isLinux && stdenv.hostPlatform.isx86_64 then "linux64"
    else if isLinux && stdenv.hostPlatform.isAarch64 then "linuxaarch64"
    else if isDarwin then "osx"
    else throw "Unsupported platform for openFrameworks";

  # The path inside the apothecary bundle where .a files live
  apothecaryLibDir =
    if isLinux then "linux/64"
    else if isDarwin then "macos"
    else throw "Unsupported platform";

in stdenv.mkDerivation {
  pname = "openframeworks";
  inherit version;

  src = lib.cleanSourceWith {
    src = ./..;
    filter = path: type:
      let baseName = baseNameOf path; in
      # Exclude nix build artifacts, git, and IDE files
      !(baseName == ".git" || baseName == "flake.nix" || baseName == "flake.lock"
        || baseName == "result" || baseName == ".vscode"
        || lib.hasSuffix ".xcodeproj" baseName
        || lib.hasSuffix ".xcworkspace" baseName);
  };

  nativeBuildInputs = [
    pkg-config
    gnumake
  ];

  buildInputs = [
    # Graphics / OpenGL
    glm
    cairo
    freetype
    fontconfig
    pixman

    # Audio
    openal
    libsndfile
    rtaudio

    # Networking
    curl
    openssl
    brotli

    # Data / Parsing
    pugixml
    uriparser
    nlohmann_json
    libxml2
    zlib
    fmt

    # System
    libusb1

    # Misc
    poco
    opencv
    assimp
    harfbuzz
  ] ++ lib.optionals isLinux [
    # Graphics / OpenGL
    libGL
    libGLU
    glew
    freeglut
    glfw

    # X11 / Windowing
    libX11
    libXrandr
    libXxf86vm
    libXi
    libXcursor
    libXinerama
    libXmu

    # Wayland
    wayland
    wayland-protocols
    libxkbcommon
    libdecor

    # Audio (Linux-specific backends)
    alsa-lib
    libjack2
    libpulseaudio
    mpg123

    # Video
    gstreamer
    gst-plugins-base
    gst-plugins-good
    gst-plugins-bad
    gst_all_1.gst-libav

    # System
    udev
    libdrm

    # GTK
    gtk3
  ] ++ lib.optionals isDarwin (with darwin.apple_sdk.frameworks; [
    Cocoa
    CoreVideo
    CoreAudio
    CoreMedia
    CoreFoundation
    CoreServices
    AVFoundation
    AudioToolbox
    Security
    AppKit
    Accelerate
    Metal
    QuartzCore
    IOKit
    SystemConfiguration
    Foundation
    OpenGL
  ]);

  # Force GST_VERSION to 1.0 so the Makefiles don't try to probe at eval time
  GST_VERSION = "1.0";

  # Ensure USE_FMOD is disabled (FMOD is proprietary)
  USE_FMOD = "0";

  # Suppress GCC warnings that get promoted to errors with newer GCC versions
  # (GCC 15+ is stricter about -Wmaybe-uninitialized in template instantiations)
  NIX_CFLAGS_COMPILE = "-Wno-error=maybe-uninitialized -Wno-error=dangling-reference";

  # Disable Nix hardening flags that conflict with OF's build
  hardeningDisable = [ "format" "fortify" ];

  configurePhase = ''
    runHook preConfigure

    export OF_ROOT="$PWD"

    # =========================================================================
    # Populate the libs/ directory with symlinks to nix-provided packages
    # and apothecary pre-built libraries for things not in nixpkgs.
    # The OF Makefiles expect: libs/{name}/include/ and libs/{name}/lib/{platform}/
    # =========================================================================

    echo "==> Setting up library symlinks..."

    # --- Header-only libraries from nixpkgs ---

    # GLM
    mkdir -p libs/glm/include
    ln -sf ${glm}/include/glm libs/glm/include/glm

    # nlohmann_json
    mkdir -p libs/json/include
    ln -sf ${nlohmann_json}/include/nlohmann libs/json/include/nlohmann

    # fmt (headers)
    mkdir -p libs/fmt/include
    ln -sf ${fmt}/include/fmt libs/fmt/include/fmt

    # --- Apothecary pre-built libraries (tess2, svgtiny, kiss, utf8, FreeImage) ---
    for libname in tess2 svgtiny kiss utf8 FreeImage; do
      if [ -d "${apothecaryLibs}/$libname" ]; then
        echo "  Linking apothecary lib: $libname"
        # Remove any existing directory (from source tree)
        rm -rf "libs/$libname"
        # Create the directory and copy contents (can't symlink dirs in Nix store easily
        # because the Makefiles do find -type d)
        mkdir -p "libs/$libname"
        cp -rL "${apothecaryLibs}/$libname"/* "libs/$libname/" 2>/dev/null || true
        chmod -R u+w "libs/$libname" 2>/dev/null || true
      fi
    done

    # Rename the apothecary lib path to match what OF expects for this platform
    # Apothecary uses libs/{name}/lib/linux/64/ but OF Makefiles look for
    # libs/{name}/lib/{platformLibSubpath}/ (e.g., linux64)
    # Actually, the Makefile uses ABI_LIB_SUBPATH which resolves via PLATFORM_LIB_SUBPATH
    # Looking at config.project.mk: ALL_OF_CORE_LIBS_PLATFORM_LIB_PATHS = $(OF_LIBS_PATH)/*/lib/$(ABI_LIB_SUBPATH)
    # And config.shared.mk: ABI_LIB_SUBPATH=$(PLATFORM_LIB_SUBPATH) for linux64
    # So it looks for: libs/*/lib/linux64/
    # But apothecary uses: libs/*/lib/linux/64/
    # We need to create the expected layout
    for libname in tess2 svgtiny kiss FreeImage; do
      apoth_lib="libs/$libname/lib/${apothecaryLibDir}"
      target_lib="libs/$libname/lib/${platformLibSubpath}"
      if [ -d "$apoth_lib" ] && [ ! -d "$target_lib" ]; then
        echo "  Remapping $apoth_lib -> $target_lib"
        mkdir -p "$target_lib"
        cp -rL "$apoth_lib"/* "$target_lib/" 2>/dev/null || true
      fi
    done

    # --- Patch the Makefile system for Nix compatibility ---

    # 0. On Linux, the Makefiles EXCLUDE libs/FreeImage/% from the third-party
    #    include search (expecting FreeImage to be a system library). Since we
    #    provide it from apothecary, add its include path via PLATFORM_HEADER_SEARCH_PATHS.
    ${lib.optionalString isLinux ''
      echo 'PLATFORM_HEADER_SEARCH_PATHS += $(OF_LIBS_PATH)/FreeImage/include' \
        >> libs/openFrameworksCompiled/project/makefileCommon/config.linux.common.mk
    ''}

    # 1. Disable mold/gold linker probing in linux64 config
    #    (Nix provides its own linker wrapper)
    substituteInPlace libs/openFrameworksCompiled/project/${platformLibSubpath}/config.${platformLibSubpath}.default.mk \
      --replace-quiet 'ifneq (, $(shell command -v mold))' 'ifeq (1,0)' \
      --replace-quiet 'ifneq (, $(shell command -v gold))' 'ifeq (1,0)' \
      || true

    # 2. Force GST_VERSION in the linux common config to avoid shell probing
    substituteInPlace libs/openFrameworksCompiled/project/makefileCommon/config.linux.common.mk \
      --replace-quiet 'ifndef GST_VERSION' 'GST_VERSION ?= 1.0
ifdef __NEVER_DEFINED__' \
      || true

    # 3. Ensure FMOD is excluded
    substituteInPlace libs/openFrameworksCompiled/project/makefileCommon/config.linux.common.mk \
      --replace-quiet 'ifeq ($(USE_FMOD),0)' 'USE_FMOD=0
ifeq ($(USE_FMOD),0)' \
      || true

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    echo "==> Building openFrameworks core library (Release)..."
    cd libs/openFrameworksCompiled/project

    make -j''${NIX_BUILD_CORES:-1} Release \
      PLATFORM_OS=${if isLinux then "Linux" else "Darwin"} \
      OF_ROOT="$OF_ROOT" \
      GST_VERSION=1.0 \
      USE_FMOD=0

    cd "$OF_ROOT"

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    echo "==> Installing openFrameworks..."

    # --- Install the compiled static library ---
    mkdir -p $out/lib
    find libs/openFrameworksCompiled/lib/${platformLibSubpath} -name "*.a" -exec cp {} $out/lib/ \;

    # --- Install core headers ---
    mkdir -p $out/include/openFrameworks
    # Copy the main header
    cp libs/openFrameworks/ofMain.h $out/include/openFrameworks/
    # Copy all subdirectory headers
    for dir in 3d app communication events gl graphics math sound types utils video; do
      if [ -d "libs/openFrameworks/$dir" ]; then
        mkdir -p "$out/include/openFrameworks/$dir"
        find "libs/openFrameworks/$dir" -name "*.h" -exec cp {} "$out/include/openFrameworks/$dir/" \;
      fi
    done

    # --- Install third-party headers that OF projects need ---
    mkdir -p $out/include/of-thirdparty

    # tess2
    if [ -d libs/tess2/include ]; then
      cp -rL libs/tess2/include/* $out/include/of-thirdparty/ 2>/dev/null || true
    fi

    # kiss (FFT)
    if [ -d libs/kiss/include ]; then
      cp -rL libs/kiss/include/* $out/include/of-thirdparty/ 2>/dev/null || true
    fi

    # utf8
    if [ -d libs/utf8/include ]; then
      cp -rL libs/utf8/include/* $out/include/of-thirdparty/ 2>/dev/null || true
    fi

    # svgtiny
    if [ -d libs/svgtiny/include ]; then
      cp -rL libs/svgtiny/include/* $out/include/of-thirdparty/ 2>/dev/null || true
    fi

    # FreeImage
    if [ -d libs/FreeImage/include ]; then
      cp -rL libs/FreeImage/include/* $out/include/of-thirdparty/ 2>/dev/null || true
    fi

    # --- Install static libs from apothecary (tess2, svgtiny, kiss, FreeImage) ---
    for libname in tess2 svgtiny kiss FreeImage; do
      libdir="libs/$libname/lib/${platformLibSubpath}"
      if [ -d "$libdir" ]; then
        find "$libdir" -name "*.a" -exec cp {} $out/lib/ \;
      fi
    done

    # --- Install addons ---
    mkdir -p $out/share/openFrameworks/addons
    for addon in addons/ofx*; do
      if [ -d "$addon" ]; then
        cp -rL "$addon" $out/share/openFrameworks/addons/ 2>/dev/null || true
      fi
    done

    # --- Install makefile infrastructure for downstream projects ---
    mkdir -p $out/share/openFrameworks/libs/openFrameworksCompiled/project/makefileCommon
    mkdir -p $out/share/openFrameworks/libs/openFrameworksCompiled/project/${platformLibSubpath}
    cp -rL libs/openFrameworksCompiled/project/makefileCommon/*.mk \
      $out/share/openFrameworks/libs/openFrameworksCompiled/project/makefileCommon/
    cp -rL libs/openFrameworksCompiled/project/${platformLibSubpath}/*.mk \
      $out/share/openFrameworks/libs/openFrameworksCompiled/project/${platformLibSubpath}/
    cp libs/openFrameworksCompiled/project/Makefile \
      $out/share/openFrameworks/libs/openFrameworksCompiled/project/

    # --- Install project templates ---
    if [ -d scripts/templates ]; then
      mkdir -p $out/share/openFrameworks/scripts
      cp -rL scripts/templates $out/share/openFrameworks/scripts/
    fi

    # --- Generate pkg-config file ---
    mkdir -p $out/lib/pkgconfig
    cat > $out/lib/pkgconfig/openframeworks.pc << EOF
    prefix=$out
    libdir=\''${prefix}/lib
    includedir=\''${prefix}/include

    Name: openFrameworks
    Description: openFrameworks creative coding library
    Version: ${version}
    Libs: -L\''${libdir} -lopenFrameworks
    Cflags: -I\''${includedir}/openFrameworks -I\''${includedir}/of-thirdparty -DGLM_FORCE_CTOR_INIT -DGLM_ENABLE_EXPERIMENTAL
    EOF

    runHook postInstall
  '';

  # Disable fixup phases that might break static libraries
  dontStrip = true;
  dontPatchELF = true;

  meta = with lib; {
    description = "openFrameworks - an open source C++ toolkit for creative coding";
    longDescription = ''
      openFrameworks is an open source C++ toolkit designed to assist the
      creative process by providing a simple and intuitive framework for
      experimentation. The toolkit is designed to work as a general purpose
      glue, and wraps together several commonly used libraries for creative
      coding.
    '';
    homepage = "https://openframeworks.cc/";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
  };
}
