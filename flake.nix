{
  description = "Heldendokument-Generator und Webinterface dazu";
  inputs = {
	nixpkgs.url = github:NixOS/nixpkgs/nixos-21.11;
	flake-utils.url = github:numtide/flake-utils;
  };
  
  outputs = { self, nixpkgs, flake-utils }: flake-utils.lib.eachSystem flake-utils.lib.allSystems (system:
	  let
		  pkgs = nixpkgs.legacyPackages.${system};
	  in rec {
      packages = {
        site = pkgs.stdenvNoCC.mkDerivation {
          name = "flyx.org";
          buildInputs = [ pkgs.jekyll ];
          src = self;
          phases = [ "unpackPhase" "buildPhase" "installPhase" ];
          buildPhase = ''
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