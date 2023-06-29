const std = @import("std");
const vm = @import("vm.zig");
const chunk = @import("chunk.zig");

pub const Value_Kind = enum {
    Bool,
    Number,
    Nil,
    Obj,
};

pub const Value = struct {
    kind: Value_Kind,
    as: union {
        boolean: bool,
        number: f64,
        obj: *Obj,
    },
};

pub const Obj_Kind = enum {
    String,
    Function,
};

pub const Obj = struct {
    kind: Obj_Kind,
    next: ?*Obj,
};

pub const Obj_String = struct {
    obj: Obj,
    chars: []const u8,
};

pub const Obj_Function = struct {
    obj: Obj,
    arity: i32,
    chunk: chunk.Chunk,
    name: []const u8,
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

pub fn init_obj(value: *Obj) Value {
    return .{ .kind = .Obj, .as = .{ .obj = value } };
}

pub fn init_function(alloc: std.mem.Allocator) *Obj_Function {
    var function = try alloc.create(Obj_Function);
    function.* = .{
        .obj = .{ .next = null, .kind = .Function },
        .arity = 0,
        .name = "",
        .chunk = try chunk.init_chunk(alloc),
    };
    return function;
}

pub fn as_bool(value: Value) bool {
    return value.as.boolean;
}

pub fn as_number(value: Value) f64 {
    return value.as.number;
}
pub fn as_obj(value: Value) *Obj {
    return value.as.obj;
}

pub fn as_string(value: Value) *Obj_String {
    return @fieldParentPtr(Obj_String, "obj", as_obj(value));
}

pub fn as_string_chars(value: Value) []const u8 {
    return @fieldParentPtr(Obj_String, "obj", as_obj(value)).chars;
}

pub fn as_function(value: Value) *Obj_Function {
    return @fieldParentPtr(Obj_Function, "obj", as_obj(value));
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

pub fn is_obj(value: Value) bool {
    return value.kind == .Obj;
}

pub fn is_string(value: Value) bool {
    return is_obj_kind(value, .String);
}

pub fn is_function(value: Value) bool {
    return is_obj_kind(value, .Function);
}

pub fn is_obj_kind(value: Value, kind: Obj_Kind) bool {
    return is_obj(value) and as_obj(value).kind == kind;
}

pub fn obj_kind(value: Value) Obj_Kind {
    return value.as.obj.kind;
}

pub fn copy_string(m: *vm.VM, chars: []const u8) !*Obj_String {
    if (m.strings.get(chars)) |interned| {
        return interned;
    }
    const new_chars = try m.alloc.alloc(u8, chars.len);
    errdefer m.alloc.free(chars);
    @memcpy(new_chars, chars);
    return allocate_string(m, new_chars);
}

fn allocate_string(m: *vm.VM, chars: []const u8) !*Obj_String {
    var string = try m.alloc.create(Obj_String);
    string.obj.next = m.objects;
    m.objects = &string.obj;
    string.obj.kind = .String;
    string.chars = chars;
    try m.strings.put(chars, string);
    return string;
}

pub fn take_string(m: *vm.VM, chars: []const u8) !*Obj_String {
    if (m.strings.get(chars)) |interned| {
        m.alloc.free(chars);
        return interned;
    }
    return allocate_string(m, chars);
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
        .Obj => try print_object(w, value),
    }
}

fn print_object(w: anytype, value: Value) !void {
    switch (obj_kind(value)) {
        .String => {
            try w.writeAll(as_string_chars(value));
        },
        .Function => {
            try print_function(w, as_function(value));
        },
    }
}

fn print_function(w: anytype, function: *Obj_Function) !void {
    if (function.name.len == 0) {
        try w.print("<script>", .{function.name});
        return;
    }
    try w.print("<fn {s}>", .{function.name});
}

pub fn values_equal(a: Value, b: Value) bool {
    if (a.kind != b.kind) return false;

    return switch (a.kind) {
        .Bool => as_bool(a) == as_bool(b),
        .Nil => true,
        .Number => as_number(a) == as_number(b),
        .Obj => return as_obj(a) == as_obj(b),
    };
}
