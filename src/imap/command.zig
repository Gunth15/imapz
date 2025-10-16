tag: Tag,
cmd: []const u8,
args: ?[][]u8,

const std = @import("std");
const Tag = @import("tag.zig");
const Types = @import("types.zig");
const Line = @import("line.zig");
const Command = @This();

pub const Pending = struct { tag: Tag, untaggaged: ExpectUntagged };
pub const ExpectUntagged = enum {
    CAPABILITY,
    NULL,
    BYE,
    ANY,

    pub fn parse(untag: []u8) !ExpectUntagged {
        const data = std.ascii.upperString(untag, untag);
        if (std.mem.eql(u8, data, "CAPABILITY")) return .CAPABILITY;
        if (std.mem.eql(u8, data, "BYE")) return .BYE;
        return error.UnknownTag;
    }
};

//Command is prefixed with identifier A001, A002, etc called tag
//Should generate tag for every command, but server MUST accept reuse
//NOTE: Only two cases when a command in not finished in one line
//1. Command Require server feedback
//2. Command is quoted with octet count
//In both cases, a command continuation request is made by the server and prefixed with "+"
//If an error happens, BAD is sent and no more of the command is can be sent.

//Some commands cause specific server responses to be returned; these
//are identified by "Responses:" in the command descriptions.
//Server data may be transmitted as a result of an command Thus, "no specific responses" is used instead of "none"
//NOTE: A single comand have more than one response associted with it(ayncronously).
//This means some commands will need be handled as an array to one command and sorced form that

//command         = tag SP (command-any / command-auth / command-nonauth /
//                  command-select) CRLF
//                    ; Modal based on state
//command-any     = "CAPABILITY" / "LOGOUT" / "NOOP" / x-command
//                    ; Valid in all states
//command-auth    = append / create / delete / examine / list / lsub /
//                  rename / select / status / subscribe / unsubscribe
//                    ; Valid only in Authenticated or Selected state
//command-nonauth = login / authenticate / "STARTTLS"
//                    ; Valid only when in Not Authenticated state

//command-select  = "CHECK" / "CLOSE" / "EXPUNGE" / copy / fetch / store /
//                  uid / search
//                    ; Valid only when in Selected state

//Memory immediately freed after use
pub fn exec(cmd: *const Command, line: Line, untagged_expected: ExpectUntagged) !Pending {
    const buff: [5]u8 = undefined;
    const tag_str = cmd.tag.to_string(buff);

    try line.write(tag_str);
    try line.write(" ");
    try line.write(cmd.cmd);

    if (cmd.args) {
        for (cmd.args.?) |arg| {
            try line.write(" ");
            try line.write(arg);
        }
    }

    try line.finish_and_send();

    return .{
        .tag = cmd.tag,
        .untaggaged = untagged_expected,
    };
}
