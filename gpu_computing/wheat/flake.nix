{
  description = "much devshell";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig.url = "github:erikarvstedt/nix-zig-build";
  };

  outputs = {
    nixpkgs,
    flake-utils,
    zig,
    ...
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
      in {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs;
            [
              zls
              # gcc

              # SDL2
              # SDL2_image # for loading images
              # SDL2_ttf # for fonts
              vulkan-headers
              vulkan-loader

              # vulkan-tools # vulkaninfo, vkcube
              # vulkan-validation-layers
              shaderc # glslc for compiling shaders
              # pkg-config # helper to find libraries
              # cmake
            ]
            ++ [zig.packages.${system}.zig];

          shellHook = ''
            # point Vulkan to the validation layers
            export VK_LAYER_PATH="${pkgs.vulkan-validation-layers}/share/vulkan/explicit_layer.d"
            export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [pkgs.vulkan-loader]}:$LD_LIBRARY_PATH"
          '';
        };
      }
    );
}
