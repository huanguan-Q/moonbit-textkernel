---
name: textkernel
description: Use the verified MoonBit textkernel CLI to escape HTML, sanitize filenames, normalize asset URLs, and choose Referrer-Policy for text crossing a trust boundary.
---

# textkernel

A small MoonBit kernel for text that crosses a trust boundary. Safety
properties of the core routines are discharged by `moon prove`; the shipped
`String` layer checks its own output invariants at runtime.

## When to use

Use this skill when a task needs any of:

- HTML text or attribute escaping before rendering untrusted content.
- Filename sanitization for uploads or generated artifacts.
- Asset URL normalization (force HTTPS, append missing query parameters).
- Host allow-list based Referrer-Policy selection.
- Deterministic JSON-lines output from a sandboxed Wasm command.

Do not use it for full HTML sanitization, URL parsing, authorization, or
resource limiting: see Boundaries below.

## Run the Wasm / moonx command

```bash
moonx huanguan-Q/textkernel/src/main@0.2.0 -- --help
moonx huanguan-Q/textkernel/src/main@0.2.0 -- escape-html '<script>x</script>'
moonx huanguan-Q/textkernel/src/main@0.2.0 -- normalize-asset-url \
  --hosts cdn.example.com --params fmt=png,v=1 \
  'http://cdn.example.com/a.png'
```

Use the explicit `src/main` package path: mooncakes.io builds the prebuilt Wasm
asset for that package, while the bare module coordinate has none.

Each command prints one JSON line with `command` and `output`, or `command`
and `error`. `--hosts` and `--params` take comma-separated values; omitting
both keeps the historical RFC 2606 example configuration.

**Check the exit status, not only the output.** It is `0` for a line with
`output` and `2` for a line with `error`; both `moonx` and the native CLI
behave the same. When a shell command runs it, test the status:

```bash
out=$(moonx huanguan-Q/textkernel/src/main@0.2.0 -- normalize-asset-url \
  --hosts cdn.example.com --params 'fmt=png,x#y' https://cdn.example.com/a.png)
# exit status 2; out is {"command":"normalize-asset-url","error":"Invalid Config: x#y"}
```

A `--params` piece that could change the structure of the URL is **refused**:
an empty piece, one starting with `=`, and one containing `#`, whitespace or a
control character. The `error` names the piece. It is refused only for a URL on
a configured host; any other URL is returned unchanged with status `0`. An
unknown command and a missing option value also exit with `2`. Do not put a
raw or unescaped value into `--params`: take `w=800` pairs from a trusted
source, and treat status `2` as a failure rather than retrying the same input.

## Native CLI with stdin

```bash
moon run src/cli --target native -- escape-html < untrusted.txt
moon run src/cli --target native -- sanitize-filename --input 'a/b:c?.png'
```

The native wrapper shares the Wasm command set and reads stdin when no input
argument is present. stdin is read as **one** input, not as a stream of lines;
to process a list, call once per line. File input is shell redirection, not an
in-process file reader.

## Library use with explicit configuration

```moonbit
let config = @lib.create_asset_config(
  ["cdn.internal.example"],
  ["w=800", "auto=1"],
)
let url = @lib.normalize_asset_url_with_config(
  "http://cdn.internal.example/a.png",
  config,
)
```

The no-suffix functions (`normalize_asset_url`, `decide_referrer_policy`,
`ensure_asset_params`) remain wrappers around the default configuration, so
existing callers keep their historical behaviour. The `*_result` forms return
`Result[String, CoreError]` and never abort; they accept the empty string and
every input up to `MAX_SHIPPING_CODE_UNITS`.

A host entry is a host name, without scheme, path or port. It matches that
host and its subdomains of an `http`/`https` URL, in any letter case, and
nothing else. A missing parameter is added to the query, before any
`#fragment`.

Text keeps its characters: one outside the BMP (an emoji, a CJK Extension B
ideograph) is copied whole by every routine. A file name comes back as
something that can be created as a file: `..` becomes `file`, control
characters and unpaired surrogate halves become `_`, and a Windows device name
such as `NUL.txt` gets a marker (`NUL_.txt`).

## Verification

```bash
moon fmt --check
moon check --target all --deny-warn
moon test --target all
node scripts/prove_gate.mjs
node scripts/build_wasm.mjs
```

Build helpers are `scripts/build_wasm.mjs`, `scripts/prove_gate.mjs`,
`scripts/why3_conf.mjs` and `scripts/why3_dual_solver.mjs`. The proof gate runs
with Alt-Ergo + Z3 and the 32-bit machine-integer prelude.

## Boundaries

- The proved kernels operate on `FixedArray[Int32]` UTF-16 code units;
  `src/proof/conform.mbt` pins them to the shipped `String` API over an
  enumerated corpus. This is corpus equivalence, not a theorem about `String`.
- Only `src/proof` is in the proof denominator. `src/lib` relies on runtime
  invariant checks.
- The input bound is arithmetic overflow protection and a shipping cap, not a
  resource quota; callers must apply their own rate limits.
- The Wasm ABI uses `wasm:js-string` builtins and has no linear-memory variant.
  Non-JS hosts cannot call it directly; see `docs/ABI-EVALUATION.md`.
- Escaping and filename sanitization do not replace a full HTML sanitizer or a
  URL parser.
- Not every rule is proved. Stripping a port from a host, parsing the query,
  trailing dots and spaces, and Windows device names are covered by tests and
  by the runtime invariant, not by a proof.
- The host rule, the filename character rule and the surrogate rule are proved
  for the code-unit kernels; a proof is about the specification, so read
  `src/proof/spec.mbtp` as the statement of what is guaranteed.
