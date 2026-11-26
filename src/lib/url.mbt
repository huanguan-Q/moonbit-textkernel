// Asset URL normalisation.
//
// The historical implementation probed the whole URL for the host string and
// for `key=`. That admitted `https://evil.com/cdn.example.com/x.png` as an
// asset, appended parameters after the `#fragment`, and took `nav=1` for `v`.
// The functions below replace the probes with a small structural parse: only
// the piece a rule names is inspected, and everything else is copied.
//
// The parse covers absolute URLs with an authority, `scheme://authority/...`,
// which is the only shape an asset URL has. Anything else — a relative
// reference, `scheme:opaque`, a bare host — is not parsed and is left alone.
//
// What is proved where. The scheme test, the end of the authority and the
// host rule mirror the kernels in `src/proof/url.mbt` and are pinned there by
// `conform.mbt`. Stripping user information and the port from the authority
// is covered by tests only.

///|
/// The pieces of an absolute URL that has an authority:
/// `scheme://authority/path?query#fragment`.
///
/// `authority` is the text between `://` and the first `/`, `\`, `?` or `#`,
/// as the browser sees it. `query` and `fragment` are stored without their
/// separators; the flags tell an absent part from an empty one, so `a.png?`
/// keeps its (empty) query and `a.png#` its (empty) fragment.
priv struct ParsedUrl {
  scheme : String
  authority : String
  path : String
  query : String
  has_query : Bool
  fragment : String
  has_fragment : Bool
}

///|
/// `c` is an ASCII letter.
fn is_scheme_letter(c : Int32) -> Bool {
  (c >= 97 && c <= 122) || (c >= 65 && c <= 90)
}

///|
/// `c` may appear in a URL scheme after its first letter.
fn is_scheme_char(c : Int32) -> Bool {
  // A letter, a digit, `+`, `-` or `.`.
  is_scheme_letter(c) || (c >= 48 && c <= 57) || c == 43 || c == 45 || c == 46
}

///|
/// Split `scheme://authority/path?query#fragment`. `None` when `input` is not
/// an absolute URL with an authority.
fn parse_absolute_url(input : String) -> ParsedUrl? {
  let n = input.length()
  if n < 4 || !is_scheme_letter(input[0].to_int()) {
    return None
  }
  let mut i = 1
  while i < n && is_scheme_char(input[i].to_int()) {
    i = i + 1
  }
  // `://` must close the scheme.
  if i + 2 >= n ||
    input[i].to_int() != 58 ||
    input[i + 1].to_int() != 47 ||
    input[i + 2].to_int() != 47 {
    return None
  }
  let authority_start = i + 3
  let mut j = authority_start
  while j < n {
    let c = input[j].to_int()
    if c == 47 || c == 92 || c == 63 || c == 35 {
      break
    }
    j = j + 1
  }
  let authority = input[authority_start:j].to_owned()
  let mut k = j
  while k < n {
    let c = input[k].to_int()
    if c == 63 || c == 35 {
      break
    }
    k = k + 1
  }
  let path = input[j:k].to_owned()
  let mut query = ""
  let mut has_query = false
  if k < n && input[k].to_int() == 63 {
    has_query = true
    let query_start = k + 1
    let mut e = query_start
    while e < n && input[e].to_int() != 35 {
      e = e + 1
    }
    query = input[query_start:e].to_owned()
    k = e
  }
  let mut fragment = ""
  let mut has_fragment = false
  if k < n && input[k].to_int() == 35 {
    has_fragment = true
    fragment = input[k + 1:].to_owned()
  }
  Some({
    scheme: input[:i].to_owned(),
    authority,
    path,
    query,
    has_query,
    fragment,
    has_fragment,
  })
}

///|
/// `scheme` is `http` or `https`, in any letter case.
fn is_http_scheme(scheme : String) -> Bool {
  ascii_ci_eq_region(scheme, 0, scheme.length(), "http") ||
  ascii_ci_eq_region(scheme, 0, scheme.length(), "https")
}

///|
/// ASCII lower case of one code unit. Nothing else is folded: a host name has
/// no other upper and lower case pairs.
fn ascii_lower(c : Int32) -> Int32 {
  if c >= 65 && c <= 90 {
    c + 32
  } else {
    c
  }
}

///|
/// True when `s[start:end)` equals `t`, ignoring ASCII letter case.
fn ascii_ci_eq_region(
  s : String,
  start : Int32,
  end : Int32,
  t : String,
) -> Bool {
  if start < 0 || end - start != t.length() {
    return false
  }
  let mut j = 0
  while j < t.length() {
    if ascii_lower(s[start + j].to_int()) != ascii_lower(t[j].to_int()) {
      return false
    }
    j = j + 1
  }
  true
}

///|
/// The host of an authority, without user information and without a port.
///
/// The host starts after the last `@` and ends before the first `:` that is
/// not inside square brackets, so `user@cdn.example.com:8443` gives
/// `cdn.example.com` and `[::1]:443` gives `[::1]`.
fn authority_host(authority : String) -> String {
  let n = authority.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if authority[i] == '@' {
      start = i + 1
    }
    i = i + 1
  }
  let mut stop = n
  let mut last_close_bracket = -1
  let mut last_colon = -1
  i = start
  while i < n {
    let c = authority[i]
    if c == ']' {
      last_close_bracket = i
    }
    if c == ':' {
      last_colon = i
    }
    i = i + 1
  }
  if last_colon > last_close_bracket {
    stop = last_colon
  }
  authority[start:stop].to_owned()
}

///|
/// True when `host` is `entry` itself or one of its subdomains.
///
/// The comparison ignores ASCII letter case, because a DNS name has none. A
/// subdomain is a whole label followed by a dot and the entry: `sub.cdn` for
/// `cdn`, but neither `cdn.example.com.evil.com` nor `notcdn.example.com` is
/// a subdomain of `cdn.example.com`.
fn host_matches_entry(host : String, entry : String) -> Bool {
  if entry.length() == 0 {
    return false
  }
  let hl = host.length()
  let el = entry.length()
  ascii_ci_eq_region(host, 0, hl, entry) ||
  (
    hl >= el + 2 &&
    host[hl - el - 1] == '.' &&
    ascii_ci_eq_region(host, hl - el, hl, entry)
  )
}

///|
/// True when `host` is in the allow-list of `config`.
fn config_allows_host(host : String, config : AssetConfig) -> Bool {
  for entry in config.hosts {
    if host_matches_entry(host, entry) {
      return true
    }
  }
  false
}

///|
/// True when `input` is an `http` or `https` URL whose host is in the
/// allow-list. This one test serves both `normalize_asset_url_with_config`
/// and `decide_referrer_policy_with_config`.
fn url_is_allowed_asset(input : String, config : AssetConfig) -> Bool {
  let parsed_opt = parse_absolute_url(input)
  if parsed_opt is None {
    return false
  }
  let parsed = parsed_opt.unwrap()
  is_http_scheme(parsed.scheme) &&
  config_allows_host(authority_host(parsed.authority), config)
}

///|
/// `p` is one parameter that can be appended to a query as it is.
///
/// A piece that could change the structure of the URL is not: an empty one,
/// one starting with `=`, and one containing `#`, whitespace or a control
/// character.
fn is_plain_param(p : String) -> Bool {
  if p.length() == 0 || p[0] == '=' {
    return false
  }
  let mut i = 0
  while i < p.length() {
    let c = p[i].to_int()
    if c == 35 || c <= 32 || c == 127 {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// True when the query already carries a parameter named `key`.
///
/// Parameters are separated by `&`. A parameter's name is the text before its
/// first `=`, or the whole parameter when it has none, and names are compared
/// whole: `nav=1` does not count as `v`, nor `xfmt=1` as `fmt`.
fn query_has_key(query : String, key : String) -> Bool {
  if key.length() == 0 {
    return false
  }
  let n = query.length()
  let mut start = 0
  let mut i = 0
  while i <= n {
    if i == n || query[i] == '&' {
      // The parameter is query[start:i); its name ends at its first `=`.
      let mut name_end = start
      while name_end < i && query[name_end] != '=' {
        name_end = name_end + 1
      }
      if ascii_region_is(query, start, name_end, key) {
        return true
      }
      start = i + 1
    }
    i = i + 1
  }
  false
}

///|
/// True when `s[start:end)` is exactly `key`.
fn ascii_region_is(
  s : String,
  start : Int32,
  end : Int32,
  key : String,
) -> Bool {
  if start < 0 || end - start != key.length() {
    return false
  }
  let mut j = 0
  while j < key.length() {
    if s[start + j] != key[j] {
      return false
    }
    j = j + 1
  }
  true
}

///|
/// The default parameters to append to `query`, in the order of the config.
///
/// `default_params` is flattened on `&`. A parameter the query already has is
/// left out, and so is a second default with the same name.
///
/// `Err(bad_piece)` for the first piece that is not a plain parameter: it is
/// not skipped, because a caller that receives a URL without the parameter it
/// asked for has no way to see why. The piece is reported as written, so the
/// caller can find it in its own configuration.
fn missing_params(
  query : String,
  default_params : Array[String],
) -> Result[Array[String], String] {
  let out : Array[String] = []
  for raw in default_params {
    for piece in split_joined(raw, "&") {
      if !is_plain_param(piece) {
        return Err(piece)
      }
      let key = param_key(piece)
      if query_has_key(query, key) {
        continue
      }
      let mut repeated = false
      for added in out {
        if param_key(added) == key {
          repeated = true
        }
      }
      if repeated {
        continue
      }
      out.push(piece)
    }
  }
  Ok(out)
}

///|
/// Pure body of `normalize_asset_url_with_config`: no domain check, no abort.
///
/// `Err(piece)` when the configuration holds a default parameter that is not a
/// plain one, and only for a URL the configuration applies to: any other URL
/// is returned unchanged before the parameters are looked at.
fn normalize_asset_url_impl(
  input : String,
  config : AssetConfig,
) -> Result[String, String] {
  let parsed_opt = parse_absolute_url(input)
  if parsed_opt is None {
    return Ok(input)
  }
  let parsed = parsed_opt.unwrap()
  if !is_http_scheme(parsed.scheme) ||
    !config_allows_host(authority_host(parsed.authority), config) {
    return Ok(input)
  }
  let missing = missing_params(parsed.query, config.default_params)
  if missing is Err(piece) {
    return Err(piece)
  }
  let missing = missing.unwrap()
  // Only the scheme may change, and only `http` does: it becomes `https`.
  // An `https` scheme is carried over as written, and so is everything after.
  let scheme = if parsed.scheme.length() == 4 { "https" } else { parsed.scheme }
  let head = scheme + "://" + parsed.authority + parsed.path
  let fragment = if parsed.has_fragment { "#" + parsed.fragment } else { "" }
  if missing.length() == 0 {
    let query = if parsed.has_query { "?" + parsed.query } else { "" }
    return Ok(head + query + fragment)
  }
  // A query that is present but empty (`a.png?`) receives the parameters
  // without a leading `&`; a non-empty query is kept and joined to them.
  let query_head = if parsed.has_query && parsed.query.length() > 0 {
    "?" + parsed.query + "&"
  } else {
    "?"
  }
  Ok(head + query_head + join_joined(missing, "&") + fragment)
}
