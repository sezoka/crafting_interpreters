const std = @import("std");

const Number = f32;

pub const Value_Kind = union(enum) {
    bool: bool,
    number: f32,
    nil,
};

pub const Value = struct {
    kind: Value_Kind,

    const Self = @This();

    pub fn init_bool(value: bool) Self {
        return .{ .kind = .{ .bool = value } };
    }

    pub fn init_num(value: Number) Self {
        return .{ .kind = .{ .number = value } };
    }

    pub fn init_nil() Self {
        return .{ .kind = .nil };
    }

    pub fn is_bool(self: Self) bool {
        return self.kind == .bool;
    }

    pub fn is_num(self: Self) bool {
        return self.kind == .number;
    }

    pub fn is_nil(self: Self) bool {
        return self.kind == .nil;
    }

    pub fn is_falsey(self: Self) bool {
        return self.is_nil() or (self.is_bool() and !self.kind.bool);
    }

    pub fn equal(a: Self, b: Self) bool {
        if (@enumToInt(a.kind) != @enumToInt(b.kind)) return false;
        return switch (a.kind) {
            .nil => true,
            .number => |a_val| a_val == b.kind.number,
            .bool => |a_val| a_val == b.kind.bool,
        };
    }

    pub fn print(self: Self) void {
        switch (self.kind) {
            .bool => |b| std.debug.print("{any}", .{b}),
            .number => |num| std.debug.print("{d}", .{num}),
            .nil => std.debug.print("nil", .{}),
        }
    }
};

pub const Value_Array = std.ArrayList(Value);
