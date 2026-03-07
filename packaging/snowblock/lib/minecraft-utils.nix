{lib}: {
  # Function to read mods from subfolders
  readMods = dir: let
    contents = builtins.readDir dir;
    folders = lib.filterAttrs (n: v: v == "directory") contents;
  in
    lib.mapAttrs (name: _: import (dir + "/${name}")) folders;

  # Function to read versions from subfolders
  readVersions = dir: let
    contents = builtins.readDir dir;
    folders = lib.filterAttrs (n: v: v == "directory") contents;
  in
    lib.mapAttrs (name: _: import (dir + "/${name}")) folders;

  # Function to get the correct mod version for a given Minecraft version
  getModForMcVersion = mod: mcVersion: let
    compatibleVersions = builtins.filter (v: builtins.elem mcVersion v.mcVersions) mod.versions;
  in
    if builtins.length compatibleVersions == 0
    then throw "No compatible version found for mod ${mod.name} for Minecraft ${mcVersion}"
    else builtins.head compatibleVersions;
}
