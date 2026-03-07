{
  description = "Minecraft mod management and instance creation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    flake-utils,
  }:
    flake-utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {inherit system;};
        inherit (pkgs) lib;

        utils = import ./lib/minecraft-utils.nix {inherit lib;};

        # Define Minecraft versions
        mcVersions = utils.readVersions ./versions;

        # Define Minecraft mods
        mcMods = utils.readMods ./mods;

        # Import Fabric versions
        fabricVersions = import ./fabric/versions.nix;

        # Import mkMinecraftInstance function
        mkMinecraftInstance = import ./lib/minecraft-instance.nix {
          inherit lib pkgs mcVersions mcMods fabricVersions utils;
        };
      in {
        lib = {
          inherit mcVersions mcMods mkMinecraftInstance;
        };

        # Example of how to use the flake
        packages.exampleInstance = mkMinecraftInstance {
          name = "example-1.21";
          mcVersion = "1.21";
          fabric = {
            enable = true;
            loaderVersion = "0.16";
            mods = with mcMods; [sodium];
          };
          modConfigs = {
            sodium = {
              setting1 = "value1";
              setting2 = "value2";
            };
          };
        };
      }
    );
}
