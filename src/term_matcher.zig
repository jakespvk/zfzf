const std = @import("std");

const matcher = @import("matcher.zig");

/// Matches every whitespace-separated query term independently against one
/// candidate. `positions` must hold at least `query.len` indexes.
pub fn findMatch(
    query: []const u8,
    candidate: []const u8,
    positions: []usize,
) matcher.MatchError!?matcher.Match {
    var queries = std.mem.tokenizeAny(u8, query, &std.ascii.whitespace);

    var match: ?matcher.Match = null;

    while (queries.next()) |q| {
        if (try matcher.findMatch(q, candidate, positions)) |current_match| {
            if (match) |m| {
                match = matcher.Match{ .start = @min(m.start, current_match.start), .end = @max(m.end, current_match.end), .score = m.score + current_match.score };
            } else {
                match = matcher.Match{ .start = current_match.start, .end = current_match.end, .score = current_match.score };
            }
        } else return null;
    }

    if (match) |m| {
        return m;
    }

    return matcher.Match{ .start = 0, .end = 0, .score = 0 };
}

test "single term preserves matcher result" {
    var positions: [5]usize = undefined;
    const expected = (try matcher.findMatch("vldtr", "validator", &positions)).?;
    const actual = (try findMatch("vldtr", "validator", &positions)).?;

    try std.testing.expectEqual(expected.start, actual.start);
    try std.testing.expectEqual(expected.end, actual.end);
    try std.testing.expectEqual(expected.score, actual.score);
}

test "terms match independently in any order" {
    var positions: [10]usize = undefined;
    const actual = try findMatch("alpha beta", "beta alpha", &positions);

    try std.testing.expect(actual != null);
}

test "terms ignore ASCII case" {
    var positions: [10]usize = undefined;
    const actual = try findMatch("ALPHA beta", "Beta Alpha", &positions);

    try std.testing.expect(actual != null);
}

test "every term is required" {
    var positions: [11]usize = undefined;

    try std.testing.expectEqual(null, try findMatch("alpha gamma", "beta alpha", &positions));
}

test "ASCII whitespace separates terms and empty terms are ignored" {
    var positions: [14]usize = undefined;
    const actual = try findMatch("  alpha\tbeta\n", "beta alpha", &positions);

    try std.testing.expect(actual != null);
}

test "repeated terms may reuse candidate bytes" {
    var positions: [7]usize = undefined;
    const actual = try findMatch("abc abc", "abc", &positions);

    try std.testing.expect(actual != null);
}

test "combined match spans all terms and sums their scores" {
    var positions: [10]usize = undefined;
    const maybe_actual = try findMatch("alpha beta", "beta alpha", &positions);
    try std.testing.expect(maybe_actual != null);
    const actual = maybe_actual.?;

    const alpha = (try matcher.findMatch("alpha", "beta alpha", &positions)).?;
    const beta = (try matcher.findMatch("beta", "beta alpha", &positions)).?;

    try std.testing.expectEqual(@as(usize, 0), actual.start);
    try std.testing.expectEqual(@as(usize, 10), actual.end);
    try std.testing.expectEqual(alpha.score + beta.score, actual.score);
}

test "combined match starts at the earliest term" {
    var positions: [10]usize = undefined;
    const actual = (try findMatch("alpha beta", "xxxx beta alpha", &positions)).?;

    try std.testing.expectEqual(@as(usize, 5), actual.start);
    try std.testing.expectEqual(@as(usize, 15), actual.end);
}

test "whitespace-only query produces an empty match" {
    var positions: [4]usize = undefined;
    const maybe_actual = try findMatch(" \t\r\n", "anything", &positions);
    try std.testing.expect(maybe_actual != null);
    const actual = maybe_actual.?;

    try std.testing.expectEqual(@as(usize, 0), actual.start);
    try std.testing.expectEqual(@as(usize, 0), actual.end);
    try std.testing.expectEqual(@as(i32, 0), actual.score);
}
