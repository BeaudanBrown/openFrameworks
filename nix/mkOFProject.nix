# mkOFProject.nix — Builder for external openFrameworks projects
#
# This is designed to be used from OTHER flakes that import openFrameworks
# as an input. Unlike mkOFExample (which builds from the OF source tree),
# this works entirely from the installed openframeworks package.
#
# It reconstructs the OF_ROOT directory layout that the Makefile system expects
# by symlinking from the installed package's share/ directory, then builds
# the user's project source.
#
# Usage from a consumer flake:
#
#   {
#     inputs.openframeworks.url = "github:you/openFrameworks";
#
#     outputs = { self, nixpkgs, openframeworks }:
#       let
#         pkgs = import nixpkgs { system = "x86_64-linux"; };
#         of = openframeworks.packages.x86_64-linux.openframeworks;
#         mkOFProject = openframeworks.lib.x86_64-linux.mkOFProject;
#       in {
#         packages.x86_64-linux.default = mkOFProject {
#           name = "myApp";
#           src = ./.;
#           # addons = [ "ofxGui" "ofxOsc" ];  # optional
#         };
#       };
#   }

{ lib
, stdenv
, pkg-config
, gnumake

# The pre-built openframeworks package
, openframeworks

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

  templatePath =
    if isLinux then
      (if stdenv.hostPlatform.isx86_64 then "linux64"
       else if stdenv.hostPlatform.isAarch64 then "linuxaarch64"
       else throw "Unsupported Linux arch")
    else if isDarwin then "osx"
    else throw "Unsupported platform";

  ofShare = "${openframeworks}/share/openFrameworks";

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

# mkOFProject :: { name, src, version?, addons? } -> derivation
#
# - name:     Project name (becomes the binary name)
# - src:      Source tree (must contain src/ with main.cpp)
# - version:  Optional version string (default "0.0.0")
# - addons:   Optional list of addon names, e.g. [ "ofxGui" "ofxOsc" ]
{ name
, src
, version ? "0.0.0"
, addons ? []
}:

stdenv.mkDerivation {
  pname = name;
  inherit version src;

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

    # ── Reconstruct OF_ROOT layout from installed package ──
    #
    # The OF Makefile system expects:
    #   OF_ROOT/
    #     libs/openFrameworks/          — core headers
    #     libs/openFrameworksCompiled/  — compiled .a + makefile infra
    #     libs/{glm,json,fmt,...}/      — third-party headers
    #     libs/{tess2,kiss,...}/        — bundled static libs
    #     addons/                       — addon source trees
    #     scripts/templates/            — project templates
    #
    # We reconstruct this with symlinks from the installed package.

    export OF_ROOT="$TMPDIR/of-root"
    mkdir -p "$OF_ROOT/libs"

    # -- Core headers: libs/openFrameworks/ --
    # We must use cp -rL (not symlinks) because the OF Makefile system uses
    # `find ... -type d` which doesn't follow symlinks. It needs real directories
    # to discover the subdirs (utils/, app/, gl/, etc.) for include paths.
    cp -rL ${openframeworks}/include/openFrameworks "$OF_ROOT/libs/openFrameworks"

    # -- Compiled library + makefile infrastructure --
    mkdir -p "$OF_ROOT/libs/openFrameworksCompiled/lib/${platformLibSubpath}"
    for f in ${openframeworks}/lib/*.a; do
      ln -sf "$f" "$OF_ROOT/libs/openFrameworksCompiled/lib/${platformLibSubpath}/$(basename "$f")"
    done
    # Makefile infrastructure
    mkdir -p "$OF_ROOT/libs/openFrameworksCompiled/project"
    ln -sf ${ofShare}/libs/openFrameworksCompiled/project/makefileCommon \
      "$OF_ROOT/libs/openFrameworksCompiled/project/makefileCommon"
    ln -sf ${ofShare}/libs/openFrameworksCompiled/project/${platformLibSubpath} \
      "$OF_ROOT/libs/openFrameworksCompiled/project/${platformLibSubpath}"
    cp ${ofShare}/libs/openFrameworksCompiled/project/Makefile \
      "$OF_ROOT/libs/openFrameworksCompiled/project/Makefile"

    # -- Third-party header-only libs --
    mkdir -p "$OF_ROOT/libs/glm/include"
    ln -sf ${glm}/include/glm "$OF_ROOT/libs/glm/include/glm"

    mkdir -p "$OF_ROOT/libs/json/include"
    ln -sf ${nlohmann_json}/include/nlohmann "$OF_ROOT/libs/json/include/nlohmann"

    mkdir -p "$OF_ROOT/libs/fmt/include"
    ln -sf ${fmt}/include/fmt "$OF_ROOT/libs/fmt/include/fmt"

    # -- Third-party headers from of-thirdparty (tess2, kiss, utf8, svgtiny, FreeImage) --
    # These are flattened in the installed package under include/of-thirdparty/
    # but the Makefile expects libs/{name}/include/
    for libname in tess2 kiss utf8 svgtiny FreeImage; do
      mkdir -p "$OF_ROOT/libs/$libname/include"
    done
    # Link the of-thirdparty include tree — it contains the merged headers
    # We need to create the structure the Makefile expects
    if [ -d "${openframeworks}/include/of-thirdparty" ]; then
      # tess2 headers
      for f in ${openframeworks}/include/of-thirdparty/tesselator.h; do
        [ -f "$f" ] && ln -sf "$f" "$OF_ROOT/libs/tess2/include/"
      done
      # kiss headers
      for f in ${openframeworks}/include/of-thirdparty/kiss_fft*.h; do
        [ -f "$f" ] && ln -sf "$f" "$OF_ROOT/libs/kiss/include/"
      done
      # utf8 headers
      if [ -d "${openframeworks}/include/of-thirdparty/utf8" ]; then
        ln -sf ${openframeworks}/include/of-thirdparty/utf8 "$OF_ROOT/libs/utf8/include/utf8"
      fi
      for f in ${openframeworks}/include/of-thirdparty/utf8.h; do
        [ -f "$f" ] && ln -sf "$f" "$OF_ROOT/libs/utf8/include/"
      done
      # svgtiny headers
      for f in ${openframeworks}/include/of-thirdparty/svgtiny*.h; do
        [ -f "$f" ] && ln -sf "$f" "$OF_ROOT/libs/svgtiny/include/"
      done
      # FreeImage headers
      for f in ${openframeworks}/include/of-thirdparty/FreeImage.h; do
        [ -f "$f" ] && ln -sf "$f" "$OF_ROOT/libs/FreeImage/include/"
      done
    fi

    # -- Bundled static libs (already in the installed package lib/) --
    # The Makefile finds them at libs/{name}/lib/{platform}/*.a
    for libname in tess2 svgtiny kiss FreeImage; do
      mkdir -p "$OF_ROOT/libs/$libname/lib/${platformLibSubpath}"
      for f in ${openframeworks}/lib/*$libname* ${openframeworks}/lib/$libname* ${openframeworks}/lib/lib$libname*; do
        [ -f "$f" ] && ln -sf "$f" "$OF_ROOT/libs/$libname/lib/${platformLibSubpath}/$(basename "$f")"
      done
    done
    # FreeImage has an unconventional name (FreeImage.a not libFreeImage.a)
    if [ -f "${openframeworks}/lib/FreeImage.a" ]; then
      ln -sf "${openframeworks}/lib/FreeImage.a" "$OF_ROOT/libs/FreeImage/lib/${platformLibSubpath}/FreeImage.a"
    fi

    # -- Addons --
    ln -sf ${ofShare}/addons "$OF_ROOT/addons"

    # -- Templates --
    mkdir -p "$OF_ROOT/scripts"
    ln -sf ${ofShare}/scripts/templates "$OF_ROOT/scripts/templates"

    # ── Patch Makefile system for Nix ──
    # The makefiles are in the nix store (read-only via symlinks).
    # We need writable copies to patch them.
    rm "$OF_ROOT/libs/openFrameworksCompiled/project/makefileCommon"
    mkdir -p "$OF_ROOT/libs/openFrameworksCompiled/project/makefileCommon"
    cp ${ofShare}/libs/openFrameworksCompiled/project/makefileCommon/*.mk \
      "$OF_ROOT/libs/openFrameworksCompiled/project/makefileCommon/"
    chmod -R u+w "$OF_ROOT/libs/openFrameworksCompiled/project/makefileCommon/"

    rm "$OF_ROOT/libs/openFrameworksCompiled/project/${platformLibSubpath}"
    mkdir -p "$OF_ROOT/libs/openFrameworksCompiled/project/${platformLibSubpath}"
    cp ${ofShare}/libs/openFrameworksCompiled/project/${platformLibSubpath}/*.mk \
      "$OF_ROOT/libs/openFrameworksCompiled/project/${platformLibSubpath}/"
    chmod -R u+w "$OF_ROOT/libs/openFrameworksCompiled/project/${platformLibSubpath}/"

    ${lib.optionalString isLinux ''
      substituteInPlace "$OF_ROOT/libs/openFrameworksCompiled/project/makefileCommon/config.linux.common.mk" \
        --replace-quiet 'PLATFORM_CORE_EXCLUSIONS += $(OF_LIBS_PATH)/FreeImage/%' \
                         '# PLATFORM_CORE_EXCLUSIONS += $(OF_LIBS_PATH)/FreeImage/%' \
        --replace-quiet 'PLATFORM_LIBRARIES += freeimage' \
                         'PLATFORM_LIBRARIES += png'

      echo 'PLATFORM_HEADER_SEARCH_PATHS += $(OF_LIBS_PATH)/FreeImage/include' \
        >> "$OF_ROOT/libs/openFrameworksCompiled/project/makefileCommon/config.linux.common.mk"
    ''}

    substituteInPlace "$OF_ROOT/libs/openFrameworksCompiled/project/${platformLibSubpath}/config.${platformLibSubpath}.default.mk" \
      --replace-quiet 'ifneq (, $(shell command -v mold))' 'ifeq (1,0)' \
      --replace-quiet 'ifneq (, $(shell command -v gold))' 'ifeq (1,0)' \
      || true

    substituteInPlace "$OF_ROOT/libs/openFrameworksCompiled/project/makefileCommon/config.linux.common.mk" \
      --replace-quiet 'ifndef GST_VERSION' 'GST_VERSION ?= 1.0
ifdef __NEVER_DEFINED__' \
      || true

    substituteInPlace "$OF_ROOT/libs/openFrameworksCompiled/project/makefileCommon/config.linux.common.mk" \
      --replace-quiet 'ifeq ($(USE_FMOD),0)' 'USE_FMOD=0
ifeq ($(USE_FMOD),0)' \
      || true

    # ── Set up the project directory ──
    PROJECT_DIR="$PWD"
    cp "$OF_ROOT/scripts/templates/${templatePath}/Makefile" "$PROJECT_DIR/"
    cp "$OF_ROOT/scripts/templates/${templatePath}/config.make" "$PROJECT_DIR/"

    # Create addons.make if addons were specified
    ${lib.optionalString (addons != []) ''
      cat > "$PROJECT_DIR/addons.make" << 'ADDONS_EOF'
${lib.concatStringsSep "\n" addons}
ADDONS_EOF
    ''}

    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    echo "==> Building project: ${name}"
    make -j''${NIX_BUILD_CORES:-1} ReleaseNoOF \
      PLATFORM_OS=${if isLinux then "Linux" else "Darwin"} \
      OF_ROOT="$OF_ROOT" \
      APPNAME="${name}" \
      GST_VERSION=1.0 \
      USE_FMOD=0

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp "bin/${name}" $out/bin/ 2>/dev/null || \
      cp bin/* $out/bin/ 2>/dev/null || \
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
    description = "openFrameworks project: ${name}";
    homepage = "https://openframeworks.cc/";
    license = licenses.mit;
    platforms = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
  };
}
