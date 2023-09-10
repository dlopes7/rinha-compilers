const std = @import("std");
const spec = @import("spec.zig");
const Allocator = std.mem.Allocator;

const ParserState = enum { root, parsing };

const Error = error{ParserError};

pub const ASTParser = struct {
    allocator: Allocator,
    source: std.json.Reader(std.json.default_buffer_size, std.fs.File.Reader),
    state: ParserState = .root,
    currentLevel: u32 = 0,
    const log = std.log.scoped(.astParser);

    fn getString(self: *@This()) Error![]const u8 {
        const value = self.source.nextAlloc(self.allocator, .alloc_if_needed) catch |err| {
            log.err("Error parsing string: {any}", .{err});
            return Error.ParserError;
        };
        try switch (value) {
            .string => |s| return s,
            else => |err| {
                log.err("getString - expected string, found {any}", .{err});
                return Error.ParserError;
            },
        };
    }

    fn getU32(self: *@This()) Error!u32 {
        const value = self.source.nextAlloc(self.allocator, .alloc_if_needed) catch |err| {
            log.err("Error parsing string: {any}", .{err});
            return Error.ParserError;
        };
        try switch (value) {
            .number => |s| {
                return std.fmt.parseInt(u32, s, 10) catch |err| {
                    log.err("Error parsing u32: {any}", .{err});
                    return Error.ParserError;
                };
            },
            else => |err| {
                log.err("getU32 - expected number, found {any}", .{err});
                return Error.ParserError;
            },
        };
    }

    fn parseRoot(self: *@This(), s: []const u8) !void {
        if (std.mem.eql(u8, s, "name")) {
            const value = try self.getString();
            self.print("Found name {s}", .{value});
        } else if (std.mem.eql(u8, s, "expression")) {
            self.state = .parsing;
        }
    }

    fn getSourceNext(self: *@This()) Error!std.json.Token {
        return self.source.next() catch |err| {
            log.err("Error parsing string: {any}", .{err});
            return Error.ParserError;
        };
    }

    fn parseLoc(self: *@This()) Error!void {
        var loc: spec.Loc = undefined;
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_begin => {
                    // self.print("parseLoc - object_begin", .{});
                    self.currentLevel += 1;
                    continue;
                },
                .object_end => {
                    self.currentLevel -= 1;
                    // self.print("parseLoc - object_end", .{});
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "start")) {
                        loc.start = try self.getU32();
                    }
                    if (std.mem.eql(u8, value, "end")) {
                        loc.end = try self.getU32();
                    }
                    if (std.mem.eql(u8, value, "filename")) {
                        loc.filename = try self.getString();
                    }
                },
                else => |err| {
                    log.err("parseLoc - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }

        self.print("Loc(./{s}:{d}:{d})", .{ loc.filename, loc.start, loc.end });
    }

    fn parseParameter(self: *@This()) Error!void {
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_begin => {
                    self.currentLevel += 1;
                    continue;
                },
                .object_end => {
                    self.currentLevel -= 1;
                    return;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "text")) {
                        const text = try self.getString();
                        self.print("Parameter(text={s})", .{text});
                    }
                    if (std.mem.eql(u8, value, "location")) {
                        try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseParameter - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }

        // if (.object_begin != try self.getSourceNext()) {
        //     log.err("Expected object_begin,", .{});
        //     return;
        // }
        // const value = try self.getString();

        // if (std.mem.eql(u8, value, "text")) {
        //     const text = try self.getString();
        //     self.print("Parameter(text={s})", .{text});
        // }
    }

    fn parseLet(self: *@This()) Error!void {
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    return;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "name")) {
                        try self.parseParameter();
                    } else if (std.mem.eql(u8, value, "value")) {
                        try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "next")) {
                        try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "location")) {
                        try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseLet - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
    }
    fn parseBinaryOp(self: *@This()) Error!void {
        const value = try self.getString();
        self.print("BinaryOp(value={s})", .{value});
    }

    fn parseBinary(self: *@This()) Error!void {
        while (true) {
            const token = try self.getSourceNext();

            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    // self.print("parseBinary - object_end", .{});
                    return;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "lhs")) {
                        try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "op")) {
                        try self.parseBinaryOp();
                    } else if (std.mem.eql(u8, value, "rhs")) {
                        try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "location")) {
                        try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseBinary - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
    }

    fn parseInt(self: *@This()) Error!void {
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    // self.print("parseInt - object_end", .{});
                    return;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "value")) {
                        const number = try self.getU32();
                        self.print("Int(value={d})", .{number});
                    } else if (std.mem.eql(u8, value, "location")) {
                        try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseInt - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
    }

    fn print(self: *@This(), comptime format: []const u8, args: anytype) void {
        for (0..self.currentLevel) |_| {
            std.debug.print("  ", .{});
        }
        std.debug.print(format, args);
        std.debug.print("\n", .{});
    }

    fn parseTerm(self: *@This(), owner: []const u8) Error!void {
        _ = owner;
        while (true) {
            const token = try self.getSourceNext();

            switch (token) {
                .object_begin => {
                    // self.print("parseTerm(owner={s}) object_begin", .{owner});
                    self.currentLevel += 1;
                    continue;
                },
                .object_end => {
                    for (0..self.currentLevel) |_| {
                        std.debug.print(" ", .{});
                    }
                    // self.print("parseTerm(owner={s}) object_end", .{owner});
                    self.currentLevel -= 1;
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "kind")) {
                        const kind = try self.getString();

                        // self.print("parseTerm(owner={s}, kind={s})", .{ owner, kind });

                        const kindEnum = std.meta.stringToEnum(spec.ValidTerms, kind) orelse {
                            log.err("Found an invalid term kind={s}", .{kind});
                            return;
                        };
                        switch (kindEnum) {
                            .Let => {
                                try self.parseLet();
                                break;
                            },
                            .Binary => {
                                try self.parseBinary();
                                break;
                            },
                            .Int => {
                                try self.parseInt();
                                break;
                            },
                            else => |k| {
                                log.err("Not implemented for kind {any}", .{k});
                                break;
                            },
                        }
                    }
                },
                else => |err| {
                    log.err("parseTerm - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
    }

    pub fn next(self: *ASTParser) !bool {
        const token = try self.source.next();
        switch (token) {
            .string => |s| {
                if (std.mem.eql(u8, s, "expression")) {
                    try self.parseTerm("expression");
                } else if (std.mem.eql(u8, s, "location")) {
                    try self.parseLoc();
                }
            },
            .object_begin => {
                return true;
            },
            .object_end, .end_of_document => return false,
            else => |key| {
                self.print("Found an invalid key {any}", .{key});
                return false;
            },
        }
        return true;
    }

    pub fn parse(allocator: Allocator, reader: std.fs.File.Reader) !void {
        var timer = try std.time.Timer.start();

        // The underlying reader, which already handles JSON
        var source = std.json.reader(allocator, reader);

        // To enable diagnostics, declare `var diagnostics = Diagnostics{};` then call `source.enableDiagnostics(&diagnostics);`
        // where `source` is either a `std.json.Reader` or a `std.json.Scanner` that has just been initialized.
        // At any time, notably just after an error, call `getLine()`, `getColumn()`, and/or `getByteOffset()`
        // to get meaningful information from this.

        var diagnostics = std.json.Diagnostics{};
        source.enableDiagnostics(&diagnostics);
        defer log.debug("Line: {d}, Column: {d}", .{ diagnostics.getLine(), diagnostics.getColumn() });

        var parser = ASTParser{
            .allocator = allocator,
            .source = source,
        };
        while (try parser.next()) {
            // self.print("Line: {d}, Column: {d}", .{ diagnostics.getLine(), diagnostics.getColumn() });
        }

        const elapsed = timer.read();
        log.debug("ASTParser.parse: {}us", .{elapsed / 1000});
    }
};

fn concat(allocator: Allocator, a: []const u8, b: []const u8) ![]u8 {
    const result = try allocator.alloc(u8, a.len + b.len);
    std.mem.copy(u8, result, a);
    std.mem.copy(u8, result[a.len..], b);
    return result;
}
