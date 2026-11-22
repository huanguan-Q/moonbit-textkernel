# Benchmark report

All numbers below were recorded on this repository, not estimated. They are a
regression guard for the `StringBuilder` migration; absolute throughput depends
on backend, CPU and host.

## Escaping: before vs after

Measured with `moon 0.1.20261104`, native release, 100 rounds of `escape_html`
over strings grown by doubling `"a<&>x"`. The harness included process startup
in both runs.

| Input (UTF-16 code units) | Before | After | Speedup |
|---:|---:|---:|---:|
| 20,480 | 6.06 s | 0.49 s | 12x |
| 81,920 | 50.54 s | 0.56 s | 90x |
| 327,680 | 187.8 s / 20 rounds | 0.73 s / 100 rounds | ~1300x per round |

A 1000-round run after the fix, reading the produced string's tail so the work
cannot be optimized away:

| Input | 1000 rounds |
|---:|---:|
| 20,480 | 0.63 s |
| 81,920 | 0.90 s |
| 327,680 | 2.35 s |

The JS backend was already linear and did not change: 0.12 s / 0.34 s at 100
rounds for 20k / 80k code units.

## Why the change mattered

The old implementation used `out = out + fragment` inside a loop, copying the
whole prefix each iteration. On native this was quadratic: 4x input produced
about 8x runtime. The shipped code uses `StringBuilder`, giving amortised O(n)
construction on all four backends.

`src/lib/string_builder_regression_test.mbt` keeps the old implementations as
private oracles and asserts byte-for-byte equality over an enumerated corpus
plus 200 deterministic pseudo-random strings. Proof kernels were untouched:
they operate on code-unit arrays and `src/proof/conform.mbt` still pins them to
the shipped `String` API.

## Reproduce

```bash
moon test --target all
node scripts/build_wasm.mjs
node examples/wasm-node/demo.mjs
node examples/wasm-node/ssr-middleware.mjs
```

To rebuild the timing harness, export the tree with `git archive HEAD`, compile
a small release executable that calls `escape_html` N times over a string grown
by doubling `"a<&>x"`, and time it with `/usr/bin/time -p`. Subtract a baseline
variant that only measures `input.length()` to remove process startup, and use
the identical harness before and after a change.

## Boundaries

These are historical measurements, not a latency SLA. The input cap in
`src/lib/invariants.mbt` is arithmetic overflow protection plus a shipping cap
of 8,000,000 code units; it is not a resource quota. Callers must apply their
own rate limits.
