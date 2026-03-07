{
  description = "much devshell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
      in {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            pkg-config
            zig_0_15
            zls_0_15
          ];

          buildInputs = with pkgs; [
            # SDL2
          ];

          # shellHook = ''
          #   export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [pkgs.SDL2]}:$LD_LIBRARY_PATH"
          # '';
        };
      }
    );
}
