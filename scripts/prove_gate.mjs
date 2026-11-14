#!/usr/bin/env node
// Gate for `moon prove`.
//
// `moon prove` has three ways to report success while proving nothing, and all
// three have been observed on this repo:
//
//   1. Why3 / z3 / alt-ergo missing  -> the proof-enabled package is *skipped*
//      silently and the command still exits 0.
//   2. A goal fails                  -> the command exits non-zero, but it never
//      prints a "Succeeded:" line; it prints an indented "Failed: N goals
//      proved, M timeout". Anchoring a regex on "^Failed:" misses it.
//   3. A partially failing run still proves most goals, so "goals proved > 0"
//      is true even when the package did not prove.
//
// The only line that answers "did everything verify" is the summary counter
// `N of M packages proved`. This script requires N === M, M > 0, no failure
// line, and at least one proved goal.
//
// Note that the *number* of proved goals is not a stable contract: the stock
// strategy runs `split_vc`, so a goal that closes in an earlier branch never
// gets split, and the same sources report anywhere between 103 and 163 goals
// across runs. The stable facts are `N of M packages proved` and zero
// invalid/timeout/unknown in the report. Treating "163" as the expected number
// would produce false alarms, which is why the check below keys on packages.
//
// It also raises the solver time limits, because the stock ones are low enough
// to make the verdict depend on machine load. `moon` bakes
// `timelimit = 5.000000` plus a strategy that names 0.2 s, 1 s and 2 s per call
// into the config it writes to `_build/verif/why3.conf`; a run that overlaps
// other work can therefore turn a solvable goal into a timeout. Measured on
// this repo: at 24 competing CPU-bound processes the stock config reports
// `0 of 1 packages proved, 157 goals proved, 6 timeout`, while a 5x config
// proves the package. That config cannot be committed (absolute `datadir` /
// `libdir` / solver paths), so `scripts/why3_conf.mjs` derives a scaled copy at
// runtime. Set `PROVE_TIME_SCALE` to change the multiplier (default 5 => 25 s
// default, 5 s and 10 s per call).
//
// Finally, the gate proves against the **machine-integer** prelude, not the
// stock math-integer one. `moon` ships two models for `Int32`:
//
//   * `prelude_proof` (default) has `type t = int` and `in_bounds _ = true`, so
//     "no overflow" is not merely unproved, it is inexpressible. Every theorem
//     is then about mathematical integers that no register can hold.
//   * `prelude_proof_machine_int` has `type t = < range -2^31 .. 2^31-1 >` and
//     every `add`/`sub`/`mul` carries `requires { in_bounds (model x + model y) }`.
//
// Measured on this repo, switching alone is not enough: at stock limits the
// machine prelude reports `0 of 1 packages proved, 345 proved, 143 timeout`,
// because nothing in the contracts bounds the lengths. After the kernels gained
// explicit `proof_require`s against `MAX_CODE_UNITS` (see `src/proof/
// codes.mbt`), the same prelude proves the package outright — 415 goals at the
// 5x limits, 416 at stock (with 6 timeouts), i.e. the gaps were missing range
// hypotheses, not missing prover power.
//
// Set `PROVE_MATH_INT=1` for a fast local loop that only checks the theorem
// shapes; CI must not, since that would prove a different theorem.

import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join, relative } from "node:path";
import { readdirSync, readFileSync, rmSync, existsSync } from "node:fs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
// This repository IS the MoonBit module root (no nested `moonbit/` dir).
const MOONBIT = ROOT;
const VERIF = join(MOONBIT, "_build", "verif");
const GENERATED = join(VERIF, "why3.conf");
const DERIVED = join(VERIF, "why3.local.conf");
const SCALE = Number(process.env.PROVE_TIME_SCALE ?? "5");

// Which `Int32` model the proof talks about. See the header for why this
// defaults to the 32-bit one and what it costs.
const USE_MATH_INT = process.env.PROVE_MATH_INT === "1";
const MACHINE_INT_PRELUDE = join(
  process.env.HOME ?? "",
  ".moon",
  "lib",
  "prelude_proof_machine_int",
);
const PRELUDE_FILE = join(MACHINE_INT_PRELUDE, "moonbit_builtin_prelude.mlw");

if (!USE_MATH_INT && !existsSync(PRELUDE_FILE)) {
  console.error(
    `[prove] the machine-integer prelude is missing: ${PRELUDE_FILE}\n` +
      "[prove] refusing to fall back to the math-integer model, which would\n" +
      "[prove] silently weaken every theorem to unbounded integers. Install a\n" +
      "[prove] toolchain that ships it, or set PROVE_MATH_INT=1 to accept that.",
  );
  process.exit(1);
}

const PROOF_ENV = USE_MATH_INT
  ? { ...process.env }
  : { ...process.env, MOON_PROVE_PRELUDE_OVERRIDE: MACHINE_INT_PRELUDE };

// Why3 keeps its session in `_build/verif/src/<pkg>/.why3harness` and `moon`
// does not clear it when sources change. A session left over from a different
// source set makes Why3 reuse recorded verdicts for goals whose shape has since
// changed, which shows up as a bogus `Failed: N goals proved, 1 timeout` on
// unchanged code. `proof.yml` caches `moonbit/_build`, so a `restore-keys`
// fallback can hand this job a session from another commit — clear it first and
// the gate becomes deterministic.
//
// This also has to happen between the two attempts below: the first attempt
// records timeouts, and a session carrying those verdicts would short-circuit
// the retry into an instant "already failed".
function clearWhy3Sessions(dir) {
  if (!existsSync(dir)) return 0;
  let removed = 0;
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (!entry.isDirectory()) continue;
    if (entry.name === ".why3harness") {
      rmSync(full, { recursive: true, force: true });
      removed += 1;
    } else {
      removed += clearWhy3Sessions(full);
    }
  }
  return removed;
}

// Spawn `moon prove`, echo its output, and fail loudly if the binary itself
// could not be started — that case yields no summary at all, so it must not be
// mistaken for "the package was skipped".
function attempt(args) {
  const run = spawnSync("moon", args, {
    cwd: MOONBIT,
    encoding: "utf8",
    maxBuffer: 64 * 1024 * 1024,
    env: PROOF_ENV,
  });
  if (run.error) {
    console.error(`[prove] could not run \`moon prove\`: ${run.error.message}`);
    process.exit(1);
  }
  const out = `${run.stdout ?? ""}${run.stderr ?? ""}`;
  process.stdout.write(out);
  return { out, status: run.status };
}

function derive(reason) {
  const res = spawnSync(
    process.execPath,
    [join(ROOT, "scripts", "why3_conf.mjs"), "--from", GENERATED, "--to", DERIVED, "--scale", String(SCALE)],
    { encoding: "utf8" },
  );
  process.stdout.write(res.stdout ?? "");
  if (res.status !== 0) {
    process.stderr.write(res.stderr ?? "");
    console.error(`[prove] could not derive a scaled Why3 config (${reason})`);
    process.exit(1);
  }
  return DERIVED;
}

// Returns the list of reasons the run does not count as a proof.
function evaluate(out, status) {
  const problems = [];

  // "N of M packages proved" — the semantic source of truth.
  const pkg = out.match(/(\d+)\s+of\s+(\d+)\s+packages?\s+proved/);
  if (!pkg) {
    problems.push(
      "no `N of M packages proved` summary — the proof package was skipped, " +
        "which happens when Why3/z3/alt-ergo are not on PATH",
    );
    return { problems };
  }

  const proved = Number(pkg[1]);
  const total = Number(pkg[2]);
  const goals = out.match(/(\d+)\s+goals?\s+proved/);
  const goalsProved = goals ? Number(goals[1]) : 0;
  const failedLines = out
    .split("\n")
    .filter((line) => /^\s*(?:Failed|Timeout):/.test(line));

  if (total === 0) problems.push("the summary lists zero proof packages");
  if (proved !== total) problems.push(`${proved} of ${total} packages proved`);
  if (goalsProved === 0) problems.push("no goals were proved");
  if (failedLines.length > 0) problems.push(`unproved goals: ${failedLines[0].trim()}`);

  // A package that sets `proof_enabled` but contributes no goals is in the
  // denominator without carrying any obligation — "2 of 2 packages proved" then
  // reads stronger than the evidence. Measured: a contract-free package prints
  // `Succeeded: 0 goals proved` and the run still exits 0, so this cannot be
  // inferred from the exit status.
  const perPackage = [...out.matchAll(/Succeeded:\s*(\d+)\s+goals?\s+proved/g)].map(
    (m) => Number(m[1]),
  );
  if (perPackage.some((n) => n === 0)) {
    problems.push("a proof-enabled package proved 0 goals (vacuous denominator)");
  }

  // A bare `Timeout` in the failure line means the solver ran out of budget
  // rather than refuting the goal, so a retry at a higher limit is meaningful.
  const timedOut = failedLines.some((line) => /timeout/i.test(line));
  if (status !== 0) problems.push(`moon prove exited ${status}`);

  return { problems, proved, total, goalsProved, timedOut };
}

let cleared = clearWhy3Sessions(VERIF);
if (cleared > 0) console.log(`[prove] cleared ${cleared} stale Why3 session(s)`);
console.log(
  USE_MATH_INT
    ? "[prove] integer model: UNBOUNDED (PROVE_MATH_INT=1 — theorems do not cover 32-bit overflow)"
    : "[prove] integer model: 32-bit machine integers (prelude_proof_machine_int)",
);

let result;

if (existsSync(GENERATED)) {
  const conf = derive("generated config present");
  const { out, status } = attempt(["prove", "--why3-config", conf]);
  result = evaluate(out, status);
} else {
  // First run on a clean tree: `moon prove` writes `_build/verif/why3.conf` as
  // a side effect, so the derived config cannot exist yet. Prove once at the
  // stock limits; only if that fails *on time* do we re-derive and retry.
  console.log("[prove] no generated Why3 config yet — proving once at stock limits");
  const first = attempt(["prove"]);
  result = evaluate(first.out, first.status);

  if (result.problems.length > 0 && result.timedOut && existsSync(GENERATED)) {
    console.error(
      `[prove] stock limits timed out; retrying at ~${SCALE}x time limits ` +
        `(the machine is probably loaded)`,
    );
    clearWhy3Sessions(VERIF);
    const conf = derive("retry after a stock-limit timeout");
    const retry = attempt(["prove", "--why3-config", conf]);
    result = evaluate(retry.out, retry.status);
    if (result.problems.length === 0) {
      console.log("[prove] the scaled limits proved what the stock ones could not");
    }
  }
}

if (result.problems.length > 0) {
  for (const p of result.problems) console.error(`[prove] ${p}`);
  console.error("[prove] FAILED — the verified core is not proven.");
  process.exit(1);
}

// Which packages actually set `proof_enabled`, read from disk.
//
// `moon prove` only prints counts, so "1 of 1 packages" silently means "one
// package happened to opt in" — a reader cannot tell whether the other packages
// were considered and passed, or never entered the denominator at all. Listing
// the names makes the claim self-describing, and comparing the count against the
// summary catches the case where the flag was added or removed without the
// message changing shape.
function proofEnabledPackages(root) {
  const found = [];
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.name === "_build" || entry.name === "node_modules" || entry.name.startsWith(".")) {
        continue;
      }
      const full = join(dir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (entry.name === "moon.pkg" || entry.name === "moon.pkg.json") {
        let text = "";
        try {
          text = readFileSync(full, "utf8");
        } catch (_) {
          continue;
        }
        if (/proof_enabled\s*=\s*true/.test(text)) {
          found.push(relative(root, dir) || ".");
        }
      }
    }
  };
  walk(root);
  return found.sort();
}

// Say what the denominator is. `moon` counts only packages that set
// `proof_enabled`, and this repository has three packages of which one is
// proof-enabled, so a bare "1/1 packages" reads as "the whole project is
// proved". It is not: `src/lib` and `src/demo` are outside the count.
const proofPackages = proofEnabledPackages(MOONBIT);
if (proofPackages.length !== result.total) {
  console.error(
    `[prove] the run proved ${result.total} package(s), but ${proofPackages.length} ` +
      `\`proof_enabled\` package(s) exist on disk: ${proofPackages.join(", ") || "(none)"}.`,
  );
  console.error(
    "[prove] the summary and the sources disagree — check whether a package was " +
      "added or the flag was toggled, and update this gate deliberately.",
  );
  process.exit(1);
}

console.log(
  `[prove] OK — ${result.proved}/${result.total} proof-enabled package(s) ` +
    `[${proofPackages.join(", ")}], ${result.goalsProved} goals proved. ` +
    `Packages without \`proof_enabled\` are not in this count and carry no ` +
    `proof obligations here.`,
);
