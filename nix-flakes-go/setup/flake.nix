{
  description = "main application";
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.11;
    flake-utils.url = github:numtide/flake-utils;
    nix-filter.url = github:numtide/nix-filter;
  };
  outputs = {self, nixpkgs, flake-utils, nix-filter}:
  let
    buildApp = { pkgs, plugins ? [] }: pkgs.buildGoModule {
      name = "mainapp";
      src = nix-filter.lib.filter {
        root = ./.;
        exclude = [ ./externals ./flake.nix ];
      };
      vendorSha256 = "sha256-pQpattmS9VmO3ZIQUFn66az8GSmB4IvYhTTCFn6SUmo=";
    };
  in flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in rec {
      packages = { app = buildApp { inherit pkgs; }; };
      defaultPackage = packages.app;
      lib = { inherit buildApp; };
    }
  );
}