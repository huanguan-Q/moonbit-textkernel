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

## What is recorded

The job prints `moon version --all` in both tracks. Read that line, not the
track name, when interpreting a CI result. The README `compat` badge covers
both matrix legs.

## Release rule

A version is eligible for release only when `quality`, `wasm`, `proof` and
both `compat` legs are green on the exact commit being released. A green badge
from an older commit is not evidence for a new one.
