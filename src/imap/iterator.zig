const std = @import("std");
const Iterator = @This();

buffer: []const u8,
index: ?usize = 0,

pub const Type = union(enum) {
    String: []const u8,
    Atom: []const u8,
    ListOpen,
    ListClose,
};

pub fn split(buffer: []const u8) Iterator {
    return .{ .buffer = buffer, .index = 0 };
}

pub fn first(self: *Iterator) ?Type {
    std.debug.assert(self.index.? == 0);
    return self.next().?;
}
pub fn peek(self: *Iterator) ?Type {
    var start = self.index orelse return null;
    while (start < self.buffer.len and self.buffer[start] == ' ') start += 1;
    if (start >= self.buffer.len) return null;

    switch (self.buffer[start]) {
        '(' => return .ListOpen,
        ')' => return .ListClose,
        '\"' => {
            const end = self.find_end_string(start) orelse return null;
            return .{ .String = self.buffer[start..end] };
        },
        else => {
            const end = self.find_end_atom(start);
            return .{ .Atom = self.buffer[start..end] };
        },
    }
    return .{ .Atom = self.buffer[start..] };
}
pub fn next(self: *Iterator) ?Type {
    const start = self.index orelse return null;
    const buff = self.peek();
    const consumed = switch (buff orelse return null) {
        .String => |s| s.len,
        .Atom => |a| a.len,
        .ListOpen => 1,
        .ListClose => 1,
    };

    var new_index = start + consumed;
    while (new_index < self.buffer.len and self.buffer[new_index] == ' ') new_index += 1;
    self.index = if (self.buffer.len >= new_index) new_index else null;

    return buff;
}
pub fn reset(self: *Iterator) ?Type {
    self.index = 0;
}
pub fn rest(self: *Iterator) ?Type {
    const end = self.buffer.len;
    const start = self.index orelse end;
    return .{ .String = self.buffer[start..end] };
}

fn find_end_string(self: *Iterator, index: usize) ?usize {
    for (index + 1..self.buffer.len) |i| {
        if (self.buffer[i] == '\"') return i + 1;
    }
    return null;
}
fn find_end_atom(self: *Iterator, index: usize) usize {
    var i: usize = index + 1;
    while (i < self.buffer.len) : (i += 1) {
        switch (self.buffer[i]) {
            '\"', ' ', '(', ')', '{' => return i,
            else => continue,
        }
    }
    return i;
}

test "basic atoms and delimiters" {
    const iter = Iterator.split("A B C");
    var i = iter;
    try std.testing.expectEqualStrings("A", i.first().?.Atom);
    try std.testing.expectEqualStrings("B", i.next().?.Atom);
    try std.testing.expectEqualStrings("C", i.next().?.Atom);
    try std.testing.expectEqual(i.next(), null);
}

test "handles list open and close" {
    const iter = Iterator.split("(INBOX)");
    var i = iter;

    try std.testing.expectEqual(@as(Iterator.Type, .ListOpen), i.first().?);
    try std.testing.expectEqualStrings("INBOX", i.next().?.Atom);
    try std.testing.expectEqual(@as(Iterator.Type, .ListClose), i.next().?);
    try std.testing.expectEqual(i.next(), null);
}

test "handles quoted string" {
    const iter = Iterator.split("\"Hello World\"");
    var i = iter;

    const token = i.first().?;
    try std.testing.expectEqualStrings("\"Hello World\"", token.String);
    try std.testing.expectEqual(i.next(), null);
}

test "handles atoms around strings" {
    const iter = Iterator.split("A \"B C\" D");
    var i = iter;

    try std.testing.expectEqualStrings("A", i.first().?.Atom);
    try std.testing.expectEqualStrings("\"B C\"", i.next().?.String);
    try std.testing.expectEqualStrings("D", i.next().?.Atom);
    try std.testing.expectEqual(i.next(), null);
}

test "nested list structure" {
    const iter = Iterator.split("(A (B C) D)");
    var i = iter;

    try std.testing.expectEqual(@as(Iterator.Type, .ListOpen), i.first().?);
    try std.testing.expectEqualStrings("A", i.next().?.Atom);
    try std.testing.expectEqual(@as(Iterator.Type, .ListOpen), i.next().?);
    try std.testing.expectEqualStrings("B", i.next().?.Atom);
    try std.testing.expectEqualStrings("C", i.next().?.Atom);
    try std.testing.expectEqual(@as(Iterator.Type, .ListClose), i.next().?);
    try std.testing.expectEqualStrings("D", i.next().?.Atom);
    try std.testing.expectEqual(@as(Iterator.Type, .ListClose), i.next().?);
    try std.testing.expectEqual(i.next(), null);
}

test "trailing spaces and empty atom handling" {
    const iter = Iterator.split("A  B ");
    var i = iter;

    try std.testing.expectEqualStrings("A", i.first().?.Atom);
    try std.testing.expectEqualStrings("B", i.next().?.Atom);
    try std.testing.expectEqual(i.next(), null);
}
