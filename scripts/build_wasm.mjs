#!/usr/bin/env node
// Build the WASM-GC export package and stage the artefact under wasm/.
//
// The committed .wasm is a convenience copy so the JS example runs straight
// after a clone. CI always rebuilds and runs the example against the fresh
// artefact, so a stale committed copy can never masquerade as working code.

import { spawnSync } from "node:child_process";
import { copyFileSync, mkdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
// Overridable because some sandboxes restrict writes inside the source tree.
const TARGET_DIR = resolve(process.env.MOON_TARGET_DIR ?? join(ROOT, "_build"));
const SRC = join(TARGET_DIR, "wasm-gc/release/build/src/main/main.wasm");
const DST = join(ROOT, "wasm/textkernel.wasm");

const run = spawnSync("moon", ["build", "--target", "wasm-gc", "--release", "--target-dir", TARGET_DIR], {
  cwd: ROOT,
  stdio: "inherit",
});
if (run.status !== 0) {
  console.error(`[wasm] moon build failed (status ${run.status})`);
  process.exit(run.status ?? 1);
}

const bytes = readFileSync(SRC);
const ex = WebAssembly.Module.exports(new WebAssembly.Module(bytes)).map((e) => e.name);
const expected = [
  "escape_html", "escape_attr", "sanitize_filename", "normalize_asset_url",
  "decide_referrer_policy", "str_contains", "escape_htmls_joined",
  "escape_attrs_joined", "sanitize_filenames_joined", "normalize_asset_urls_joined",
];
const missing = expected.filter((n) => !ex.includes(n));
if (missing.length) {
  console.error(`[wasm] missing exports: ${missing.join(", ")}`);
  process.exit(1);
}

mkdirSync(dirname(DST), { recursive: true });
copyFileSync(SRC, DST);
console.log(`[wasm] ${statSync(DST).size} bytes -> ${DST}`);
console.log(`[wasm] ${ex.length} exports: ${ex.join(", ")}`);
