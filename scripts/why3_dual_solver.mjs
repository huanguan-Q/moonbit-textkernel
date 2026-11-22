#!/usr/bin/env node
// Derive a portable Why3 config with the verified dual-solver strategy.
//
// The locally verified `_build/verif/why3.conf` registers both Alt-Ergo and Z3
// and gives `MoonBit_Auto` four literal per-call limits plus two fractions.
// Freshly generated configs from newer MoonBit CLIs only contain Z3, which
// makes the proof gate time out on CI runners even with a modern Z3 binary.
// This script keeps the machine-specific fields from the generated config but
// rebuilds the prover table and strategy in the verified shape, using the
// solver binaries actually present on PATH.
//
// The output is still machine-specific (absolute paths), so it is written to
// `_build/verif/why3.dual.conf` and never committed. `why3_conf.mjs` then
// derives the scaled, runnable config from it.

import { spawnSync } from "node:child_process";
import { accessSync, constants, readFileSync, writeFileSync } from "node:fs";
import { isAbsolute, join, resolve } from "node:path";

const args = process.argv.slice(2);
const opt = (name, fallback) => {
  const i = args.indexOf(`--${name}`);
  return i === -1 ? fallback : args[i + 1];
};
const from = opt("from");
const to = opt("to");
const altErgOverride = opt("alt-ergo");
const z3Override = opt("z3");
const quiet = args.includes("--quiet");

if (!from || !to) {
  console.error(
    "usage: why3_dual_solver.mjs --from <generated conf> --to <output> " +
      "[--alt-ergo PATH] [--z3 PATH] [--quiet]",
  );
  process.exit(2);
}

const findOnPath = (name) => {
  const candidates = (process.env.PATH ?? "").split(":").filter(Boolean);
  for (const dir of candidates) {
    const full = isAbsolute(dir) ? join(dir, name) : resolve(dir, name);
    try {
      accessSync(full, constants.X_OK);
      return full;
    } catch {
      // keep looking
    }
  }
  return null;
};

const solverVersion = (path) => {
  const res = spawnSync(path, ["--version"], { encoding: "utf8" });
  if (res.error) return null;
  const text = `${res.stdout ?? ""}${res.stderr ?? ""}`;
  const m = text.match(/\d+\.\d+\.\d+(?:[.+~][\w.+-]+)?/);
  return m ? m[0] : null;
};

const altErgPath = altErgOverride ?? findOnPath("alt-ergo");
const z3Path = z3Override ?? findOnPath("z3");
if (!altErgPath || !z3Path) {
  console.error(
    `[dual-solver] both alt-ergo and z3 must be on PATH ` +
      `(found alt-ergo=${altErgPath ?? "no"}, z3=${z3Path ?? "no"})`,
  );
  process.exit(1);
}
const altErgVersion = solverVersion(altErgPath);
const z3Version = solverVersion(z3Path);
if (!altErgVersion || !z3Version) {
  console.error(
    `[dual-solver] could not parse versions ` +
      `(alt-ergo=${altErgVersion ?? "?"}, z3=${z3Version ?? "?"})`,
  );
  process.exit(1);
}

const src = readFileSync(resolve(from), "utf8");
const field = (key) => {
  const m = src.match(new RegExp(`^${key}\\s*=\\s*(.*)$`, "m"));
  return m ? m[1].trim() : null;
};
const mainKeys = [
  "magic",
  "datadir",
  "libdir",
  "memlimit",
  "running_provers_max",
  "timelimit",
];
const values = Object.fromEntries(mainKeys.map((k) => [k, field(k)]));
const missing = mainKeys.filter((k) => values[k] === null);
if (missing.length > 0) {
  console.error(`[dual-solver] generated config is missing: ${missing.join(", ")}`);
  process.exit(1);
}

const quote = (s) => `"${s.replace(/\\/g, "\\\\").replace(/"/g, '\\"')}"`;
const prover = (name, path, version) =>
  [`[partial_prover]`, `name = ${quote(name)}`, `path = ${quote(path)}`, `version = ${quote(version)}`, ""].join("\n");

const out = [
  "[main]",
  ...mainKeys.map((k) => `${k} = ${values[k]}`),
  "",
  prover("Alt-Ergo", altErgPath, altErgVersion),
  prover("Z3", z3Path, z3Version),
  "[strategy]",
  "code = \"start:",
  `c Alt-Ergo,${altErgVersion} .2 1000`,
  `c Z3,${z3Version} .2 1000`,
  `c Alt-Ergo,${altErgVersion} 1 1000 | Z3,${z3Version} 1 1000`,
  "t compute_specified start",
  "t split_vc start",
  `c Alt-Ergo,${altErgVersion} 2 4000 | Z3,${z3Version} 2 4000`,
  "\"",
  "desc = \"Automatic@ run@ of@ provers@ and@ most@ useful@ transformations\"",
  "name = \"MoonBit_Auto\"",
  "shortcut = \"4\"",
  "",
].join("\n");

const dest = resolve(to);
writeFileSync(dest, out);
if (!quiet) {
  console.log(
    `[dual-solver] ${dest}: Alt-Ergo ${altErgVersion} (${altErgPath}), ` +
      `Z3 ${z3Version} (${z3Path})`,
  );
}
