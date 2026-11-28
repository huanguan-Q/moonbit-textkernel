# textkernel

[![quality](https://github.com/huanguan-Q/moonbit-textkernel/actions/workflows/ci.yml/badge.svg?branch=main&job=quality)](https://github.com/huanguan-Q/moonbit-textkernel/actions/workflows/ci.yml)
[![proof](https://github.com/huanguan-Q/moonbit-textkernel/actions/workflows/ci.yml/badge.svg?branch=main&job=proof)](https://github.com/huanguan-Q/moonbit-textkernel/actions/workflows/ci.yml)
[![wasm](https://github.com/huanguan-Q/moonbit-textkernel/actions/workflows/ci.yml/badge.svg?branch=main&job=wasm)](https://github.com/huanguan-Q/moonbit-textkernel/actions/workflows/ci.yml)
[![compat](https://github.com/huanguan-Q/moonbit-textkernel/actions/workflows/ci.yml/badge.svg?branch=main&job=compat)](https://github.com/huanguan-Q/moonbit-textkernel/actions/workflows/ci.yml)
[![mooncakes](https://img.shields.io/badge/mooncakes-0.2.2-blue)](https://mooncakes.io/docs/huanguan-Q/textkernel)
[![skills](https://img.shields.io/badge/mooncakes%20skills-0.2.2-purple)](https://mooncakes.io/skills/huanguan-Q/textkernel@0.2.2)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**A small MoonBit kernel for text that crosses a trust boundary.**

When a program takes a string from one system and puts it into another — into
HTML, into a filename, into a URL, into a batch API — four things can go wrong:
markup can be injected, a filename can escape its directory, a URL can be
rewritten incorrectly, and a batch loop can drop an item. `textkernel` is
the set of routines for those four jobs, with the safety properties of their
code-unit kernels discharged by `moon prove` rather than by inspection, and
the shipped `String` layer checking its own output invariants at runtime.

One rule runs through all of them: **well-formed text passes through.** A
character outside the BMP — an emoji, a CJK Extension B ideograph — is one
character and is copied whole. Only an unpaired surrogate half is replaced.

```
huanguan-Q/textkernel    215 tests × 4 backends    every proof goal discharged    13 WASM API exports (+ `_start`)    zero deps
```

Built and verified with **moonc v1.0.0-rc1** (`moon 0.1.20261126`); see
[Reproduce](#reproduce) for the toolchain and the exact commands.

## What is in the box

| Routine | What it guarantees |
|---|---|
| `escape_html` / `escape_attr` | Output contains no raw `<` `>` (nor `"` `'` for attributes); every `&` starts a complete entity the library emits; every other character is copied as it is |
| `sanitize_filename` | Replaces the nine reserved characters, control characters and unpaired surrogate halves; never returns a directory reference such as `..`, a trailing dot or space, or a Windows device name; clamps to 120 code units without cutting a character; never returns empty |
| `normalize_asset_url` | For an `http`/`https` URL whose host is configured, or is a subdomain of one: forces `https` and appends the missing default params to the query, before any `#fragment`. Any other URL is returned unchanged |
| `decide_referrer_policy` | Picks a Referrer-Policy with the same host test `normalize_asset_url` uses |
| `str_contains` | UTF-16 code-unit substring test (the host gate above) |
| `split_joined` / `join_joined` | Exact inverse pair for batch calls; slices by code unit so non-BMP characters survive |
| `batch_process_custom` | Applies an operation in bounded chunks; a non-positive chunk size is clamped to 1, never divided by, and no chunk size can drop an item |

Default parameters are split on `&`. A piece that could change the structure
of the URL is **refused, not skipped**: an empty piece, one starting with `=`,
and one containing `#`, whitespace or a control character. For a URL on a
configured host, `normalize_asset_url_with_config_result` returns
`Err(InvalidConfig(piece))` and names the piece; the String-returning form
aborts. A URL the configuration does not apply to is returned unchanged, and
its parameters are not looked at, so a program that serves only its own hosts
is not stopped by a piece it would never append. An empty value (`k=`) is a
plain parameter.

`*_result` variants return `Result[T, CoreError]`. They accept the empty
string and every input up to `MAX_SHIPPING_CODE_UNITS` (8,000,000 code
units), and return `Err(InputTooLarge)` beyond it.
The shipping layer also checks its own output against the invariants before
returning and aborts on violation — a regression fails loudly instead of
quietly emitting markup the caller believes is escaped.

## Reproduce

Requires **moonc 1.0.0-rc1 or newer** (`moon 0.1.20261126`). Install it with
the official installer, which provides the latest release:

```bash
curl -fsSL https://cli.moonbitlang.com/install/unix.sh -o /tmp/moon-install.sh
bash /tmp/moon-install.sh
moon version --all    # moonc v1.0.0-rc1 or newer
```

Then, from the repository root:

```bash
moon fmt --check
moon check --target all --deny-warn       # wasm / wasm-gc / js / native, zero warnings
moon test --target all                    # 215/215 on each backend
moon prove                               # 207 goals at the stock solver limits; 3 report a timeout
node scripts/prove_gate.mjs              # every goal; 10x solver limits in CI, machine-int model
moon run src/demo --target native        # runnable example
moon package --list                      # validate package contents without releasing
node scripts/build_wasm.mjs              # build wasm/textkernel.wasm
node examples/wasm-node/demo.mjs         # call the WASM exports from JavaScript
node examples/wasm-node/render.mjs       # downstream consumer example
```

Two proof counts appear above because they answer different questions. The
stock `moon prove` run uses the mathematical-integer prelude and short solver
limits: it discharges 207 goals and leaves 3 timing out, in the escape kernels.
`scripts/prove_gate.mjs` retries at higher solver limits (5x by default, 10x in
CI) under the 32-bit machine-integer prelude and proves every goal. **The gate
is the verdict** and it is what CI uses. The number it reports is not a
contract: across five clean runs it was 355 three times and 488 twice, because
`split_vc` cuts a goal differently depending on solver timing. What has to hold
is `1 of 1 packages proved` with nothing left unproved. A stock run that reports timeouts is
not a regression by itself: its outcome depends on solver timing, and the same
kernels had a goal at the stock limits before that z3 alone could not close.

Toolchain for the numbers above: **moonc v1.0.0-rc1 (`moon 0.1.20261126`)**,
Why3 1.7.2, Z3 4.15.4, Alt-Ergo 2.4.3, re-verified 2026-11-27 on a clean
checkout: format and `moon check --target all --deny-warn` are clean, 215/215
tests pass on all four backends, `node scripts/build_wasm.mjs` builds the
artefact, all three `examples/wasm-node` scripts pass, and
`PROVE_TIME_SCALE=10` proves 488 goals (`1 of 1 packages proved`). This is the
same toolchain CI installs on every run. The proof verdicts depend on the VC
generator, so pin the toolchain when reproducing.

Earlier records, kept for the history of the numbers. `moon 0.1.20261119`
(moonc v0.10.22), Why3 1.7.2, Z3 4.15.4, Alt-Ergo 2.4.3, verified 2026-11-25
after the URL and filename rules were added: 193/193 tests, 207 goals proved
at the stock limits with 3 timeouts. The proof verdicts depend on the VC
generator, so pin the toolchain when reproducing.

Re-verified 2026-11-19 on the local toolchain `moon 0.1.20261117 (eb64713)`:
146/146 tests pass on all four backends, `moon prove` discharges 191 goals,
`node scripts/prove_gate.mjs` discharges 419, and `moon check --target all
--deny-warn` is clean after migrating `StringBuilder(size_hint=...)` to the
official `StringBuilder(capacity=...)` spelling (warning 0020).

Release update 2026-11-22: the dated CLI binaries for 0.1.20261104 and
0.1.20261117 are no longer downloadable, so CI now installs the latest
available MoonBit CLI and runs the proof job on `ubuntu-22.04` (Ubuntu 26.04's
OCaml 5.4 conflicts with why3 1.7.2). Re-checked locally on `moon 0.1.20261119`:
format, check and all 151x4 tests are green; `scripts/prove_gate.mjs` at the
default 5x budget reports 425 goals proved with 1 timeout and fails, while
`PROVE_TIME_SCALE=10` proves all 419 goals. CI therefore uses the 10x budget.
Treat the proof result as environment-sensitive and do not bump the prover
without re-establishing the gate.

Update 2026-11-25, after the URL and filename rules were reworked: format,
check and all 190x4 tests are green, `PROVE_TIME_SCALE=10` proves every goal,
and a stock `moon prove` proves 207 and reports 3 timeouts. The gate's goal
count moved from 419 to 355–488 with the shape of the kernels. Three contracts
were changed on purpose — the per-unit escape rule, the sanitizer's character
rule and length, and the referrer decision — and kernels were added for the
scheme test, the end of the authority, the start of the host and the dot-only
rule.

## Use

### Add it to a module

```bash
moon add huanguan-Q/textkernel@0.2.2
```

Then declare the package in the `moon.pkg` of the package that calls it.
`src/lib` is the library; the other packages of the module (`src/cli`,
`src/demo`, `src/main`, `src/proof`) are not for callers.

```json
import {
  "huanguan-Q/textkernel/src/lib",
}
```

`@lib` in the examples is the alias of that package. To exit with a status on
an error, import `"moonbitlang/core/env"` as well and call `@env.exit`.

### Call it

```moonbit
let safe = @lib.escape_html("<script>alert(1)</script>")
// &lt;script&gt;alert(1)&lt;/script&gt;

let name = @lib.sanitize_filename("report/2026:Q4?.md")
// report_2026_Q4_.md

let items = @lib.split_joined("a|b|c", "|")
let out = @lib.join_joined(@lib.quick_batch_escape_htmls(items), "|")
```

A `*_result` function returns `Result[String, CoreError]`. `CoreError` does not
implement `Show`, so the result cannot be printed directly: match on it and turn
the error with `error_to_string`.

```moonbit
match @lib.normalize_asset_url_result("http://cdn.example.com/a.png") {
  Ok(url) => println(url)
  Err(e) => {
    println(@lib.error_to_string(e))
    @env.exit(2)
  }
}
```

The call above succeeds. A default parameter that cannot be appended, such as
one containing `#`, is refused instead: with
`create_asset_config(["cdn.example.com"], ["fmt=png#frag"])`, the function
`normalize_asset_url_with_config_result` returns
`Err(InvalidConfig("fmt=png#frag"))` for the same URL, and the error branch
above exits with `2`.

See `src/demo/main.mbt` for a complete runnable example and
`examples/wasm-node/ssr-middleware.mjs` for an SSR/UGC consumer.

## Explicit configuration and CLI

Host allow-lists and default query parameters are data, not source constants.
A host entry is a host name — no scheme, path or port — and matches that host
and its subdomains in any letter case:

```moonbit
let config = @lib.create_asset_config(
  ["cdn.internal.example"],
  ["w=800", "auto=1"],
)
let url = @lib.normalize_asset_url_with_config(
  "http://cdn.internal.example/a.png",
  config,
)
// https://cdn.internal.example/a.png?w=800&auto=1
```

The no-suffix functions remain wrappers around the historical RFC 2606
configuration, so existing callers do not break.

The same operations are available as a CLI with JSON-lines output:

```bash
moonx huanguan-Q/textkernel/src/main@0.2.2 -- --help
moonx huanguan-Q/textkernel/src/main@0.2.2 -- escape-html '<script>x</script>'
moon run src/cli --target native -- sanitize-filename --input 'a/b:c?.png'
moon run src/cli --target native -- sanitize-filename < name.txt
```

The native CLI reads stdin as **one** input, not as a stream of lines. To
process a list, call it once per line.

Use the explicit `src/main` package path for moonx: the bare module coordinate
has no prebuilt Wasm asset on mooncakes.io.

The CLI prints one JSON line and its **exit status tells success from failure**:
`0` with an `output` line, `2` with an `error` line. Both entry points behave
the same, so a script or an agent can test the status instead of parsing the
output:

```bash
moonx huanguan-Q/textkernel/src/main@0.2.2 -- normalize-asset-url \
  --hosts cdn.example.com --params 'fmt=png,x#y' https://cdn.example.com/a.png
# {"command":"normalize-asset-url","error":"Invalid Config: x#y"}   exit status 2
```

`--params` holds comma-separated pairs, and `&` may join several in one pair.
A pair that is empty, starts with `=`, or contains `#`, whitespace or a control
character is refused for a URL on a configured host. An unknown command and a
missing option value also exit with `2`.

## WASM / calling from JavaScript

`src/main` is an export shim plus a small CLI entry point. With
`use-js-builtin-string` the linker exposes `String -> String` functions
directly to a JS host — no linear-memory ABI, no manual allocation, no UTF-8
copy:

| Single value | Joined-list batch (`joined`, `sep`) |
|---|---|
| `escape_html`, `escape_attr`, `sanitize_filename` | `escape_htmls_joined`, `escape_attrs_joined`, `sanitize_filenames_joined` |
| `normalize_asset_url`, `decide_referrer_policy`, `str_contains` | `normalize_asset_urls_joined` |
| `escape_html_safe`, `escape_attr_safe`, `sanitize_filename_safe` | — never-fail variants |

```bash
node scripts/build_wasm.mjs        # ~27 KB artefact; verifies 13 API exports (+ `_start`)
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
`Result[String, CoreError]` and cover every failure source: an input outside
the shipping domain (`InputTooLarge`), a violated output invariant
(`InvariantViolation`), and a default parameter that cannot be appended
(`InvalidConfig`). `CoreError` also carries `InvalidInput` and
`PerformanceWarning`; only `validate_string_input` produces them. Every tier
enforces the same bound, `MAX_SHIPPING_CODE_UNITS`, and treats the empty string
as a valid input.

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
- The host allow-list and default query params are **data**, passed through
  `AssetConfig`. The no-suffix functions keep the historical RFC 2606 example
  domains (`cdn.example.com`, `assets.example.org`) as a compatibility default.
- **Not every rule of the URL and filename routines is proved.** Proved: the
  scheme test, where the authority ends, where the host starts, the host rule,
  the filename character rule, its clamp and its dot-only rule. Not proved, and
  covered by tests and the runtime invariant instead: stripping the port from a
  host, trailing dots and spaces, Windows device names.
- **A proof is about its specification, not about the intent.** The first
  specification of the escapers replaced every surrogate unit, and the proof,
  the implementation and the tests all agreed — an emoji became `__`. The
  specification was wrong. Read `spec.mbtp` as the statement of what is proved.
- **A precondition is the caller's obligation.** `batch_ceil` is proved for a
  chunk size of at most `MAX_CODE_UNITS`. The shipped loop used to pass it any
  `Int32`, and a size near the maximum silently dropped the list. It now keeps
  the size inside the proved domain.
- **A lone surrogate half cannot occur in a MoonBit corpus.** The compiler
  rejects `"\u{D800}"` and slicing snaps to character boundaries. Such a half
  can only arrive from a host that passes ill-formed UTF-16; the kernels are
  driven on raw code units, and `examples/wasm-node/demo.mjs` sends one through
  the WASM exports from JS.
- **An unpaired half becomes `_`, not U+FFFD.** It has no character to copy, so
  it has to become something. `_` is the one replacement the project already
  uses — `sanitize_filename` writes it for every reserved character — and both
  are a single UTF-16 code unit, so the escapers' `5n` / `6n` output bounds
  hold unchanged. The cost is that a literal `_` and a replaced half are
  indistinguishable in the output; U+FFFD would make them distinguishable and
  is a one-code-unit change, but it changes what a stable function returns and
  is therefore a minor release, not a patch.
- **No verified third-party adoption yet.** There are no downstream dependents
  outside this repository's own examples. `ssr-middleware.mjs` shows the shape
  a consumer would write; it is not evidence of adoption.

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
restates the contract with plain concatenation and asserts equality over
an enumerated corpus plus 200 deterministic pseudo-random strings, on all four
backends. The proof kernels operate on code-unit arrays, and
`src/proof/conform.mbt` still pins them to the shipped String API.

The joined-list path had the same quadratic concatenation in `join_joined`, and
it went unnoticed because JS hosts make string concatenation cheap. On the
native backend 1,000 items took 32 ms and each doubling of the list took about
four times as long (16,000 items: 2.2 s). With a `StringBuilder` the same run
takes 21 ms for 1,000 items and 31 ms for 16,000.

To reproduce, export the tree with `git archive HEAD`, build a small release
executable that calls `escape_html` N times over a string grown by doubling
`"a<&>x"`, and time it with `/usr/bin/time -p`. Subtract a baseline variant
that only measures `input.length()` to remove process startup, and use the
identical harness before and after a change. The numbers are a regression
guard, not a promise: absolute throughput depends on the backend and host.

## Evidence and further reading

- `docs/BENCHMARK.md` — recorded native timings and reproduction method.
- `docs/PROOF-REPORT.md` — what the proof gates establish and where the trusted seam is.
- `docs/FORMAL-VERIFICATION-ARTICLE.md` — a reproducible walkthrough of the proof design.
- `docs/ABI-EVALUATION.md` — why the current Wasm artefact needs JS string builtins and the proposed WASI path.
- `docs/TOOLCHAIN-PIN.md` — why the CI compatibility pin is a repository variable.
- Mooncakes Skills entry: <https://mooncakes.io/skills/huanguan-Q/textkernel@0.2.2>.
- `SKILL.md` — agent-facing command reference.
- `docs/API-STABILITY.md` — SemVer contract and stable API surface.
- `CHANGELOG.md` — release history.
- `CONTRIBUTING.md` — development and review gates.
- `SECURITY.md` — supported versions and private reporting.

## Versioning

This project follows Semantic Versioning 2.0.0. Patch releases are
output-preserving bug fixes; minor releases add APIs with compatibility
defaults, and a fix that changes what a stable function returns for some
input is released as a minor, never as a patch; major releases may remove or
change stable names. The stable surface and deprecation path are listed in
`docs/API-STABILITY.md`.

Every published version has a tag `vX.Y.Z` on the commit whose `moon.mod`
carries that version, so a release can be checked out with
`git checkout v0.2.2`. The tags up to `v0.2.1` were added on 2026-11-28, after
those releases; they point at the release commits and their own timestamps are
not the release dates. From `v0.2.2` on, a tag is pushed with the release.
`CHANGELOG.md` records the compiler each recent release was built with.

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
