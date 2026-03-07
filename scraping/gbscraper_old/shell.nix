{pkgs ? import <nixpkgs> {}}:
pkgs.callPackage (
  {
    mkShell,
    # rustc,
    # cargo,
    # rustPlatform,
    # rustfmt,
    # clippy,
    # rust-analyzer,
    pkg-config,
    openssl,
    sqlite,
    unzip,
  }:
    mkShell {
      strictDeps = true;
      nativeBuildInputs = [
        # rustc
        # cargo
        # rustfmt
        # clippy
        # rust-analyzer
        pkg-config
        openssl
        sqlite
        unzip
      ];

      # Certain Rust tools won't work without this
      # rust-analyzer from nixpkgs does not need this.
      # This can also be fixed by using oxalica/rust-overlay and specifying the rust-src extension
      # See https://discourse.nixos.org/t/rust-src-not-found-and-other-misadventures-of-developing-rust-on-nixos/11570/3?u=samuela. for more details.
      # RUST_SRC_PATH = "${rustPlatform.rustLibSrc}";
      PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
    }
) {}
