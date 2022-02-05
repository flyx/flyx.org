{
  description = "Heldendokument-Generator und Webinterface dazu";
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.11;
    utils.url = github:numtide/flake-utils;
    go-plugins.url = github:flyx/nix-flakes-go-plugins;
    go-plugins.inputs = {
      nixpkgs.follows = "nixpkgs";
      utils.follows = "utils";
    };
  };
  
  outputs = { self, nixpkgs, utils, go-plugins }:
    utils.lib.eachSystem utils.lib.allSystems (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      nix-go-plugins = go-plugins.packages.${system}.sources;
    in rec {
      packages = {
        site = pkgs.stdenvNoCC.mkDerivation {
          name = "flyx.org";
          nativeBuildInputs = [ pkgs.jekyll nix-go-plugins ];
          srcs = self;
          phases = [ "unpackPhase" "buildPhase" "installPhase" ];
          buildPhase = ''
            mkdir -p nix-flakes-go
            cp -r -t nix-flakes-go ${nix-go-plugins}/*
            jekyll build
          '';
          installPhase = ''
            cp -r _site $out
          '';
        };
      };
      defaultPackage = packages.site;
    });
}