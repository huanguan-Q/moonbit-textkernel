# textkernel

**A small, formally verified MoonBit kernel for text that crosses a trust boundary.**

When a program takes a string from one system and puts it into another — into
HTML, into a filename, into a URL, into a batch API — four things can go wrong:
markup can be injected, a filename can escape its directory, a URL can be
rewritten incorrectly, and a batch loop can drop an item. `textkernel` is the
set of routines for those four jobs, with the safety properties discharged by
`moon prove` rather than by inspection.

```
huanguan-Q/textkernel    146 tests × 4 backends    419 proof goals    13 WASM API exports (+ `_start`)    zero deps
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
moon test --target all                    # 146/146 on each backend
moon prove                               # 191 goals with the stock solver limits
node scripts/prove_gate.mjs              # 419 goals, 10x solver limits in CI, machine-int model
moon run src/demo --target native        # runnable example
moon package --list                      # validate package contents without releasing
node scripts/build_wasm.mjs              # build wasm/textkernel.wasm
node examples/wasm-node/demo.mjs         # call the WASM exports from JavaScript
node examples/wasm-node/render.mjs       # downstream consumer example
```

Two proof counts appear above because they answer different questions: the
stock `moon prove` run discharges 191 goals, while `scripts/prove_gate.mjs`
retries at higher solver limits (5x by default, 10x in CI) under the 32-bit
machine-integer prelude and discharges 419. The gate is what CI uses; the extra
budget is needed because the newest CLI leaves one goal timing out at 5x.

Toolchain used to produce the numbers above: `moon 0.1.20261104`, Why3 1.7.2,
z3. The proof verdicts depend on the VC generator, so pin the toolchain when
reproducing; the historical pin is kept here for provenance.

Re-verified 2026-11-19 on the local toolchain `moon 0.1.20261117 (eb64713)`:
146/146 tests pass on all four backends, `moon prove` discharges 191 goals,
`node scripts/prove_gate.mjs` discharges 419, and `moon check --target all
--deny-warn` is clean after migrating `StringBuilder(size_hint=...)` to the
official `StringBuilder(capacity=...)` spelling (warning 0020).

Release update 2026-11-22: the dated CLI binaries for 0.1.20261104 and
0.1.20261117 are no longer downloadable, so CI now installs the latest
available MoonBit CLI and runs the proof job on `ubuntu-22.04` (Ubuntu 26.04's
OCaml 5.4 conflicts with why3 1.7.2). Re-checked locally on `moon 0.1.20261119`:
format, check and all 146x4 tests are green; `scripts/prove_gate.mjs` at the
default 5x budget reports 425 goals proved with 1 timeout and fails, while
`PROVE_TIME_SCALE=10` proves all 419 goals. CI therefore uses the 10x budget.
Treat the proof result as environment-sensitive and do not bump the prover
without re-establishing the gate.

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
| `escape_html_safe`, `escape_attr_safe`, `sanitize_filename_safe` | — never-fail variants |

```bash
node scripts/build_wasm.mjs        # ~9.6 KB artefact, verifies 13 API exports (+ `_start`)
node examples/wasm-node/demo.mjs   # assertions across all 13 API exports
node examples/wasm-node/render.mjs # realistic downstream consumer
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

## Error handling

**The production path never aborts.** The `*_result` variants return
`Result[String, CoreError]` and cover both failure sources: an input outside
the shipping domain (`InputTooLarge`) and a violated output invariant
(`InvariantViolation`). `CoreError` carries both alongside the original
`InvalidInput` / `PerformanceWarning`; `error_to_string` renders all four.

The String-returning `escape_html` / `escape_attr` / `sanitize_filename` are a
**compatibility layer** kept for existing callers and the WASM ABI. They route
every failure through `apply_failure_policy` — the single place in the library
that can abort. Callers choose a policy explicitly with `*_with_policy`:

| Policy | Behaviour | Use |
|---|---|---|
| `FailFast` (compatibility default) | abort | Trusted inputs; preserves historical semantics |
| `EmptyOnError` | return `""` | Trust boundaries where a trap would take down the host |

`""` is safe for every kernel: it is neither markup nor an unsanitised
filename. `*_safe` variants and their three WASM exports use `EmptyOnError`.

`examples/wasm-node/render.mjs` exercises the whole thing as a downstream
consumer would: it renders untrusted comments into HTML, escapes text nodes
and attributes separately, rejects an 8,000,001-code-unit payload **without
trapping the host**, and shows that the fail-fast export still traps — now an
explicit policy choice instead of the only behaviour available.

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
  timing. `BatchConfig` now has exactly one field (`batch_size`): the earlier
  `max_concurrent` / `enable_memory_pool` / `timeout_ms` were removed because
  a pure function has no scheduler, pool or clock to honour them.
- **The WASM ABI requires JS string builtins.** It is not usable from a host
  without `wasm:js-string` support (e.g. a plain `wasmtime` embedder). A
  linear-memory ABI is not currently provided.
- The host allow-list and default query params are **constants in `core.mbt`**,
  deliberately set to reserved example domains (`cdn.example.com`,
  `assets.example.org`, RFC 2606). This is a general-purpose library; it has no
  knowledge of, and no integration with, any specific content platform.
- **No third-party adoption yet.** There are no downstream dependents
  outside this repository's own examples. `render.mjs` shows the shape a
  consumer would write; it is not evidence of adoption.

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

To reproduce, export the tree with `git archive HEAD`, build a small release
executable that calls `escape_html` N times over a string grown by doubling
`"a<&>x"`, and time it with `/usr/bin/time -p`. Subtract a baseline variant
that only measures `input.length()` to remove process startup, and use the
identical harness before and after a change. The numbers are a regression
guard, not a promise: absolute throughput depends on the backend and host.

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
