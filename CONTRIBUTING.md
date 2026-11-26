# Contributing

Thanks for helping improve textkernel. This library sits on a trust boundary:
a small convenience change can turn into an escaping regression, so the bar for
merging is deliberately explicit.

## Before you start

- Read `docs/API-STABILITY.md`. If your change affects a stable name, open an
  issue first and describe the compatibility path.
- Read `docs/PROOF-REPORT.md` to understand what the prover does and does not
  cover.
- Check open issues for an existing design discussion.

## Local setup

```bash
git clone https://github.com/huanguan-Q/moonbit-textkernel.git
cd moonbit-textkernel
```

Stage explicit paths rather than `git add .` or `git add -A`, so that local
files are never committed by accident.

## Required gates

Every change must pass:

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

If you change an escaping kernel, also add a regression case to
`src/lib/core_test.mbt` or `src/lib/core_edge_cases_test.mbt` and, where the
kernel changed, to `src/proof/conform.mbt`.

If you add a Wasm export, update:

1. `src/main/moon.pkg` `link.exports` for `wasm-gc`,
2. `scripts/build_wasm.mjs` expected export list,
3. `examples/wasm-node/demo.mjs`,
4. `CHANGELOG.md`,
5. `docs/API-STABILITY.md` if the export is stable.

## Commit and PR style

- One logical change per commit; write what changed and why.
- Do not rewrite published history without coordination.
- PRs should include: problem, approach, compatibility impact, tests run.
- Refusals are acceptable: if a change would weaken an escaping invariant or
  invent an API promise, say so in the PR.

## Adding configuration

Prefer a new `*_with_config` function over changing the default behaviour.
The no-suffix functions must continue to reproduce the historical output.
Document new fields in `docs/API-STABILITY.md` with their default.

## Security fixes

Follow `SECURITY.md`. Do not open a public issue for an exploitable finding
before a fix is available.

## License

Contributions are accepted under the repository's MIT license. By submitting
a PR you confirm you have the right to license the contribution that way.
