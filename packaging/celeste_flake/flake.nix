{
  description = "Declarative Celeste Everest Mods";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "aarch64-linux"];

      flake = {
        homeManagerModules.celeste-mods = {
          config,
          lib,
          pkgs,
          ...
        }: let
          cfg = config.game.celeste;

          resolveMod = name: version: let
            firstLetter = lib.toLower (builtins.substring 0 1 name);
            modFile = self + "/mods/${firstLetter}/${name}.nix";

            modData = import modFile {inherit (pkgs) fetchurl;};
            target = modData.${version} or (throw "Version ${version} of ${name} not found in generated Nix files!");

            resolvedDeps = lib.concatMap (dep: resolveMod dep.name dep.version) target.dependencies;
          in
            [
              {
                inherit name;
                inherit (target) src;
              }
            ]
            ++ resolvedDeps;

          enabledMods = lib.optionals cfg.strawberryjam2021.enable (resolveMod "StrawberryJam2021" "1.0.8");

          uniqueMods = lib.genericClosure {
            startSet =
              builtins.map (m: {
                key = m.name;
                inherit (m) src;
              })
              enabledMods;
            operator = [];
          };

          modsDirectory = pkgs.linkFarm "celeste-mods-dir" (
            builtins.map (m: {
              name = "${m.key}.zip";
              path = m.src;
            })
            uniqueMods
          );
        in {
          options.game.celeste = {
            strawberryjam2021.enable = lib.mkEnableOption "Strawberry Jam 2021 Modpack";
          };

          config = lib.mkIf (enabledMods != []) {
            home.file.".local/share/Celeste/Mods".source = modsDirectory;
          };
        };
      };
    };
}
