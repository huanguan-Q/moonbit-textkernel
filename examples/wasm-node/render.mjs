// A realistic downstream consumer: rendering untrusted comments into HTML.
//
// This is not a unit test of the library — it is the shape a consumer would
// actually write. It shows the two trust boundaries that matter in practice:
//   * text nodes need escape_html, attribute values need escape_attr;
//   * an oversized input must not trap the host process.
//
// Run:  node examples/wasm-node/render.mjs

import assert from "node:assert/strict";
import { loadTextKernel } from "./loader.mjs";

const k = loadTextKernel(process.argv[2]);

/** Render one comment, or return null when the kernel rejects the input. */
export function renderComment({ author, body }) {
  const safeAuthor = k.escape_attr_safe(author);
  const safeBody = k.escape_html_safe(body);
  // "" is the EmptyOnError failure signal. Never fall back to the raw text:
  // that would reintroduce the injection the kernel exists to prevent.
  if (safeAuthor === "" || safeBody === "") {
    return null;
  }
  return `<div class="comment" data-author="${safeAuthor}"><p>${safeBody}</p></div>`;
}

const normal = renderComment({ author: "Ada", body: "Hello <b>world</b> & friends" });
assert.equal(
  normal,
  '<div class="comment" data-author="Ada"><p>Hello &lt;b&gt;world&lt;/b&gt; &amp; friends</p></div>',
);

const hostile = renderComment({
  author: '" onmouseover="alert(1)',
  body: "<script>alert(document.cookie)</script>",
});
assert.equal(hostile.includes("<script>"), false);
assert.equal(hostile.includes('onmouseover="alert'), false);
assert.equal(hostile.includes("&lt;script&gt;"), true);
assert.equal(hostile.includes("&quot; onmouseover=&quot;"), true);

// A character outside the BMP is two UTF-16 code units and comes through
// whole; only an unpaired half, which a JS caller can still send, becomes `_`.
const emoji = renderComment({ author: "Ada😀", body: "好😀 <b>tail" });
assert.equal(
  emoji,
  '<div class="comment" data-author="Ada😀"><p>好😀 &lt;b&gt;tail</p></div>',
);
assert.equal(k.escape_attr_safe("x\uD800y"), "x_y");

// The shipping cap is 8,000,000 code units. A payload one unit over it used
// to abort inside WASM (a trap that takes down the embedder). The safe export
// now returns "" and the caller can degrade gracefully.
const oversized = "a".repeat(8_000_001);
assert.equal(k.escape_html_safe(oversized), "");
assert.equal(renderComment({ author: "Ada", body: oversized }), null);

// The fail-fast compatibility export still traps — now an explicit choice
// rather than the only behaviour available.
let trapped = false;
try {
  k.escape_html(oversized);
} catch {
  trapped = true;
}
assert.equal(trapped, true, "FailFast should still trap on oversized input");

console.log("render.mjs: downstream consumer assertions passed");
console.log("normal   :", normal);
console.log("hostile  :", hostile);
console.log("oversized: rejected without trapping the host");
console.log("fail-fast: traps by explicit policy choice");
