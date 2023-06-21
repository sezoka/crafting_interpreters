const std = @import("std");

pub const Value_Kind = enum {
    Bool,
    Nil,
    Number,
};

pub const Value = struct {
    kind: Value_Kind,
    as: union {
        boolean: bool,
        number: f64,
    },
};

pub const Value_Array = std.ArrayList(Value);

pub fn init_bool(value: bool) Value {
    return .{ .kind = .Bool, .as = .{ .boolean = value } };
}

pub fn init_nil() Value {
    return .{ .kind = .Nil, .as = .{ .number = 0 } };
}

pub fn init_number(value: f64) Value {
    return .{ .kind = .Number, .as = .{ .number = value } };
}

pub fn as_bool(value: Value) bool {
    return value.as.boolean;
}

pub fn as_number(value: Value) f64 {
    return value.as.number;
}

pub fn is_bool(value: Value) bool {
    return value.kind == .Bool;
}

pub fn is_nil(value: Value) bool {
    return value.kind == .Nil;
}

pub fn is_number(value: Value) bool {
    return value.kind == .Number;
}

pub fn print_value(value: Value) !void {
    const writer = std.io.getStdOut().writer();
    try print_value_with_writer(writer, value);
}

pub fn print_value_with_writer(w: anytype, value: Value) !void {
    switch (value.kind) {
        .Number => try w.print("{d}", .{as_number(value)}),
        .Bool => try w.print("{}", .{as_bool(value)}),
        .Nil => try w.print("nil", .{}),
    }
}

pub fn values_equal(a: Value, b: Value) bool {
    if (a.kind != b.kind) return false;

    return switch (a.kind) {
        .Bool => as_bool(a) == as_bool(b),
        .Nil => true,
        .Number => as_number(a) == as_number(b),
        // else => return false,
    };
}
