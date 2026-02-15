# mkOFExample.nix — Shared builder function for openFrameworks example projects
#
# The OF Makefile system is deeply coupled to the source tree: it expects
# OF_ROOT to point at a full openFrameworks checkout with libs/, addons/,
# and the makefile infrastructure.  The `Release` target even rebuilds the
# core library before building the project.
#
# Strategy:
#   1. Copy the full OF source tree (filtered) into the build dir.
#   2. Run the same configure phase as openframeworks.nix (symlink libs, patch Makefiles).
#   3. Place the pre-built core .a from the openframeworks package so the
#      core "build" is a no-op (the Makefile checks for the .a existence).
#   4. Copy the example's Makefile + config.make from the template.
#   5. Build with `make ReleaseNoOF` (skips core rebuild).
#   6. Install the resulting binary and bin/data/ to $out.

{ lib
, stdenv
, pkg-config
, gnumake

# The pre-built openframeworks package (provides the core .a and headers)
, openframeworks

# The apothecary pre-built libs
, apothecaryLibs

# Graphics / OpenGL
, libGL ? null
, libGLU ? null
, glew ? null
, freeglut ? null
, glfw ? null
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
, libpng

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
}:

let
  isLinux = stdenv.hostPlatform.isLinux;
  isDarwin = stdenv.hostPlatform.isDarwin;

  platformLibSubpath =
    if isLinux && stdenv.hostPlatform.isx86_64 then "linux64"
    else if isLinux && stdenv.hostPlatform.isAarch64 then "linuxaarch64"
    else if isDarwin then "osx"
    else throw "Unsupported platform for openFrameworks";

  apothecaryLibDir =
    if isLinux then "linux/64"
    else if isDarwin then "macos"
    else throw "Unsupported platform";

  templatePath =
    if isLinux then
      (if stdenv.hostPlatform.isx86_64 then "linux64"
       else if stdenv.hostPlatform.isAarch64 then "linuxaarch64"
       else throw "Unsupported Linux arch")
    else if isDarwin then "osx"
    else throw "Unsupported platform";

  buildInputs' = [
    glm cairo freetype fontconfig pixman libpng
    openal libsndfile rtaudio
    curl openssl brotli
    pugixml uriparser nlohmann_json libxml2 zlib fmt
    libusb1
    poco opencv assimp harfbuzz
  ] ++ lib.optionals isLinux [
    libGL libGLU glew freeglut glfw
    libX11 libXrandr libXxf86vm libXi libXcursor libXinerama libXmu
    wayland wayland-protocols libxkbcommon libdecor
    alsa-lib libjack2 libpulseaudio mpg123
    gstreamer gst-plugins-base gst-plugins-good gst-plugins-bad
    gst_all_1.gst-libav
    udev libdrm gtk3
  ] ++ lib.optionals isDarwin (with darwin.apple_sdk.frameworks; [
    Cocoa CoreVideo CoreAudio CoreMedia CoreFoundation CoreServices
    AVFoundation AudioToolbox Security AppKit Accelerate Metal
    QuartzCore IOKit SystemConfiguration Foundation OpenGL
  ]);

in

# mkOFExample :: { name, category, examplePath } -> derivation
#
# - name:        The example directory name (e.g. "polygonExample")
# - category:    The category directory name (e.g. "graphics")
# - examplePath: Relative path from OF_ROOT (e.g. "examples/graphics/polygonExample")
{ name
, category
, examplePath
}:

stdenv.mkDerivation {
  pname = "of-example-${category}-${name}";
  version = openframeworks.version;

  # Use the full OF source tree — the Makefile system needs it
  src = lib.cleanSourceWith {
    src = ./..;
    filter = path: type:
      let baseName = baseNameOf path; in
      !(baseName == ".git" || baseName == "flake.nix" || baseName == "flake.lock"
        || baseName == "result" || baseName == ".vscode"
        || lib.hasSuffix ".xcodeproj" baseName
        || lib.hasSuffix ".xcworkspace" baseName);
  };

  nativeBuildInputs = [
    pkg-config
    gnumake
  ];

  buildInputs = buildInputs';

  GST_VERSION = "1.0";
  USE_FMOD = "0";
  NIX_CFLAGS_COMPILE = "-Wno-error=maybe-uninitialized -Wno-error=dangling-reference";
  hardeningDisable = [ "format" "fortify" ];

  configurePhase = ''
    runHook preConfigure

    export OF_ROOT="$PWD"

    # ── Populate libs/ with symlinks (same as openframeworks.nix) ──

    # Header-only from nixpkgs
    mkdir -p libs/glm/include
    ln -sf ${glm}/include/glm libs/glm/include/glm

    mkdir -p libs/json/include
    ln -sf ${nlohmann_json}/include/nlohmann libs/json/include/nlohmann

    mkdir -p libs/fmt/include
    ln -sf ${fmt}/include/fmt libs/fmt/include/fmt

    # Apothecary pre-built libraries
    for libname in tess2 svgtiny kiss utf8 FreeImage; do
      if [ -d "${apothecaryLibs}/$libname" ]; then
        rm -rf "libs/$libname"
        mkdir -p "libs/$libname"
        cp -rL "${apothecaryLibs}/$libname"/* "libs/$libname/" 2>/dev/null || true
        chmod -R u+w "libs/$libname" 2>/dev/null || true
      fi
    done

    # Remap apothecary lib paths to platform layout
    for libname in tess2 svgtiny kiss FreeImage; do
      apoth_lib="libs/$libname/lib/${apothecaryLibDir}"
      target_lib="libs/$libname/lib/${platformLibSubpath}"
      if [ -d "$apoth_lib" ] && [ ! -d "$target_lib" ]; then
        mkdir -p "$target_lib"
        cp -rL "$apoth_lib"/* "$target_lib/" 2>/dev/null || true
      fi
    done

    # ── Patch Makefile system for Nix (same as openframeworks.nix) ──

    ${lib.optionalString isLinux ''
      # FreeImage: The linux config excludes libs/FreeImage/% from the bundled
      # library search and adds -lfreeimage as a system library. Since we provide
      # FreeImage as a static .a from apothecary (not a system lib), we need to:
      # 1. Remove the exclusion so the bundled .a is found
      # 2. Remove -lfreeimage from PLATFORM_LIBRARIES
      # 3. Add the FreeImage include path
      substituteInPlace libs/openFrameworksCompiled/project/makefileCommon/config.linux.common.mk \
        --replace-quiet 'PLATFORM_CORE_EXCLUSIONS += $(OF_LIBS_PATH)/FreeImage/%' \
                         '# PLATFORM_CORE_EXCLUSIONS += $(OF_LIBS_PATH)/FreeImage/% # Nix: use bundled static lib' \
        --replace-quiet 'PLATFORM_LIBRARIES += freeimage' \
                         'PLATFORM_LIBRARIES += png # Nix: FreeImage is a static lib that needs libpng'

      echo 'PLATFORM_HEADER_SEARCH_PATHS += $(OF_LIBS_PATH)/FreeImage/include' \
        >> libs/openFrameworksCompiled/project/makefileCommon/config.linux.common.mk
    ''}

    substituteInPlace libs/openFrameworksCompiled/project/${platformLibSubpath}/config.${platformLibSubpath}.default.mk \
      --replace-quiet 'ifneq (, $(shell command -v mold))' 'ifeq (1,0)' \
      --replace-quiet 'ifneq (, $(shell command -v gold))' 'ifeq (1,0)' \
      || true

    substituteInPlace libs/openFrameworksCompiled/project/makefileCommon/config.linux.common.mk \
      --replace-quiet 'ifndef GST_VERSION' 'GST_VERSION ?= 1.0
ifdef __NEVER_DEFINED__' \
      || true

    substituteInPlace libs/openFrameworksCompiled/project/makefileCommon/config.linux.common.mk \
      --replace-quiet 'ifeq ($(USE_FMOD),0)' 'USE_FMOD=0
ifeq ($(USE_FMOD),0)' \
      || true

    # ── Place the pre-built core .a so the core build is a no-op ──
    mkdir -p libs/openFrameworksCompiled/lib/${platformLibSubpath}
    for f in ${openframeworks}/lib/*.a; do
      cp "$f" libs/openFrameworksCompiled/lib/${platformLibSubpath}/
    done

    # ── Set up the example project ──
    cd "${examplePath}"

    # Copy the template Makefile and config.make
    cp "$OF_ROOT/scripts/templates/${templatePath}/Makefile" .
    cp "$OF_ROOT/scripts/templates/${templatePath}/config.make" .

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    echo "==> Building example: ${category}/${name}"
    make -j''${NIX_BUILD_CORES:-1} ReleaseNoOF \
      PLATFORM_OS=${if isLinux then "Linux" else "Darwin"} \
      OF_ROOT="$OF_ROOT" \
      GST_VERSION=1.0 \
      USE_FMOD=0

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp "bin/${name}" $out/bin/ 2>/dev/null || \
      cp bin/*  $out/bin/ 2>/dev/null || \
      (echo "ERROR: No binary found in bin/"; ls -la bin/; exit 1)

    # Install data directory if it exists and has content
    if [ -d bin/data ] && [ "$(ls -A bin/data 2>/dev/null)" ]; then
      mkdir -p $out/share/${name}
      cp -rL bin/data $out/share/${name}/
    fi

    runHook postInstall
  '';

  dontStrip = true;
  dontPatchELF = true;

  meta = with lib; {
    description = "openFrameworks example: ${category}/${name}";
    homepage = "https://openframeworks.cc/";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
  };
}
