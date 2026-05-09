# hello-actor

A minimal reference template for building [Theater](https://github.com/colinrozzi/theater) actors. Two exported functions, two host imports, a recorded chain, and a CI replay test. ~60 lines of Rust.

## What it does

```rust
init(state: value) -> result<actor-state, string>
greet(state: actor-state, name: string) -> result<tuple<actor-state, string>, string>
```

`init` logs `[hello] init` and shuts the actor down. `greet` returns `"<greeting>, <name>!"` and increments a counter on the actor state.

## Quickstart

```sh
nix run .#run        # build the WASM and start in theater
nix run .#replay     # replay the recorded chain at chains/hello-init.chain
nix develop          # dev shell with rust + theater
```

Or with a local theater build:

```sh
cargo build --release --target wasm32-unknown-unknown
theater start manifest.toml --save .chains
```

## Replay

The committed chain at `chains/hello-init.chain` records a known-good run of `init`. `manifests/replay-init.toml` points the replay handler at it; `theater start ... --no-init` lets the handler drive the call sequence.

The replay handler verifies every event hash against the recorded chain. Any drift — a behavior change in the actor, a regression in pack or theater — fails the run with a divergence error. CI runs this on every push.

## Layout

```
src/lib.rs              — actor source
manifest.toml           — run manifest
manifests/replay-init.toml — replay manifest
chains/hello-init.chain — recorded chain (committed, drives the replay test)
flake.nix               — nix targets: default (build wasm), run, replay, update-deps
.github/workflows/ci.yml — build + replay smoke test
```

## License

Apache-2.0
