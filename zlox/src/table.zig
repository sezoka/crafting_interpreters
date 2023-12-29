const std = @import("std");
const object = @import("object.zig");
const Obj_String = object.Obj_String;

pub const Obj_String_Set = std.HashMap(*Obj_String, void, Obj_String_Context, 80);

pub const Obj_String_Context = struct {
    pub fn hash(self: @This(), s: *Obj_String) u64 {
        _ = self;
        return hash_Obj_String(s);
    }
    pub fn eql(self: @This(), a: *Obj_String, b: *Obj_String) bool {
        _ = self;
        return eql_Obj_String(a, b);
    }
};

pub fn eql_Obj_String(a: *Obj_String, b: *Obj_String) bool {
    return std.mem.eql(u8, a.chars, b.chars);
}

pub fn hash_Obj_String(s: *Obj_String) u64 {
    return std.hash.Wyhash.hash(0, s.chars);
}

pub fn get_by_slice(set: Obj_String_Set, chars: []const u8) ?*Obj_String {
    var tmp_str: Obj_String = undefined;
    tmp_str.chars = chars;
    return set.getKey(&tmp_str);
}
