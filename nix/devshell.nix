{ lib
, mkShell
, openframeworks
, gdb ? null
, ccache
, pkg-config
, gnumake
, stdenv
}:

mkShell {
  name = "openframeworks-dev";

  # Inherit all build dependencies from the openframeworks derivation
  inputsFrom = [ openframeworks ];

  packages = [
    gnumake
    pkg-config
    ccache
  ] ++ lib.optionals (gdb != null) [ gdb ];

  shellHook = ''
    # Set OF_ROOT to the current directory (for in-tree development)
    export OF_ROOT="''${OF_ROOT:-$(pwd)}"
    export GST_VERSION=1.0
    export USE_FMOD=0

    echo ""
    echo "  ┌──────────────────────────────────────────┐"
    echo "  │   openFrameworks Development Environment  │"
    echo "  │   Version: ${openframeworks.version}                       │"
    echo "  │   OF_ROOT: $OF_ROOT                       "
    echo "  └──────────────────────────────────────────┘"
    echo ""
    echo "  Build OF:    cd libs/openFrameworksCompiled/project && make Release"
    echo "  Build app:   cd examples/graphics/polygonExample && make"
    echo ""
  '';
}
