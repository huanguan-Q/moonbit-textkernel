// Verified arithmetic behind the batch pipeline.
//
// `@lib`'s `batch_processing.mbt` sizes its batches with
// `(items.length() + batch_size - 1) / batch_size` and slices each batch with
// `min(start + batch_size, items.length())`. Those two expressions are where the
// module's integer bugs lived — three of them divided by a user-supplied
// `batch_size` / `max_concurrent` that could be zero.
//
// The kernels below are the exact expressions, with the arithmetic obligations
// discharged by the prover instead of by inspection.

///|
/// Clamp a configured batch size to a strictly positive value.
///
/// Proved: the result is exactly `requested` when the request was positive and
/// exactly `1` when it was not (`safe_batch_post`). The weaker pair "`result > 0`"
/// plus "identity iff positive" is not enough to pick the clamped value out — it
/// also admitted `42` — so the value itself is now a proof obligation and the
/// grid test is a cross-check rather than the only thing holding it.
///
/// This is the guard that makes the division in `batch_ceil` total.
pub fn safe_batch_size(
  requested : Int32,
) -> Int32 where {
  proof_ensure: result => result > 0,
  proof_ensure: result => (requested > 0) == (result == requested),
  proof_ensure: result => safe_batch_post(requested, result),
} {
  if requested <= 0 {
    1
  } else {
    requested
  }
}

///|
/// Number of batches needed to cover `n` items at `bs` items per batch.
///
/// Proved: the count is non-negative, `count * bs >= n` (nothing is left over),
/// and `(count - 1) * bs < n` (no batch is wasted). Together those pin the value
/// to `ceil(n / bs)` without naming a division.
pub fn batch_ceil(
  n : Int32,
  bs : Int32,
) -> Int32 where {
  proof_require: 0 <= n,
  proof_require: 0 < bs,
  proof_require: n <= MAX_CODE_UNITS,
  proof_require: bs <= MAX_CODE_UNITS,
  proof_ensure: result => 0 <= result,
  proof_ensure: result => result * bs >= n,
  proof_ensure: result => (result - 1) * bs < n,
} {
  (n + bs - 1) / bs
}

///|
/// End index (exclusive) of the batch starting at `start`.
///
/// Proved: the result is exactly `min(start + bs, n)` (`batch_end_post`), so the
/// slice `[start, batch_end(start, bs, n))` is not merely well formed — it is the
/// right one. The weaker pair "`result <= n`" plus "`start <= result`" also
/// admitted the constant `n`, which would make every batch empty except the last.
pub fn batch_end(
  start : Int32,
  bs : Int32,
  n : Int32,
) -> Int32 where {
  proof_require: 0 <= start,
  proof_require: start <= n,
  proof_require: 0 <= bs,
  proof_require: n <= MAX_CODE_UNITS,
  proof_require: bs <= MAX_CODE_UNITS,
  proof_ensure: result => result <= n,
  proof_ensure: result => start <= result,
  proof_ensure: result => batch_end_post(start, bs, n, result),
} {
  // NOTE: do not name this local `end` — `end` is a WhyML keyword and the
  // lowering emits a raw syntax error instead of a proof failure.
  let stop = start + bs
  if stop < n {
    stop
  } else {
    n
  }
}
