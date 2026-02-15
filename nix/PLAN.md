# Nix Flake Plan for openFrameworks 0.12.1

## Executive Summary

This plan details the creation of a Nix flake to build openFrameworks as a reusable library package and development shell for the four standard Nix-supported desktop platforms: `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, and `aarch64-darwin`. The flake wraps the existing Makefile-based build system, sources most dependencies from nixpkgs, packages FreeImage from source, and fetches tess2/svgtiny binaries from OF's apothecary releases.

---

## 1. Files to Create

| File | Purpose |
|------|---------|
| `flake.nix` | Main flake definition with inputs, outputs, packages, and devShells |
| `flake.lock` | Auto-generated lockfile (created by first `nix flake lock`) |
| `nix/freeimage.nix` | Derivation to build FreeImage from source |
| `nix/tess2.nix` | Fixed-output derivation to fetch tess2 from apothecary |
| `nix/svgtiny.nix` | Fixed-output derivation to fetch svgtiny from apothecary |
| `nix/openframeworks.nix` | Main derivation for the openFrameworks core library |
| `nix/devshell.nix` | Development shell definition |

---

## 2. Flake Structure (`flake.nix`)

### 2.1 Inputs
```
inputs:
  nixpkgs  →  github:NixOS/nixpkgs/nixos-unstable
  flake-utils  →  github:numtide/flake-utils
```

### 2.2 Outputs (per system via `flake-utils.lib.eachDefaultSystem`)

For each of `x86_64-linux`, `aarch64-linux`, `x86_64-darwin`, `aarch64-darwin`:

| Output | Description |
|--------|-------------|
| `packages.default` | `openframeworks` — the compiled core library + headers + addons |
| `packages.freeimage` | FreeImage built from source |
| `devShells.default` | Full development environment with all OF dependencies |

---

## 3. Dependency Mapping

### 3.1 Dependencies Available in nixpkgs (Linux — via `buildInputs` / `nativeBuildInputs`)

| OF Dependency | nixpkgs Package | Type |
|---------------|----------------|------|
| **Build tools** | `pkg-config`, `gnumake` | `nativeBuildInputs` |
| **OpenGL** | `libGL`, `libGLU`, `glew`, `freeglut`, `mesa` | `buildInputs` |
| **Windowing** | `glfw`, `xorg.libX11`, `xorg.libXrandr`, `xorg.libXxf86vm`, `xorg.libXi`, `xorg.libXcursor`, `xorg.libXinerama`, `xorg.libXmu` | `buildInputs` |
| **Wayland** | `wayland`, `wayland-protocols`, `libxkbcommon`, `libdecor` | `buildInputs` |
| **Graphics/Fonts** | `cairo`, `freetype`, `fontconfig`, `pixman` | `buildInputs` |
| **Audio** | `openal`, `libsndfile`, `rtaudio`, `libpulseaudio`, `alsa-lib`, `libjack2` | `buildInputs` |
| **Video** | `gstreamer`, `gst-plugins-base`, `gst-plugins-good`, `gst-plugins-bad`, `gst-libav` | `buildInputs` |
| **Networking** | `curl`, `openssl`, `brotli` | `buildInputs` |
| **Data/Parsing** | `pugixml`, `uriparser`, `nlohmann_json`, `libxml2`, `zlib`, `fmt` | `buildInputs` |
| **Image** | **FreeImage** (custom, see §4) | `buildInputs` |
| **Tessellation** | **tess2** (apothecary, see §5) | `buildInputs` |
| **SVG** | **svgtiny** (apothecary, see §5) | `buildInputs` |
| **System** | `udev`, `libusb1`, `libdrm` | `buildInputs` |
| **Misc** | `poco`, `opencv`, `assimp`, `mpg123`, `harfbuzz` | `buildInputs` |
| **Header-only** | `glm` (available as `glm` in nixpkgs) | `buildInputs` |
| **GTK** | `gtk3` | `buildInputs` |

### 3.2 macOS (Darwin) — Framework Differences

On Darwin, replace X11/Wayland/GStreamer with Apple frameworks:

| Component | Darwin Approach |
|-----------|----------------|
| **Windowing** | `glfw` from nixpkgs (uses Cocoa internally) |
| **OpenGL** | `darwin.apple_sdk.frameworks.OpenGL` |
| **System Frameworks** | `Cocoa`, `CoreVideo`, `CoreAudio`, `CoreMedia`, `CoreFoundation`, `IOKit`, `AVFoundation`, `AudioToolbox`, `Security`, `AppKit`, `Accelerate`, `Metal`, `QuartzCore`, `SystemConfiguration`, `CoreServices`, `Foundation` |
| **Video** | No GStreamer on macOS; video uses AVFoundation |
| **Audio** | `CoreAudio` framework + `rtaudio` from nixpkgs |

### 3.3 Missing from nixpkgs — Requires Custom Packaging

| Library | Solution | Rationale |
|---------|----------|-----------|
| **FreeImage** | Build from source (`nix/freeimage.nix`) | Well-known library, straightforward Makefile build |
| **tess2** | Fetch apothecary pre-built (`nix/tess2.nix`) | Small, obscure polygon tessellation library |
| **svgtiny** | Fetch apothecary pre-built (`nix/svgtiny.nix`) | Niche SVG parsing library, only used by ofxSvg addon |

---

## 4. Custom FreeImage Derivation (`nix/freeimage.nix`)

```
Source: https://freeimage.sourceforge.io/ (or mirror)
Build: stdenv.mkDerivation using FreeImage's own Makefile
Output: libfreeimage.a / libfreeimage.so + headers (FreeImage.h, FreeImagePlus.h)
```

**Key details:**
- FreeImage uses a simple `make` / `make install` workflow
- Set `DESTDIR` and `INCDIR`/`INSTALLDIR` to control output paths
- Patches may be needed for modern GCC compatibility
- Install headers to `$out/include` and libs to `$out/lib`

---

## 5. Apothecary Fetchers (`nix/tess2.nix`, `nix/svgtiny.nix`)

Each will be a `fetchurl` + simple unpack derivation:

```
Source: https://github.com/openframeworks/apothecary/releases/
Format: Fixed-output derivation with sha256 hash
Structure: Extract to $out/include and $out/lib matching OF's expected layout
```

---

## 6. Main openFrameworks Derivation (`nix/openframeworks.nix`)

### 6.1 Build Strategy

Wrap the existing Makefile system. The core build is:
```
cd libs/openFrameworksCompiled/project && make Release
```

### 6.2 Key Build Phase Overrides

**`configurePhase`:**
1. Populate `libs/` with symlinks to Nix-provided packages
2. Ensure `pkg-config` can find all system libraries
3. Set `OF_ROOT` to the source directory

**`buildPhase`:**
```bash
cd libs/openFrameworksCompiled/project
make -j$NIX_BUILD_CORES Release
```

**`installPhase`:**
- Install static library, headers, addon sources, makefile templates

### 6.3 Platform-Specific Handling

| Platform | `PLATFORM_LIB_SUBPATH` |
|----------|----------------------|
| `x86_64-linux` | `linux64` |
| `aarch64-linux` | `linuxaarch64` |
| `x86_64-darwin` | `osx` |
| `aarch64-darwin` | `osx` |

### 6.4 Patching Requirements

1. Disable hardcoded `mold`/`gold` linker preferences
2. Force `GST_VERSION=1.0`
3. Ensure header layout compatibility via symlink forest

---

## 7. Development Shell (`nix/devshell.nix`)

Provides an environment where users can build OF and their own projects.

---

## 8. Implementation Order

| Step | Task | Complexity |
|------|------|-----------|
| **1** | Create `flake.nix` skeleton | Low |
| **2** | Write `nix/freeimage.nix` | Medium |
| **3** | Write `nix/tess2.nix` | Low |
| **4** | Write `nix/svgtiny.nix` | Low |
| **5** | Write `nix/openframeworks.nix` for Linux x86_64 | High |
| **6** | Test and iterate the Linux x86_64 build | High |
| **7** | Add aarch64-linux support | Low |
| **8** | Add Darwin support | High |
| **9** | Write `nix/devshell.nix` | Low |
| **10** | Wire everything into `flake.nix` outputs | Medium |
| **11** | Test builds on all platforms | High |

---

## 9. Validation Criteria

1. `nix build .#openframeworks` succeeds on x86_64-linux and produces `libopenFrameworks.a`
2. `nix build .#openframeworks` succeeds on aarch64-linux
3. `nix build .#openframeworks` succeeds on x86_64-darwin and aarch64-darwin
4. `nix develop` drops into a shell where `make` can build an OF example project
5. Headers and library are correctly installed for downstream consumption
6. `nix flake check` passes
