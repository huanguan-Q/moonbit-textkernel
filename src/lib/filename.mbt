// Filename sanitising: the character rule, the length clamp and the platform
// rules that turn a user-supplied string into a name that can be created as a
// file on Linux, macOS and Windows — and that is never a directory reference.
//
// What is proved where. The character rule (nine reserved characters, C0
// controls, DEL and unpaired surrogate halves become `_`; a well-formed pair
// is copied whole), the clamp (no longer than `FILENAME_LIMIT` code units, and
// never through the middle of a character) and the dot-only rule (`.`, `..`,
// `...` name directories, not files) mirror the kernels in
// `src/proof/sanitize.mbt` and are pinned there by `conform.mbt`. The two
// Windows-only rules — trailing dots and spaces, device names — are covered by
// tests and by the runtime invariant `filename_is_sanitized`, not by a proof.

///|
/// Longest name `sanitize_filename` returns, in UTF-16 code units.
const FILENAME_LIMIT : Int32 = 120

///|
/// `code` is a C0 control character or DEL. NUL and the line breaks matter
/// most: a name is copied into C strings, logs and shell pipelines.
fn is_control_filename_char(code : UInt16) -> Bool {
  code.to_int() < 32 || code.to_int() == 127
}

///|
/// Check if a character code represents an invalid filename character.
/// Invalid set: / \ : * ? " < > |
fn is_invalid_filename_char(code : UInt16) -> Bool {
  code == '/' ||
  code == '\\' ||
  code == ':' ||
  code == '*' ||
  code == '?' ||
  code == '"' ||
  code == '<' ||
  code == '>' ||
  code == '|'
}

///|
/// The device names Windows reserves, in lower case and without extension.
/// `NUL.txt` and `Com1` are the devices, not files.
fn windows_device_names() -> Array[String] {
  [
    "con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7",
    "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8",
    "lpt9", "conin$", "conout$",
  ]
}

///|
/// True when every character of `name` is a dot. `name` is not empty here.
fn is_all_dots(name : String) -> Bool {
  if name.length() == 0 {
    return false
  }
  let mut i = 0
  while i < name.length() {
    if name[i] != '.' {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// True when `name` ends with a dot or a space. Windows removes both from the
/// end of a name, so `report.` and `report` would be the same file.
fn has_trailing_dot_or_space(name : String) -> Bool {
  let n = name.length()
  n > 0 && (name[n - 1] == '.' || name[n - 1] == ' ')
}

///|
/// Replace every dot and space at the end of `name` with `_`. The length does
/// not change, so a name that fitted the clamp still fits it.
fn replace_trailing_dots_and_spaces(name : String) -> String {
  let n = name.length()
  let mut end = n
  while end > 0 && (name[end - 1] == '.' || name[end - 1] == ' ') {
    end = end - 1
  }
  if end == n {
    return name
  }
  let out = StringBuilder(capacity=n)
  out.write_stringview(name[:end])
  let mut i = end
  while i < n {
    out.write_char('_')
    i = i + 1
  }
  out.to_string()
}

///|
/// True when the name, up to its first dot and without trailing spaces, is a
/// Windows device name. Letter case does not matter.
fn is_windows_device_name(name : String) -> Bool {
  let n = name.length()
  let mut stem_end = n
  let mut i = 0
  while i < n {
    if name[i] == '.' {
      stem_end = i
      break
    }
    i = i + 1
  }
  while stem_end > 0 && name[stem_end - 1] == ' ' {
    stem_end = stem_end - 1
  }
  for device in windows_device_names() {
    if ascii_ci_eq_region(name, 0, stem_end, device) {
      return true
    }
  }
  false
}

///|
/// Put the marker into a device name, right after its stem: `nul.txt` becomes
/// `nul_.txt`.
///
/// The marker has to precede the first dot, because Windows decides by the
/// text before it — `nul.txt_` would still be the NUL device. It goes after the
/// last character of the stem and before the spaces that may follow it, so
/// `con .txt` becomes `con_ .txt`. A name that would grow past
/// `FILENAME_LIMIT` gives up its end instead, never through the middle of a
/// character.
fn mark_filename(name : String) -> String {
  let n = name.length()
  let mut insert_at = n
  let mut i = 0
  while i < n {
    if name[i] == '.' {
      insert_at = i
      break
    }
    i = i + 1
  }
  while insert_at > 0 && name[insert_at - 1] == ' ' {
    insert_at = insert_at - 1
  }
  let marked = name[:insert_at].to_owned() + "_" + name[insert_at:].to_owned()
  if marked.length() <= FILENAME_LIMIT {
    return marked
  }
  let mut cut = FILENAME_LIMIT
  while marked[cut - 1].is_leading_surrogate() {
    cut = cut - 1
  }
  marked[:cut].to_owned()
}

///|
/// Apply the platform rules to a name that has already had its characters
/// replaced and been clamped to `FILENAME_LIMIT`:
///
/// * a name made of dots only (`.`, `..`, `...`) is a directory reference,
///   never a file, so it becomes the default name;
/// * trailing dots and spaces become `_`, because Windows removes them;
/// * a Windows device name gets a trailing `_`.
///
/// The result is never empty and never longer than `FILENAME_LIMIT`.
fn finalize_filename(name : String) -> String {
  if is_all_dots(name) {
    return "file"
  }
  let marked = replace_trailing_dots_and_spaces(name)
  if is_windows_device_name(marked) {
    mark_filename(marked)
  } else {
    marked
  }
}
