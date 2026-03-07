{
  lib,
  pkgs,
  mcVersions,
  mcMods,
  fabricVersions,
  utils,
}: {
  name,
  mcVersion,
  fabric ? null,
  forge ? null,
  modConfigs ? {},
}: let
  fabricInfo =
    if (fabric != null && fabric.enable && fabricVersions ? ${mcVersion} && fabricVersions.${mcVersion} ? ${fabric.loaderVersion})
    then fabricVersions.${mcVersion}.${fabric.loaderVersion}
    else null;

  # Define mod lists within the function scope
  fabricMods =
    if (fabric != null && fabric.enable)
    then fabric.mods
    else [];
  forgeMods =
    if (forge != null && forge.enable)
    then forge.mods
    else [];
  allMods = fabricMods ++ forgeMods;

  # Download mods
  modSrcs =
    map (
      mod: let
        modVersion = utils.getModForMcVersion mod mcVersion;
      in
        pkgs.fetchurl {
          name = "${mod.name}-${modVersion.version}.jar";
          inherit (modVersion) url sha256;
        }
    )
    allMods;

  # Fetch Minecraft server jar
  serverJar = pkgs.fetchurl {
    inherit (mcVersions.${mcVersion}) url;
    inherit (mcVersions.${mcVersion}) sha256;
  };

  # Fetch Fabric components if enabled and available
  fabricServerJar =
    if (fabricInfo != null)
    then pkgs.fetchurl fabricInfo.installerJar
    else null;
in
  pkgs.stdenv.mkDerivation {
    inherit name;

    buildInputs = [pkgs.jre];

    # We don't need a source, as we're creating everything from scratch
    dontUnpack = true;

    buildPhase = ''
      mkdir -p $out/server
      cp ${serverJar} $out/server/minecraft_server.jar

      mkdir -p $out/mods
      for mod in ${toString modSrcs}; do
        cp $mod $out/mods/
      done

      # Apply mod configurations
      mkdir -p $out/config
      ${lib.concatStringsSep "\n" (lib.mapAttrsToList (modName: modConfig: ''
          cat > $out/config/${modName}.cfg <<EOF
          ${builtins.toJSON modConfig}
          EOF
        '')
        modConfigs)}

      # Set up Fabric if enabled and available
      ${lib.optionalString (fabricInfo != null) ''
        cp ${fabricServerJar} $out/server/fabric-server-launch.jar
      ''}

      # Install Forge if enabled
      ${lib.optionalString (forge != null && forge.enable) ''
        ${pkgs.curl}/bin/curl -L -o $out/server/forge-installer.jar ${forge.installerUrl}
        ${pkgs.jre}/bin/java -jar $out/server/forge-installer.jar --installServer $out/server
      ''}
    '';

    installPhase = ''
      mkdir -p $out/bin
      cat > $out/bin/start-minecraft <<EOF
      #!/bin/sh
      cd $out/server
      exec ${pkgs.jre}/bin/java -jar ${
        if fabricInfo != null
        then "fabric-server-launch.jar"
        else if forge != null && forge.enable
        then "forge-${mcVersion}-universal.jar"
        else "minecraft_server.jar"
      } nogui
      EOF
      chmod +x $out/bin/start-minecraft
    '';
  }
