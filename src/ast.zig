const std = @import("std");
const spec = @import("spec.zig");
const Allocator = std.mem.Allocator;

const ParserState = enum { root, parsing };

const Error = error{ParserError};

pub const ASTParser = struct {
    allocator: Allocator,
    source: std.json.Reader(std.json.default_buffer_size, std.fs.File.Reader),
    state: ParserState = .root,
    const log = std.log.scoped(.astParser);

    pub fn parse(allocator: Allocator, reader: std.fs.File.Reader) !void {
        var timer = try std.time.Timer.start();

        // The underlying reader, which already handles JSON
        const source = std.json.reader(allocator, reader);

        var parser = ASTParser{
            .allocator = allocator,
            .source = source,
        };
        while (try parser.next()) {}

        const elapsed = timer.read();
        log.debug("ASTParser.parse: {}us", .{elapsed / 1000});
    }

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
            log.debug("Found name {s}", .{value});
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
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_begin => {
                    continue;
                },
                .object_end => {
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "start")) {
                        const start = try self.getU32();
                        log.debug("Location(start={d})", .{start});
                    }
                    if (std.mem.eql(u8, value, "end")) {
                        const end = try self.getU32();
                        log.debug("Location(end={d})", .{end});
                    }
                    if (std.mem.eql(u8, value, "filename")) {
                        const filename = try self.getString();
                        log.debug("Location(filename={s})", .{filename});
                    }
                },
                else => |err| {
                    log.err("parseLoc - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
    }

    fn parseParameter(self: *@This()) Error!void {
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_begin => {
                    continue;
                },
                .object_end => {
                    return;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "text")) {
                        const text = try self.getString();
                        log.debug("Parameter(text={s})", .{text});
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
        //     log.debug("Parameter(text={s})", .{text});
        // }
    }

    fn parseLet(self: *@This()) Error!void {
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    log.debug("parseLet - Found object_end", .{});
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

    fn parseTerm(self: *@This(), s: []const u8) Error!void {
        const key = std.meta.stringToEnum(spec.ValidKeys, s) orelse {
            log.err("Key {s} not in spec.ValidKeys", .{s});
            return;
        };
        switch (key) {
            .kind => {
                const value = try self.getString();
                log.debug("parseTerm(key={s}, kind={s})", .{ s, value });
                const kind = std.meta.stringToEnum(spec.ValidTerms, value) orelse {
                    log.err("Found an invalid term kind={s}", .{value});
                    return;
                };
                switch (kind) {
                    .Let => {
                        try self.parseLet();
                    },
                    else => |k| {
                        log.err("Not implemented for kind {any}", .{k});
                    },
                }
            },
            else => |k| {
                log.err("Not implemented for key {any}", .{k});
                return Error.ParserError;
            },
        }
    }

    pub fn next(self: *ASTParser) !bool {
        const token = try self.source.next();
        switch (token) {
            .string => |str| {
                switch (self.state) {
                    .root => {
                        try self.parseRoot(str);
                    },
                    .parsing => {
                        try self.parseTerm(str);
                    },
                }
            },

            .object_begin => {
                return true;
            },
            .object_end, .end_of_document => return false,
            else => |key| {
                log.debug("Found an invalid key {any}", .{key});
                return false;
            },
        }
        return true;
    }
};
