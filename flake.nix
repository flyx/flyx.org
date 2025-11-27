{
  description = "flyx.org Website";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    utils.url = "github:numtide/flake-utils";
    go-plugins.url = "github:flyx/nix-flakes-go-plugins";
    go-plugins.inputs = {
      nixpkgs.follows = "nixpkgs";
      utils.follows = "utils";
    };
    zicross.url = "github:flyx/Zicross";
    zicross.inputs = {
      nixpkgs.follows = "nixpkgs";
      utils.follows = "utils";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      utils,
      go-plugins,
      zicross,
    }:
    utils.lib.eachSystem utils.lib.allSystems (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        nix-go-plugins = go-plugins.packages.${system}.sources;
        cross-compiling = zicross.packages.${system}.articleSources;
      in
      rec {
        packages = {
          site = pkgs.stdenvNoCC.mkDerivation {
            name = "flyx.org";
            nativeBuildInputs = [
              pkgs.jekyll
              nix-go-plugins
            ];
            srcs = self;
            phases = [
              "unpackPhase"
              "buildPhase"
              "installPhase"
            ];
            buildPhase = ''
              mkdir -p nix-flakes-go
              cp -r -t nix-flakes-go ${nix-go-plugins}/*
              mkdir -p cross-compiling
              cp -r -t cross-compiling ${cross-compiling}/*
              jekyll build
              rm -rf _site/cross-compiling
            '';
            installPhase = ''
              cp -r _site $out
            '';
          };
        };
        defaultPackage = packages.site;
      }
    );
}
