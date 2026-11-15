// Runnable cross-language example:  node examples/wasm-node/demo.mjs
// Rebuild the artefact first with:  node scripts/build_wasm.mjs

import assert from "node:assert/strict";
import { loadTextKernel } from "./loader.mjs";

const k = loadTextKernel(process.argv[2]);

assert.equal(k.escape_html("<script>a & b</script>"), "&lt;script&gt;a &amp; b&lt;/script&gt;");
assert.equal(k.escape_attr("x\" onload='y'"), "x&quot; onload=&#39;y&#39;");
assert.equal(k.sanitize_filename("report/2026:Q4?.md"), "report_2026_Q4_.md");
assert.equal(k.normalize_asset_url("http://cdn.example.com/a.png"), "https://cdn.example.com/a.png?fmt=png&v=1");
assert.equal(k.decide_referrer_policy("https://cdn.example.com/a.png"), "no-referrer-when-downgrade");
assert.equal(k.decide_referrer_policy("https://elsewhere.example/a.png"), "no-referrer");
assert.equal(k.str_contains("abc", "b"), "true");
assert.equal(k.str_contains("abc", "z"), "false");

// Never-fail variants agree with the fail-fast API on valid input.
for (const s of ["", "abc", "<a & b>", "中文😀"]) {
  assert.equal(k.escape_html_safe(s), k.escape_html(s));
  assert.equal(k.escape_attr_safe(s), k.escape_attr(s));
  assert.equal(k.sanitize_filename_safe(s), k.sanitize_filename(s));
}

// Never-fail variants agree with the fail-fast API on valid input.
for (const s of ["", "abc", "<a & b>", "中文😀"]) {
  assert.equal(k.escape_html_safe(s), k.escape_html(s));
  assert.equal(k.escape_attr_safe(s), k.escape_attr(s));
  assert.equal(k.sanitize_filename_safe(s), k.sanitize_filename(s));
}

const sep = "|";
assert.equal(k.escape_htmls_joined("<a>|<b>&", sep), "&lt;a&gt;|&lt;b&gt;&amp;");
assert.equal(k.escape_attrs_joined("a\"|b'", sep), "a&quot;|b&#39;");
assert.equal(k.sanitize_filenames_joined("a/b|c:d", sep), "a_b|c_d");
assert.equal(
  k.normalize_asset_urls_joined("http://cdn.example.com/a.png|https://example.org/b.png", sep),
  "https://cdn.example.com/a.png?fmt=png&v=1|https://example.org/b.png",
);

console.log("textkernel WASM example: all assertions passed");
console.log("escape_html  :", k.escape_html("<script>a & b</script>"));
console.log("escape_attr  :", k.escape_attr("x\" onload='y'"));
console.log("sanitise     :", k.sanitize_filename("report/2026:Q4?.md"));
console.log("normalise    :", k.normalize_asset_url("http://cdn.example.com/a.png"));
console.log("batch escape :", k.escape_htmls_joined("<a>|<b>&", sep));
