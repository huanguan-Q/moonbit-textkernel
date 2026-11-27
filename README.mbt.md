# textkernel

A formally verified MoonBit kernel for HTML escaping, filename sanitisation,
URL rewriting and joined-list batch operations. Zero dependencies, four
backends, 215 tests and every proof goal discharged under the CI gate.
Requires moonc 1.0.0-rc1 or newer.

## Usage

```moonbit
let safe = @lib.escape_html("<script>alert(1)</script>")
let name = @lib.sanitize_filename("report/2026:Q4?.md")
let url = @lib.normalize_asset_url("http://cdn.example.com/a.png")
let parts = @lib.split_joined("a|b|c", "|")
```

`*_result` variants return `Result[T, CoreError]`. They accept the empty string
and every input up to `MAX_SHIPPING_CODE_UNITS`. The shipping layer verifies
its own output against the escape invariants before returning.

Well-formed text passes through: a character outside the BMP (an emoji, a CJK
Extension B ideograph) is copied whole by every routine. Only an unpaired
surrogate half is replaced.

`sanitize_filename` returns a name that can be created as a file on Linux,
macOS and Windows: no directory reference such as `..`, no control character,
no trailing dot or space, no device name such as `NUL.txt`.

A host entry of `AssetConfig` is a host name. It matches that host and its
subdomains of an `http`/`https` URL in any letter case, and nothing else; a
missing default parameter goes before the `#fragment`.

Default parameters are split on `&`. A piece that could change the structure
of the URL is **refused, not skipped**: an empty piece, one starting with `=`,
and one containing `#`, whitespace or a control character. For a URL on a
configured host, the `*_result` functions return `Err(InvalidConfig(piece))`
and the String-returning form aborts. A URL on any other host is returned
unchanged and its parameters are not looked at.

Pass an explicit `AssetConfig` to `*_with_config` to replace the example-domain
allow-list and default query params without forking. The no-suffix functions
keep the historical defaults. The same operations are available as a CLI:

```bash
moonx huanguan-Q/textkernel/src/main@0.2.0 -- escape-html '<script>x</script>'
moon run src/cli --target native -- sanitize-filename --input 'a/b:c?.png'
```

## Verification

Run `moon test --target all` and `node scripts/prove_gate.mjs` (10x solver
limits in CI, 32-bit machine-integer model). The gate is the verdict; the
number of goals it reports, 355 or 488, depends on how they are split. A bare `moon prove` at the stock limits discharges 207 goals under the
mathematical-integer model and reports 3 timeouts in the escape kernels; its
outcome depends on solver timing. Re-verified 2026-11-27 on
**moonc v1.0.0-rc1 (`moon 0.1.20261126`)**: 215/215 tests pass on all four
backends and the 10x gate proves 488 goals. The proved
kernels live in
`src/proof` over UTF-16 code-unit arrays; `src/proof/conform.mbt` pins them to
the shipped `String` API over an enumerated corpus. `src/lib` is not in the
proof denominator because the prover has no `String` model — runtime invariant
checks cover that layer instead. Full boundaries are documented in `README.md`.

## Performance

All three string builders and `join_joined` use a `StringBuilder`, so output
construction is amortised O(n) on every backend. A reference-vs-rewrite
differential test (`string_builder_regression_test.mbt`) pins byte-for-byte
equality.

## Errors

`*_result` returns `Result[String, CoreError]` and never aborts. It accepts the
empty string and every input up to `MAX_SHIPPING_CODE_UNITS`. The
String-returning API is a compatibility layer with an explicit
`FailurePolicy` (`FailFast` / `EmptyOnError`); `*_safe` always uses the latter.

## WASM

`node scripts/build_wasm.mjs` builds a WASM-GC artefact with 13 business
exports over JS strings (14 module exports including `_start`). The ABI relies
on `wasm:js-string` builtins and offers no linear-memory alternative. See
`examples/wasm-node/demo.mjs` for a runnable host example.

## Versioning and governance

Semantic Versioning 2.0.0; see `CHANGELOG.md`, `CONTRIBUTING.md`,
`SECURITY.md` and `docs/API-STABILITY.md` in the repository. Stable names keep
their signature and semantics within a major version; configuration is additive.

## Provenance & License

Independent implementation by the repository owner, extracted from a larger
private codebase and generalised: platform-specific names replaced with RFC
2606 example domains, and the validation and batching layers rewritten to
remove scaffolding dependencies. No third-party or ported source code.

MIT — see `LICENSE`.
