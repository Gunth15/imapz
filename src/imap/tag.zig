const std = @import("std");
const Tag = @This();

level: u8,
id: u32,

pub fn to_string(t: *Tag, buff: [5]u8) []u8 {
    return std.fmt.bufPrint(buff[0..4], "{c}{d:0>3}", .{ t.level, t.id }) catch {
        unreachable;
    };
}
pub fn from_string(tag: []u8) !Tag {
    const level = tag[0];

    var id: u32 = 0;
    for (tag[1..tag.len], 0..) |char, i| {
        //UTF* offset for number is 48
        if (char < 48 or char > 57) return error.InvalidNumber;
        id += (char - 48) * std.math.pow(u32, 10, i);
    }

    return .{
        .id = id,
        .level = level,
    };
}
