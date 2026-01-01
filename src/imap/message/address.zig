const std = @import("std");
const Iterator = @import("../iterator.zig");
//RFC 5322
name: ?[]const u8,
adl: ?[]const u8,
mailbox: ?[]const u8,
host: ?[]const u8,

const Address = @This();
const Error = error{ NoOpenDelim, NoCloseDelim, InvalidName, InvalidAdl, InvalidMailbox, InvalidHost, BadAddress, NoMemory };
pub fn parse(iter: *Iterator) Error!Address {
    switch (iter.next() orelse return Error.BadAddress) {
        .ListOpen => {
            const addr: @This() = .{
                .name = switch (iter.next() orelse return Error.BadAddress) {
                    .String => |s| s[1 .. s.len - 1],
                    .Atom => null,
                    else => return Error.InvalidName,
                },
                .adl = switch (iter.next() orelse return Error.BadAddress) {
                    .String => |s| s[1 .. s.len - 1],
                    .Atom => null,
                    else => return Error.InvalidAdl,
                },
                .mailbox = switch (iter.next() orelse return Error.BadAddress) {
                    .String => |s| s[1 .. s.len - 1],
                    .Atom => null,
                    else => return Error.InvalidMailbox,
                },
                .host = switch (iter.next() orelse return Error.BadAddress) {
                    .String => |s| s[1 .. s.len - 1],
                    .Atom => null,
                    else => return Error.InvalidHost,
                },
            };
            switch (iter.next() orelse return error.BadAddress) {
                .ListClose => return addr,
                else => return Error.BadAddress,
            }
        },
        else => return Error.NoOpenDelim,
    }
}
//TODO: remove ToOwnedSLice in other place since the allocator used is expected to be an areana
pub fn parseList(iter: *Iterator, arena: std.mem.Allocator) Error![]Address {
    switch (iter.next() orelse return Error.BadAddress) {
        .ListOpen => {
            var list = std.ArrayList(Address).initCapacity(arena, 10) catch return Error.NoMemory;
            while (true) {
                switch (iter.peek() orelse return Error.BadAddress) {
                    .ListOpen => {
                        const addr = try parse(iter);
                        list.append(arena, addr) catch return Error.NoMemory;
                    },
                    .ListClose => {
                        _ = iter.next();
                        break;
                    },
                    else => return Error.BadAddress,
                }
            }
            return list.items;
        },
        else => return error.NoOpenDelim,
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
    try std.testing.expectError(Error.InvalidHost, result);
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

test "Address.parseList handles single address with all fields" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\(("John Doe" NIL "john" "example.com"))
    ;

    var iter = Iterator.split(input);
    const result = try Address.parseList(&iter, allocator);

    try testing.expectEqual(@as(usize, 1), result.len);
    try testing.expectEqualStrings("John Doe", result[0].name.?);
    try testing.expect(result[0].adl == null);
    try testing.expectEqualStrings("john", result[0].mailbox.?);
    try testing.expectEqualStrings("example.com", result[0].host.?);
}

test "Address.parseList handles multiple addresses" {
    const testing = std.testing;
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\(("Alice" NIL "alice" "example.com") ("Bob" NIL "bob" "other.com") ("Bob" NIL "bob" "other.com"))
    ;

    var iter = Iterator.split(input);
    const result = try Address.parseList(&iter, allocator);

    try testing.expectEqual(@as(usize, 3), result.len);
    try testing.expectEqualStrings("Alice", result[0].name.?);
    try testing.expectEqualStrings("alice", result[0].mailbox.?);
    try testing.expectEqualStrings("Bob", result[1].name.?);
    try testing.expectEqualStrings("bob", result[1].mailbox.?);
}
