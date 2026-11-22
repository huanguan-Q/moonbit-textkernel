# Security policy

## Scope

textkernel is a library for text crossing a trust boundary. It covers:

- HTML text and attribute escaping.
- Filename sanitization.
- Asset URL normalization and host allow-list based Referrer-Policy selection.
- Bounded batch processing of those operations.

It does **not** provide authorization, full HTML sanitization, URL parsing,
rate limiting, filesystem sandboxing, or secret management. Findings in those
areas belong to the calling application.

## Supported versions

| Version | Supported |
|---|---|
| 0.1.x (latest patch) | Yes |
| Older 0.1.x patches | No; upgrade to the latest patch |
| Unpublished commits | No |

Only the latest published patch receives security fixes. Breaking fixes follow
the major-version path in `docs/API-STABILITY.md`.

## Reporting a vulnerability

Use GitHub's private vulnerability reporting for this repository:

<https://github.com/huanguan-Q/moonbit-textkernel/security/advisories/new>

Do **not** open a public issue for an exploitable finding. Include:

- affected version and backend (wasm / wasm-gc / js / native),
- a minimal input that demonstrates the problem,
- the expected and actual output,
- whether the `*_safe` API is affected.

Please do not include real credentials, customer data or private competition
material in the report.

## Response expectations

- Acknowledge within 3 working days.
- Triage and decide severity within 7 working days.
- Ship a fix or a documented mitigation within 30 days for high/critical
  findings; lower severity issues may wait for the next planned release.
- Credit reporters in `CHANGELOG.md` unless they ask to remain anonymous.

## Severity guide

- **Critical**: output escaping can be bypassed with attacker-controlled input
  on a default configuration, or the library executes input.
- **High**: a bound check can be bypassed, or a `*_safe` function can trap on
  attacker-controlled input.
- **Medium**: incorrect result for a clearly documented edge case, with a
  workaround.
- **Low**: misleading documentation or non-security API inconsistency.

## Trusted seam reminder

The proved kernels operate on `FixedArray[Int32]` UTF-16 code units; the
shipped `String` layer is pinned by a conformance corpus and runtime invariant
checks. A finding in that seam is in scope. A change in solver verdicts alone
is not a security issue.
