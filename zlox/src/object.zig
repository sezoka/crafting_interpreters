const std = @import("std");
const value = @import("value.zig");
const vm = @import("vm.zig");
const table = @import("table.zig");

const VM = vm.VM;
const Value = value.Value;

pub const Obj_Kind = enum {
    string,
};

pub const Obj = struct {
    kind: Obj_Kind,
    next: ?*Obj,
};

pub const Obj_String = struct {
    obj: Obj,
    chars: []const u8,
};

pub fn is_string(val: Value) bool {
    return is_obj_kind(val, .string);
}

pub fn is_obj_kind(val: Value, kind: Obj_Kind) bool {
    return value.is_obj(val) and value.as_obj(val).kind == kind;
}

pub fn as_string(val: Value) *Obj_String {
    return @alignCast(@ptrCast(value.as_obj(val)));
}

pub fn as_string_slice(val: Value) []const u8 {
    return as_string(val).chars;
}

pub fn copy_string(v: *VM, chars: []const u8) !*Obj_String {
    const maybe_interned = table.get_by_slice(v.strings, chars);
    if (maybe_interned) |interned| return interned;
    const allocated_chars = try v.ally.dupe(u8, chars);
    return allocate_string(v, allocated_chars);
}

pub fn allocate_string(v: *VM, chars: []const u8) !*Obj_String {
    var string = try allocate_obj(v, Obj_String, Obj_Kind.string);
    string.chars = chars;
    try v.strings.put(string, {});
    return string;
}

pub fn allocate_obj(v: *VM, comptime obj_type: type, kind: Obj_Kind) !*obj_type {
    var obj = try v.ally.create(obj_type);
    obj.obj.kind = kind;
    obj.obj.next = v.objects;
    v.objects = &obj.obj;
    return obj;
}

pub fn print_obj(val: Value) void {
    switch (val) {
        .obj => |obj| {
            switch (obj.kind) {
                .string => {
                    std.debug.print("{s}", .{as_string_slice(val)});
                },
            }
        },
        else => unreachable,
    }
}

pub fn take_string(v: *VM, chars: []const u8) !*Obj_String {
    const maybe_interned = table.get_by_slice(v.strings, chars);
    if (maybe_interned) |interned| {
        v.ally.free(chars);
        return interned;
    }
    return allocate_string(v, chars);
}
