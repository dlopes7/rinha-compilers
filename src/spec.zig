pub const File = struct {
    name: []const u8,
    expression: Term,
    location: Loc,
};

pub const Term = union(enum) {
    function: *Function,
    let: *Let,
    ifTerm: *If,
    varTerm: *Var,
    binary: *Binary,
    int: Int,
    str: Str,
    boolean: Bool,
    call: *Call,
    print: *Print,
    tuple: *Tuple,
};

const Loc = struct { start: u32, end: u32, filename: []const u8 };

const BinaryOp = enum {
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

const Parameter = struct { text: []const u8, location: Loc };

pub const ValidKeys = enum { kind, condition, then, otherwise, name, next, callee, arguments, parameters, lhs, op, rhs, first, second, text, value, location, filename, start, end };
pub const ValidTerms = enum { If, Let, Str, Bool, Int, Binary, Call, Function, Print, First, Second, Tuple, Var };

pub const If = struct { kind: []const u8, condition: Term, then: Term, otherwise: Term, location: Loc };
pub const Let = struct { kind: []const u8, name: Parameter, value: Term, next: Term, location: Loc };
pub const Str = struct { kind: []const u8, value: []const u8, location: Loc };
pub const Bool = struct { kind: []const u8, value: bool, location: Loc };
pub const Int = struct { kind: []const u8, value: i32, location: Loc };
pub const Binary = struct { kind: []const u8, lhs: Term, op: BinaryOp, rhs: Term, location: Loc };
pub const Call = struct { kind: []const u8, callee: Term, arguments: []Term, location: Loc };
pub const Function = struct { kind: []const u8, parameters: []Parameter, value: Term, location: Loc };
pub const Print = struct { kind: []const u8, value: Term, location: Loc };
pub const First = struct { kind: []const u8, value: Term, location: Loc };
pub const Second = struct { kind: []const u8, value: Term, location: Loc };
pub const Tuple = struct { kind: []const u8, first: Term, second: Term, location: Loc };
pub const Var = struct { kind: []const u8, text: []const u8, location: Loc };
