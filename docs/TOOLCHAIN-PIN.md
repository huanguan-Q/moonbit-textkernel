# Toolchain pin and compatibility tracks

The CI workflow has a `compat` job with two tracks:

| Track | CLI version | Purpose |
|---|---|---|
| `latest` | always `latest` from `cli.moonbitlang.com` | detect breaking changes from new toolchains early |
| `current` | repository variable `MOONBIT_PINNED_VERSION` when set, otherwise `latest` | reproduce the project's declared baseline |

Both tracks run the same compatibility gate: format check, all-backend check,
all-backend tests and one native CLI call. They are independent
(`fail-fast: false`) so a failure in one is reported even if the other passes.

## Why the baseline is a variable

Historically this repository recorded CLI versions `0.1.20261104` and
`0.1.20261117`. As of 2026-11-23 the dated binaries at
`https://cli.moonbitlang.com/binaries/<version>/...` return HTTP 403, so an
unconditional pinned install would make every CI run fail for an infrastructure
reason. The repository variable makes the pin explicit without hiding that
fact:

- If a downloadable version is available, set
  `MOONBIT_PINNED_VERSION=0.1.<date>` in GitHub repository variables.
- If it is unset, `current` falls back to `latest` and the job still reports
  which version it actually used.
- If a configured pin is unavailable, the `current` track fails loudly instead
  of silently claiming to have tested it.

## Status 2026-11-27

Re-verified 2026-11-27: every dated binary is still unavailable —
`https://cli.moonbitlang.com/binaries/<date>/...` returns HTTP 403 for
`0.1.20261119` and `0.1.20261117` on both `linux-x86_64` and
`darwin-aarch64`, while `latest` and `nightly` return 200. Two
consequences:

- `MOONBIT_PINNED_VERSION` still has no installable value, so `current`
  runs the same toolchain as `latest`. The two tracks are independent CI
  jobs but not version-diverse: a green pair currently proves one
  toolchain, not two.
- The toolchain that built and published `0.2.0` (`0.1.20261119`, moonc
  `v0.10.22+124d61d05`) can no longer be installed from the official
  source. Its build is reproducible only while a copy of that exact
  toolchain is retained offline; treat the `latest` track as the only live
  compatibility signal — a green run means "today's `latest` compiles this
  commit", not "the release toolchain does".

When a dated release becomes downloadable again, set the variable and
update this section in the same commit.

## What is recorded

The job prints `moon version --all` in both tracks. Read that line, not the
track name, when interpreting a CI result. The README `compat` badge covers
both matrix legs.

## Release rule

A version is eligible for release only when `quality`, `wasm`, `proof` and
both `compat` legs are green on the exact commit being released. A green badge
from an older commit is not evidence for a new one.
