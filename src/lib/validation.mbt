// Input validation for the Result-returning API variants.
//
// This is a dependency-free rewrite of the validation layer: the original
// implementation sat inside a logging module and emitted log records as a side
// effect of rejecting an input. Validation here is pure — the caller decides
// what to do with the error — so the runtime package has no external imports.

///|
/// Errors produced by the validated API variants.
pub enum CoreError {
  InvalidInput(String)
  PerformanceWarning(String)
}

///|
/// Render an error as a human-readable string.
pub fn error_to_string(error : CoreError) -> String {
  match error {
    InvalidInput(msg) => "Invalid Input: " + msg
    PerformanceWarning(msg) => "Performance Warning: " + msg
  }
}

///|
/// Reject empty inputs and inputs longer than `max_length`.
///
/// `function_name` is carried into the error message so a caller that validates
/// several fields can tell which one failed. The `Unit` payload keeps the return
/// type usable as a guard: `validate_string_input(...)?` then continue.
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
