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

    fn getNumber(self: *@This(), comptime T: type) Error!T {
        const value = self.source.nextAlloc(self.allocator, .alloc_if_needed) catch |err| {
            log.err("Error parsing string: {any}", .{err});
            return Error.ParserError;
        };
        try switch (value) {
            .number => |s| {
                return std.fmt.parseInt(T, s, 10) catch |err| {
                    log.err("Error parsing u32: {any}", .{err});
                    return Error.ParserError;
                };
            },
            else => |err| {
                log.err("getNumber - expected number, found {any}", .{err});
                return Error.ParserError;
            },
        };
    }

    fn parseRoot(self: *@This(), s: []const u8) !void {
        if (std.mem.eql(u8, s, "name")) {
            const value = try self.getString();
            self.println("Found name {s}", .{value});
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

    fn parseLoc(self: *@This()) Error!spec.Loc {
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
                        loc.start = try self.getNumber(u32);
                    }
                    if (std.mem.eql(u8, value, "end")) {
                        loc.end = try self.getNumber(u32);
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

        self.println("Loc(./{s}:{d}:{d})", .{ loc.filename, loc.start, loc.end });
        return loc;
    }

    fn parseParameters(self: *@This()) Error!void {
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_begin => {
                    self.currentLevel += 1;
                    try self.parseParameter();
                    continue;
                },
                .array_begin => {
                    continue;
                },
                .array_end => {
                    break;
                },
                else => |err| {
                    log.err("parseParameters - expected object_begin, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
    }

    fn parseParameter(self: *@This()) Error!void {
        var param: spec.Parameter = undefined;
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_begin => {
                    self.currentLevel += 1;
                    continue;
                },
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "text")) {
                        param.text = try self.getString();
                    }
                    if (std.mem.eql(u8, value, "location")) {
                        param.location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseParameter - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }

        self.println("Parameter(text={s}, location=...)", .{param.text});
    }

    fn parseLet(self: *@This()) Error!spec.Let {
        var let: spec.Let = undefined;
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "name")) {
                        // TODO assign
                        try self.parseParameter();
                    } else if (std.mem.eql(u8, value, "value")) {
                        // TODO assign
                        try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "next")) {
                        // TODO assign
                        try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "location")) {
                        let.location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseLet - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
        return let;
    }

    fn parseFunction(self: *@This()) Error!spec.Function {
        var function: spec.Function = undefined;
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "parameters")) {
                        // TODO - assign
                        try self.parseParameters();
                    } else if (std.mem.eql(u8, value, "value")) {
                        // TODO - assign
                        try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "location")) {
                        function.location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseFunction - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
        return function;
    }

    fn parseBinaryOp(self: *@This()) Error!void {
        const value = try self.getString();
        self.println("BinaryOp(value={s})", .{value});
    }

    fn parseBinary(self: *@This()) Error!spec.Binary {
        var bin: spec.Binary = undefined;
        while (true) {
            const token = try self.getSourceNext();

            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    // self.print("parseBinary - object_end", .{});
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "lhs")) {
                        // TODO - assign
                        try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "op")) {
                        // TODO - assign
                        try self.parseBinaryOp();
                    } else if (std.mem.eql(u8, value, "rhs")) {
                        // TODO - assign
                        try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "location")) {
                        bin.location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseBinary - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
        return bin;
    }

    fn parseInt(self: *@This()) Error!spec.Int {
        var int: spec.Int = undefined;
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    // self.print("parseInt - object_end", .{});
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "value")) {
                        int.value = try self.getNumber(i32);
                    } else if (std.mem.eql(u8, value, "location")) {
                        int.location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseInt - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
        self.println("Int(value={d})", .{int.value});
        return int;
    }

    fn parseVar(self: *@This()) Error!spec.Var {
        var variable: spec.Var = undefined;
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "text")) {
                        variable.text = try self.getString();
                    } else if (std.mem.eql(u8, value, "location")) {
                        variable.location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseVar - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
        self.println("Var({s})", .{variable.text});
        return variable;
    }

    fn parseCall(self: *@This()) Error!spec.Call {
        var call: spec.Call = undefined;
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "callee")) {
                        // TODO -  call.callee = try self.parseTerm(value);
                        try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "arguments")) {
                        // TODO - call.arguments = try self.parseTerms(value);
                        try self.parseTerms(value);
                    } else if (std.mem.eql(u8, value, "location")) {
                        call.location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseVar - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
        self.println("Call({any})", .{call.location});
        return call;
    }

    fn parsePrint(self: *@This()) Error!spec.Print {
        var print: spec.Print = undefined;

        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "value")) {
                        // TODO print.value = try self.parseTerm(value);
                        try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "location")) {
                        print.location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parsePrint - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }

        return print;
    }

    fn parseIf(self: *@This()) Error!spec.If {
        var specIf: spec.If = undefined;

        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "condition")) {
                        // TODO specIf.condition = try self.parseTerm(value);
                        try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "then")) {
                        try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "otherwise")) {
                        try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "location")) {
                        specIf.location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseIf - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }

        return specIf;
    }

    fn println(self: *@This(), comptime format: []const u8, args: anytype) void {
        for (0..self.currentLevel) |_| {
            std.debug.print("  ", .{});
        }
        std.debug.print(format, args);
        std.debug.print("\n", .{});
    }

    fn parseTerms(self: *@This(), owner: []const u8) Error!void {
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_begin => {
                    self.currentLevel += 1;
                    try self.parseTerm(owner);
                    continue;
                },
                .array_begin => {
                    continue;
                },
                .array_end => {
                    break;
                },
                else => |err| {
                    log.err("parseTerms - expected object_begin, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
    }

    fn parseTerm(self: *@This(), owner: []const u8) Error!void {
        while (true) {
            const token = try self.getSourceNext();

            switch (token) {
                .object_begin => {
                    self.println("parseTerm(owner={s}) object_begin", .{owner});
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

                        self.println("parseTerm(owner={s}, kind={s})", .{ owner, kind });

                        const kindEnum = std.meta.stringToEnum(spec.ValidTerms, kind) orelse {
                            log.err("Found an invalid term kind={s}", .{kind});
                            return;
                        };
                        switch (kindEnum) {
                            .Let => {
                                _ = try self.parseLet();
                                break;
                            },
                            .Function => {
                                _ = try self.parseFunction();
                                break;
                            },
                            .Binary => {
                                _ = try self.parseBinary();
                                break;
                            },
                            .Int => {
                                _ = try self.parseInt();
                                break;
                            },
                            .Var => {
                                _ = try self.parseVar();
                                break;
                            },
                            .Call => {
                                _ = try self.parseCall();
                                break;
                            },
                            .Print => {
                                _ = try self.parsePrint();
                                break;
                            },
                            .If => {
                                _ = try self.parseIf();
                                break;
                            },
                            else => |k| {
                                // TODO - Str, Bool, First, Second, Tuple
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
                    _ = try self.parseLoc();
                }
            },
            .object_begin => {
                return true;
            },
            .object_end, .end_of_document => return false,
            else => |key| {
                self.println("Found an invalid key {any}", .{key});
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
        defer log.debug("Line: {any}", .{diagnostics.getLine()});

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
