const std = @import("std");
const Address = @import("address.zig");
const Iterator = @import("../iterator.zig");
const Envelope = @This();

//envelope        = "(" env-date SP env-subject SP env-from SP
//         env-sender SP env-reply-to SP env-to SP env-cc SP
//         env-bcc SP env-in-reply-to SP env-message-id ")"
date: ?[]const u8,
subject: ?[]const u8,
from: ?Address,
to: ?Address,
sender: ?Address,
reply_to: ?Address,
cc: ?Address,
bcc: ?Address,
in_reply_to: ?[]const u8,
message_id: ?[]const u8,
const Error = error{ NoOpen, NoDate, NoSubject, NoFrom, NoSender, NoReply, NoTo, NoCC, NoBCC, NoInReply, NoMessageId, BadFrom, BadSender, BadReply, BadTo, BadCC, BadBCC };
pub fn parse(iter: *Iterator) Error!Envelope {
    switch (iter.next() orelse return Error.NoMessageId) {
        .ListOpen => return .{
            .date = switch (iter.next() orelse return Error.NoDate) {
                .String => |s| s[1 .. s.len - 1],
                .Atom => null,
                else => return Error.NoDate,
            },
            .subject = switch (iter.next() orelse return Error.NoSubject) {
                .String => |s| s[1 .. s.len - 1],
                .Atom => null,
                else => return Error.NoSubject,
            },
            .from = switch (iter.peek() orelse return Error.NoFrom) {
                .ListOpen => Address.parse(iter) catch return Error.BadFrom,
                .Atom => null,
                else => return Error.NoFrom,
            },
            .to = switch (iter.peek() orelse return Error.NoTo) {
                .ListOpen => Address.parse(iter) catch return Error.BadTo,
                .Atom => null,
                else => return Error.NoTo,
            },
            .sender = switch (iter.peek() orelse return Error.NoSender) {
                .ListOpen => Address.parse(iter) catch return Error.BadSender,
                .Atom => null,
                else => return Error.NoSender,
            },
            .reply_to = switch (iter.peek() orelse return Error.NoReply) {
                .ListOpen => Address.parse(iter) catch return Error.BadReply,
                .Atom => null,
                else => return Error.NoReply,
            },
            .cc = switch (iter.peek() orelse return Error.NoCC) {
                .ListOpen => Address.parse(iter) catch return Error.BadCC,
                .Atom => null,
                else => return Error.NoCC,
            },
            .bcc = switch (iter.peek() orelse return Error.NoBCC) {
                .ListOpen => Address.parse(iter) catch return Error.BadBCC,
                .Atom => null,
                else => return Error.NoBCC,
            },
            .in_reply_to = switch (iter.next() orelse return Error.NoInReply) {
                .String => |s| s[1 .. s.len - 1],
                .Atom => null,
                else => return Error.NoInReply,
            },
            .message_id = switch (iter.next() orelse return Error.NoMessageId) {
                .String => |s| s[1 .. s.len - 1],
                .Atom => null,
                else => return Error.NoMessageId,
            },
        },
        else => return Error.NoOpen,
    }
}
test "Envelope.parse parses full valid envelope" {
    const input =
        \\("Mon, 1 Jan 2024 10:00:00 +0000" "Subject line" ("John" NIL "john" "example.com") ("John" NIL "john" "example.com") ("John" NIL "john" "example.com") ("John" NIL "john" "example.com") ("John" NIL "john" "example.com") ("John" NIL "john" "example.com") "<inreply@example.com>" "<msgid@example.com>")
    ;
    var iter = Iterator.split(input);

    const env = try Envelope.parse(&iter);

    try std.testing.expectEqualStrings("Mon, 1 Jan 2024 10:00:00 +0000", env.date.?);
    try std.testing.expectEqualStrings("Subject line", env.subject.?);
    try std.testing.expect(env.from != null);
    try std.testing.expectEqualStrings("john", env.from.?.mailbox.?);
    try std.testing.expectEqualStrings("example.com", env.from.?.host.?);
    try std.testing.expectEqualStrings("<inreply@example.com>", env.in_reply_to.?);
    try std.testing.expectEqualStrings("<msgid@example.com>", env.message_id.?);
}

test "Envelope.parse handles NIL address fields" {
    const input =
        \\("Tue, 2 Jan 2024" "Test subject" (NIL NIL "bob" "example.org") (NIL NIL "bob" "example.org") (NIL NIL "bob" "example.org") (NIL NIL "bob" "example.org") (NIL NIL "bob" "example.org") (NIL NIL "bob" "example.org") "<inreply@x.org>" "<msgid@x.org>")
    ;
    var iter = Iterator.split(input);

    const env = try Envelope.parse(&iter);

    try std.testing.expectEqualStrings("Test subject", env.subject.?);
    try std.testing.expectEqualStrings("bob", env.from.?.mailbox.?);
    try std.testing.expectEqualStrings("example.org", env.from.?.host.?);
}

test "Envelope.parse fails with missing date(mssing date retruns no subject error)" {
    const input =
        \\("Subject" (("John" NIL "john" "example.com")) (("John" NIL "john" "example.com")) (("John" NIL "john" "example.com")) (("John" NIL "john" "example.com")) (("John" NIL "john" "example.com")) (("John" NIL "john" "example.com")) "<inreply@example.com>" "<msgid@example.com>")
    ;
    var iter = Iterator.split(input);

    const result = Envelope.parse(&iter);
    try std.testing.expectError(Envelope.Error.NoSubject, result);
}

test "Envelope.parse fails with incomplete address section" {
    const input =
        \\("Mon, 1 Jan" "Subject" ("John" NIL "john" "example.com") ("John" NIL "john" "example.com") ("John" NIL "john" "example.com") ("John" NIL "john" "example.com") ("John" NIL "john" "example.com") (  ; <-- missing closing parenthesis "<inreply@example.com>" "<msgid@example.com>")
    ;
    var iter = Iterator.split(input);

    const result = Envelope.parse(&iter);
    try std.testing.expectError(Envelope.Error.BadBCC, result);
}

test "Envelope.parse fails when message-id missing" {
    const input =
        \\("Mon, 1 Jan 2024"
        \\"Subj"
        \\(("John" NIL "john" "example.com"))
        \\(("John" NIL "john" "example.com"))
        \\(("John" NIL "john" "example.com"))
        \\(("John" NIL "john" "example.com"))
        \\(("John" NIL "john" "example.com"))
        \\(("John" NIL "john" "example.com"))
        \\"<inreply@example.com>")
    ;
    var iter = Iterator.split(input);

    const result = Envelope.parse(&iter);
    try std.testing.expectError(Envelope.Error.NoInReply, result);
}
