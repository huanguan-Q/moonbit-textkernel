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

// A character outside the BMP is two UTF-16 code units, and it is copied whole.
assert.equal(k.escape_html("中文😀 <b>"), "中文😀 &lt;b&gt;");
assert.equal(k.escape_attr("a\"😀'"), "a&quot;😀&#39;");
assert.equal(k.sanitize_filename("报告😀.pdf"), "报告😀.pdf");

// An unpaired surrogate half has no character to copy and becomes `_`. Such a
// half can be written in JS but not in MoonBit source, so a JS host is the
// only place where that path can be exercised end to end.
assert.equal(k.escape_html_safe("a\uD800b"), "a_b");
assert.equal(k.escape_attr_safe("a\uDC00b"), "a_b");
// Two leading halves and a trailing one: only the second leading half is paired.
assert.equal(k.escape_html_safe("a\uD83D\uD83D\uDE00b"), "a_😀b");
assert.equal(k.sanitize_filename_safe("a\uD83D\uD83D\uDE00b"), "a_😀b");

// A file name is never a directory reference, never holds a control character,
// and a Windows device name gets a marker.
assert.equal(k.sanitize_filename(".."), "file");
assert.equal(k.sanitize_filename("a\u0000b."), "a_b_");
assert.equal(k.sanitize_filename("nul.txt"), "nul_.txt");

// The allow-list is applied to the URL's own host, a missing parameter goes
// before the fragment, and letter case does not make another host.
const lookAlike = "https://cdn.example.com.evil.com/a.png";
assert.equal(k.normalize_asset_url(lookAlike), lookAlike);
assert.equal(k.decide_referrer_policy(lookAlike), "no-referrer");
assert.equal(
  k.normalize_asset_url("https://cdn.example.com/a.png#frag"),
  "https://cdn.example.com/a.png?fmt=png&v=1#frag",
);
assert.equal(
  k.normalize_asset_url("HTTP://CDN.EXAMPLE.COM/a.png"),
  "https://CDN.EXAMPLE.COM/a.png?fmt=png&v=1",
);

const sep = "|";
assert.equal(k.escape_htmls_joined("<a>|<b>&", sep), "&lt;a&gt;|&lt;b&gt;&amp;");
assert.equal(k.escape_attrs_joined("a\"|b'", sep), "a&quot;|b&#39;");
assert.equal(k.sanitize_filenames_joined("a/b|c:d", sep), "a_b|c_d");
assert.equal(k.escape_htmls_joined("😀|<b>&", sep), "😀|&lt;b&gt;&amp;");
assert.equal(
  k.normalize_asset_urls_joined("http://cdn.example.com/a.png|https://example.org/b.png", sep),
  "https://cdn.example.com/a.png?fmt=png&v=1|https://example.org/b.png",
);

console.log("textkernel WASM example: all assertions passed");
console.log("escape_html  :", k.escape_html("<script>a & b</script>"));
console.log("escape_attr  :", k.escape_attr("x\" onload='y'"));
console.log("non-BMP      :", k.escape_html("中文😀 <b>"), "|", k.escape_html_safe("a\uD800b"));
console.log("sanitise     :", k.sanitize_filename("report/2026:Q4?.md"), "|", k.sanitize_filename(".."));
console.log("normalise    :", k.normalize_asset_url("http://cdn.example.com/a.png"));
console.log("batch escape :", k.escape_htmls_joined("<a>|<b>&", sep));
