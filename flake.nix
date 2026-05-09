{
  description = "Hello actor for Theater";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    crane.url = "github:ipetkov/crane";

    theater = {
      url = "github:colinrozzi/theater/release-20260509";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.rust-overlay.follows = "rust-overlay";
      inputs.crane.follows = "crane";
    };
  };

  outputs = { self, nixpkgs, flake-utils, rust-overlay, crane, theater }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        overlays = [ (import rust-overlay) ];
        pkgs = import nixpkgs { inherit system overlays; };

        rustToolchain = pkgs.rust-bin.stable.latest.default.override {
          targets = [ "wasm32-unknown-unknown" ];
        };

        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        src = pkgs.lib.cleanSourceWith {
          src = ./.;
          filter = path: type:
            (pkgs.lib.hasSuffix ".rs" path) ||
            (pkgs.lib.hasSuffix ".toml" path) ||
            (pkgs.lib.hasSuffix ".lock" path) ||
            (pkgs.lib.hasSuffix ".pact" path) ||
            (type == "directory");
        };

        commonArgs = {
          inherit src;
          pname = "hello-actor";
          version = "0.1.0";
          cargoExtraArgs = "--target wasm32-unknown-unknown";
          CARGO_BUILD_TARGET = "wasm32-unknown-unknown";
          doCheck = false;
        };

        cargoArtifacts = craneLib.buildDepsOnly commonArgs;

        theaterBin = theater.packages.${system}.default;

      in {
        # nix build — produces the .wasm artifact
        packages.default = craneLib.buildPackage (commonArgs // {
          inherit cargoArtifacts;
          installPhaseCommand = ''
            mkdir -p $out
            cp target/wasm32-unknown-unknown/release/hello_actor.wasm $out/
          '';
        });

        # nix run — build nix wasm and start in theater
        packages.run = pkgs.writeShellScriptBin "run-actor" ''
          set -e
          WASM="${self.packages.${system}.default}/hello_actor.wasm"
          MANIFEST=$(mktemp)
          cat > "$MANIFEST" <<TOML
          name = "hello"
          version = "0.1.0"
          package = "$WASM"

          [[handler]]
          type = "runtime"
          TOML
          ${theaterBin}/bin/theater start "$MANIFEST" --save .chains
          rm -f "$MANIFEST"
        '';

        # nix run .#replay — replay from a chain file
        # ReplayHandler drives all calls from the recorded chain, so --no-init
        # prevents the runtime from auto-calling init on top of that.
        # Builds the WASM via nix and writes a temp manifest so paths resolve
        # correctly regardless of cwd (works in dev and in CI).
        packages.replay = pkgs.writeShellScriptBin "replay-actor" ''
          set -e
          WASM="${self.packages.${system}.default}/hello_actor.wasm"
          CHAIN="''${1:-chains/hello-init.chain}"
          if [ ! -f "$CHAIN" ]; then
            echo "Chain file not found: $CHAIN" >&2
            exit 1
          fi
          MANIFEST=$(mktemp)
          cat > "$MANIFEST" <<TOML
          name = "hello-replay"
          version = "0.1.0"
          package = "$WASM"

          [[handler]]
          type = "runtime"

          [[handler]]
          type = "store"

          [[handler]]
          type = "replay"
          chain = "$(realpath "$CHAIN")"
          TOML
          ${theaterBin}/bin/theater start "$MANIFEST" --no-init
          rm -f "$MANIFEST"
        '';

        # nix develop — dev shell
        devShells.default = craneLib.devShell {
          packages = [
            rustToolchain
            theaterBin
          ];

          shellHook = ''
            echo "hello-actor dev environment"
            echo "  nix build          Build the WASM (isolated)"
            echo "  nix run .#run      Build + start in theater"
            echo "  nix run .#replay   Replay from chains/hello-init.chain"
            echo "  cargo build ...    Build locally (fast)"
            echo "  theater start ...  Run with local theater"
          '';
        };

        # nix run .#update-deps — bump packr and theater versions
        packages.update-deps = pkgs.writeShellScriptBin "update-deps" ''
          set -e
          echo "Updating dependencies..."

          # Update packr in Cargo.toml
          PACKR_LATEST=$(cargo search packr-guest --limit 1 2>/dev/null | head -1 | ${pkgs.gnused}/bin/sed 's/.*= "\([^"]*\)".*/\1/')
          if [ -n "$PACKR_LATEST" ]; then
            ${pkgs.gnused}/bin/sed -i "s/packr-guest = { version = \"[^\"]*\"/packr-guest = { version = \"$PACKR_LATEST\"/" Cargo.toml
            echo "  packr-guest -> $PACKR_LATEST"
          fi

          # Update theater flake input if version provided
          if [ -n "''${1:-}" ]; then
            ${pkgs.gnused}/bin/sed -i "s|github:colinrozzi/theater/[^\";]*|github:colinrozzi/theater/$1|" flake.nix
            nix flake update theater
            echo "  theater -> $1"
          fi

          echo ""
          echo "Done. Review changes:"
          git diff --stat
        '';
      });
}
