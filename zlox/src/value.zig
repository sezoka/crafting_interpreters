const std = @import("std");
const VM = @import("vm.zig").VM;

const Number = f32;

pub const Obj_Kind = enum {
    string,
};

const Writer = std.io.BufferedWriter(4096, @TypeOf(std.io.getStdOut().writer())).Writer;

pub const Value_Array = std.ArrayList(Value);

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

    pub fn init(slice: []const u8, copy_string: bool, free_string: bool, vm: *VM) !*Self {
        var interned_slice: []const u8 = undefined;

        if (vm.strings.getKey(slice)) |s| {
            interned_slice = s;
            if (free_string) {
                vm.alloc.free(slice);
            }
        } else {
            if (copy_string) {
                const slice_copy = try vm.alloc.alloc(u8, slice.len);
                @memcpy(slice_copy, slice);
                try vm.strings.put(slice_copy, undefined);
            } else {
                try vm.strings.put(slice, undefined);
            }
            interned_slice = vm.strings.getKey(slice) orelse unreachable;
        }

        const obj_ptr = try vm.alloc.create(Self);
        obj_ptr.* = .{ .obj = Obj.init(.string), .chars = interned_slice.ptr, .len = interned_slice.len };

        return obj_ptr;
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
                const a_str = a.as_string();
                const b_str = b.as_string();

                return a_str.chars == b_str.chars;
            },
        };
    }

    pub fn print(self: Self, writer: Writer) void {
        // const writer = std.io.getStdOut().writer();

        const maybe_err = switch (self.kind) {
            .bool => |b| writer.print("{any}", .{b}),
            .number => |num| writer.print("{d}", .{num}),
            .nil => writer.print("nil", .{}),
            .obj => |obj| switch (obj.kind) {
                .string => writer.print("{s}", .{self.as_string_slice()}),
            },
        };

        maybe_err catch {};
    }

    pub fn print_unbuff(self: Self) void {
        const writer = std.io.getStdOut().writer();

        const maybe_err = switch (self.kind) {
            .bool => |b| writer.print("{any}", .{b}),
            .number => |num| writer.print("{d}", .{num}),
            .nil => writer.print("nil", .{}),
            .obj => |obj| switch (obj.kind) {
                .string => writer.print("{s}", .{self.as_string_slice()}),
            },
        };

        maybe_err catch {};
    }
};
