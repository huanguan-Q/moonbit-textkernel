// Batch pipeline over the arithmetic proved in `src/proof/batch.mbt`.
//
// This is a dependency-free rewrite of the original batching layer, which
// pulled in a content-analysis module and a wall-clock monitor just to size
// chunks. None of that is needed to process a list, and carrying it would make
// the library's core depend on scaffolding.
//
// The three arithmetic helpers below are the exact expressions discharged by
// `safe_batch_post`, `batch_ceil_post` and `batch_end_post` in the proof
// package; `src/proof/conform.mbt` drives this loop with degenerate batch sizes
// (0, -1, min_int32) so the guarded path stays pinned to the theorem.

///|
/// Chunking configuration. `batch_size <= 0` is clamped to 1, never divided by.
///
/// This struct deliberately has exactly one field. The original batching layer
/// also exposed `max_concurrent`, `enable_memory_pool` and `timeout_ms`, but
/// none of them affected the loop — a pure function has no scheduler, no pool
/// and no clock. Keeping them would have advertised semantics the code does
/// not implement.
pub struct BatchConfig {
  batch_size : Int32
}

///|
/// Result of one batch run.
pub struct BatchResult[T] {
  results : Array[T]
  processed_count : Int32
  failed_count : Int32
}

///|
pub fn create_batch_config(batch_size : Int32) -> BatchConfig {
  { batch_size, }
}

///|
pub fn create_large_dataset_config() -> BatchConfig {
  create_batch_config(500)
}

///|
pub fn create_realtime_config() -> BatchConfig {
  create_batch_config(50)
}

///|
/// Clamp a requested chunk size to a strictly positive value.
fn safe_batch_size(requested : Int32) -> Int32 {
  if requested > 0 {
    requested
  } else {
    1
  }
}

///|
/// Number of chunks needed for `total` items.
fn batch_ceil(total : Int32, size : Int32) -> Int32 {
  (total + size - 1) / size
}

///|
/// Exclusive end index of one chunk, clamped to `total`.
fn batch_end(start : Int32, size : Int32, total : Int32) -> Int32 {
  if start + size < total {
    start + size
  } else {
    total
  }
}

///|
/// Apply `operation` to every item in bounded chunks.
///
/// No item is dropped or repeated regardless of the configured chunk size —
/// this is what `conform.mbt` asserts against the proved arithmetic.
pub fn[T, R] batch_process_custom(
  items : Array[T],
  operation : (T) -> R,
  config : BatchConfig,
) -> BatchResult[R] {
  let size = safe_batch_size(config.batch_size)
  let count = batch_ceil(items.length(), size)
  let results : Array[R] = []
  let mut processed = 0
  for batch_index = 0; batch_index < count; batch_index = batch_index + 1 {
    let start = batch_index * size
    let end = batch_end(start, size, items.length())
    let mut i = start
    while i < end {
      results.push(operation(items[i]))
      processed = processed + 1
      i = i + 1
    }
  }
  { results, processed_count: processed, failed_count: 0, }
}

///|
/// Normalise a list of asset URLs in one call.
pub fn quick_batch_normalize_urls(urls : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for url in urls {
    out.push(normalize_asset_url(url))
  }
  out
}

///|
/// Sanitise a list of filenames in one call.
pub fn quick_batch_sanitize_filenames(
  filenames : Array[String],
) -> Array[String] {
  let out : Array[String] = []
  for name in filenames {
    out.push(sanitize_filename(name))
  }
  out
}
