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
  // The CLI entry point adds WASI-like imports: argv and file-system access
  // (`__moonbit_fs_unstable`), process exit (`__moonbit_sys_unstable`) and a
  // console import. Business exports call none of them, so a stub is enough
  // for library hosts. The module names are read from the import table rather
  // than listed here, so a new CLI option cannot break this loader again.
  // Calling one is a programming error and fails loudly rather than silently.
  const unsupported = new Proxy({}, {
    get: (_target, name) => () => {
      throw new Error(`textkernel Wasm host does not implement ${String(name)}`)
    },
  })
  const imports = { "_": constants, "console": { log: () => {} } };
  for (const imp of WebAssembly.Module.imports(module)) {
    if (imp.module.startsWith("__moonbit_") && !(imp.module in imports)) {
      imports[imp.module] = unsupported;
    }
  }
  const instance = new WebAssembly.Instance(module, imports);
  return instance.exports;
}
