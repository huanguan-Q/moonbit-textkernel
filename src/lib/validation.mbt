// Input validation for the Result-returning API variants.
//
// This is a dependency-free rewrite of the validation layer: the original
// implementation sat inside a logging module and emitted log records as a side
// effect of rejecting an input. Validation here is pure — the caller decides
// what to do with the error — so the runtime package has no external imports.

///|
/// Errors produced by the validated API variants.
///
/// The `*_result` functions return `InputTooLarge` for an input outside the
/// shipping domain and `InvariantViolation` when a shipped result fails its
/// own runtime check. `normalize_asset_url*` also returns `InvalidConfig` when
/// the `AssetConfig` holds a default parameter that cannot be appended.
/// `InvalidInput` and `PerformanceWarning` are kept for compatibility: only
/// `validate_string_input` produces them.
pub enum CoreError {
  InvalidInput(String)
  PerformanceWarning(String)
  InputTooLarge(String)
  InvariantViolation(String)
  InvalidConfig(String)
}

///|
/// Render an error as a human-readable string.
pub fn error_to_string(error : CoreError) -> String {
  match error {
    InvalidInput(msg) => "Invalid Input: " + msg
    PerformanceWarning(msg) => "Performance Warning: " + msg
    InputTooLarge(msg) => "Input Too Large: " + msg
    InvariantViolation(msg) => "Invariant Violation: " + msg
    InvalidConfig(msg) => "Invalid Config: " + msg
  }
}

///|
/// What the String-returning compatibility layer does when a checked call
/// fails. `FailFast` keeps the historical behaviour (abort); `EmptyOnError`
/// returns `""`, which is safe for every kernel — it is neither markup nor an
/// unsanitised filename. Callers should treat `""` as a failure signal.
///
/// Production code should prefer the `*_result` API and never need a policy:
/// the Result carries the error and no abort is possible on that path.
pub enum FailurePolicy {
  FailFast
  EmptyOnError
}

///|
/// Cross-package constructors. Enum variants are read-only outside their own
/// package, so blackbox tests and FFI shims need these to obtain a policy.
pub fn fail_fast_policy() -> FailurePolicy {
  FailFast
}

///|
pub fn empty_on_error_policy() -> FailurePolicy {
  EmptyOnError
}

///|
/// The single place in this library that can abort. Keeping it here means the
/// abort surface is one function, not four scattered checks.
pub fn apply_failure_policy(
  error : CoreError,
  policy : FailurePolicy,
) -> String {
  match policy {
    FailFast => abort("textkernel: " + error_to_string(error))
    EmptyOnError => ""
  }
}

///|
/// Reject empty inputs and inputs longer than `max_length`.
///
/// `function_name` is carried into the error message so a caller that validates
/// several fields can tell which one failed. The `Unit` payload keeps the return
/// type usable as a guard: `validate_string_input(...)?` then continue.
///
/// This is a general helper for callers that want a field-length rule of their
/// own. The library's `*_result` functions no longer go through it: an empty
/// string is a valid input for all of them, and the only bound they enforce is
/// `MAX_SHIPPING_CODE_UNITS`, reported as `InputTooLarge`.
pub fn validate_string_input(
  function_name : String,
  input : String,
  max_length : Int32,
) -> Result[Unit, CoreError] {
  if input.is_empty() {
    return Err(InvalidInput(function_name + ": input is empty"))
  }
  if input.length() > max_length {
    return Err(
      PerformanceWarning(
        function_name +
        ": Input length (" +
        input.length().to_string() +
        ") exceeds recommended maximum (" +
        max_length.to_string() +
        ")",
      ),
    )
  }
  Ok(())
}
