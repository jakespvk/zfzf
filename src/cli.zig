const std = @import("std");

const filter = @import("filter.zig");

pub const max_input_bytes = 64 * 1024 * 1024;

pub const Options = struct {
    query: []const u8,
    limit: ?usize,
};

pub const ParseArgsError = error{
    InvalidArguments,
    InvalidLimit,
};

/// Parses either `<query>` or `--limit <count> <query>`.
pub fn parseArgs(args: []const []const u8) ParseArgsError!Options {
    // Challenge 7: add --limit parsing.
    if (args.len < 1) return error.InvalidArguments;

    if (args.len == 1) return .{ .query = args[0], .limit = null };

    if (std.mem.eql(u8, args[0], "--limit")) {
        if (args.len >= 3) {
            const limit = try parseLimit(args[1]);
            return .{ .query = args[2], .limit = limit };
        } else return error.InvalidArguments;
    }

    return error.InvalidArguments;
}

fn parseLimit(limit_arg: []const u8) ParseArgsError!usize {
    return std.fmt.parseInt(usize, limit_arg, 10) catch return error.InvalidLimit;
}

/// Reads newline-delimited candidates, filters them, and writes ranked matches.
pub fn run(
    allocator: std.mem.Allocator,
    query: []const u8,
    limit: ?usize,
    input: *std.Io.Reader,
    output: *std.Io.Writer,
) !void {
    const input_text = try input.allocRemaining(allocator, .limited(max_input_bytes));
    defer allocator.free(input_text);

    if (input_text.len == 0) return;

    var input_split = std.mem.splitScalar(u8, input_text, '\n');
    var candidates: std.ArrayList([]const u8) = .empty;
    defer candidates.deinit(allocator);

    while (input_split.next()) |candidate| {
        if (std.mem.endsWith(u8, candidate, "\r")) {
            try candidates.append(allocator, candidate[0 .. candidate.len - 1]);
        } else {
            try candidates.append(allocator, candidate);
        }
    }

    if (std.mem.endsWith(u8, input_text, "\n")) {
        _ = candidates.pop();
    }

    const matches = if (limit) |max_results|
        try filter.filterCandidatesLimit(allocator, query, candidates.items, max_results)
    else
        try filter.filterCandidates(allocator, query, candidates.items);
    defer allocator.free(matches);

    for (matches) |match| {
        try output.print("{s}\n", .{match.candidate});
    }
}

fn expectOutput(query: []const u8, input_text: []const u8, expected: []const u8) !void {
    var input = std.Io.Reader.fixed(input_text);
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    try run(std.testing.allocator, query, null, &input, &output.writer);

    try std.testing.expectEqualStrings(expected, output.written());
}

test "prints matching candidates in ranked order" {
    try expectOutput(
        "abc",
        "aXbYc\nabc\nnope\n",
        "abc\naXbYc\n",
    );
}

test "supports case-insensitive unordered terms" {
    try expectOutput(
        "ALPHA beta",
        "Alpha only\nBeta Alpha\nalpha beta\n",
        "alpha beta\nBeta Alpha\n",
    );
}

test "accepts CRLF input and writes LF output" {
    try expectOutput(
        "vldtr",
        "compiler\r\nValidator\r\n",
        "Validator\n",
    );
}

test "includes an unterminated final candidate" {
    try expectOutput("abc", "nope\nabc", "abc\n");
}

test "preserves interior empty candidates" {
    try expectOutput("", "long\n\nx\n", "\nx\nlong\n");
}

test "terminal newline does not create another candidate" {
    try expectOutput("", "long\nx\n", "x\nlong\n");
}

test "unterminated CR-only candidate is preserved" {
    try expectOutput("", "\r", "\n");
}

test "empty input produces no output" {
    try expectOutput("", "", "");
}

test "parses a query without a limit" {
    const options = try parseArgs(&.{"abc"});

    try std.testing.expectEqualStrings("abc", options.query);
    try std.testing.expectEqual(null, options.limit);
}

test "parses a decimal result limit" {
    const options = try parseArgs(&.{ "--limit", "2", "abc" });

    try std.testing.expectEqualStrings("abc", options.query);
    try std.testing.expectEqual(@as(?usize, 2), options.limit);
}

test "zero is a valid result limit" {
    const options = try parseArgs(&.{ "--limit", "0", "abc" });

    try std.testing.expectEqual(@as(?usize, 0), options.limit);
}

test "rejects a missing limit value" {
    try std.testing.expectError(error.InvalidArguments, parseArgs(&.{ "--limit", "abc" }));
}

test "rejects a non-decimal limit" {
    try std.testing.expectError(error.InvalidLimit, parseArgs(&.{ "--limit", "two", "abc" }));
}

test "rejects an overflowing limit" {
    try std.testing.expectError(error.InvalidLimit, parseArgs(&.{ "--limit", "999999999999999999999999999999999", "abc" }));
}

test "run applies the result limit" {
    var input = std.Io.Reader.fixed("a---b---c\naXbYc\nabc\n");
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    try run(std.testing.allocator, "abc", 2, &input, &output.writer);

    try std.testing.expectEqualStrings("abc\naXbYc\n", output.written());
}
