///|
/// Black-box tests for characters outside the BMP.
///
// A character outside the BMP is two UTF-16 code units, a leading and a
// trailing surrogate. Every routine in the library treats such a pair as one
// character and copies it whole; before, each half was replaced with `_`, so
// an emoji or a CJK Extension B ideograph became `__`.
//
// An *unpaired* half still becomes `_`. It cannot be written in MoonBit source
// — `"\u{D800}"` is rejected by the compiler, and slicing snaps to character
// boundaries — so a MoonBit program never holds one. It can arrive from a JS
// host: `examples/wasm-node/demo.mjs` sends one through the WASM exports, and
// `src/proof/escape.mbt` exercises the kernel on raw code units.

///|
test "[non-bmp] the escapers copy a character outside the BMP as it is" {
  assert_eq(
    @lib.escape_html("中文😀, 𠮷, 🇯🇵"),
    "中文😀, 𠮷, 🇯🇵",
  )
  assert_eq(@lib.escape_attr("<😀>&\"'"), "&lt;😀&gt;&amp;&quot;&#39;")
  // Four characters outside the BMP, joined by zero-width joiners.
  assert_eq(
    @lib.escape_html("👨‍👩‍👧<b>"),
    "👨‍👩‍👧&lt;b&gt;",
  )
}

///|
test "[non-bmp] the characters above the surrogate block are ordinary ones" {
  // U+E000..U+FFFF are BMP characters that sit above the surrogate block, so
  // they do not take the fast path of the escapers. They are not surrogates
  // and must come through untouched.
  let high = "\u{E000}\u{F8FF}\u{FFFD}\u{FFFE}\u{FFFF}"
  assert_eq(@lib.escape_html(high), high)
  assert_eq(@lib.escape_attr(high), high)
  assert_eq(@lib.sanitize_filename(high + ".txt"), high + ".txt")
}

///|
test "[non-bmp] the runtime mirrors accept them" {
  assert_true(@lib.html_is_escaped(@lib.escape_html("中文😀<>&")))
  assert_true(@lib.attr_is_escaped(@lib.escape_attr("中文😀\"'")))
  assert_true(
    @lib.filename_is_sanitized(@lib.sanitize_filename("中文😀/x")),
  )
}

///|
test "[non-bmp] the joined batch path goes through the same routines" {
  assert_eq(
    @lib.join_joined(
      @lib.quick_batch_escape_htmls(@lib.split_joined("😀|<b>", "|")),
      "|",
    ),
    "😀|&lt;b&gt;",
  )
  assert_eq(
    @lib.join_joined(
      @lib.quick_batch_escape_attrs(@lib.split_joined("a\"|🇯🇵", "|")),
      "|",
    ),
    "a&quot;|🇯🇵",
  )
  assert_eq(
    @lib.join_joined(
      @lib.quick_batch_sanitize_filenames(
        @lib.split_joined("😀/x.png|y:z", "|"),
      ),
      "|",
    ),
    "😀_x.png|y_z",
  )
}
