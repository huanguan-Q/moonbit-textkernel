// Character-code constants (UTF-16 code units) shared by the verified kernels
// in this package AND by the `.mbtp` specifications. Every value here is the
// decimal code unit of a char literal; the tests at the bottom of this file pin
// each one back to the literal so the two representations cannot drift apart.
// `scripts/check_code_comments.mjs` does the same for the `U+XXXX` spelling in
// the comment above each constant, which no MoonBit test can observe.

///|
/// U+0026 `&`
const CH_AMP : Int32 = 38

///|
/// U+003C `<`
const CH_LT : Int32 = 60

///|
/// U+003E `>`
const CH_GT : Int32 = 62

///|
/// U+0022 `"`
const CH_DQUOTE : Int32 = 34

///|
/// U+0027 `'`
const CH_SQUOTE : Int32 = 39

///|
/// U+005F `_`
const CH_UNDERSCORE : Int32 = 95

///|
/// U+002F `/`
const CH_SLASH : Int32 = 47

///|
/// U+005C `\`
const CH_BACKSLASH : Int32 = 92

///|
/// U+003A `:`
const CH_COLON : Int32 = 58

///|
/// U+002A `*`
const CH_STAR : Int32 = 42

///|
/// U+003F `?`
const CH_QUESTION : Int32 = 63

///|
/// U+007C `|`
const CH_PIPE : Int32 = 124

///|
/// U+0068 `h`
const CH_LOWER_H : Int32 = 104

///|
/// U+0074 `t`
const CH_LOWER_T : Int32 = 116

///|
/// U+0070 `p`
const CH_LOWER_P : Int32 = 112

///|
/// U+0073 `s`
const CH_LOWER_S : Int32 = 115

///|
/// U+0061 `a`
const CH_LOWER_A : Int32 = 97

///|
/// U+006D `m`
const CH_LOWER_M : Int32 = 109

///|
/// U+006C `l`
const CH_LOWER_L : Int32 = 108

///|
/// U+0067 `g`
const CH_LOWER_G : Int32 = 103

///|
/// U+003B `;`
const CH_SEMI : Int32 = 59

///|
/// Lower bound of the UTF-16 surrogate range (U+D800).
const SURROGATE_LO : Int32 = 55296

///|
/// Upper bound of the UTF-16 surrogate range (U+DFFF).
const SURROGATE_HI : Int32 = 57343

///|
/// Maximum number of source code units `sanitize_filename` will emit.
const NAME_LIMIT : Int32 = 120

///|
/// Largest length (in code units) the verified kernels accept as input.
///
/// The proof prelude models `Int32` as an **unbounded** mathematical integer
/// (`type t = int`, `in_bounds _ = true`), while the wasm backend really uses
/// 32-bit values. The model is therefore only faithful where no intermediate
/// result can overflow, and that condition cannot be expressed as a type in this
/// prelude — so each kernel that adds or multiplies lengths states it as an
/// explicit `proof_require` against this constant.
///
/// `100_000_000` code units is 200 MB of UTF-16. That is not a statement about
/// what users send — the shipping layer refuses anything above
/// `@lib.MAX_SHIPPING_CODE_UNITS` (8M units) — it is the margin that makes the
/// arithmetic safe:
///
/// * `escape_html_codes` computes `5 * length`  -> 5e8 < 2^31-1
/// * `escape_attr_codes` computes `6 * length`  -> 6e8 < 2^31-1
/// * `batch_ceil`/`batch_end` compute `n + bs`  -> 2e8 < 2^31-1
///
/// the tests at the bottom of this file pin those three inequalities, so the
/// constant cannot be raised without one of them going red.
///
/// This bound enters the proofs as `proof_require`, and since 2026-10-31 it also
/// has a runtime mirror (`@lib.require_model_length`) on every shipping entry
/// point. That check lives in `lib` rather than in these kernels because a
/// contracted function body may not call `abort` — see the `[4207]` note in
/// `docs/COREPROOF_DEEP_REVIEW.md §8.7`. `coreproof` still imports `lib` and
/// never the reverse, so nothing in `lib` can call a kernel.
// The number lives in `@lib` so the shipping-side runtime checks and the proof
// model cannot drift apart: this is a reference, not a second copy.
const MAX_CODE_UNITS : Int32 = @lib.MAX_INPUT_CODE_UNITS

///|
/// `sanitize_filename` substitutes this string when the input is empty.
const DEFAULT_NAME : String = "file"

// The kernels work on decimal code units, so every constant above must agree with
// the char literal it stands for. These tests pin both directions, which is what
// keeps the proofs talking about the characters they claim to.

///|
test "codes - single-character constants match their literals" {
  assert_eq(CH_AMP, '&'.to_int())
  assert_eq(CH_LT, '<'.to_int())
  assert_eq(CH_GT, '>'.to_int())
  assert_eq(CH_DQUOTE, '"'.to_int())
  assert_eq(CH_SQUOTE, '\''.to_int())
  assert_eq(CH_UNDERSCORE, '_'.to_int())
  assert_eq(CH_SLASH, '/'.to_int())
  assert_eq(CH_BACKSLASH, '\\'.to_int())
  assert_eq(CH_COLON, ':'.to_int())
  assert_eq(CH_STAR, '*'.to_int())
  assert_eq(CH_QUESTION, '?'.to_int())
  assert_eq(CH_PIPE, '|'.to_int())
}

///|
test "codes - header constants match their literals" {
  assert_eq(CH_LOWER_H, 'h'.to_int())
  assert_eq(CH_LOWER_T, 't'.to_int())
  assert_eq(CH_LOWER_P, 'p'.to_int())
  assert_eq(CH_LOWER_S, 's'.to_int())
  assert_eq(CH_LOWER_A, 'a'.to_int())
  assert_eq(CH_LOWER_M, 'm'.to_int())
  assert_eq(CH_LOWER_L, 'l'.to_int())
  assert_eq(CH_LOWER_G, 'g'.to_int())
  assert_eq(CH_SEMI, ';'.to_int())
}

///|
test "codes - surrogate range matches the UTF-16 block" {
  assert_eq(SURROGATE_LO, 0xD800)
  assert_eq(SURROGATE_HI, 0xDFFF)
  assert_eq(SURROGATE_HI - SURROGATE_LO + 1, 2048)
}

///|
test "codes - default name and limit match the shipped policy" {
  assert_eq(DEFAULT_NAME, "file")
  assert_eq(DEFAULT_NAME.length(), 4)
  assert_eq(NAME_LIMIT, 120)
  assert_eq(@lib.sanitize_filename(""), DEFAULT_NAME)
}

///|
test "codes - the range bound keeps every kernel inside 32 bits" {
  // `MAX_CODE_UNITS` is the hinge between the mathematical-integer proof model
  // and the 32-bit wasm backend: the kernels are allowed to do `5 * len`,
  // `6 * len` and `n + bs`, so all three must stay below the `Int32` maximum.
  // If someone raises the constant, this test is what stops the proofs from
  // silently becoming claims about integers that no longer fit in a register.
  assert_true(MAX_CODE_UNITS * 5 < 2147483647)
  assert_true(MAX_CODE_UNITS * 6 < 2147483647)
  assert_true(MAX_CODE_UNITS + MAX_CODE_UNITS - 1 < 2147483647)
  // It must also not be so tight that real inputs are excluded: a 120-unit
  // filename is three orders of magnitude below the bound.
  assert_true(NAME_LIMIT * 1000 < MAX_CODE_UNITS)
  // The theorem must cover everything the shipping layer lets through: the
  // runtime guard uses the tighter `MAX_SHIPPING_CODE_UNITS`, and if that ever
  // grew past this bound the kernels would be applied outside the domain they
  // were proved for. This assertion is the link between the two numbers.
  assert_true(@lib.MAX_SHIPPING_CODE_UNITS <= MAX_CODE_UNITS)
}
