{
  description = "openFrameworks 0.12.1 — an open source C++ toolkit for creative coding";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachSystem [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
        };

        isLinux = pkgs.stdenv.hostPlatform.isLinux;
        isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

        # Pre-built third-party libraries from OF's apothecary project
        # These provide tess2, svgtiny, kiss, utf8, and FreeImage
        apothecaryLibs = pkgs.callPackage ./nix/apothecary-libs.nix {
          inherit system;
        };

        # The main openFrameworks library
        openframeworks = pkgs.callPackage ./nix/openframeworks.nix ({
          inherit apothecaryLibs;
        } // pkgs.lib.optionalAttrs isLinux {
          inherit (pkgs) libX11 libXrandr libXxf86vm libXi libXcursor libXinerama libXmu;
          inherit (pkgs) wayland wayland-protocols libxkbcommon libdecor;
          inherit (pkgs) alsa-lib libjack2 libpulseaudio mpg123;
          inherit (pkgs) udev libdrm gtk3;
          inherit (pkgs) gst_all_1;
          gstreamer = pkgs.gst_all_1.gstreamer;
          gst-plugins-base = pkgs.gst_all_1.gst-plugins-base;
          gst-plugins-good = pkgs.gst_all_1.gst-plugins-good;
          gst-plugins-bad = pkgs.gst_all_1.gst-plugins-bad;
        } // pkgs.lib.optionalAttrs isDarwin {
          inherit (pkgs) darwin;
        });

      in {
        packages = {
          default = openframeworks;
          inherit openframeworks;
          apothecary-libs = apothecaryLibs;
        };

        devShells.default = pkgs.callPackage ./nix/devshell.nix {
          inherit openframeworks;
        };
      }
    );
}
