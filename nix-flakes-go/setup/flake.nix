{
  description = "main application";
  inputs = {
    nixpkgs.url = github:NixOS/nixpkgs/nixos-21.11;
    flake-utils.url = github:numtide/flake-utils;
    nix-filter.url = github:numtide/nix-filter;
  };
  outputs = {self, nixpkgs, flake-utils, nix-filter}:
  let
    requirePlugin = plugin: ''
      require ${plugin.goPlugin.goModName}
      replace ${plugin.goPlugin.goModName} => ${plugin.outPath}/src
    '';
    buildApp = { pkgs, vendorSha256, plugins ? [] }: pkgs.buildGoModule {
      name = "mainapp";
      src = nix-filter.lib.filter {
        root = ./.;
        exclude = [ ./externals ./flake.nix ./flake.lock ];
      };
      inherit vendorSha256;
      PLUGINS_GO = import ./plugins.go.nix plugins;
      GO_MOD_APPEND = builtins.foldl' (a: b: a + "${requirePlugin b}\n") "" plugins;
      postConfigure = ''
        printenv PLUGINS_GO >plugins.go
        printenv GO_MOD_APPEND >>go.mod
      '';
    };
  in flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
    in rec {
      packages.app = buildApp {
        inherit pkgs;
        vendorSha256 = "sha256-pQpattmS9VmO3ZIQUFn66az8GSmB4IvYhTTCFn6SUmo=";
      };
      defaultPackage = packages.app;
      lib = {
        inherit buildApp;
        pluginMetadata = goModFile: {
          goModName = with builtins; head
            (match "module ([^[:space:]]+)" (readFile goModFile));
        };
      };
    }
  );
}