# textkernel

A formally verified MoonBit kernel for HTML escaping, filename sanitisation,
URL rewriting and joined-list batch operations. Zero dependencies, four
backends, 137 tests and 191 proof goals.

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

Run `moon test --target all` and `moon prove`. The proved kernels live in
`src/proof` over UTF-16 code-unit arrays; `src/proof/conform.mbt` pins them to
the shipped `String` API over an enumerated corpus. `src/lib` is not in the
proof denominator because the prover has no `String` model — runtime invariant
checks cover that layer instead. Full boundaries are documented in `README.md`.

## Provenance & License

Independent implementation by the repository owner, extracted from a larger
private codebase and generalised: platform-specific names replaced with RFC
2606 example domains, and the validation and batching layers rewritten to
remove scaffolding dependencies. No third-party or ported source code.

MIT — see `LICENSE`.
