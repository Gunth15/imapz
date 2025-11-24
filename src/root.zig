//! By convention, root.zig is the root source file when making a library. If
//! you are making an executable, the convention is to delete this file and
//! start with main.zig instead.
pub const ImapSession = @import("imap/session.zig");

pub export fn add(a: i32, b: i32) i32 {
    return a + b;
}

test {
    _ = .{
        @import("imap/iterator.zig"),
        @import("imap/message/envelope.zig"),
        @import("imap/message/address.zig"),
        @import("imap/message/body.zig"),
    };
}
