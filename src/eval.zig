const std = @import("std");
const spec = @import("spec.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const print = std.debug.print;

const SupportedValues = union(enum) { int: i32, str: []const u8, bool: bool };

const Error = error{ EvalError, CompilerError, OutOfMemory };

fn evalParameters(params: ArrayList(spec.Parameter), allocator: Allocator) Error!ArrayList([]const u8) {
    var result = ArrayList([]const u8).init(allocator);
    for (params.items) |param| {
        const value = evalParameter(param);
        try result.append(value);
    }
    return result;
}
fn evalParameter(param: spec.Parameter) []const u8 {
    return param.text;
}

fn evalTerms(terms: ArrayList(spec.Term), allocator: Allocator) Error!ArrayList(SupportedValues) {
    var result = ArrayList(SupportedValues).init(allocator);
    for (terms.items) |term| {
        const value = try eval(term, allocator);
        try result.append(value);
    }
    return result;
}

pub fn eval(term: spec.Term, allocator: Allocator) Error!SupportedValues {
    switch (term) {
        .function => |f| {
            // print("eval function {any}\n", .{f});
            const parameters = try evalParameters(f.parameters, allocator);
            _ = parameters;
            const value = try eval(f.value, allocator);
            _ = value;

            // print("Function - (", .{});
            // for (parameters.items) |param| {
            //     print(" {s} ", .{param});
            // }
            // print(")\n", .{});

            return SupportedValues{ .str = "function" };
        },
        .let => |l| {
            print("eval let {any}\n", .{l});
            const name = evalParameter(l.name);
            _ = name;
            const value = try eval(l.value, allocator);
            _ = value;
            const next = try eval(l.next, allocator);
            _ = next;
            // print("Let - {s}({any}) -> {any}", .{ name, value, next });
            return SupportedValues{ .str = "let" };
        },
        .ifTerm => |v| {
            print("eval if {any}\n", .{v});
        },
        .varTerm => |v| {
            print("eval var {any}\n", .{v});
            return SupportedValues{ .str = v.text };
        },
        .binary => |bin| {
            print("eval binary {any}\n", .{bin});

            switch (bin.op) {
                .Add => {
                    const left = try eval(bin.lhs, allocator);
                    const right = try eval(bin.rhs, allocator);
                    switch (left) {
                        .int => |l| {
                            switch (right) {
                                .int => |r| {
                                    // l is int, r is int
                                    return SupportedValues{ .int = l + r };
                                },
                                .str => |r| {
                                    // l is int, r is str
                                    const concatenated = try std.fmt.allocPrint(allocator, "{any}{any}", .{ l, r });
                                    return SupportedValues{ .str = concatenated };
                                },
                                else => {
                                    // l is int, r is unsupported
                                    return Error.CompilerError;
                                },
                            }
                        },
                        .str => |l| {
                            switch (right) {
                                .int => |r| {
                                    // l is str, r is int
                                    const concatenated = try std.fmt.allocPrint(allocator, "{any}{any}", .{ l, r });
                                    return SupportedValues{ .str = concatenated };
                                },
                                .str => |r| {
                                    // l is str, r is str
                                    const concatenated = try std.fmt.allocPrint(allocator, "{any}{any}", .{ l, r });
                                    return SupportedValues{ .str = concatenated };
                                },
                                else => |r| {
                                    // l is str, r is unsupported
                                    print("Compiler error:  cannot perform {any} on {any} and {any}\n", .{ bin.op, l, r });
                                    return Error.CompilerError;
                                },
                            }
                        },
                        else => {
                            print("Compiler error: cannot perform {any} on {any} and {any}\n", .{ bin.op, left, right });
                            return Error.CompilerError;
                        },
                    }
                },

                else => {
                    print("unsupported binary op {any}\n", .{bin.op});
                },
            }
        },
        .int => |v| {
            print("eval int {any}\n", .{v});
            return SupportedValues{ .int = v.value };
        },
        .str => |v| {
            return SupportedValues{ .str = v.value };
        },
        .boolean => |v| {
            print("eval boolean {any}\n", .{v});
        },
        .call => |c| {
            print("eval call {any}\n", .{c});
            const callee = try eval(c.callee, allocator);
            _ = callee;
            const arguments = try evalTerms(c.arguments, allocator);
            _ = arguments;
            return SupportedValues{ .str = "call" };
        },
        .print => |p| {
            // print("eval print {any}\n", .{p});
            const value = try eval(p.value, allocator);
            switch (value) {
                .int => |v| {
                    print("compiler: {d}\n", .{v});
                },
                .str => |v| {
                    print("compiler: {s}\n", .{v});
                },
                else => {
                    print("compiler: {any}\n", .{value});
                },
            }

            return SupportedValues{ .str = "print" };
        },
        .tuple => |v| {
            print("eval tuple {any}\n", .{v});
        },
    }
    print("EVAL - unsupported term {any}\n", .{term});
    return Error.EvalError;
}
