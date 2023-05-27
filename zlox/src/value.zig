const std = @import("std");

const Number = f32;

pub const Obj_Kind = enum {
    string,
};

pub const Obj = packed struct {
    kind: Obj_Kind,
    next: ?*Obj,

    const Self = @This();

    pub fn init(kind: Obj_Kind) Self {
        return .{ .kind = kind, .next = null };
    }
};

pub const Obj_String = packed struct {
    obj: Obj,
    chars: [*]const u8,
    len: usize,

    const Self = @This();

    pub fn init(slice: []const u8) Self {
        return .{ .obj = Obj.init(.string), .chars = slice.ptr, .len = slice.len };
    }
};

pub const Value_Kind = union(enum) {
    bool: bool,
    number: f32,
    obj: *Obj,
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

    pub fn init_obj(value: *Obj) Self {
        return .{ .kind = .{ .obj = value } };
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

    pub fn is_obj(self: Self) bool {
        return self.kind == .obj;
    }

    pub fn is_obj_kind(self: Self, kind: Obj_Kind) bool {
        return self.is_obj() and self.obj_kind() == kind;
    }

    pub fn is_string(self: Self) bool {
        return self.is_obj_kind(.string);
    }

    pub fn is_falsey(self: Self) bool {
        return self.is_nil() or (self.is_bool() and !self.kind.bool);
    }

    pub fn obj_kind(self: Self) Obj_Kind {
        return self.kind.obj.kind;
    }

    pub fn as_string(self: Self) *Obj_String {
        return @ptrCast(*Obj_String, @alignCast(@alignOf(*Obj_String), self.kind.obj));
    }

    pub fn as_string_slice(self: Self) []const u8 {
        const str = self.as_string();
        return str.chars[0..str.len];
    }

    pub fn equal(a: Self, b: Self) bool {
        if (@enumToInt(a.kind) != @enumToInt(b.kind)) return false;
        return switch (a.kind) {
            .nil => true,
            .number => |a_val| a_val == b.kind.number,
            .bool => |a_val| a_val == b.kind.bool,
            .obj => {
                const a_str = a.as_string_slice();
                const b_str = b.as_string_slice();
                return std.mem.eql(u8, a_str, b_str);
            },
        };
    }

    pub fn print(self: Self) void {
        switch (self.kind) {
            .bool => |b| std.debug.print("{any}", .{b}),
            .number => |num| std.debug.print("{d}", .{num}),
            .nil => std.debug.print("nil", .{}),
            .obj => |obj| switch (obj.kind) {
                .string => std.debug.print("{s}", .{self.as_string_slice()}),
            },
        }
    }
};

pub const Value_Array = std.ArrayList(Value);
