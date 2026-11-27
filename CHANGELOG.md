# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).
See [docs/API-STABILITY.md](docs/API-STABILITY.md) for what counts as a public
API change.

## [0.2.1] - 2026-11-27

This is a patch release. No public name, signature, command or output changes:
the library and proof sources are byte-for-byte those of 0.2.0. What changes is
the evidence that ships with them — the tests, the CI gate and the recorded
toolchain — and the published artefact is now built with a compiler that meets
the current requirement of moonc 1.0.0-rc1 or newer.

### Added

- Tests for the CLI surface (`src/lib/cli_test.mbt`): CSV splitting, config
  merging, every command of `run_cli` including the two failures that produce
  exit status `2`, and the JSON-lines shapes.
- Tests for the WASM export shim (`src/main/exports_wbtest.mbt`): all 13 exports
  agree with the library API, the `str_contains` boolean mapping, and the
  joined-string round trip.
- A CI step that pins the process-level exit contract advertised in 0.2.0: an
  `error` line exits with `2`, `--help` with `0`.

### Changed

- The repository is verified on **moonc v1.0.0-rc1** (`moon 0.1.20261126`):
  215 tests on each of the four backends and every proof goal discharged under
  the 10x gate (488 goals). The README states this requirement.
- `docs/TOOLCHAIN-PIN.md` records that the dated CLI binaries remain
  unavailable, so the compatibility pin has no installable value and the two
  CI tracks currently run the same toolchain.
- `wasm/textkernel.wasm` is rebuilt with moonc 1.0.0-rc1: 27,908 bytes, the
  same 13 exports plus `_start`, same behaviour. The 2-byte difference from the
  0.2.0 artefact (27,906) is compiler output, not a source change.
- The test count in the package summary and in `docs/PROOF-REPORT.md` is
  updated to 215.

## [0.2.0] - 2026-11-26

This is a minor release because several fixes change what a stable function
returns for some inputs: text with a character outside the BMP, `..`, a URL on
a look-alike host, a long article, a default parameter that cannot be
appended. Under `docs/API-STABILITY.md` such a fix is not released as a patch.
The function names and their signatures are unchanged; the 13 WASM exports are
unchanged. A caller that upgrades needs to look at three things: a `match` over
`CoreError` needs an `InvalidConfig` arm, a script that tests the CLI's exit
status now sees `2` on failure, and code that relied on the old output above
changes behaviour.

### Fixed

- `escape_html` and `escape_attr` keep a character outside the BMP (emoji, CJK
  Extension B and beyond). Before, both halves of a well-formed surrogate pair
  became `_`, so `中文😀` came out as `中文__`. Only an unpaired surrogate half is
  replaced now. The proof specification said the same as the old code and was
  wrong with it; `html_at` / `attr_at` carry the corrected rule.
- `sanitize_filename` returns a name that can be created as a file:
  - a name made of dots only (`.`, `..`, `...`) becomes `file` instead of a
    directory reference;
  - C0 control characters and DEL are replaced, NUL and line breaks included;
  - trailing dots and spaces become `_`, because Windows removes them;
  - a Windows device name (`CON`, `NUL.txt`, `Com1`, ...) gets a `_` after its
    stem (`nul_.txt`);
  - a character outside the BMP is kept, and the 120-unit clamp never cuts one.
- `normalize_asset_url` and `decide_referrer_policy` apply the allow-list to the
  URL's own host. Before, the host string was searched for anywhere in the URL,
  so `https://evil.com/cdn.example.com/x.png` was rewritten and
  `https://cdn.example.com.evil.com/` got the downgrade policy.
  - Only an `http` or `https` URL can match, and letter case does not matter.
    A DNS name has no letter case, so `CDN.EXAMPLE.COM` is the configured host
    `cdn.example.com`. Before, an upper-case host was left alone, which was a
    side effect of searching for the host string. The host is kept as written
    in the output; only its matching ignores case.
  - A configured host matches itself and its subdomains, on whole labels.
  - A missing parameter is inserted before the `#fragment`, not after it, and
    only a parameter with exactly that name counts as present (`nav=1` is not
    `v=1`).
  - A URL that ends in `?` gets `?fmt=png&v=1`, no longer `?&fmt=png&v=1`.
  - Default parameters are split on `&`, and a piece that could change the
    structure of the URL is **refused instead of appended**: an empty piece,
    one starting with `=`, and one containing `#`, whitespace or a control
    character. Before, every piece was appended as it was, so a default
    `"x#y"` put a second fragment into the URL and `"a=1&b=2"` became two
    parameters. See *Changed* for how the refusal is reported.
- The `*_result` functions accept the empty string and every input up to
  `MAX_SHIPPING_CODE_UNITS`. Before, `escape_html_result` and
  `escape_attr_result` refused more than 8,192 code units, the other six more
  than 4,096, and all of them refused `""`.
- `batch_process_custom` no longer drops the whole list when the configured
  chunk size is 2,147,483,644 or more: `(total + size - 1)` overflowed. The
  chunk size now stays inside the domain its arithmetic was proved on.
- `join_joined`, and with it the `*_joined` WASM exports, is linear on the
  native backend. 16,000 items took 2.2 s; they take 31 ms now.

### Changed

- An `HTTP://` URL on a configured host is rewritten to `https`, and its
  parameters are appended. An `HTTPS://` URL keeps its scheme as written.
- A default parameter that cannot be appended is an error, not a silent loss.
  - `normalize_asset_url_with_config_result` and `normalize_asset_url_result`
    return `Err(InvalidConfig(piece))`; the message is the offending piece, so
    the caller can find it in its own configuration. Nothing is half-applied.
  - `normalize_asset_url_with_config`, `normalize_asset_url` and the
    `ensure_asset_params` aliases abort for it, as they do for any other
    failure of the String-returning layer.
  - The parameters are looked at only for a URL the configuration applies to.
    Any other URL is returned unchanged, so a configuration with a bad piece
    still works for the hosts it is never used on.
  - A `match` over `CoreError` written against 0.1.4 is rejected as a partial
    match (`0011`) until it has an `InvalidConfig` arm. Outside this package
    the variant cannot be constructed, only matched, as with every other
    `CoreError` variant.
- **The CLI exits with status `2` when it prints an `error` line**, and with
  `0` when it prints an `output` line. Both `moonx` and the native CLI behave
  the same. Before, every command exited `0`, so `textkernel ... || exit 1`
  never ran and a caller had to parse the JSON to see a failure. An unknown
  command, a missing option value and a refused default parameter all exit
  with `2`. `--help` exits with `0`.
- `CoreError::InvalidInput` and `CoreError::PerformanceWarning` are no longer
  produced by the library. `validate_string_input` still returns them and is
  kept for callers that want a length rule of their own.

### Added

- `CoreError::InvalidConfig(String)`, returned by `normalize_asset_url*_result`
  for a default parameter that cannot be appended; `error_to_string` renders it
  as `Invalid Config: <piece>`.
- `CLI_USAGE_EXIT` (`2`), the process exit status of both CLI entry points
  when they print an `error` line.
- Proof kernels for the scheme test, the end of the authority, the start of the
  host and the host rule (`src/proof/url.mbt`); the dot-only rule and the
  surrogate pair in the sanitizer (`src/proof/sanitize.mbt`).
- Regression tests for each fix, and a JS-host test that sends an unpaired
  surrogate half through the WASM exports.

## [0.1.4] - 2026-11-23

### Fixed

- Republished the mooncakes skill so its bundle contains the 0.1.3 changelog
  entry and the skills badge/link that were added to the repository after
  `huanguan-Q/textkernel@0.1.3` was published. The old skill version is
  immutable; 0.1.4 is the corrected bundle.
- Updated all documented `moonx` coordinates and badges to 0.1.4.

## [0.1.3] - 2026-11-23

### Added

- `CHANGELOG.md`, `CONTRIBUTING.md`, `SECURITY.md` and
  `docs/API-STABILITY.md`: SemVer commitment, stable API tiers and private
  vulnerability reporting.
- `docs/FORMAL-VERIFICATION-ARTICLE.md`: a reproducible walkthrough of the
  proof design.
- `docs/TOOLCHAIN-PIN.md` and a dual-track `compat` CI job for current/latest
  toolchains.
- README badges for quality, proof, wasm and compatibility jobs.
- Published the skill bundle as `huanguan-Q/textkernel@0.1.3` on the mooncakes
  Skills Marketplace.

### Fixed

- README no longer claims host allow-lists are source constants; they are
  injected through `AssetConfig` since 0.1.1.

## [0.1.2] - 2026-11-23

### Changed

- Documented the verified `moonx` coordinate as
  `moonx huanguan-Q/textkernel/src/main@0.1.2`; the bare module coordinate has
  no prebuilt Wasm asset on mooncakes.io.
- Added this changelog, contributing guide, security policy and API stability
  commitment.

## [0.1.1] - 2026-11-22

### Added

- `AssetConfig` with `create_asset_config` and `*_with_config` variants, so
  commercial consumers can replace the host allow-list and default query
  parameters without forking.
- Shared CLI logic with `--help`, argument/stdin input and JSON-lines output.
  `src/main` is now executable through `moonx`; `src/cli` is a native wrapper
  with stdin support.
- `docs/BENCHMARK.md`, `docs/PROOF-REPORT.md`, `docs/ABI-EVALUATION.md`.
- `SKILL.md` for agent-facing discovery.
- SSR/UGC middleware example.

### Changed

- Wasm-GC artefact grew from about 9.6 KB to 23,574 bytes because the CLI entry
  point adds argument handling; the 13 business exports and `_start` are
  unchanged.
- `examples/wasm-node/loader.mjs` now supplies stubs for the CLI's argv/console
  imports. Business exports still call none of them.
- Test suite grew from 146 to 151 per backend.

## [0.1.0] - 2026-11-19

### Added

- Initial public release on GitHub and mooncakes.io.
- HTML escaping, attribute escaping, filename sanitization, asset URL
  normalization, Referrer-Policy selection, UTF-16 substring search and
  joined-list batch operations.
- Fail-fast, `Result`-based and never-fail (`*_safe`) variants.
- Formal proof kernels in `src/proof`, the 419-goal CI proof gate, and the
  four-backend test matrix.
