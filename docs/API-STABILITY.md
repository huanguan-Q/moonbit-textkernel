# API stability and versioning commitment

textkernel follows [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).
The published version in `moon.mod` is the contract. Moving from `0.1.x` to
`0.2.x` may introduce breaking changes only after the deprecation path below;
the `0.x` series does not grant a license to break callers silently.

## Public API tiers

### Stable

These names will not be removed or have their signature or semantics changed
without a major version bump:

- `escape_html`, `escape_attr`, `sanitize_filename`, `normalize_asset_url`,
  `decide_referrer_policy`, `ensure_asset_params`, `str_contains`.
- `*_result` variants and `CoreError` / `error_to_string`. A minor release may
  add a `CoreError` variant; no variant is removed or renamed. A `match` that
  lists every variant without a wildcard arm is rejected by the compiler until
  it handles the new one, so such a `match` needs one line per minor release.
  Outside this package a variant can be matched but not constructed.
- `*_safe` variants and their Wasm exports.
- `split_joined`, `join_joined`, `BatchConfig`, `batch_process_custom` and
  `create_batch_config`.
- `AssetConfig`, `create_asset_config`, `default_asset_config` and all
  `*_with_config` variants added in 0.1.1.
- The 13 business exports of `wasm/textkernel.wasm` (`_start` is a runtime
  entry point, not a callable API).
- `moonx huanguan-Q/textkernel/src/main@<version>` command names and their
  JSON-lines key names (`command`, `output`, `error`).
- The CLI exit status: `0` when the line has an `output`, `2` when it has an
  `error`. A script may rely on `textkernel ... || exit 1`. A command that
  fails never exits `0`.

### Provisional

These may change in a minor release with a changelog entry:

- Individual CLI flags beyond `--help`, `--input`, `--hosts`, `--params`.
- Help text wording and human-readable error messages.
- `docs/ABI-EVALUATION.md` recommendations.

### Experimental

No compatibility promise:

- `src/proof` internals and the number of discharged goals.
- The exact byte layout of `wasm/textkernel.wasm`.
- Timing numbers in `docs/BENCHMARK.md`.
- The native CLI package `src/cli` (native only, experimental async runtime).

## Compatibility rules

- **Patch**: bug fixes and output-preserving performance work only. No API
  removals, renames, signature changes, or semantic changes to escaping.
- **Minor**: additive APIs, new config fields with defaults, new commands, and
  a fix that changes what a stable function returns for some input (below).
  Deprecations must keep the old spelling working for at least one minor plus
  one patch release.
- **Major**: removal or signature change of a stable name; a deliberate change
  to what a stable function promises; a change to the Wasm export set.
- A change in a solver, proof-goal count, benchmark number or help sentence is
  not an API change. A change in escaping output *is*.
- A fix that changes what a stable function returns for some input is not a
  patch. It is released as a minor version, with a `CHANGELOG.md` entry that
  names the inputs it affects. That is the one case where "patch" above does
  not apply: keeping a wrong answer to save a version number is the worse
  break. The fixes in the `[Unreleased]` section do this for text with a
  character outside the BMP, for `..`, for URLs on a look-alike host, and for
  a default parameter that cannot be appended.

## Configuration compatibility

`default_asset_config()` preserves the historical RFC 2606 example domains and
`fmt=png` / `v=1`. A host entry is a host name and matches itself and its
subdomains; that reading of an entry is part of the contract. New
`AssetConfig` fields, if any, will always have a default
that reproduces current behaviour. Consumers should construct config through
`create_asset_config` rather than relying on a struct literal, so added fields
cannot break their code.

## Verification gates for a release

```bash
moon fmt --check
moon check --target all --deny-warn
moon test --target all
node scripts/prove_gate.mjs
node scripts/build_wasm.mjs
node examples/wasm-node/demo.mjs
node examples/wasm-node/render.mjs
node examples/wasm-node/ssr-middleware.mjs
```

A release also requires a `CHANGELOG.md` entry and a mooncakes publish check.
