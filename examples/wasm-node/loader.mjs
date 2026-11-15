// Runtime-agnostic loader for the MoonBit WASM-GC export package.
//
// `use-js-builtin-string` makes the linker emit:
//   * `wasm:js-string` builtin imports  -> provided by the host via
//     `new WebAssembly.Module(bytes, { builtins: ["js-string"] })`
//   * imported string constants under module "_", where each field name IS
//     the constant's value. Chrome's `importedStringConstants` compile option
//     can synthesise these, but Node 22 does not implement that option. Reading
//     the import table and supplying the values as plain JS globals works on
//     both, and needs no hard-coded constant list that could drift.

import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const DEFAULT_WASM = resolve(HERE, "../../wasm/textkernel.wasm");

export function loadTextKernel(wasmPath = DEFAULT_WASM) {
  const bytes = readFileSync(wasmPath);
  const module = new WebAssembly.Module(bytes, { builtins: ["js-string"] });

  const constants = {};
  for (const imp of WebAssembly.Module.imports(module)) {
    if (imp.module === "_" && imp.kind === "global" && !(imp.name in constants)) {
      constants[imp.name] = imp.name;
    }
  }
  const instance = new WebAssembly.Instance(module, { "_": constants });
  return instance.exports;
}
