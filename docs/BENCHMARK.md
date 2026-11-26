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

## Joined lists: quadratic concatenation in `join_joined`

The fix above covered the three builders and missed the batch glue.
`join_joined` still concatenated in a loop (`out = out + sep + item`), so the
joined-list path — `split_joined`, escape each element, `join_joined` — was
quadratic on the native backend. It went unnoticed because JS hosts make
string concatenation cheap: the same path is linear there.

Measured after the fix on `moon 0.1.20261119`, native release, 80-character
comments joined with `|`; best of five, including process start:

| Items | Before | After |
|---:|---:|---:|
| 1,000 | 32 ms | 21 ms |
| 4,000 | 142 ms | 22 ms |
| 16,000 | 2,245 ms | 31 ms |
| 64,000 | not measured | 63 ms |

Each doubling of the list used to take about four times as long; it now takes
a few milliseconds more.

## Throughput of the escapers

400 escapes (200 × `escape_html` and 200 × `escape_attr`) over 524,288 UTF-16
units of mixed HTML and CJK text, native release, net of a baseline that only
reads the length: about 450 MB/s, counting two bytes per code unit. The
surrogate pairing test costs about 3%; a fast path for the units below the
surrogate block keeps it that low. In a JS host the same WASM exports reach
125–160 MB/s where a plain `String.replace` reaches 280–325 MB/s, so the WASM
artefact is not the way to make a JS program faster.

## Reproduce

```bash
moon test --target all
node scripts/build_wasm.mjs
node examples/wasm-node/demo.mjs
node examples/wasm-node/ssr-middleware.mjs
```

To rebuild the timing harness, export the tree with `git archive HEAD`, add a
small executable package that builds N copies of a string, joins them, splits
them, escapes each and joins again, build it with
`moon build --target native --release`, and time it with `/usr/bin/time -p`.
Use the identical harness before and after a change.

## Boundaries

These are historical measurements, not a latency SLA. The input cap in
`src/lib/invariants.mbt` is arithmetic overflow protection plus a shipping cap
of 8,000,000 code units; it is not a resource quota. Callers must apply their
own rate limits.
