const std = @import("std");
const ArrayList = std.ArrayList;

pub const File = struct {
    name: []const u8,
    expression: Term,
    location: Loc,
};

pub const Term = union(enum) {
    function: Function,
    let: Let,
    ifTerm: If,
    varTerm: Var,
    binary: Binary,
    int: Int,
    str: Str,
    boolean: Bool,
    call: Call,
    print: Print,
    tuple: Tuple,
};

pub const Loc = struct {
    start: u32,
    end: u32,
    filename: []const u8,
};

pub const BinaryOp = enum {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Eq,
    Neq,
    Lt,
    Gt,
    Lte,
    Gte,
    And,
    Or,
};

pub const Parameter = struct {
    text: []const u8,
    location: Loc,
};

pub const ValidKeys = enum {
    kind,
    condition,
    then,
    otherwise,
    name,
    next,
    callee,
    arguments,
    parameters,
    lhs,
    op,
    rhs,
    first,
    second,
    text,
    value,
    location,
    filename,
    start,
    end,
};
pub const ValidTerms = enum {
    If,
    Let,
    Str,
    Bool,
    Int,
    Binary,
    Call,
    Function,
    Print,
    First,
    Second,
    Tuple,
    Var,
};

pub const If = struct {
    kind: ValidTerms,
    condition: *const Term,
    then: *const Term,
    otherwise: *const Term,
    location: Loc,
};
pub const Let = struct {
    kind: ValidTerms,
    name: Parameter,
    value: *const Term,
    next: *const Term,
    location: Loc,
};
pub const Str = struct {
    kind: ValidTerms,
    value: []const u8,
    location: Loc,
};
pub const Bool = struct {
    kind: ValidTerms,
    value: bool,
    location: Loc,
};
pub const Int = struct {
    kind: ValidTerms,
    value: i32,
    location: Loc,
};
pub const Binary = struct {
    kind: ValidTerms,
    lhs: *const Term,
    op: BinaryOp,
    rhs: *const Term,
    location: Loc,
};
pub const Call = struct {
    kind: ValidTerms,
    callee: *const Term,
    arguments: ArrayList(Term),
    location: Loc,
};
pub const Function = struct {
    kind: ValidTerms,
    parameters: ArrayList(Parameter),
    value: *const Term,
    location: Loc,
};
pub const Print = struct {
    kind: ValidTerms,
    value: *const Term,
    location: Loc,
};
pub const First = struct {
    kind: ValidTerms,
    value: *const Term,
    location: Loc,
};
pub const Second = struct {
    kind: ValidTerms,
    value: *const Term,
    location: Loc,
};
pub const Tuple = struct {
    kind: ValidTerms,
    first: *const Term,
    second: *const Term,
    location: Loc,
};
pub const Var = struct {
    kind: ValidTerms,
    text: []const u8,
    location: Loc,
};
