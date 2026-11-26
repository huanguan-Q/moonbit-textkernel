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

// The joined ABI goes through the same escapers as the single-value exports,
// so a character outside the BMP survives either way. It does slice by
// UTF-16 code unit, so the separator must not split a character: use one the
// content cannot contain.
const rendered = renderCommentBatch(["<b>a</b>", "x & y", "中文", "好😀 <i>"]);
assert.deepEqual(rendered, ["&lt;b&gt;a&lt;/b&gt;", "x &amp; y", "中文", "好😀 &lt;i&gt;"]);

// Path separators go, and so does every other way of naming something other
// than a file: `..` is a directory, a trailing dot vanishes on Windows, and
// `nul.txt` is a device.
const uploadPath = prepareUpload("../../etc/passwd?.png");
assert.equal(uploadPath, "uploads/.._.._etc_passwd_.png");
assert.equal(prepareUpload(".."), "uploads/file");
assert.equal(prepareUpload("report."), "uploads/report_");
assert.equal(prepareUpload("nul.txt"), "uploads/nul_.txt");
assert.equal(prepareUpload("报告😀.pdf"), "uploads/报告😀.pdf");

// The allow-list applies to the URL's own host. A CDN address that is only
// part of somebody else's URL is left alone and gets the strict policy.
const lookAlike = assetUrl("https://cdn.example.com.evil.com/a.png");
assert.equal(lookAlike.url, "https://cdn.example.com.evil.com/a.png");
assert.equal(lookAlike.referrerPolicy, "no-referrer");

const asset = assetUrl("http://cdn.example.com/a.png");
assert.equal(asset.url, "https://cdn.example.com/a.png?fmt=png&v=1");
assert.equal(asset.referrerPolicy, "no-referrer-when-downgrade");

console.log(JSON.stringify({ html, rendered, uploadPath, asset }, null, 2));
