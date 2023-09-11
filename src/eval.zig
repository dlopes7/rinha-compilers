const std = @import("std");
const spec = @import("spec.zig");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const print = std.debug.print;

const SupportedValues = union(enum) {
    int: i32,
    str: []const u8,
    bool: bool,
    funcDef: FunctionDefinition,
    biNDef: BinaryDefinition,
    ifDef: ifDefinition,
    letDef: letDefinition,
    callDef: callDefinition,
};

const Error = error{ EvalError, CompilerError, OutOfMemory };

var globals = std.StringHashMapUnmanaged(SupportedValues){};
var invocations = std.StringHashMapUnmanaged(FunctionInvocation){};
var variables = std.StringHashMapUnmanaged(SupportedValues){};

const letDefinition = struct {
    name: []const u8,
    value: *SupportedValues,
    next: *SupportedValues,
};

const callDefinition = struct {
    callee: *SupportedValues,
    arguments: ArrayList(SupportedValues),
};

const FunctionDefinition = struct {
    parameters: ArrayList([]const u8),
    value: *SupportedValues,
};

const FunctionInvocation = struct {
    name: []const u8,
    arguments: ArrayList(SupportedValues),
};

const BinaryDefinition = struct {
    op: spec.BinaryOp,
    lhs: *SupportedValues,
    rhs: *SupportedValues,
};

const ifDefinition = struct {
    condition: *SupportedValues,
    then: *SupportedValues,
    otherwise: *SupportedValues,
};

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
            print("eval function {any}\n", .{&f});
            const parameters = try evalParameters(f.parameters, allocator);
            var value = try eval(f.value, allocator);
            return SupportedValues{ .funcDef = FunctionDefinition{ .parameters = parameters, .value = &value } };
        },
        .let => |l| {
            print("eval let {any}\n", .{&l});
            const name = evalParameter(l.name);
            var value = try eval(l.value, allocator);
            var next = try eval(l.next, allocator);
            return SupportedValues{ .letDef = letDefinition{ .name = name, .value = &value, .next = &next } };
            // switch (l.value) {
            //     .function => |f| {
            //         const params = try evalParameters(f.parameters, allocator);
            //         const fDef = SupportedValues{ .funcDef = FunctionDefinition{ .name = name, .parameters = params, .value = &value } };
            //         print("Putting {s} in functions\n", .{name});
            //         try globals.put(allocator, name, fDef);
            //         // try functions.put(allocator, name, fDef);
            //     },

            //     else => |v| {
            //         print("COMPILER ERROR - not supported let definition for {any}\n", .{v});
            //     },
            // }

            // // print("Let - {s}({any}) -> {any}", .{ name, value, next });

        },
        .ifTerm => |i| {
            print("eval if {any}\n", .{&i});
            var condition = try eval(i.condition, allocator);
            var then = try eval(i.then, allocator);
            var otherwise = try eval(i.otherwise, allocator);
            return SupportedValues{ .ifDef = ifDefinition{ .condition = &condition, .then = &then, .otherwise = &otherwise } };

            // const condition = try eval(i.condition, allocator);
            // switch (condition) {
            //     .bool => |b| {
            //         if (b) {
            //             return try eval(i.then, allocator);
            //         } else {
            //             return try eval(i.otherwise, allocator);
            //         }
            //     },
            //     else => |e| {
            //         print("COMPILER ERROR - not supported if condition for {any}\n", .{e});
            //     },
            // }
        },
        .varTerm => |v| {
            print("eval var {s}\n", .{v.text});
            return SupportedValues{ .str = v.text };
        },
        .binary => |bin| {
            print("eval binary {any}\n", .{&bin});
            var left = try eval(bin.lhs, allocator);
            var right = try eval(bin.rhs, allocator);
            return SupportedValues{ .biNDef = BinaryDefinition{ .op = bin.op, .lhs = &left, .rhs = &right } };

            // switch (bin.op) {
            //     .Add, .Sub => |op| {
            //         const left = try eval(bin.lhs, allocator);
            //         const right = try eval(bin.rhs, allocator);
            //         switch (left) {
            //             .int => |l| {
            //                 switch (right) {
            //                     .int => |r| {
            //                         // l is int, r is int
            //                         switch (op) {
            //                             .Add => return SupportedValues{ .int = l + r },
            //                             .Sub => return SupportedValues{ .int = l - r },
            //                             else => {
            //                                 print("COMPILER ERROR - unsupported binary op: {any} {any} {any}\n", .{ l, op, r });
            //                                 return Error.CompilerError;
            //                             },
            //                         }
            //                     },
            //                     .str => |r| {
            //                         // l is int, r is str
            //                         const concatenated = try std.fmt.allocPrint(allocator, "{any}{any}", .{ l, r });
            //                         switch (op) {
            //                             .Add => return SupportedValues{ .str = concatenated },
            //                             else => {
            //                                 print("COMPILER ERROR - unsupported binary op: {any} {any} {any}\n", .{ l, op, r });
            //                                 return Error.CompilerError;
            //                             },
            //                         }
            //                     },
            //                     else => |r| {
            //                         // l is int, r is unsupported
            //                         print("COMPILER ERROR - unsupported binary op: {any} {any} {any}\n", .{ l, op, r });
            //                         return Error.CompilerError;
            //                     },
            //                 }
            //             },
            //             .str => |l| {
            //                 switch (right) {
            //                     .int => |r| {
            //                         // l is str, r is int
            //                         const concatenated = try std.fmt.allocPrint(allocator, "{any}{any}", .{ l, r });
            //                         switch (op) {
            //                             .Add => return SupportedValues{ .str = concatenated },
            //                             else => {
            //                                 print("COMPILER ERROR - unsupported binary op: {any} {any} {any}\n", .{ l, op, r });
            //                                 return Error.CompilerError;
            //                             },
            //                         }
            //                     },
            //                     .str => |r| {
            //                         // l is str, r is str
            //                         const concatenated = try std.fmt.allocPrint(allocator, "{any}{any}", .{ l, r });
            //                         switch (op) {
            //                             .Add => return SupportedValues{ .str = concatenated },
            //                             else => {
            //                                 print("COMPILER ERROR - unsupported binary op: {any} {any} {any}\n", .{ l, op, r });
            //                                 return Error.CompilerError;
            //                             },
            //                         }
            //                     },
            //                     else => |r| {
            //                         // l is str, r is unsupported
            //                         print("COMPILER ERROR - cannot perform {any} on {any} and {any}\n", .{ bin.op, l, r });
            //                         return Error.CompilerError;
            //                     },
            //                 }
            //             },
            //             else => {
            //                 print("COMPILER ERROR - cannot perform {any} on {any} and {any}\n", .{ bin.op, left, right });
            //                 return Error.CompilerError;
            //             },
            //         }
            //     },
            //     .Eq => {
            //         const left = try eval(bin.lhs, allocator);
            //         const right = try eval(bin.rhs, allocator);
            //         const result = std.meta.eql(left, right);
            //         print("Result of {any} == {any} = {any}\n", .{ left, right, result });
            //         return SupportedValues{ .bool = result };
            //     },
            //     .Lt => {
            //         const left = try eval(bin.lhs, allocator);
            //         const right = try eval(bin.rhs, allocator);
            //         switch (left) {
            //             .int => |l| {
            //                 switch (right) {
            //                     .int => |r| {
            //                         // l is int, r is int
            //                         return SupportedValues{ .bool = l < r };
            //                     },
            //                     else => |r| {
            //                         // l is int, r is unsupported
            //                         print("COMPILER ERROR - cannot perform {any} on {any} and {any}\n", .{ bin.op, l, r });
            //                         return Error.CompilerError;
            //                     },
            //                 }
            //             },
            //             else => {
            //                 print("COMPILER ERROR - cannot perform {any} on {any} and {any}\n", .{ bin.op, left, right });
            //                 return Error.CompilerError;
            //             },
            //         }
            //     },

            //     else => {
            //         print("COMPILER ERROR - unsupported binary op {any}\n", .{bin.op});
            //     },
            // }
        },
        .int => |v| {
            print("eval int {any}\n", .{&v});
            return SupportedValues{ .int = v.value };
        },
        .str => |v| {
            print("eval str {any}\n", .{&v});
            return SupportedValues{ .str = v.value };
        },
        .boolean => |v| {
            print("eval boolean {any}\n", .{&v});
        },
        .call => |c| {
            print("eval call {any}\n", .{&c});
            const arguments = try evalTerms(c.arguments, allocator);
            var callee = try eval(c.callee, allocator);
            return SupportedValues{ .callDef = callDefinition{ .callee = &callee, .arguments = arguments } };

            // switch (callee) {
            //     .str => |text| {
            //         const fInvocation = FunctionInvocation{ .name = text, .arguments = arguments };
            //         print("Want to invoke {s} with {any}\n", .{ text, arguments.items });
            //         try invocations.put(allocator, text, fInvocation);
            //     },
            //     else => {
            //         print("unsupported callee {any}\n", .{callee});
            //     },
            // }

        },
        .print => |p| {
            print("eval print {any}\n", .{&p});
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
            print("eval tuple {any}\n", .{&v});
        },
    }
    print("EVAL - unsupported term {any}\n", .{term});
    return Error.EvalError;
}

pub fn traverse(term: spec.Term, list: *ArrayList(spec.Term)) !void {
    try list.append(term);
    switch (term) {
        .function => |f| {
            print("traverse function {any}\n", .{&f});
            try traverse(f.value, list);
        },
        .let => |l| {
            print("traverse let {any}\n", .{&l});
            try traverse(l.value, list);
            try traverse(l.next, list);
        },
        .ifTerm => |i| {
            print("traverse if {any}\n", .{&i});
            try traverse(i.condition, list);
            try traverse(i.then, list);
            try traverse(i.otherwise, list);
        },
        .varTerm => |v| {
            print("traverse var {s}\n", .{v.text});
        },
        .binary => |bin| {
            print("traverse binary {any}\n", .{&bin});
            try traverse(bin.lhs, list);
            try traverse(bin.rhs, list);
        },
        .int => |v| {
            print("traverse int {any}\n", .{&v});
        },
        .str => |v| {
            print("traverse str {any}\n", .{&v});
        },
        .boolean => |v| {
            print("traverse boolean {any}\n", .{&v});
        },
        .call => |c| {
            print("traverse call {any}\n", .{&c});
            try traverse(c.callee, list);
        },
        .print => |p| {
            print("traverse print {any}\n", .{&p});
            try traverse(p.value, list);
        },
        .tuple => |v| {
            print("traverse tuple {any}\n", .{&v});
        },
    }
}
