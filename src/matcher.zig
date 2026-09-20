const std = @import("std");

/// Returns whether every byte in `query` appears in `candidate` in the same
/// order. Allocations are not needed.
pub fn isSubsequence(query: []const u8, candidate: []const u8) bool {
    if (query.len == 0) return true;

    var query_idx: usize = 0;
    for (candidate) |candidate_char| {
        if (query_idx == query.len) {
            return true;
        }

        if (areCharsEqualCaseInsensitive(query[query_idx], candidate_char)) {
            query_idx += 1;
        }
    }

    return query_idx == query.len;
}

pub const Match = struct {
    start: usize,
    end: usize,
    score: i32,
};

pub const MatchError = error{
    PositionBufferTooSmall,
};

/// Writes matching candidate indexes to `positions` and returns bounds and score.
/// `end` is exclusive, as it is in a Zig slice.
pub fn findMatch(query: []const u8, candidate: []const u8, positions: []usize) MatchError!?Match {
    if (positions.len < query.len) return error.PositionBufferTooSmall;

    var match = Match{ .start = 0, .end = 0, .score = 0 };

    if (query.len == 0) return match;

    var query_idx: usize = 0;
    for (candidate, 0..) |candidate_char, c_i| {
        if (query_idx == query.len) {
            break;
        }

        if (areCharsEqualCaseInsensitive(query[query_idx], candidate_char)) {
            positions[query_idx] = c_i;
            query_idx += 1;
        }
    }

    var idx: isize = @intCast(positions[positions.len - 1]);
    var pos_idx = positions.len - 1;
    while (positionsIter(idx)) |i| : (idx -= 1) {
        if (i > 0 and areCharsEqualCaseInsensitive(candidate[i], candidate[positions[pos_idx]])) {
            positions[pos_idx] = i;
            pos_idx -= 1;
        }
    }

    if (query_idx == query.len) {
        // Challenge 8: tighten the window, then rebuild greedy positions before scoring.
        var prev_p: ?usize = null;
        for (positions[0..query.len]) |p| {
            match.score += 16;

            if (p == 0) {
                match.score += 8;
            }

            if (p > 0 and isBoundaryChar(candidate[p - 1])) {
                match.score += 8;
            }

            if (prev_p) |pp| {
                if (p == pp + 1) {
                    match.score += 4;
                } else {
                    match.score -= @intCast(1 + p - pp);
                }
            }

            prev_p = p;
        }

        match.start = positions[0];
        match.end = positions[query.len - 1] + 1;

        return match;
    }

    return null;
}

fn positionsIter(idx: isize) ?usize {
    return if (idx < 0) null else @intCast(idx);
}

fn areCharsEqualCaseInsensitive(a: u8, b: u8) bool {
    return std.ascii.toLower(a) == std.ascii.toLower(b);
}

fn isBoundaryChar(c: u8) bool {
    return std.ascii.isWhitespace(c) or c == '/' or c == '\\' or c == '-' or c == '_' or c == '.';
}

test "empty query matches every candidate" {
    try std.testing.expect(isSubsequence("", "anything"));
}

test "identical text matches" {
    try std.testing.expect(isSubsequence("validator", "validator"));
}

test "query may omit candidate characters" {
    try std.testing.expect(isSubsequence("vldtr", "validator"));
}

test "query characters must retain their order" {
    try std.testing.expect(!isSubsequence("validtaor", "validator"));
}

test "query cannot contain a missing character" {
    try std.testing.expect(!isSubsequence("validx", "validator"));
}

test "subsequence matching ignores ASCII case" {
    try std.testing.expect(isSubsequence("VLDTR", "validator"));
}

test "subsequence matching remains byte based outside ASCII" {
    try std.testing.expect(!isSubsequence("\xc3\x89", "\xc3\xa9"));
}

test "empty query produces an empty match" {
    var positions: [0]usize = .{};
    const maybe_actual = try findMatch("", "anything", &positions);
    try std.testing.expect(maybe_actual != null);
    const actual = maybe_actual.?;

    try std.testing.expectEqual(@as(usize, 0), actual.start);
    try std.testing.expectEqual(@as(usize, 0), actual.end);
    try std.testing.expectEqual(@as(i32, 0), actual.score);
}

test "match contains greedy candidate positions and exclusive bounds" {
    var positions: [5]usize = undefined;
    const maybe_actual = try findMatch("vldtr", "validator", &positions);
    try std.testing.expect(maybe_actual != null);
    const actual = maybe_actual.?;

    try std.testing.expectEqualSlices(usize, &.{ 0, 2, 4, 6, 8 }, &positions);
    try std.testing.expectEqual(@as(usize, 0), actual.start);
    try std.testing.expectEqual(@as(usize, 9), actual.end);
}

test "scored matching ignores ASCII case" {
    var positions: [3]usize = undefined;
    const maybe_actual = try findMatch("AbC", "aBc", &positions);
    try std.testing.expect(maybe_actual != null);
    const actual = maybe_actual.?;

    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, &positions);
    try std.testing.expectEqual(@as(usize, 0), actual.start);
    try std.testing.expectEqual(@as(usize, 3), actual.end);
    try std.testing.expectEqual(@as(i32, 64), actual.score);
}

test "refinement tightens the first completed alignment" {
    var positions: [2]usize = undefined;
    const maybe_actual = try findMatch("ab", "a---ab", &positions);
    try std.testing.expect(maybe_actual != null);
    const actual = maybe_actual.?;

    try std.testing.expectEqualSlices(usize, &.{ 4, 5 }, &positions);
    try std.testing.expectEqual(@as(usize, 4), actual.start);
    try std.testing.expectEqual(@as(usize, 6), actual.end);
    try std.testing.expectEqual(@as(i32, 44), actual.score);
}

test "refinement keeps the first completion despite a tighter later occurrence" {
    var positions: [2]usize = undefined;
    const maybe_actual = try findMatch("ab", "aXXb ab", &positions);
    try std.testing.expect(maybe_actual != null);
    const actual = maybe_actual.?;

    try std.testing.expectEqualSlices(usize, &.{ 0, 3 }, &positions);
    try std.testing.expectEqual(@as(usize, 0), actual.start);
    try std.testing.expectEqual(@as(usize, 4), actual.end);
    try std.testing.expectEqual(@as(i32, 36), actual.score);
}

test "refinement rebuilds greedy interior positions within the tightened window" {
    var positions: [3]usize = undefined;
    const maybe_actual = try findMatch("abc", "a-abXbYc", &positions);
    try std.testing.expect(maybe_actual != null);
    const actual = maybe_actual.?;

    try std.testing.expectEqualSlices(usize, &.{ 2, 3, 7 }, &positions);
    try std.testing.expectEqual(@as(usize, 2), actual.start);
    try std.testing.expectEqual(@as(usize, 8), actual.end);
    try std.testing.expectEqual(@as(i32, 55), actual.score);
}

test "refinement uses ASCII case-insensitive comparison" {
    var positions: [2]usize = undefined;
    const maybe_actual = try findMatch("AB", "a---Ab", &positions);
    try std.testing.expect(maybe_actual != null);
    const actual = maybe_actual.?;

    try std.testing.expectEqualSlices(usize, &.{ 4, 5 }, &positions);
    try std.testing.expectEqual(@as(usize, 4), actual.start);
    try std.testing.expectEqual(@as(usize, 6), actual.end);
    try std.testing.expectEqual(@as(i32, 44), actual.score);
}

test "refinement uses distinct positions for repeated query bytes" {
    var positions: [3]usize = undefined;
    const maybe_actual = try findMatch("aab", "aXaaab", &positions);
    try std.testing.expect(maybe_actual != null);
    const actual = maybe_actual.?;

    try std.testing.expectEqualSlices(usize, &.{ 3, 4, 5 }, &positions);
    try std.testing.expectEqual(@as(usize, 3), actual.start);
    try std.testing.expectEqual(@as(usize, 6), actual.end);
    try std.testing.expectEqual(@as(i32, 56), actual.score);
}

test "single-byte refinement keeps the first occurrence" {
    var positions: [1]usize = undefined;
    const maybe_actual = try findMatch("a", "x a a", &positions);
    try std.testing.expect(maybe_actual != null);
    const actual = maybe_actual.?;

    try std.testing.expectEqualSlices(usize, &.{2}, &positions);
    try std.testing.expectEqual(@as(usize, 2), actual.start);
    try std.testing.expectEqual(@as(usize, 3), actual.end);
    try std.testing.expectEqual(@as(i32, 24), actual.score);
}

test "refinement leaves extra positions buffer entries untouched" {
    var positions: [4]usize = @splat(99);
    const maybe_actual = try findMatch("ab", "a---ab", &positions);
    try std.testing.expect(maybe_actual != null);

    try std.testing.expectEqualSlices(usize, &.{ 4, 5, 99, 99 }, &positions);
}

test "non-matching query returns null" {
    var positions: [6]usize = undefined;
    try std.testing.expectEqual(null, try findMatch("zigzag", "zig", &positions));
}

test "position buffer must hold one index per query byte" {
    var positions: [2]usize = undefined;
    try std.testing.expectError(
        error.PositionBufferTooSmall,
        findMatch("abc", "abc", &positions),
    );
}

test "scoring rewards matches and consecutive bytes" {
    var positions: [3]usize = undefined;
    const maybe_actual = try findMatch("abc", "abc", &positions);
    try std.testing.expect(maybe_actual != null);
    const actual = maybe_actual.?;

    try std.testing.expectEqual(@as(i32, 64), actual.score);
}

test "scoring penalizes gaps" {
    var positions: [3]usize = undefined;
    const maybe_actual = try findMatch("abc", "aXbYc", &positions);
    try std.testing.expect(maybe_actual != null);
    const actual = maybe_actual.?;

    try std.testing.expectEqual(@as(i32, 50), actual.score);
}

test "scoring rewards word boundaries" {
    var positions: [2]usize = undefined;
    const maybe_actual = try findMatch("ab", "x ab", &positions);
    try std.testing.expect(maybe_actual != null);
    const actual = maybe_actual.?;

    try std.testing.expectEqual(@as(i32, 44), actual.score);
}

test "gap extension penalty is smaller than gap start penalty" {
    var positions: [2]usize = undefined;
    const maybe_actual = try findMatch("ab", "aXYZb", &positions);
    try std.testing.expect(maybe_actual != null);
    const actual = maybe_actual.?;

    try std.testing.expectEqual(@as(i32, 35), actual.score);
}

test "backwards for loop" {
    var positions: [3]usize = undefined;
    _ = try findMatch("abc", "axabxccx", &positions);
}
