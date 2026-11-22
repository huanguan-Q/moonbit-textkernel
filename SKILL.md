---
name: textkernel
description: Use the verified MoonBit textkernel CLI to escape HTML, sanitize filenames, normalize asset URLs, and choose Referrer-Policy for text crossing a trust boundary.
---

# textkernel

A small MoonBit kernel for text that crosses a trust boundary. Safety
properties of the core routines are discharged by `moon prove`; the shipped
`String` layer checks its own output invariants at runtime.

## When to use

Use this skill when a task needs any of:

- HTML text or attribute escaping before rendering untrusted content.
- Filename sanitization for uploads or generated artifacts.
- Asset URL normalization (force HTTPS, append missing query parameters).
- Host allow-list based Referrer-Policy selection.
- Deterministic JSON-lines output from a sandboxed Wasm command.

Do not use it for full HTML sanitization, URL parsing, authorization, or
resource limiting: see Boundaries below.

## Run the Wasm / moonx command

```bash
moonx huanguan-Q/textkernel/src/main@0.1.4 -- --help
moonx huanguan-Q/textkernel/src/main@0.1.4 -- escape-html '<script>x</script>'
moonx huanguan-Q/textkernel/src/main@0.1.4 -- normalize-asset-url \
  --hosts cdn.example.com --params fmt=png,v=1 \
  'http://cdn.example.com/a.png'
```

Use the explicit `src/main` package path: mooncakes.io builds the prebuilt Wasm
asset for that package, while the bare module coordinate has none.

Each command prints one JSON line with `command` and `output`, or `command`
and `error`. `--hosts` and `--params` take comma-separated values; omitting
both keeps the historical RFC 2606 example configuration.

## Native CLI with stdin

```bash
moon run src/cli --target native -- escape-html < untrusted.txt
moon run src/cli --target native -- sanitize-filename --input 'a/b:c?.png'
```

The native wrapper shares the Wasm command set and reads stdin when no input
argument is present. File input is shell redirection, not an in-process file
reader.

## Library use with explicit configuration

```moonbit
let config = @lib.create_asset_config(
  ["cdn.internal.example"],
  ["w=800", "auto=1"],
)
let url = @lib.normalize_asset_url_with_config(
  "http://cdn.internal.example/a.png",
  config,
)
```

The no-suffix functions (`normalize_asset_url`, `decide_referrer_policy`,
`ensure_asset_params`) remain wrappers around the default configuration, so
existing callers keep their historical behaviour. The `*_result` forms return
`Result[String, CoreError]` and never abort.

## Verification

```bash
moon fmt --check
moon check --target all --deny-warn
moon test --target all
node scripts/prove_gate.mjs
node scripts/build_wasm.mjs
```

Build helpers are `scripts/build_wasm.mjs`, `scripts/prove_gate.mjs`,
`scripts/why3_conf.mjs` and `scripts/why3_dual_solver.mjs`. The proof gate runs
with Alt-Ergo + Z3 and the 32-bit machine-integer prelude.

## Boundaries

- The proved kernels operate on `FixedArray[Int32]` UTF-16 code units;
  `src/proof/conform.mbt` pins them to the shipped `String` API over an
  enumerated corpus. This is corpus equivalence, not a theorem about `String`.
- Only `src/proof` is in the proof denominator. `src/lib` relies on runtime
  invariant checks.
- The input bound is arithmetic overflow protection and a shipping cap, not a
  resource quota; callers must apply their own rate limits.
- The Wasm ABI uses `wasm:js-string` builtins and has no linear-memory variant.
  Non-JS hosts cannot call it directly; see `docs/ABI-EVALUATION.md`.
- Escaping and filename sanitization do not replace a full HTML sanitizer or a
  URL parser.
