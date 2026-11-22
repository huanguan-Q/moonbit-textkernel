# Non-JS Wasm ABI evaluation

## Current state

`wasm/textkernel.wasm` is a WASM-GC module built from `src/main` with
`use-js-builtin-string`. It exposes 13 business exports plus `_start` and uses
JS string builtins; a host must provide `wasm:js-string`. The current artefact
is 23,574 bytes after the CLI entry point was added (it was 9,550 bytes when
the shim only re-exported library functions).

A separate linear-memory build is possible:

```bash
moon build --target wasm --release
```

It produces `_build/wasm/release/build/src/main/main.wasm` (36,456 bytes) with
exports `memory` and `_start`, and imports `wasi_snapshot_preview1.fd_write`
plus the MoonBit `__moonbit_fs_unstable` argv helpers. It does **not** currently
export the 13 business functions: the `link.exports` declaration in
`src/main/moon.pkg` is scoped to `wasm-gc`.

## Constraint

The business API is `String -> String`. Under WASM-GC with JS builtins the host
can pass JS strings directly. In a linear-memory module a `String` is not a
Wasm value type; a caller needs an explicit layout such as
`(ptr: i32, len: i32) -> i32` plus an allocator, or a WASI command that reads
stdin and writes stdout. Simply adding the same names to `link.exports` for the
`wasm` target would export functions with an undocumented MoonBit-internal
layout, which is worse than no ABI.

## Options

| Option | Host support | Work required | Recommendation |
|---|---|---|---|
| Keep WASM-GC + JS builtins | Node/Chrome only | none | Keep as the primary library artefact |
| WASI command (`fd_read`/`fd_write`, JSON lines) | wasmtime, wasmedge, container runtimes | add a `wasm`-target executable package that calls the shared CLI logic; no new memory ABI needed | **Best next step** for non-JS hosts |
| Linear-memory function ABI (`ptr,len -> ptr,len`) | any Wasm runtime | define ownership, allocator, UTF-8 vs UTF-16, and free rules; new tests and docs | Higher risk; do after the WASI command proves demand |
| Host-side reimplementation of escaping | any | duplicates the verified kernel | Reject: defeats the point |

## Decision

Do not publish a half-defined linear-memory function ABI now. Add a WASI
command package that reuses `src/lib/cli.mbt` and emits the same JSON lines as
the native CLI. That removes the `wasm:js-string` lock for process-style
consumers without inventing a memory contract, and leaves a clean path to a
function ABI if in-process embedders ask for it.

Until then, non-JS hosts can call the native CLI (`moon run src/cli`) or use the
existing WASM-GC artefact from a JS host.
