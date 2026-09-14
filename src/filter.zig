const std = @import("std");

const matcher = @import("matcher.zig");
const term_matcher = @import("term_matcher.zig");

pub const RankedMatch = struct {
    candidate: []const u8,
    input_index: usize,
    match: matcher.Match,
};

/// Returns an owned result slice whose candidate text is borrowed from
/// `candidates`. The caller must free the returned slice with `allocator`.
pub fn filterCandidates(
    allocator: std.mem.Allocator,
    query: []const u8,
    candidates: []const []const u8,
) std.mem.Allocator.Error![]RankedMatch {
    var matches = try std.ArrayList(RankedMatch).initCapacity(allocator, 5);
    defer matches.deinit(allocator);
    const positions = try allocator.alloc(usize, query.len);
    defer allocator.free(positions);

    for (candidates, 0..) |candidate, i| {
        const match = term_matcher.findMatch(query, candidate, positions) catch unreachable;

        if (match) |m| {
            const new_match = RankedMatch{ .candidate = candidate, .input_index = i, .match = m };
            try matches.append(allocator, new_match);
        }
    }

    std.mem.sort(RankedMatch, matches.items, {}, lessThan);

    return try matches.toOwnedSlice(allocator);
}

/// Returns at most `limit` ranked matches without retaining every match.
pub fn filterCandidatesLimit(
    allocator: std.mem.Allocator,
    query: []const u8,
    candidates: []const []const u8,
    limit: usize,
) std.mem.Allocator.Error![]RankedMatch {
    if (limit == 0) return allocator.alloc(RankedMatch, 0);

    var matches: std.PriorityQueue(RankedMatch, void, compareWorstFirst) = .empty;
    defer {
        matches.clearAndFree(allocator);
        matches.deinit(allocator);
    }
    const positions = try allocator.alloc(usize, query.len);
    defer allocator.free(positions);

    for (candidates, 0..) |candidate, i| {
        const match = term_matcher.findMatch(query, candidate, positions) catch unreachable;

        if (match) |m| {
            const new_match = RankedMatch{ .candidate = candidate, .input_index = i, .match = m };

            if (matches.count() < limit) {
                try matches.push(allocator, new_match);
            } else {
                if (lessThan(matches.peek().?, new_match)) {
                    _ = matches.pop();
                    try matches.push(allocator, new_match);
                }
            }
        }
    }

    const output_slice = try allocator.dupe(RankedMatch, matches.items);
    std.mem.sort(RankedMatch, output_slice, {}, lessThan);

    return output_slice;
}

fn lessThan(_: void, lhs: RankedMatch, rhs: RankedMatch) bool {
    if (lhs.match.score == rhs.match.score) {
        if (lhs.candidate.len == rhs.candidate.len) {
            return lhs.input_index < rhs.input_index;
        }

        return lhs.candidate.len < rhs.candidate.len;
    }

    return lhs.match.score > rhs.match.score;
}

fn compareWorstFirst(_: void, lhs: RankedMatch, rhs: RankedMatch) std.math.Order {
    if (lhs.match.score == rhs.match.score) {
        if (lhs.candidate.len == rhs.candidate.len) {
            return if (lhs.input_index < rhs.input_index) std.math.Order.lt else std.math.Order.gt;
        }

        return if (lhs.candidate.len < rhs.candidate.len) std.math.Order.lt else std.math.Order.gt;
    }

    return if (lhs.match.score > rhs.match.score) std.math.Order.lt else std.math.Order.gt;
}

test "filter excludes non-matches and keeps match metadata" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "compiler", "validator", "validation" };

    const results = try filterCandidates(allocator, "vldtr", &candidates);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("validator", results[0].candidate);
    try std.testing.expectEqual(@as(usize, 1), results[0].input_index);
    try std.testing.expectEqual(@as(usize, 0), results[0].match.start);
    try std.testing.expectEqual(@as(usize, 9), results[0].match.end);
}

test "higher scores sort first" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "aXbYc", "abc" };

    const results = try filterCandidates(allocator, "abc", &candidates);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 2), results.len);
    try std.testing.expectEqualStrings("abc", results[0].candidate);
    try std.testing.expectEqualStrings("aXbYc", results[1].candidate);
    try std.testing.expect(results[0].match.score > results[1].match.score);
}

test "shorter candidates break score ties" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "alphabet", "atom", "arc" };

    const results = try filterCandidates(allocator, "a", &candidates);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 3), results.len);
    try std.testing.expectEqualStrings("arc", results[0].candidate);
    try std.testing.expectEqualStrings("atom", results[1].candidate);
    try std.testing.expectEqualStrings("alphabet", results[2].candidate);
}

test "input order breaks remaining ties" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "arc", "ant", "ape" };

    const results = try filterCandidates(allocator, "a", &candidates);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 3), results.len);
    for (results, candidates) |result, candidate| {
        try std.testing.expectEqualStrings(candidate, result.candidate);
    }
}

test "result records borrow candidate text" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{"abc"};

    const results = try filterCandidates(allocator, "abc", &candidates);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqual(@intFromPtr(candidates[0].ptr), @intFromPtr(results[0].candidate.ptr));
}

test "case-insensitive filtering preserves original candidate text" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "Validator", "compiler" };

    const results = try filterCandidates(allocator, "VLDTR", &candidates);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("Validator", results[0].candidate);
    try std.testing.expectEqual(@intFromPtr(candidates[0].ptr), @intFromPtr(results[0].candidate.ptr));
}

test "empty query includes every candidate" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "long", "x", "mid" };

    const results = try filterCandidates(allocator, "", &candidates);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, candidates.len), results.len);
    try std.testing.expectEqualStrings("x", results[0].candidate);
    try std.testing.expectEqualStrings("mid", results[1].candidate);
    try std.testing.expectEqualStrings("long", results[2].candidate);
}

test "empty candidate list returns an owned empty slice" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{};

    const results = try filterCandidates(allocator, "abc", &candidates);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "filter supports terms in any candidate order" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "alpha only", "beta alpha", "alpha beta" };

    const results = try filterCandidates(allocator, "alpha beta", &candidates);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 2), results.len);
    try std.testing.expectEqualStrings("alpha beta", results[0].candidate);
    try std.testing.expectEqualStrings("beta alpha", results[1].candidate);
}

test "limited filtering returns only the best matches" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "a---b---c", "aXbYc", "abc", "nope" };

    const results = try filterCandidatesLimit(allocator, "abc", &candidates, 2);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 2), results.len);
    try std.testing.expectEqualStrings("abc", results[0].candidate);
    try std.testing.expectEqualStrings("aXbYc", results[1].candidate);
}

test "limited filtering preserves ranking tie breakers" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "alphabet", "atom", "arc", "ape" };

    const results = try filterCandidatesLimit(allocator, "a", &candidates, 2);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 2), results.len);
    try std.testing.expectEqualStrings("arc", results[0].candidate);
    try std.testing.expectEqualStrings("ape", results[1].candidate);
}

test "zero limit returns an owned empty slice" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "abc", "alphabet" };

    const results = try filterCandidatesLimit(allocator, "a", &candidates, 0);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 0), results.len);
}

test "limit larger than match count returns every match" {
    const allocator = std.testing.allocator;
    const candidates = [_][]const u8{ "abc", "nope" };

    const results = try filterCandidatesLimit(allocator, "abc", &candidates, 10);
    defer allocator.free(results);

    try std.testing.expectEqual(@as(usize, 1), results.len);
    try std.testing.expectEqualStrings("abc", results[0].candidate);
}

test "limited filtering memory does not grow with match count" {
    var buffer: [4096]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&buffer);
    const candidates: [1000][]const u8 = @splat("abc");

    const results = try filterCandidatesLimit(fixed.allocator(), "abc", &candidates, 3);

    try std.testing.expectEqual(@as(usize, 3), results.len);
}
