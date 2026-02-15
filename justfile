# openFrameworks Justfile
# Usage: just <recipe>

# Default recipe: list available commands
default:
    @just --list

# Build the core openFrameworks library
build-core:
    nix build .#openframeworks -L

# Build a single example by name (e.g., just build-example graphics polygonExample)
build-example category name:
    nix build ".#example-{{category}}-{{name}}" -L

# Build all examples (parallel, with up to 4 concurrent builds)
build-all-examples:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Discovering examples..."
    examples=$(nix flake show --json 2>/dev/null \
      | nix run nixpkgs#jq -- -r \
          '.packages."x86_64-linux" // .packages."aarch64-linux" // .packages."x86_64-darwin" // .packages."aarch64-darwin" | keys[] | select(startswith("example-"))' \
      2>/dev/null)
    total=$(echo "$examples" | wc -l)
    echo "Found $total examples. Building all (4 jobs in parallel)..."
    echo ""
    failed=0
    succeeded=0
    failures=""
    echo "$examples" | xargs -P10 -I{} sh -c '
      if nix build ".#{}" -L 2>&1 | tail -1; then
        echo "  ✓ {}"
      else
        echo "  ✗ {} FAILED"
        exit 1
      fi
    ' || true
    # Run sequentially for accurate counts
    for ex in $examples; do
      if nix path-info ".#$ex" >/dev/null 2>&1; then
        succeeded=$((succeeded + 1))
      else
        failed=$((failed + 1))
        failures="$failures\n  - $ex"
      fi
    done
    echo ""
    echo "Results: $succeeded/$total succeeded, $failed failed"
    if [ $failed -gt 0 ]; then
      echo -e "Failed examples:$failures"
      exit 1
    fi

# Build a batch of examples from one category (e.g., just build-category graphics)
build-category category:
    #!/usr/bin/env bash
    set -euo pipefail
    examples=$(nix flake show --json 2>/dev/null \
      | nix run nixpkgs#jq -- -r \
          '.packages."x86_64-linux" // .packages."aarch64-linux" // .packages."x86_64-darwin" // .packages."aarch64-darwin" | keys[] | select(startswith("example-{{category}}-"))' \
      2>/dev/null)
    total=$(echo "$examples" | wc -l)
    echo "Building $total examples in category '{{category}}'..."
    failed=0
    for ex in $examples; do
      if nix build ".#$ex" -L 2>/dev/null; then
        echo "  ✓ $ex"
      else
        echo "  ✗ $ex FAILED"
        failed=$((failed + 1))
      fi
    done
    echo ""
    if [ $failed -gt 0 ]; then
      echo "$failed/$total builds failed"
      exit 1
    else
      echo "All $total builds succeeded"
    fi

# List all available example packages
list-examples:
    @nix flake show --json 2>/dev/null \
      | nix run nixpkgs#jq -- -r \
          '.packages."x86_64-linux" // .packages."aarch64-linux" // .packages."x86_64-darwin" // .packages."aarch64-darwin" | keys[] | select(startswith("example-"))' \
      2>/dev/null

# List example categories
list-categories:
    @nix flake show --json 2>/dev/null \
      | nix run nixpkgs#jq -- -r \
          '.packages."x86_64-linux" // .packages."aarch64-linux" // .packages."x86_64-darwin" // .packages."aarch64-darwin" | keys[] | select(startswith("example-")) | split("-")[1]' \
      2>/dev/null | sort -u

# Count total examples
count-examples:
    @nix flake show --json 2>/dev/null \
      | nix run nixpkgs#jq -- -r \
          '[.packages."x86_64-linux" // .packages."aarch64-linux" // .packages."x86_64-darwin" // .packages."aarch64-darwin" | keys[] | select(startswith("example-"))] | length' \
      2>/dev/null

# Enter the development shell
dev:
    nix develop

# Clean build artifacts
clean:
    rm -rf result result-*
