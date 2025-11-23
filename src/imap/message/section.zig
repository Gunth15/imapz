const std = @import("std");
const Iter = @import("../iterator.zig");
//"BODY" section ["<" number ">"] SP nstring
//
//   section         = "[" [section-spec] "]"
//
//   section-binary  = "[" [section-part] "]"
//   section-msgtext = "HEADER" /
//                     "HEADER.FIELDS" [".NOT"] SP header-list /
//                     "TEXT"
//                       ; top-level or MESSAGE/RFC822 or
//                       ; MESSAGE/GLOBAL part
//
//   section-part    = nz-number *("." nz-number)
//                       ; body part reference.
//                       ; Allows for accessing nested body parts.
//
//   section-spec    = section-msgtext / (section-part ["." section-text])
//
//   section-text    = section-msgtext / "MIME"
//                       ; text other than actual body part (headers,
//                       ; etc.)
const Section = @This();
msgtext: Text,
section_part: ?[]const u8,
data: []const u8,
pub fn parse(str: []const u8, allocator: std.mem.Allocator) !Section {
    std.debug.assert(str[0] == '[' and str[str.len - 1] == ']');
    var sec = Section{ .section_part = null };
    const iter = Iter.split(str[1 .. str.len - 2]);
    const n = try iter.string();
    msg_or_part: for (n, 0..) |char, i| {
        if (char == '.') continue :msg_or_part;
        const buf: [1]u8 = .{char};
        std.fmt.parseInt(u8, buf, 10) catch |e| {
            //only care if not number
            switch (e) {
                error.InvalidCharacter => {
                    sec.msgtext = try parse_msgtext(n[i + 1 ..], Iter, allocator);
                    if (i != 0) sec.section_part = n[0 .. i + 1];
                    break :msg_or_part;
                },
                else => return error.ParseError,
            }
        };
    }
    sec.data = try iter.string();
    return sec;
}
fn parse_msgtext(str: []const u8, iter: Iter, allocator: std.mem.Allocator) !Text {
    if (std.mem.eql(u8, str, "HEADER")) return .header;
    if (std.mem.eql(u8, str, "MIME")) return .mime;
    if (std.mem.eql(u8, str, "TEXT")) return .text;
    if (std.mem.eql(u8, str, "HEADER.FIELDS")) return .{ .header_fields = try parse_header_list(iter, allocator) };
    if (std.mem.eql(u8, str, "HEADER.FIELDS.NOT")) return .{ .header_fields_not = try parse_header_list(iter, allocator) };
}
fn parse_header_list(iter: Iter, allocator: std.mem.Allocator) !HeaderList {
    const list: std.ArrayList([]u8) = .empty;
    while (iter.next()) |t| {
        switch (t) {
            .ListOpen => continue,
            .Atom, .String => |s| try list.append(allocator, s),
            .ListClose => break,
        }
    }
    return list.toOwnedSlice(allocator);
}

const HeaderList = [][]const u8;
const Text = union(enum) {
    header,
    header_fields: HeaderList,
    header_fields_not: HeaderList,
    text,
    mime,
};
