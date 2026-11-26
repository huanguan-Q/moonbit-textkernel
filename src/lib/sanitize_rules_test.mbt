///|
/// Black-box tests for the filename rules in `filename.mbt`.
///
/// Before these rules, `sanitize_filename` replaced nine characters and
/// nothing else: `..` came back as `..`, a NUL came back as a NUL, and a
/// character outside the BMP became two underscores.

///|
test "[sanitize] a directory reference is never a file name" {
  for name in [".", "..", "...", "...."] {
    assert_eq(@lib.sanitize_filename(name), "file")
    assert_false(@lib.filename_is_sanitized(name))
  }
  // Path separators are still replaced, wherever they are.
  assert_eq(@lib.sanitize_filename("../../etc/passwd"), ".._.._etc_passwd")
  assert_eq(@lib.sanitize_filename("/etc/passwd"), "_etc_passwd")
  assert_eq(
    @lib.sanitize_filename("C:\\Windows\\win.ini"),
    "C__Windows_win.ini",
  )
}

///|
test "[sanitize] control characters are replaced" {
  // NUL, tab, line feed, the last C0 control, and DEL.
  assert_eq(@lib.sanitize_filename("a\u{0}b"), "a_b")
  assert_eq(@lib.sanitize_filename("a\tb\nc"), "a_b_c")
  assert_eq(@lib.sanitize_filename("a\u{1F}b\u{7F}"), "a_b_")
  // A space is not a control character.
  assert_eq(@lib.sanitize_filename("report 2026.txt"), "report 2026.txt")
}

///|
test "[sanitize] trailing dots and spaces do not vanish on Windows" {
  assert_eq(@lib.sanitize_filename("report."), "report_")
  assert_eq(@lib.sanitize_filename("report "), "report_")
  assert_eq(@lib.sanitize_filename("report. .txt"), "report. .txt")
  assert_eq(@lib.sanitize_filename("a.."), "a__")
  assert_eq(@lib.sanitize_filename("a. "), "a__")
  // A dot inside the name, a leading one included, is a real character.
  assert_eq(@lib.sanitize_filename("archive.tar.gz"), "archive.tar.gz")
  assert_eq(@lib.sanitize_filename(".hidden"), ".hidden")
}

///|
test "[sanitize] a Windows device name gets a marker after its stem" {
  assert_eq(@lib.sanitize_filename("CON"), "CON_")
  assert_eq(@lib.sanitize_filename("nul.txt"), "nul_.txt")
  assert_eq(@lib.sanitize_filename("Com1.tar.gz"), "Com1_.tar.gz")
  // The device check ignores spaces at the end of the stem, so the marker
  // goes before them.
  assert_eq(@lib.sanitize_filename("con .txt"), "con_ .txt")
  // Only the whole stem counts: these are ordinary names.
  assert_eq(@lib.sanitize_filename("console.txt"), "console.txt")
  assert_eq(@lib.sanitize_filename("com10"), "com10")
  assert_eq(@lib.sanitize_filename("nul_report.txt"), "nul_report.txt")
}

///|
test "[sanitize] a device name at full length still gets its marker" {
  // 3 + 1 + 116 = 120 units. The marker is inserted, the end gives way.
  let full = "CON." + repeat('a', 116)
  assert_eq(@lib.sanitize_filename(full), "CON_." + repeat('a', 115))
}

///|
test "[sanitize] the clamp never cuts a character in half" {
  // 118 + 2 = 120: the character fits.
  assert_eq(
    @lib.sanitize_filename(repeat('x', 118) + "🙂tail"),
    repeat('x', 118) + "🙂",
  )
  // The character would cross the limit: the name stops before it.
  assert_eq(
    @lib.sanitize_filename(repeat('x', 119) + "🙂tail"),
    repeat('x', 119),
  )
  assert_eq(@lib.sanitize_filename(repeat('x', 119) + "🙂").length(), 119)
}

///|
test "[sanitize] a character outside the BMP is one character" {
  assert_eq(
    @lib.sanitize_filename("生日🎂派对.jpg"),
    "生日🎂派对.jpg",
  )
  assert_eq(@lib.sanitize_filename("𠮷.txt"), "𠮷.txt")
  assert_eq(@lib.sanitize_filename("README🙂:2026.md"), "README🙂_2026.md")
}

///|
test "[sanitize] every result satisfies the invariant" {
  for
    name in [
      "",
      ".",
      "..",
      " ",
      "  ",
      "a\u{0}b",
      "CON",
      "nul.txt",
      "report.",
      "x" + repeat('/', 200),
      repeat('x', 119) + "🙂tail",
      "CON." + repeat('a', 200),
      "../../etc/passwd",
      "文档V1",
    ] {
    let safe = @lib.sanitize_filename(name)
    assert_true(@lib.filename_is_sanitized(safe))
    assert_true(safe.length() > 0)
    assert_true(safe.length() <= 120)
    // Sanitizing a sanitized name changes nothing.
    assert_eq(@lib.sanitize_filename(safe), safe)
  }
}
