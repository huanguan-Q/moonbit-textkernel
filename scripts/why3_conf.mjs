#!/usr/bin/env node
// Derive a portable Why3 configuration from the one `moon prove` generates.
//
// Why this exists
// ---------------
// `moon` bakes its Why3 configuration template into the binary
// (`timelimit = 5.000000`, `running_provers_max = 16`, strategy `MoonBit_Auto`)
// and writes it to `_build/verif/why3.conf` on first use. That file cannot be
// committed: it carries absolute, machine-specific paths in `datadir`,
// `libdir` and each `[partial_prover] path`. So the only way to raise the time
// limits is to derive a new file at runtime, which is what this script does.
//
// Why raising them is worth doing
// -------------------------------
// With the stock configuration the effective ceiling per solver call is a
// couple of seconds: `[main] timelimit = 5` and the strategy asks for `.2`
// (20% of the default, i.e. 1 s), `1` and `2` literal seconds. Observations on
// this box that constrain the design:
//
//   * Sub-second limits do not behave the way one would guess: setting the
//     default to `0.000001`, and every per-call limit to `0.05`, still proved
//     every goal. A run like that is not evidence that the limits are tight.
//     The session file records the strategy's `.2` verbatim as
//     `timelimit="0.2"`, so `.2` is treated here as an absolute value rather
//     than a percentage of the default. It is left alone regardless, because
//     every rewrite below is non-decreasing under either reading.
//   * The config is genuinely authoritative: pointing the prover paths at
//     nonexistent binaries turns the run into `Failed: 0 goals proved, 837
//     unknown`. So a derived file really is used, and the silenter failure mode
//     ("config ignored") is ruled out.
//   * Scaling `[main] timelimit` alone is not enough: it leaves the literal `1`
//     and `2` per-call values untouched, and the strategy specifies a limit on
//     every call. Each of those has to be scaled too.
//
// This script therefore rewrites `[main] timelimit` and every literal per-call
// limit, and leaves `.`-prefixed values alone so they follow the default.
//
// It is deliberately paranoid about template drift: if `moon` changes the
// template such that nothing matches, this exits non-zero instead of writing a
// file that looks derived but is not.

import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : args[i + 1];
};

const from = opt("from");
const to = opt("to");
const scale = Number(opt("scale", "5"));
const quiet = args.includes("--quiet");

if (!from || !to) {
  console.error("usage: why3_conf.mjs --from <generated conf> --to <output> [--scale N]");
  process.exit(2);
}
if (!Number.isFinite(scale) || scale < 1) {
  console.error(`[why3-conf] --scale must be a finite number >= 1, got ${opt("scale")}`);
  process.exit(2);
}

const src = readFileSync(resolve(from), "utf8");
const lines = src.split("\n");

// One `c` segment looks like `c Z3,4.15.4 .2 1000` (the `c` only on the first
// segment of a line) or `Z3,4.15.4 2 4000` after a `|`. It is matched as a
// whole, not by scanning for numbers: an earlier attempt anchored on the
// trailing memory limit and, on a segment that had lost that field, happily
// mistook the prover version `4.15.4` for a time limit and emitted `NaN`.
const SEGMENT =
  /^(\s*)(c\s+)?([A-Za-z0-9_.+-]+,[0-9][A-Za-z0-9_.+-]*)(\s+)([.%]?[0-9.]+)(\s+)([0-9]+)(\s*)$/;

let scaledCalls = 0;
let fractionCalls = 0;
let mainScaled = 0;
// Every `c` segment must be accounted for. Counting only the ones that were
// rewritten would let a segment in an unexpected shape slip through with its
// stock limit untouched while the totals still look healthy.
let expectedCalls = 0;
const unknownSegments = [];

const scaled = (raw) => {
  const value = Number(raw) * scale;
  if (!Number.isFinite(value)) return null;
  // Sub-second limits are read as 0 by Why3 (= unlimited), so never emit one.
  return String(Math.max(1, Math.round(value)));
};

const out = lines.map((line) => {
  const main = line.match(/^timelimit(\s*)=(\s*)([0-9.]+)\s*$/);
  if (main) {
    mainScaled += 1;
    return `timelimit${main[1]}=${main[2]}${scaled(main[3])}`;
  }
  if (!line.startsWith("c ")) return line;

  const segments = line.split("|");
  expectedCalls += segments.length;

  const rebuilt = segments.map((segment) => {
    const m = segment.match(SEGMENT);
    if (!m) {
      unknownSegments.push(segment.trim());
      return segment;
    }
    const [, lead, c, prover, ws1, tl, ws2, mem, trail] = m;
    if (tl.startsWith(".") || tl.startsWith("%")) {
      // A fraction follows `[main] timelimit`, which is scaled above.
      fractionCalls += 1;
      return segment;
    }
    const next = scaled(tl);
    if (next === null) {
      unknownSegments.push(segment.trim());
      return segment;
    }
    scaledCalls += 1;
    return `${lead}${c ?? ""}${prover}${ws1}${next}${ws2}${mem}${trail}`;
  });

  return rebuilt.join("|");
});

// ---------- invariants ----------
// Everything below guards the same failure this repo keeps hitting: a tool that
// silently does nothing and still reports success.

const problems = [];
if (mainScaled !== 1) {
  problems.push(`expected exactly one \`[main] timelimit\`, found ${mainScaled}`);
}
if (scaledCalls === 0) {
  problems.push(
    "no literal per-call time limits were rewritten — the `c` line format in " +
      "the generated config no longer matches, so this file would be a copy " +
      "that only looks derived",
  );
}
if (scaledCalls + fractionCalls !== expectedCalls) {
  problems.push(
    `only ${scaledCalls + fractionCalls} of ${expectedCalls} per-call limits were ` +
      "recognized — at least one `c` segment is in a shape this script does not " +
      "understand, and would silently keep its stock limit",
  );
}
if (unknownSegments.length > 0) {
  problems.push(
    `unrecognized \`c\` segment(s): ${unknownSegments.map((s) => JSON.stringify(s)).join(", ")}`,
  );
}
if (/^timelimit\s*=\s*(?:NaN|null|Infinity)\s*$/m.test(out.join("\n"))) {
  problems.push("a scaled time limit is not a number");
}
if (out.length !== lines.length) {
  problems.push(`line count changed: ${lines.length} -> ${out.length}`);
}

// Only intended lines may differ.
const unintended = [];
for (let i = 0; i < lines.length; i += 1) {
  if (out[i] === lines[i]) continue;
  const isTimelimit = /^timelimit\s*=/.test(lines[i]);
  const isCall = lines[i].startsWith("c ");
  if (!isTimelimit && !isCall) unintended.push(i + 1);
}
if (unintended.length > 0) {
  problems.push(`unintended edits on line(s) ${unintended.join(", ")}`);
}

// Paths must survive verbatim: they are what makes the file machine-specific,
// and corrupting one would make Why3 look like it proved something it did not.
for (const key of ["datadir", "libdir", "memlimit", "running_provers_max", "magic"]) {
  const pick = (text) => (text.match(new RegExp(`^${key}\\s*=.*$`, "m")) || [""])[0];
  if (pick(src) !== pick(out.join("\n"))) {
    problems.push(`\`${key}\` changed — paths and solver budget must pass through verbatim`);
  }
}
const proverPaths = (src.match(/^path\s*=\s*".*"$/gm) || []).join("\n");
const outPaths = (out.join("\n").match(/^path\s*=\s*".*"$/gm) || []).join("\n");
if (proverPaths !== outPaths || proverPaths === "") {
  problems.push("solver `path` entries changed or vanished");
}
const strategyNames = (text) => (text.match(/^name\s*=\s*"MoonBit_Auto"$/gm) || []).length;
if (strategyNames(src) !== 1 || strategyNames(out.join("\n")) !== 1) {
  problems.push("the `MoonBit_Auto` strategy must exist exactly once");
}

if (problems.length > 0) {
  for (const p of problems) console.error(`[why3-conf] ${p}`);
  console.error("[why3-conf] refusing to write a derived config.");
  process.exit(1);
}

writeFileSync(resolve(to), out.join("\n"));

if (!quiet) {
  console.log(
    `[why3-conf] scale ${scale}x: [main] timelimit -> ${out.find((l) => /^timelimit/.test(l))?.split("=")[1].trim()}, ` +
      `${scaledCalls} per-call limit(s) scaled, ${fractionCalls} fraction(s) left to follow the default`,
  );
}
