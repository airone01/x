{
  description = "Cool flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      devShells.default = pkgs.mkShell {
        nativeBuildInputs = [ pkgs.bashInteractive ];
        buildInputs = with pkgs; [
          # Node tools
          nodejs_22
          bun
          openssl
          lld

          # Sharp
          stdenv.cc.cc.lib
        ];
        shellHook = with pkgs; ''
          # Sharp
          export PATH="$PWD/node_modules/.bin/:$PATH"
          export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${pkgs.stdenv.cc.cc.lib}/lib:"
        '';
      };
    });
}
