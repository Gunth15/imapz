const std = @import("std");
const Iterator = @import("../iterator.zig");
//RFC 5322
name: ?[]const u8,
adl: ?[]const u8,
mailbox: ?[]const u8,
host: ?[]const u8,

const Address = @This();
pub fn parse(iter: *Iterator) error{BadAddress}!Address {
    switch (iter.next() orelse return error.BadAddress) {
        .ListOpen => {
            const addr: @This() = .{
                .name = switch (iter.next() orelse return error.BadAddress) {
                    .String => |s| s[1 .. s.len - 1],
                    .Atom => null,
                    else => return error.BadAddress,
                },
                .adl = switch (iter.next() orelse return error.BadAddress) {
                    .String => |s| s[1 .. s.len - 1],
                    .Atom => null,
                    else => return error.BadAddress,
                },
                .mailbox = switch (iter.next() orelse return error.BadAddress) {
                    .String => |s| s[1 .. s.len - 1],
                    .Atom => null,
                    else => return error.BadAddress,
                },
                .host = switch (iter.next() orelse return error.BadAddress) {
                    .String => |s| s[1 .. s.len - 1],
                    .Atom => null,
                    else => return error.BadAddress,
                },
            };
            switch (iter.next() orelse return error.BadAddress) {
                .ListClose => return addr,
                else => return error.BadAddress,
            }
        },
        else => return error.BadAddress,
    }
}

test "Address.parse parses valid address list" {
    const input =
        \\("John Doe" NIL "john" "example.com")
    ;
    var iter = Iterator.split(input);

    const addr = try Address.parse(&iter);

    try std.testing.expectEqualStrings("John Doe", addr.name.?);
    try std.testing.expect(addr.adl == null);
    try std.testing.expectEqualStrings("john", addr.mailbox.?);
    try std.testing.expectEqualStrings("example.com", addr.host.?);
}

test "Address.parse handles NIL values" {
    const input =
        \\(NIL NIL "bob" "mail.org")
    ;
    var iter = Iterator.split(input);

    const addr = try Address.parse(&iter);

    try std.testing.expect(addr.name == null);
    try std.testing.expect(addr.adl == null);
    try std.testing.expectEqualStrings("bob", addr.mailbox.?);
    try std.testing.expectEqualStrings("mail.org", addr.host.?);
}

test "Address.parse fails with missing fields" {
    const input =
        \\("Missing" "too" "few")
    ;
    var iter = Iterator.split(input);

    const result = Address.parse(&iter);
    try std.testing.expectError(error.BadAddress, result);
}

test "Address.parse fails if no closing parenthesis" {
    const input =
        \\("John" NIL "user" "example.com"
    ;
    var iter = Iterator.split(input);

    const result = Address.parse(&iter);
    try std.testing.expectError(error.BadAddress, result);
}

test "Address.parse fails on unexpected trailing tokens" {
    const input =
        \\("John" NIL "user" "example.com" "extra")
    ;
    var iter = Iterator.split(input);

    const result = Address.parse(&iter);
    try std.testing.expectError(error.BadAddress, result);
}
