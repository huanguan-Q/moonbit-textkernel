///|
/// Black-box tests for the chunk arithmetic of `batch_process_custom`.
///
/// The arithmetic is proved for `0 < bs <= MAX_CODE_UNITS` and
/// `n <= MAX_CODE_UNITS`. Before the chunk size was bounded, a size of
/// 2,147,483,644 or more made `(total + size - 1)` overflow, the chunk count
/// came out as 0, and every item was silently dropped.

///|
/// Run the batch over `n` items in chunks of `size`, and report how many came
/// out, in order. `-1` when one is missing, repeated or out of place.
fn batch_count(size : Int32, n : Int32) -> Int32 {
  let items : Array[Int32] = []
  for i = 0; i < n; i = i + 1 {
    items.push(i)
  }
  let result = @lib.batch_process_custom(
    items,
    fn(x) { x * 10 },
    @lib.create_batch_config(size),
  )
  let mut in_order = result.results.length() == n
  for i = 0; i < n; i = i + 1 {
    if in_order && result.results[i] != i * 10 {
      in_order = false
    }
  }
  if in_order {
    result.processed_count
  } else {
    -1
  }
}

///|
test "[batch] a chunk size near Int32 max no longer drops the list" {
  let min_int32 = -2147483647 - 1
  let sizes = [
    2147483647, 2147483646, 2147483645, 2147483644, 2147483643, 100000001, 100000000,
    99999999, 500, 1, 0, -1, min_int32,
  ]
  for size in sizes {
    assert_eq(batch_count(size, 5), 5)
    assert_eq(batch_count(size, 1200), 1200)
  }
}

///|
test "[batch] an empty list stays empty in every chunk size" {
  let min_int32 = -2147483647 - 1
  for size in [1, 500, 2147483647, min_int32] {
    assert_eq(batch_count(size, 0), 0)
  }
}
