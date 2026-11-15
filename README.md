# textkernel

**A small, formally verified MoonBit kernel for text that crosses a trust boundary.**

When a program takes a string from one system and puts it into another — into
HTML, into a filename, into a URL, into a batch API — four things can go wrong:
markup can be injected, a filename can escape its directory, a URL can be
rewritten incorrectly, and a batch loop can drop an item. `textkernel` is the
set of routines for those four jobs, with the safety properties discharged by
`moon prove` rather than by inspection.

```
huanguan-Q/textkernel    140 tests × 4 backends    419 proof goals    10 WASM exports    zero deps
```

## What is in the box

| Routine | What it guarantees |
|---|---|
| `escape_html` / `escape_attr` | Output contains no raw `<` `>` (nor `"` `'` for attributes); every `&` starts a complete entity the library emits |
| `sanitize_filename` | Replaces the nine unsafe characters and lone surrogates, clamps to 120 code units, never returns empty |
| `normalize_asset_url` | Forces `https` for configured hosts and appends missing default query params; the tail is carried over verbatim |
| `decide_referrer_policy` | Picks a Referrer-Policy from a configured host allow-list |
| `str_contains` | UTF-16 code-unit substring test (the host gate above) |
| `split_joined` / `join_joined` | Exact inverse pair for batch calls; slices by code unit so non-BMP characters survive |
| `batch_process_custom` | Applies an operation in bounded chunks; a non-positive chunk size is clamped to 1, never divided by |

`*_result` variants return `Result[T, CoreError]` with an explicit input bound.
The shipping layer also checks its own output against the invariants before
returning and aborts on violation — a regression fails loudly instead of
quietly emitting markup the caller believes is escaped.

## Reproduce

```bash
moon fmt --check
moon check --target all --deny-warn       # wasm / wasm-gc / js / native, zero warnings
moon test --target all                    # 137/137 on each backend
moon prove                               # 191 goals with the stock solver limits
node scripts/prove_gate.mjs              # 419 goals, 5x limits, machine-int model
moon run src/demo --target native        # runnable example
moon publish --dry-run                   # validate package metadata without releasing
node scripts/build_wasm.mjs              # build wasm/textkernel.wasm
node examples/wasm-node/demo.mjs         # call the WASM exports from JavaScript
```

Two proof counts appear above because they answer different questions: the
stock `moon prove` run discharges 191 goals, while `scripts/prove_gate.mjs`
retries at ~5x solver limits under the 32-bit machine-integer prelude and
discharges 419. The gate is what CI uses; a bare `moon prove` can report a
handful of timeouts on a loaded machine.

Toolchain used to produce the numbers above: `moon 0.1.20261104`, Why3 1.7.2,
z3. The proof verdicts depend on the VC generator, so pin the toolchain when
reproducing; `.github/workflows/ci.yml` asserts the version.

## Use

```moonbit
let safe = @lib.escape_html("<script>alert(1)</script>")
// &lt;script&gt;alert(1)&lt;/script&gt;

let name = @lib.sanitize_filename("report/2026:Q4?.md")
// report_2026_Q4_.md

let items = @lib.split_joined("a|b|c", "|")
let out = @lib.join_joined(@lib.quick_batch_escape_htmls(items), "|")
```

See `src/demo/main.mbt` for a complete runnable example.

## WASM / calling from JavaScript

`src/main` is a thin export shim. With `use-js-builtin-string` the linker
exposes `String -> String` functions directly to a JS host — no linear-memory
ABI, no manual allocation, no UTF-8 copy:

| Single value | Joined-list batch (`joined`, `sep`) |
|---|---|
| `escape_html`, `escape_attr`, `sanitize_filename` | `escape_htmls_joined`, `escape_attrs_joined`, `sanitize_filenames_joined` |
| `normalize_asset_url`, `decide_referrer_policy`, `str_contains` | `normalize_asset_urls_joined` |

```bash
node scripts/build_wasm.mjs        # 8.4 KB artefact, verifies all 10 exports
node examples/wasm-node/demo.mjs   # 11 assertions across all 10 exports
```

`examples/wasm-node/loader.mjs` reads the module's import table and supplies
the imported string constants as plain JS globals. That works on **Node 22+
and Chrome** alike: Chrome can synthesise them with the
`importedStringConstants` compile option, but Node 22 does not implement that
option, so the loader does not depend on it. The builtin `wasm:js-string`
functions come from `new WebAssembly.Module(bytes, { builtins: ["js-string"] })`.

The committed `wasm/textkernel.wasm` is a convenience copy so the example runs
straight after a clone. CI rebuilds from source on every push and runs the
example again, so a stale artefact cannot claim to be working code.

## Boundaries — read this before relying on it

- **The prover has no model for `String`.** The proved kernels in `src/proof`
  operate on `FixedArray[Int32]` UTF-16 code units. `src/proof/conform.mbt`
  pins each kernel to the shipped `String` implementation over an enumerated
  corpus. That two-line conversion is the trusted seam; it is a corpus
  equivalence, not a theorem about `String`.
- **Only `src/proof` is proof-enabled.** `src/lib` and `src/demo` are not in
  the `moon prove` denominator — `proof_enabled` is a whole-package switch and
  the `String`/`Array` usage in `src/lib` is outside the current model. The
  runtime invariant checks in `src/lib/invariants.mbt` are what close that gap.
- **Input bounds are arithmetic, not resource limits.** `MAX_INPUT_CODE_UNITS`
  keeps the kernels' `5 * length` / `6 * length` inside 32 bits;
  `MAX_SHIPPING_CODE_UNITS` (8,000,000 code units) is the tighter bound the
  shipping layer enforces. Both are documented in `invariants.mbt`.
- **`batch.mbt` proves the arithmetic**, not scheduling, concurrency or
  timing. `BatchConfig.max_concurrent` / `timeout_ms` are configuration
  fields, not enforced behaviour.
- **The WASM ABI requires JS string builtins.** It is not usable from a host
  without `wasm:js-string` support (e.g. a plain `wasmtime` embedder). A
  linear-memory ABI is not currently provided.
- The host allow-list and default query params are **constants in `core.mbt`**,
  deliberately set to reserved example domains (`cdn.example.com`,
  `assets.example.org`, RFC 2606). This is a general-purpose library; it has no
  knowledge of, and no integration with, any specific content platform.

## Performance

The escapers and the filename sanitiser used to build their result with
`out = out + fragment` inside a loop. That copies the whole prefix on every
iteration, which made the **native** backend quadratic: 4x input produced ~8x
runtime. They now write into a `StringBuilder`, which is amortised O(n).

Measured on `moon 0.1.20261104`, native release, 100 rounds of `escape_html`
(identical harness before and after, inclusive of process startup):

| Input (UTF-16 code units) | Before | After | Speedup |
|---:|---:|---:|---:|
| 20,480 | 6.06 s | 0.49 s | 12x |
| 81,920 | 50.54 s | 0.56 s | 90x |
| 327,680 | 187.8 s / **20 rounds** | 0.73 s / **100 rounds** | ~1300x per round |

A 1000-round run after the fix (which also reads the produced string's tail, so
the work cannot be optimised away) stays linear: 0.63 s / 0.90 s / 2.35 s for
20k / 80k / 327k code units. The JS backend was already linear and is
unchanged: 0.12 s / 0.34 s for 20k / 80k at 100 rounds.

Output is byte-for-byte identical. `src/lib/string_builder_regression_test.mbt`
keeps the original implementations as private oracles and asserts equality over
an enumerated corpus plus 200 deterministic pseudo-random strings, on all four
backends. The proof kernels and their 419 goals are untouched — they operate on
code-unit arrays, and `src/proof/conform.mbt` still pins them to the shipped
String API.

Reproduce the benchmark by exporting the tree and generating the variants in
`/tmp/tk-bench2` (see `.workbuddy/audits/2026-11-15-textkernel-commercial-value.md`
for the harness). The numbers are a regression guard, not a promise: absolute
throughput depends on the backend and host.

## Provenance & License

All code here is an independent implementation. It was extracted from a larger
private codebase by the same author and generalised for this repository:
platform-specific host names and query parameters were replaced with reserved
example domains, and two layers were rewritten from scratch to remove
scaffolding dependencies —

- `src/lib/validation.mbt`: rewritten without the original logging side effects.
- `src/lib/batching.mbt`: rewritten without the original content-analysis and
  wall-clock modules; the arithmetic it uses is the exact expression discharged
  by `src/proof/batch.mbt`.

No third-party source code is included. No code was translated or ported from
another project. The proof obligations, specifications and test corpora are
original work.

Licensed under **MIT** — see `LICENSE`.
