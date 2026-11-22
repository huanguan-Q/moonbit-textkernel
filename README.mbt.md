# textkernel

A formally verified MoonBit kernel for HTML escaping, filename sanitisation,
URL rewriting and joined-list batch operations. Zero dependencies, four
backends, 146 tests and 419 proof goals under the CI proof gate.

## Usage

```moonbit
let safe = @lib.escape_html("<script>alert(1)</script>")
let name = @lib.sanitize_filename("report/2026:Q4?.md")
let url = @lib.normalize_asset_url("http://cdn.example.com/a.png")
let parts = @lib.split_joined("a|b|c", "|")
```

`*_result` variants return `Result[T, CoreError]`. The shipping layer verifies
its own output against the escape invariants before returning.

## Verification

Run `moon test --target all` and `node scripts/prove_gate.mjs` (10x solver
limits in CI, 32-bit machine-integer model, 419 goals). A bare `moon prove`
discharges 191 goals with the stock limits and may report timeouts.
Re-verified 2026-11-22 on `moon 0.1.20261119`: 146/146 tests pass on all four
backends. The proved kernels live in
`src/proof` over UTF-16 code-unit arrays; `src/proof/conform.mbt` pins them to
the shipped `String` API over an enumerated corpus. `src/lib` is not in the
proof denominator because the prover has no `String` model — runtime invariant
checks cover that layer instead. Full boundaries are documented in `README.md`.

## Performance

All three string builders use `StringBuilder`, so output construction is
amortised O(n) on every backend. A legacy-vs-rewrite differential test
(`string_builder_regression_test.mbt`) pins byte-for-byte equality.

## Errors

`*_result` returns `Result[String, CoreError]` and never aborts. The
String-returning API is a compatibility layer with an explicit
`FailurePolicy` (`FailFast` / `EmptyOnError`); `*_safe` always uses the latter.

## WASM

`node scripts/build_wasm.mjs` builds a WASM-GC artefact with 13 business
exports over JS strings (14 module exports including `_start`). The ABI relies
on `wasm:js-string` builtins and offers no linear-memory alternative. See
`examples/wasm-node/demo.mjs` for a runnable host example.

## Provenance & License

Independent implementation by the repository owner, extracted from a larger
private codebase and generalised: platform-specific names replaced with RFC
2606 example domains, and the validation and batching layers rewritten to
remove scaffolding dependencies. No third-party or ported source code.

MIT — see `LICENSE`.
