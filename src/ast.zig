const std = @import("std");
const spec = @import("spec.zig");
const eval = @import("eval.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const ParserState = enum { root, parsing };

const Error = error{ ParserError, OutOfMemory, EvalError, CompilerError };

fn createInit(alloc: std.mem.Allocator, comptime T: type, props: anytype) !*T {
    const new = try alloc.create(T);
    new.* = props;
    return new;
}

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
            .string => |s| {
                // allocate a new string
                var str = ArrayList(u8).init(self.allocator);
                try str.appendSlice(s);
                return try str.toOwnedSlice();
            },
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

    fn parseString(self: *@This()) Error!spec.Str {
        var value: []const u8 = undefined;
        var location: spec.Loc = undefined;
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
                .string => |v| {
                    if (std.mem.eql(u8, v, "value")) {
                        value = try self.getString();
                    }
                    if (std.mem.eql(u8, v, "location")) {
                        location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseString - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
        return spec.Str{ .kind = spec.ValidTerms.Str, .value = value, .location = location };
    }

    fn parseLoc(self: *@This()) Error!spec.Loc {
        var start: u32 = 0;
        var end: u32 = 0;
        var filename: []const u8 = undefined;

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
                        start = try self.getNumber(u32);
                    }
                    if (std.mem.eql(u8, value, "end")) {
                        end = try self.getNumber(u32);
                    }
                    if (std.mem.eql(u8, value, "filename")) {
                        filename = try self.getString();
                    }
                },
                else => |err| {
                    log.err("parseLoc - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }

        // self.println("Loc(./{s}:{d}:{d})", .{ filename, start, end });
        return spec.Loc{ .start = start, .end = end, .filename = filename };
    }

    fn parseParameters(self: *@This()) Error!ArrayList(spec.Parameter) {
        var params = ArrayList(spec.Parameter).init(self.allocator);
        // defer params.deinit();

        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_begin => {
                    self.currentLevel += 1;
                    var param = try self.parseParameter();
                    params.append(param) catch |err| {
                        log.err("Error appending parameter: {any}", .{err});
                        return Error.ParserError;
                    };
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
        // var ret = try createInit(self.allocator, ArrayList(*spec.Parameter), .{ .items = params.items, .allocator = params.allocator });
        return params;
    }

    fn parseParameter(self: *@This()) Error!spec.Parameter {
        // var param: spec.Parameter = undefined;
        var text: []const u8 = undefined;
        var location: spec.Loc = undefined;
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
                        text = try self.getString();
                    }
                    if (std.mem.eql(u8, value, "location")) {
                        location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseParameter - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }

        // self.println("Parameter(text={s}, location=...)", .{param.text});
        // var ret = try createInit(self.allocator, spec.Parameter, .{ .text = param.text, .location = param.location });
        return spec.Parameter{ .text = text, .location = location };
    }

    fn parseLet(self: *@This()) Error!spec.Let {
        var name: spec.Parameter = undefined;
        var value: spec.Term = undefined;
        var nextTerm: spec.Term = undefined;
        var location: spec.Loc = undefined;

        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |v| {
                    if (std.mem.eql(u8, v, "name")) {
                        name = try self.parseParameter();
                    } else if (std.mem.eql(u8, v, "value")) {
                        value = try self.parseTerm(v);
                    } else if (std.mem.eql(u8, v, "next")) {
                        nextTerm = try self.parseTerm(v);
                    } else if (std.mem.eql(u8, v, "location")) {
                        location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseLet - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
        // var ret = try createInit(self.allocator, spec.Let, .{ .kind = let.kind, .name = let.name, .value = let.value, .next = let.next, .location = let.location });
        return spec.Let{ .kind = spec.ValidTerms.Let, .name = name, .value = value, .next = nextTerm, .location = location };
    }

    fn parseFunction(self: *@This()) Error!spec.Function {
        // var function: spec.Function = undefined;
        // function.kind = spec.ValidTerms.Function;
        var parameters: ArrayList(spec.Parameter) = undefined;
        var value: spec.Term = undefined;
        var location: spec.Loc = undefined;

        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |v| {
                    if (std.mem.eql(u8, v, "parameters")) {
                        parameters = try self.parseParameters();
                    } else if (std.mem.eql(u8, v, "value")) {
                        value = try self.parseTerm(v);
                    } else if (std.mem.eql(u8, v, "location")) {
                        location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseFunction - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
        // var ret = try createInit(self.allocator, spec.Function, .{ .kind = function.kind, .parameters = function.parameters, .value = function.value, .location = function.location });
        return spec.Function{ .kind = spec.ValidTerms.Function, .parameters = parameters, .value = value, .location = location };
    }

    fn parseBinaryOp(self: *@This()) Error!spec.BinaryOp {
        const value = try self.getString();
        var enumValue = std.meta.stringToEnum(spec.BinaryOp, value) orelse {
            log.err("Found an invalid binary op {s}", .{value});
            return Error.ParserError;
        };
        return enumValue;
    }

    fn parseBinary(self: *@This()) Error!spec.Binary {
        // var bin: spec.Binary = undefined;
        // bin.kind = spec.ValidTerms.Binary;
        var lhs: spec.Term = undefined;
        var op: spec.BinaryOp = undefined;
        var rhs: spec.Term = undefined;
        var location: spec.Loc = undefined;
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
                        lhs = try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "op")) {
                        op = try self.parseBinaryOp();
                    } else if (std.mem.eql(u8, value, "rhs")) {
                        rhs = try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "location")) {
                        location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseBinary - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
        // self.println("Binary(lhs={any}, op={any}, rhs={any})", .{ bin.lhs, bin.op, bin.rhs });
        // var ret = try createInit(self.allocator, spec.Binary, .{ .kind = bin.kind, .lhs = bin.lhs, .op = bin.op, .rhs = bin.rhs, .location = bin.location });
        return spec.Binary{ .kind = spec.ValidTerms.Binary, .lhs = lhs, .op = op, .rhs = rhs, .location = location };
    }

    fn parseInt(self: *@This()) Error!spec.Int {
        var value: i32 = 0;
        var location: spec.Loc = undefined;
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    // self.print("parseInt - object_end", .{});
                    break;
                },
                .string => |v| {
                    if (std.mem.eql(u8, v, "value")) {
                        value = try self.getNumber(i32);
                    } else if (std.mem.eql(u8, v, "location")) {
                        location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseInt - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
        // self.println("Int(value={d})", .{int.value});
        // var ret = try createInit(self.allocator, spec.Int, .{ .kind = int.kind, .value = int.value, .location = int.location });

        return spec.Int{ .kind = spec.ValidTerms.Int, .value = value, .location = location };
    }

    fn parseVar(self: *@This()) Error!spec.Var {
        var text: []const u8 = undefined;
        var location: spec.Loc = undefined;
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "text")) {
                        text = try self.getString();
                    } else if (std.mem.eql(u8, value, "location")) {
                        location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseVar - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
        // self.println("parseVar({any})", .{variable});
        // var ret = try createInit(self.allocator, spec.Var, .{ .kind = variable.kind, .text = variable.text, .location = variable.location });
        return spec.Var{ .kind = spec.ValidTerms.Var, .text = text, .location = location };
    }

    fn parseCall(self: *@This()) Error!spec.Call {
        var callee: spec.Term = undefined;
        var arguments: ArrayList(spec.Term) = undefined;
        var location: spec.Loc = undefined;

        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "callee")) {
                        callee = try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "arguments")) {
                        arguments = try self.parseTerms(value);
                    } else if (std.mem.eql(u8, value, "location")) {
                        location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseVar - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
        // self.println("Call({any})", .{call.location});
        // var ret = try createInit(self.allocator, spec.Call, .{ .kind = call.kind, .callee = call.callee, .arguments = call.arguments, .location = call.location });
        return spec.Call{ .kind = spec.ValidTerms.Call, .callee = callee, .arguments = arguments, .location = location };
    }

    fn parsePrint(self: *@This()) Error!spec.Print {
        var value: spec.Term = undefined;
        var location: spec.Loc = undefined;

        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |v| {
                    if (std.mem.eql(u8, v, "value")) {
                        value = try self.parseTerm(v);
                    } else if (std.mem.eql(u8, v, "location")) {
                        location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parsePrint - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
        // var ret = try createInit(self.allocator, spec.Print, .{ .kind = print.kind, .value = print.value, .location = print.location });
        return spec.Print{ .kind = spec.ValidTerms.Print, .value = value, .location = location };
    }

    fn parseIf(self: *@This()) Error!spec.If {
        var condition: spec.Term = undefined;
        var then: spec.Term = undefined;
        var otherwise: spec.Term = undefined;
        var location: spec.Loc = undefined;

        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "condition")) {
                        condition = try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "then")) {
                        then = try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "otherwise")) {
                        otherwise = try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "location")) {
                        location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseIf - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }

        // var ret = try createInit(self.allocator, spec.If, .{ .kind = specIf.kind, .condition = specIf.condition, .then = specIf.then, .otherwise = specIf.otherwise, .location = specIf.location });
        return spec.If{ .kind = spec.ValidTerms.If, .condition = condition, .then = then, .otherwise = otherwise, .location = location };
    }

    fn println(self: *@This(), comptime format: []const u8, args: anytype) void {
        for (0..self.currentLevel) |_| {
            std.debug.print("  ", .{});
        }
        std.debug.print(format, args);
        std.debug.print("\n", .{});
    }

    fn parseTerms(self: *@This(), owner: []const u8) Error!ArrayList(spec.Term) {
        var terms = ArrayList(spec.Term).init(self.allocator);
        // defer terms.deinit();
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_begin => {
                    self.currentLevel += 1;
                    const term = try self.parseTerm(owner);
                    terms.append(term) catch |err| {
                        log.err("Error appending term: {any}", .{err});
                        return Error.ParserError;
                    };
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
        return terms;
    }

    fn parseTerm(self: *@This(), owner: []const u8) Error!spec.Term {
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
                            return Error.ParserError;
                        };
                        switch (kindEnum) {
                            .Let => {
                                const let = try self.parseLet();
                                var allocated = try createInit(self.allocator, spec.Let, .{ .kind = let.kind, .name = let.name, .value = let.value, .next = let.next, .location = let.location });
                                return spec.Term{ .let = allocated };
                            },
                            .Function => {
                                const function = try self.parseFunction();
                                var allocated = try createInit(self.allocator, spec.Function, .{ .kind = function.kind, .parameters = function.parameters, .value = function.value, .location = function.location });
                                return spec.Term{ .function = allocated };
                            },
                            .Binary => {
                                const binary = try self.parseBinary();
                                var allocated = try createInit(self.allocator, spec.Binary, .{ .kind = binary.kind, .lhs = binary.lhs, .op = binary.op, .rhs = binary.rhs, .location = binary.location });
                                return spec.Term{ .binary = allocated };
                            },
                            .Int => {
                                const int = try self.parseInt();
                                var allocated = try createInit(self.allocator, spec.Int, .{ .kind = int.kind, .value = int.value, .location = int.location });
                                return spec.Term{ .int = allocated };
                            },
                            .Var => {
                                const varTerm = try self.parseVar();
                                var allocated = try createInit(self.allocator, spec.Var, .{ .kind = varTerm.kind, .text = varTerm.text, .location = varTerm.location });
                                return spec.Term{ .varTerm = allocated };
                            },
                            .Call => {
                                const call = try self.parseCall();
                                var allocated = try createInit(self.allocator, spec.Call, .{ .kind = call.kind, .callee = call.callee, .arguments = call.arguments, .location = call.location });
                                return spec.Term{ .call = allocated };
                            },
                            .Print => {
                                const print = try self.parsePrint();
                                var allocated = try createInit(self.allocator, spec.Print, .{ .kind = print.kind, .value = print.value, .location = print.location });
                                return spec.Term{ .print = allocated };
                            },
                            .If => {
                                const ifTerm = try self.parseIf();
                                var allocated = try createInit(self.allocator, spec.If, .{ .kind = ifTerm.kind, .condition = ifTerm.condition, .then = ifTerm.then, .otherwise = ifTerm.otherwise, .location = ifTerm.location });
                                return spec.Term{ .ifTerm = allocated };
                            },
                            .Str => {
                                const str = try self.parseString();
                                var allocated = try createInit(self.allocator, spec.Str, .{ .kind = str.kind, .value = str.value, .location = str.location });
                                return spec.Term{ .str = allocated };
                            },

                            else => |k| {
                                // TODO -  Bool, First, Second, Tuple
                                log.err("Not implemented for kind {any}", .{k});
                                return Error.ParserError;
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
        return Error.ParserError;
    }

    const NextElement = struct { term: ?spec.Term, end: bool };

    pub fn next(self: *ASTParser) !bool {
        var token = try self.source.next();
        // defer self.allocator.free(token);
        switch (token) {
            .string => |s| {
                if (std.mem.eql(u8, s, "expression")) {
                    var program = try self.parseTerm("expression");
                    // _ = try eval.eval(program, self.allocator);
                    var terms: ArrayList(spec.Term) = ArrayList(spec.Term).init(self.allocator);
                    try eval.traverse(program, &terms);
                    var i: usize = terms.items.len;
                    while (i > 0) {
                        i -= 1;
                        // self.println("Traversed term {any}", .{terms.items[i]});
                        _ = try eval.eval(terms.items[i], self.allocator);
                    }
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

        while (try parser.next()) {}

        const elapsed = timer.read();
        log.debug("ASTParser.parse: {}us", .{elapsed / 1000});
    }
};
