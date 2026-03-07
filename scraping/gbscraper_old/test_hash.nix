{pkgs ? import <nixpkgs> {}}:
pkgs.fetchurl {
  name = "test-mod.zip";

  # PASTE THE URL HERE
  url = "https://gamebanana.com/dl/433956";

  # PASTE THE SRI HASH HERE (It must look like "sha256-XXXX...")
  hash = "sha256-BJEfGWpWmmG1j50Yjzec5UZzQ1+DvlBT3NEVggTErRY=";
}
