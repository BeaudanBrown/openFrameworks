# examples.nix — Auto-discover and build all openFrameworks example projects
#
# This module scans the examples/ directory at Nix evaluation time,
# discovers all valid example projects (those with src/main.cpp),
# and generates a derivation for each one using mkOFExample.
#
# Excluded categories (mobile/embedded platforms):
#   android, ios, tvOS, gles
#
# Usage from flake.nix:
#   examples = import ./nix/examples.nix { inherit pkgs mkOFExample; ofRoot = ./.; };
#   # => { example-graphics-polygonExample = <drv>; example-gui-guiExample = <drv>; ... }

{ pkgs
, mkOFExample
, ofRoot
}:

let
  lib = pkgs.lib;

  # Categories to exclude (mobile/embedded platforms)
  excludedCategories = [ "android" "ios" "tvOS" "gles" ];

  # The examples directory
  examplesDir = ofRoot + "/examples";

  # Get all category directories
  categoryNames = builtins.filter
    (name:
      let path = examplesDir + "/${name}"; in
      builtins.pathExists path
      && (builtins.readFileType path) == "directory"
      && !(builtins.elem name excludedCategories)
    )
    (builtins.attrNames (builtins.readDir examplesDir));

  # For a given category, get all example project names
  # An example is valid if it has src/main.cpp
  getExamplesInCategory = category:
    let
      categoryDir = examplesDir + "/${category}";
      entries = builtins.readDir categoryDir;
      dirNames = builtins.filter
        (name: entries.${name} == "directory")
        (builtins.attrNames entries);
    in
    builtins.filter
      (name: builtins.pathExists (categoryDir + "/${name}/src/main.cpp"))
      dirNames;

  # Build a single example entry: { name, value } for listToAttrs
  mkExampleEntry = category: name: {
    name = "example-${category}-${name}";
    value = mkOFExample {
      inherit name category;
      examplePath = "examples/${category}/${name}";
    };
  };

  # Generate all example entries across all categories
  allEntries = builtins.concatMap
    (category:
      builtins.map (mkExampleEntry category) (getExamplesInCategory category)
    )
    categoryNames;

in builtins.listToAttrs allEntries
