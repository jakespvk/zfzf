# zfzf

A guided Zig implementation of a fuzzy finder, beginning with the matching
core and eventually growing into an interactive Windows terminal program.

The project requires Zig `0.17.0-dev.1857+3c46da14d` or newer. This is a
nightly compiler series, so later nightlies may require small API updates.

## Progress

- [x] Challenge 1: ordered subsequence matching
- [x] Challenge 2: match positions, bounds, and a basic score
- [x] Challenge 3: filter and rank candidates
- [x] Challenge 4: unordered query terms
- [x] Challenge 5: ASCII case-insensitive matching
- [x] Challenge 6: non-interactive stdin/stdout CLI
- [ ] Challenge 7: bounded results and `--limit`

## Challenge 7: Bounded Results and `--limit`

Implement `filterCandidatesLimit` in `src/filter.zig` and complete `parseArgs`
in `src/cli.zig`.

Users often need only the best few matches. Add this invocation:

```text
zfzf --limit 10 query
```

The easy implementation would filter and sort every match, then truncate the
result. Do not do that: when the limit is small, retain only the best `limit`
matches while scanning candidates.

Keep the existing `filterCandidates` API unchanged for unlimited callers.
`cli.run` already chooses the bounded API only when `--limit` is supplied.

### Ranking Heap

Use a priority queue whose root is the **worst retained match**. Once the queue
contains `limit` items, a new match replaces the root only when the new match
ranks better. Finally, copy and sort only the retained matches into normal best-
first output order.

### Requirements

- `filterCandidatesLimit` must return at most `limit` matches in the exact same
  order as the first `limit` results from `filterCandidates`.
- Preserve score-descending, length-ascending, and input-index-ascending ranking.
- Retain at most `limit` matches while scanning. Memory for match records must
  be `O(limit)`, not `O(number of matches)`.
- Match every candidate so later high-scoring candidates can displace earlier
  results.
- Reuse one positions allocation, preserve candidate borrowing, and return a
  caller-owned result slice.
- A zero limit returns an owned empty slice and need not run the matcher.
- Limits larger than the number of matches return all matches.
- Parse either `<query>` or `--limit <count> <query>`.
- Parse `count` as a base-10 `usize`; zero is valid.
- Return `error.InvalidLimit` for non-numeric or overflowing counts, and
  `error.InvalidArguments` for every other argument shape.
- Do not change unlimited CLI behavior when `--limit` is absent.

Run the tests:

```powershell
zig build test
```

## Concepts

- A top-k algorithm keeps only the best `k` values seen so far.
- A worst-first heap exposes the current cutoff in `O(1)`. Insertion and
  replacement cost `O(log k)`, making the scan `O(n log k)`.
- `std.PriorityQueue` comparators return `std.math.Order`, unlike sort
  comparators, which return `bool`.
- Heap storage is not sorted output. Sort the final retained slice with the
  existing best-first comparator.
- `std.fmt.parseInt(usize, text, 10)` distinguishes valid decimal values from
  invalid and overflowing input through errors.

## Hint Ladder

Stop after the first hint that gets you moving.

1. Return `allocator.alloc(RankedMatch, 0)` immediately when `limit == 0`.
2. Allocate `query.len` positions once, as in `filterCandidates`.
3. Create a private `std.PriorityQueue(RankedMatch, void, compareWorstFirst)`.
   Its comparator must reverse the existing best-first ranking so `peek()` is
   the worst retained item.
4. For each match: push while `queue.count() < limit`. Once full, compare the
   new item with `queue.peek().?`; if the new item is better, pop then push it.
5. After scanning, duplicate `queue.items` into an owned result slice, sort it
   with `lessThan`, and return it. Defer queue cleanup independently.
6. In `parseArgs`, accept lengths 1 and 3 only. For length 3, require the first
   argument to equal `--limit` before parsing the second with `parseInt`.
7. Map every `parseInt` error to `error.InvalidLimit`; return the third argument
   as the query. `main.zig` already maps either parse error to usage exit code 2.

When all tests pass, share your implementation for review. Challenge 8 will
improve match quality by finding a tighter alignment instead of accepting only
the first greedy subsequence.
