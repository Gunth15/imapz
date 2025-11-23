const std = @import("std");
const net = @import("std").net;
const tag = @import("tag.zig");
const types = @import("types.zig");
const Line = @import("line.zig");
const Responses = @import("response.zig");
const Tls = @import("tls.zig").init;
const command = @import("command.zig");

const Client = @This();
allocator: std.mem.Allocator,
conn: std.net.Stream,
state: State,
line: Line,
responses: Responses,

//Port 143 for plain text(usually not supported)
//Port 993 for TLS(implicit TLS for IMAP)
const IMAP_PORT = 143;
const TLS_IMAP_PORT = 993;

//UID given to each message(u32)
//Any change of unique identifiers between sessions MUST be detectable using the UIDVALIDITY(u32)
//  required for a client to resynchronize its state from a previous
//   session with the server (e.g., disconnected or offline access clients
//  [IMAP-MODEL]); this is discussed further in [IMAP-DISC].
//Together form unique 64-bit value
// Persistent unique identifiers are

const State = enum {
    GREETING,
    NOAUTH,
    AUTH,
    SELECTED,
    LOGOUT,
};

const ImapError = enum {
    InvalidState,
};

//pub fn connect(address: []const u8) Client {}
//pub fn auth(user: []const u8, pass: []const u8) Client {}
//pub fn upgrade(self: *Client, hostname: []const u8) !void {
//    const tls = try Tls.init();
//    try tls.upgrade_conn(self.conn, hostname);
//    //TODO: handle deinitializing upgraded connection
//}
pub fn deinit(self: *Client) void {
    //TODO: handle secure connection
    self.conn.close();
    self.responses.deinit(self.allocator);
}

pub fn wait(self: *Client) !void {
    var areana = std.heap.ArenaAllocator.init(self.allocator);
    defer areana.deinit();

    const allocator = areana.allocator();

    var list = std.ArrayList(u8).empty;

    read_loop: while (true) {
        const resp = try self.line.read_until_clrf(allocator, .unlimited);

        const begin = std.mem.lastIndexOf(u8, resp, "{");
        const end = resp.len - 1;

        if (begin == null or resp[end] != '}') {
            try list.appendSlice(self.allocator, resp);
            break :read_loop;
        }

        try list.appendSlice(self.allocator, resp[0..begin]);

        const n = std.fmt.parseInt(u32, resp[begin + 1 .. end], 10) catch return error.InvalidFormat;
        const bytes = try self.line.read_bytes(allocator, n);

        try list.append(self.allocator, ' ');
        try list.appendSlice(self.allocator, bytes);
    }

    const resp = try Responses.parse_respone(try list.toOwnedSlice(self.allocator));
    _ = try self.responses.add_response(resp, self.allocator);
}

const CmdCompletion = union(enum) {
    done: Responses.Done,
    data: ?Responses.Data,
};
//pub fn complete(self: *Client, promise: command.Pending) !CmdCompletion {
//    //TODO: DELETE after fetching
//    const tagged = try self.responses.get_response_tag(promise.tag);
//    const data = try self.responses.get_responses_untagged(.{ .untagged = promise.untaggaged }, self.allocator);
//}
//Most commands are only valid in certain states
//It is a protocol error for client to attempt command in inappropriate state(server should respond with BAD or NO)

//Client States
//Not Authenticated State: Entered on connection start unless preauthenticated

//Authenticated: MUST select mailbox to access commands that effect messages
//entered when preauth,credentials approved, error selecting mailbox, or successful CLOSE/UNSELECT

//Selected: Entered when mailbox is successfully selected

//Logout: Entered on request from client(via LOGOUT) or by unilateral action on the part of either client or the server.
//If requested by client, server MUST respond with untagged BYE and tagged OK, and client MUST read befor closing conection
//Server SHOULD NOT close connection w/o an untagged BYE response that contains the reason for doing so.

//                    +----------------------+
//                    |connection established|
//                    +----------------------+
//                               ||
//                               \/
//              +--------------------------------------+
//              |          server greeting             |
//             +--------------------------------------+
//                        || (1)       || (2)        || (3)
//                        \/           ||            ||
//              +-----------------+    ||            ||
//             |Not Authenticated|    ||            ||
//             +-----------------+    ||            ||
//              || (7)   || (4)       ||            ||
//              ||       \/           \/            ||
//              ||     +----------------+           ||
//              ||     | Authenticated  |<=++       ||
//              ||     +----------------+  ||       ||
//              ||       || (7)   || (5)   || (6)   ||
//              ||       ||       \/       ||       ||
//              ||       ||    +--------+  ||       ||
//              ||       ||    |Selected|==++       ||
//              ||       ||    +--------+           ||
//              ||       ||       || (7)            ||
//              \/       \/       \/                \/
//             +--------------------------------------+
//             |               Logout                 |
//             +--------------------------------------+
//                               ||
//                               \/
//                 +-------------------------------+
//                 |both sides close the connection|
//                 +-------------------------------+

//command         = tag SP (command-any / command-auth / command-nonauth /
//                  command-select) CRLF
//                    ; Modal based on state
//command-auth    = append / create / delete / examine / list / lsub /
//                  rename / select / status / subscribe / unsubscribe
//                    ; Valid only in Authenticated or Selected state
//command-nonauth = login / authenticate / "STARTTLS"
//                    ; Valid only when in Not Authenticated state

//command-select  = "CHECK" / "CLOSE" / "EXPUNGE" / copy / fetch / store /
//                  uid / search
//                    ; Valid only when in Selected state
//command-select  = "CHECK" / "CLOSE" / "EXPUNGE" / copy / fetch / store /
//                  uid / search
//                    ; Valid only when in Selected state
pub inline fn exec(c: *Client, cmd: *const command, untagged_expected: command.ExpectUntagged) !command.Pending {
    return try cmd.exec(c.conn, c.writer, untagged_expected);
}

//any-state

///Requests a listing of capabilities that the server supports.
///The server MUST send a single untagged CAPABILITY response with "IMAP4rev1" as
///one of the listed capabilities before the (tagged) OK response.
pub inline fn capability(c: *Client) !command.Pending {
    return try c.exec(.{ .cmd = "CAPABILITY", .args = null }, .CAPABILITY);
}

///NOOP command can be used as a periodic poll for new messages
///message status updates during a period of inactivity (this is the
///preferred method to do this).  The NOOP command can also be used
///to reset any inactivity autologout timer on the server.
pub inline fn noop(c: *Client) !command.Pending {
    return try c.exec(.{ .cmd = "NOOP", .args = null }, .ANY);
}

///The LOGOUT command informs the server that the client is done with
///the connection.  The server MUST send a BYE untagged response
///before the (tagged) OK response, and then close the network
///connection.
pub inline fn logout(c: *Client) !command.Pending {
    return try c.exec(.{ .cmd = "LOGOUT", .args = null }, .BYE);
}

//not-authenticated

/// The STARTTLS command is an alternate form of establishing session
///  privacy protection and integrity checking, but does not establish
///  authentication or enter the authenticated state.
//NOTE: No other commands can be issued,
//so it is safe to wait for starttls completion and start TLS handshake.
pub inline fn starttls(c: *Client) !command.Pending {
    //TODO:: Make socket upgrade code
    if (c.state != State.NOAUTH) return ImapError.InvalidState;

    const promise = try c.exec(.{ .cmd = "STARTTLS", .args = null }, .NULL);
    try c.wait();
    const com = try c.complete(promise);

    if (com.done.status != .OK) return error.BadResponse;

    //starttls negotiation
    try c.upgrade();
    //get capabilities
}

//The AUTHENTICATE command provides a general mechanism for a variety of
//authentication techniques, privacy protection, and integrity checking
pub inline fn authenticate(c: *Client) !command.Pending {
    c.exec(.{ .cmd = "STARTTLS", .args = null }, .NULL);
}

//LOGIN command uses a traditional user name and
//plaintext password pair and has no means of establishing privacy
//protection or integrity checking
//pub inline fn login(c: *Client) !command.Pending {}
