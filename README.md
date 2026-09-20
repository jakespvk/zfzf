# zfzf

A guided Zig implementation of a fuzzy finder, beginning with the matching
core and eventually growing into an interactive Windows terminal program.

The project requires Zig `0.17.0-dev.1857+3c46da14d` or newer. This is a
nightly compiler series, so later nightlies may require small API updates.

## Learning Workflow

You write the implementation. The assistant maintains the challenge instructions
and tests, gives focused hints when asked, and reviews your work. It should not
complete the exercise for you. After a successful review, it prepares the next
challenge.

Existing behavior remains the reference unless the current challenge explicitly
changes it. Tests must follow those requirements and the established scoring
rules.

## Progress

- [x] Challenge 1: ordered subsequence matching
- [x] Challenge 2: match positions, bounds, and a basic score
- [x] Challenge 3: filter and rank candidates
- [x] Challenge 4: unordered query terms
- [x] Challenge 5: ASCII case-insensitive matching
- [x] Challenge 6: non-interactive stdin/stdout CLI
- [x] Challenge 7: bounded results and `--limit`
- [ ] Challenge 8: forward/backward match refinement

## Challenge 8: Forward/Backward Match Refinement

Improve `findMatch` in `src/matcher.zig` by tightening the match window before
scoring it.

Your forward scan currently finds query `ab` in candidate `a---ab` at positions
`[0, 5]`. The same match can end at position 5 while starting at position 4,
giving the tighter alignment `[4, 5]`.

This challenge explicitly changes **alignment selection**. Keep the existing
scoring formula and candidate ranking rules from the earlier challenges.

### Alignment Rules

For a non-empty query that matches:

1. Scan forward greedily to find the **first completed match**. Keep that match's
   exclusive end index fixed.
2. Starting at that end, match the query backwards to find the **latest possible
   start** for a match ending there.
3. Scan forward greedily again inside the tightened `[start, end)` window to
   write the final positions.
4. Compute `start`, `end`, and `score` from those final positions using the
   existing scoring rules.

The backward scan chooses the window; the final forward scan chooses the
positions within it. For query `abc` in `a-abXbYc`, the final positions must be
`[2, 3, 7]`: choose the first `b` within the tightened window.

Keep the first completion even if a later occurrence is shorter or scores more
highly. For example, `ab` in `aXXb ab` still uses `[0, 3]`. Finding the globally
best-scoring alignment is a separate problem.

### Examples

Indexes refer to the original candidate, and `end` is exclusive.

| Query | Candidate | Final positions | Bounds | Score |
| --- | --- | --- | --- | --- |
| `ab` | `a---ab` | `[4, 5]` | `[4, 6)` | 44 |
| `abc` | `a-abXbYc` | `[2, 3, 7]` | `[2, 8)` | 55 |
| `ab` | `aXXb ab` | `[0, 3]` | `[0, 4)` | 36 |

These scores use your existing matcher. For example, `[4, 5]` in `a---ab`
earns 32 for the two matched bytes, 8 for the boundary before `a`, and 4 for the
consecutive `b`: 44 in total.

Tightening does not guarantee a higher score for every possible input under the
existing bonuses. Always score the final alignment according to the same rules.

### Requirements

- Keep the public `findMatch` signature, `Match`, and `MatchError` unchanged.
- Follow the forward/backward/forward selection rules above.
- Preserve ASCII case-insensitive comparison in every scan. Matching remains
  byte-based outside ASCII.
- Write strictly increasing original candidate indexes into
  `positions[0..query.len]`. Repeated query bytes require distinct positions.
- Leave any extra entries in the caller's positions buffer untouched.
- Derive the returned bounds and score from the final positions.
- Preserve the empty-query result `{ .start = 0, .end = 0, .score = 0 }` and
  return `null` for non-matches.
- Preserve `error.PositionBufferTooSmall` when `positions.len < query.len`.
- Use no allocations. Reuse the caller's positions buffer and use `O(1)` extra
  storage with `O(candidate.len + query.len)` running time.
- Keep `isSubsequence` unchanged. Term matching, unlimited filtering, bounded
  filtering, and the CLI should inherit refinement through their existing calls.

### Tests

The previous test requiring `[0, 5]` for `ab` in `a---ab` now requires `[4, 5]`.
That expectation changes because alignment refinement is the new requirement.
Additional tests cover window selection, final positions, scoring, case folding,
repeated bytes, buffer reuse, and integration with term matching and ranking.

The existing implementation is your starting point. The new refinement
expectations will fail until you implement this challenge.

Run the tests on Windows or Linux:

```sh
zig build test
```

## Concepts

- Multiple linear scans still have linear overall running time.
- Window selection and position selection can be separate steps.
- `usize` is unsigned. A reverse loop must stop before subtracting below zero.
- An exclusive cursor can start one past the last byte and decrement before
  accessing an element, provided it is greater than zero.
- Select positions first, then use the existing scoring code on those positions.

## Hint Ladder

Stop after the first hint that gets you moving.

1. Your existing forward scan already supplies the first completion's exclusive
   end: one past its last recorded position.
2. Work backwards from that end with a candidate cursor and a count of query
   bytes still to match. Reuse the existing case-insensitive comparison helper.
3. Each backward match consumes one query byte and one candidate position.
   When the first query byte is matched, you have the tightened start.
4. Reset query progress and scan forward within the tightened window, writing
   the final positions greedily using original candidate indexes.
5. Run the existing scoring and bounds code after the final forward scan.

When all tests pass, share your implementation for review.
