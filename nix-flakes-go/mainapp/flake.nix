{
  description = "main application";
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.11;
    flake-utils.url = github:numtide/flake-utils;
    nix-filter.url = github:numtide/nix-filter;
  };
  outputs = {self, nixpkgs, flake-utils, nix-filter}:
  let
    buildApp = { pkgs, vendorSha256, plugins ? [] }:
      let
        requirePlugin = plugin: ''
          require ${plugin.goPlugin.goModName} v0.0.0
          replace ${plugin.goPlugin.goModName} => ${plugin.outPath}/src
        '';
        sources = pkgs.stdenvNoCC.mkDerivation {
          name = "mainapp-with-plugins-source";
          src = nix-filter.lib.filter {
            root = ./.;
            exclude = [ ./flake.nix ./flake.lock ];
          }; 
          phases = [ "unpackPhase" "buildPhase" "installPhase" ];
          PLUGINS_GO = import ./plugins.go.nix plugins;
          GO_MOD_APPEND = builtins.foldl' (a: b: a + "${requirePlugin b}\n") "" plugins;
          buildPhase = ''
            printenv PLUGINS_GO >plugins.go
            printenv GO_MOD_APPEND >>go.mod
          '';
          installPhase = ''
            mkdir -p $out/src
            cp -r -t $out/src *
          '';
        };
      in pkgs.buildGoModule {
        name = "mainapp";
        src = builtins.trace "sources at ${sources}" sources;
        modRoot = "src";
        inherit vendorSha256;
        nativeBuildInputs = plugins;
      };
  in (flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in rec {
      packages.app = buildApp {
        inherit pkgs;
        vendorSha256 = "sha256-pQpattmS9VmO3ZIQUFn66az8GSmB4IvYhTTCFn6SUmo=";
      };
      defaultPackage = packages.app;
    }
  )) // {
    lib = {
      inherit buildApp;
      pluginMetadata = goModFile: {
        goModName = with builtins; head
          (match "module ([^[:space:]]+).*" (readFile goModFile));
      };
    };
  };
}