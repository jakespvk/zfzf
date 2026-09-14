const std = @import("std");

const zfzf = @import("zfzf");

pub fn main(init: std.process.Init) !u8 {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();

    _ = args.skip();
    var cli_args: std.ArrayList([]const u8) = .empty;
    defer cli_args.deinit(init.gpa);
    while (args.next()) |arg| try cli_args.append(init.gpa, arg);

    const options = zfzf.cli.parseArgs(cli_args.items) catch return usage(init.io);

    var stdin_buffer: [4096]u8 = undefined;
    var stdin_file_reader: std.Io.File.Reader = .init(.stdin(), init.io, &stdin_buffer);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    try zfzf.cli.run(init.gpa, options.query, options.limit, &stdin_file_reader.interface, stdout_writer);
    try stdout_writer.flush();

    return 0;
}

fn usage(io: std.Io) u8 {
    var stderr_buffer: [256]u8 = undefined;
    var stderr_file_writer: std.Io.File.Writer = .init(.stderr(), io, &stderr_buffer);
    const stderr_writer = &stderr_file_writer.interface;

    stderr_writer.writeAll("usage: zfzf [--limit <count>] <query>\n") catch {};
    stderr_writer.flush() catch {};

    return 2;
}
