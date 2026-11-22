// A realistic downstream consumer: SSR rendering + upload filename hygiene.
// Run: node examples/wasm-node/ssr-middleware.mjs
//
// This is the shape a web framework or UGC pipeline would use: the framework
// owns routing, auth and rate limits; textkernel owns the trust-boundary
// transformations that are easy to get wrong.

import assert from "node:assert/strict";
import { loadTextKernel } from "./loader.mjs";

const k = loadTextKernel(process.argv[2]);

function renderComment(comment, author) {
  const safeBody = k.escape_html_safe(comment);
  const safeTitle = k.escape_attr_safe(author);
  return `<article data-author="${safeTitle}"><p>${safeBody}</p></article>`;
}

function renderCommentBatch(comments) {
  // The joined ABI crosses Wasm once for the whole list.
  return k.escape_htmls_joined(comments.join("|"), "|").split("|");
}

function prepareUpload(originalName) {
  const safeName = k.sanitize_filename_safe(originalName);
  assert.notEqual(safeName, "");
  return `uploads/${safeName}`;
}

function assetUrl(raw) {
  const safeUrl = k.normalize_asset_url(raw);
  const policy = k.decide_referrer_policy(safeUrl);
  return { url: safeUrl, referrerPolicy: policy };
}

const html = renderComment(
  `<script>alert("x")</script> & hello`,
  `O'Neil "admin"`,
);
assert.equal(
  html,
  `<article data-author="O&#39;Neil &quot;admin&quot;"><p>&lt;script&gt;alert("x")&lt;/script&gt; &amp; hello</p></article>`,
);

// The joined ABI works on UTF-16 code units and maps lone surrogates to '_',
// so non-BMP characters must go through the single-value exports instead.
const rendered = renderCommentBatch(["<b>a</b>", "x & y", "中文"]);
assert.deepEqual(rendered, ["&lt;b&gt;a&lt;/b&gt;", "x &amp; y", "中文"]);

const uploadPath = prepareUpload("../../etc/passwd?.png");
assert.equal(uploadPath, "uploads/.._.._etc_passwd_.png");

const asset = assetUrl("http://cdn.example.com/a.png");
assert.equal(asset.url, "https://cdn.example.com/a.png?fmt=png&v=1");
assert.equal(asset.referrerPolicy, "no-referrer-when-downgrade");

console.log(JSON.stringify({ html, rendered, uploadPath, asset }, null, 2));
