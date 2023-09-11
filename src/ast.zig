const std = @import("std");
const spec = @import("spec.zig");
const eval = @import("eval.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

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

    fn parseString(self: *@This()) Error!spec.Str {
        var str: spec.Str = undefined;
        str.kind = spec.ValidTerms.Str;
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
                    if (std.mem.eql(u8, value, "value")) {
                        str.value = try self.getString();
                    }
                    if (std.mem.eql(u8, value, "location")) {
                        str.location = try self.parseLoc();
                    }
                },
                else => |err| {
                    log.err("parseString - expected string, found {any}", .{err});
                    return Error.ParserError;
                },
            }
        }
        return str;
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

    fn parseParameters(self: *@This()) Error!ArrayList(spec.Parameter) {
        var params = ArrayList(spec.Parameter).init(self.allocator);

        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_begin => {
                    self.currentLevel += 1;
                    const param = try self.parseParameter();
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
        return params;
    }

    fn parseParameter(self: *@This()) Error!spec.Parameter {
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
        return param;
    }

    fn parseLet(self: *@This()) Error!spec.Let {
        var let: spec.Let = undefined;
        let.kind = spec.ValidTerms.Let;
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "name")) {
                        let.name = try self.parseParameter();
                    } else if (std.mem.eql(u8, value, "value")) {
                        let.value = &try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "next")) {
                        let.next = &try self.parseTerm(value);
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
        function.kind = spec.ValidTerms.Function;
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "parameters")) {
                        function.parameters = try self.parseParameters();
                    } else if (std.mem.eql(u8, value, "value")) {
                        function.value = &try self.parseTerm(value);
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

    fn parseBinaryOp(self: *@This()) Error!spec.BinaryOp {
        const value = try self.getString();
        const enumValue = std.meta.stringToEnum(spec.BinaryOp, value) orelse {
            log.err("Found an invalid binary op {s}", .{value});
            return Error.ParserError;
        };
        return enumValue;
    }

    fn parseBinary(self: *@This()) Error!spec.Binary {
        var bin: spec.Binary = undefined;
        bin.kind = spec.ValidTerms.Binary;
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
                        bin.lhs = &try self.parseTerm(value);
                        self.println("bin.lhs={any}", .{bin.lhs.varTerm});
                    } else if (std.mem.eql(u8, value, "op")) {
                        bin.op = try self.parseBinaryOp();
                    } else if (std.mem.eql(u8, value, "rhs")) {
                        bin.rhs = &try self.parseTerm(value);
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
        self.println("Binary(lhs={any}, op={any}, rhs={any})", .{ bin.lhs, bin.op, bin.rhs });
        return bin;
    }

    fn parseInt(self: *@This()) Error!spec.Int {
        var int: spec.Int = undefined;
        int.kind = spec.ValidTerms.Int;
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
        variable.kind = spec.ValidTerms.Var;
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
                        self.println("parseVar={s}", .{variable.text});
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
        self.println("parseVar({any})", .{variable});
        return variable;
    }

    fn parseCall(self: *@This()) Error!spec.Call {
        var call: spec.Call = undefined;
        call.kind = spec.ValidTerms.Call;
        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "callee")) {
                        call.callee = &try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "arguments")) {
                        call.arguments = try self.parseTerms(value);
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
        print.kind = spec.ValidTerms.Print;

        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "value")) {
                        print.value = &try self.parseTerm(value);
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
        specIf.kind = spec.ValidTerms.If;

        while (true) {
            const token = try self.getSourceNext();
            switch (token) {
                .object_end => {
                    self.currentLevel -= 1;
                    break;
                },
                .string => |value| {
                    if (std.mem.eql(u8, value, "condition")) {
                        specIf.condition = &try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "then")) {
                        specIf.then = &try self.parseTerm(value);
                    } else if (std.mem.eql(u8, value, "otherwise")) {
                        specIf.otherwise = &try self.parseTerm(value);
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

    fn parseTerms(self: *@This(), owner: []const u8) Error!ArrayList(spec.Term) {
        var terms = ArrayList(spec.Term).init(self.allocator);
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
        var term: spec.Term = undefined;
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
                                term = spec.Term{ .let = let };
                                break;
                            },
                            .Function => {
                                const function = try self.parseFunction();
                                term = spec.Term{ .function = function };
                                break;
                            },
                            .Binary => {
                                const binary = try self.parseBinary();
                                term = spec.Term{ .binary = binary };
                                break;
                            },
                            .Int => {
                                const int = try self.parseInt();
                                term = spec.Term{ .int = int };
                                break;
                            },
                            .Var => {
                                term = spec.Term{ .varTerm = try self.parseVar() };
                                break;
                            },
                            .Call => {
                                const call = try self.parseCall();
                                term = spec.Term{ .call = call };
                                break;
                            },
                            .Print => {
                                const print = try self.parsePrint();
                                term = spec.Term{ .print = print };
                                break;
                            },
                            .If => {
                                const ifTerm = try self.parseIf();
                                term = spec.Term{ .ifTerm = ifTerm };
                                break;
                            },
                            .Str => {
                                const str = try self.parseString();
                                term = spec.Term{ .str = str };
                                break;
                            },

                            else => |k| {
                                // TODO -  Bool, First, Second, Tuple
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

        // _ = eval.eval(term, self.allocator) catch |err| {
        //     log.err("Error evaluating term: {any}", .{err});
        //     return Error.ParserError;
        // };
        return term;
    }

    pub fn next(self: *ASTParser) !bool {
        const token = try self.source.next();
        switch (token) {
            .string => |s| {
                if (std.mem.eql(u8, s, "expression")) {
                    var t = try self.parseTerm("expression");
                    self.println("********** Try to eval {any}", .{t});
                    _ = eval.eval(t, self.allocator) catch |err| {
                        log.err("Error evaluating term: {any}", .{err});
                        return Error.ParserError;
                    };
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
