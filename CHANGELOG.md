# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html).
See [docs/API-STABILITY.md](docs/API-STABILITY.md) for what counts as a public
API change.

## [Unreleased]

### Added

- Planned: WASI/JSON-lines command package for non-JS hosts, subject to demand.

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
