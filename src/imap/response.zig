//Serer -> Client
//Repsonses that do not indicate command completions are prefixed with a "*" and are called untagged
//MAY be sent as client or MAY be sent unilaterally by server
//Completion result indocates success or failure. Tagged with same tag as command
//If multiple commands in progress, tag can be used to identify which command goes to what.
//
//Server repsonses that need continutation from clinet are tagged with "+"
//Server repsonses that do not indicate command completion are tagged with "*"(untagged)
//  There is no diffrenece from untagged generated from command or unlateral server event
//Server responses that signify completion have the same tag as the command that created it
//NOTE: Client must be prepared to accept server repsonse at all times.
//Including unrequested data and all of it SHOUlD be cached.
const std = @import("std");
const Tag = @import("tag.zig");
const UntaggedExpected = @import("command.zig").ExpectUntagged;
const Responses = @This();

done_resp: std.ArrayListUnmanaged(?Done),
continue_resp: std.ArrayListUnmanaged(?Continue),
data_resp: std.ArrayListUnmanaged(?Data),

pub const Status = enum {
    OK, //Success
    BAD, //Unrecognized command or command syntax error
    NO, //Failure
};

//NOTE: Continue may be base64 encoded
pub const Continue = struct { resp_text_code: ?[]u8, text: []const u8 };
pub const Done = struct { tag: Tag, status: Status, resp_code: ?[]const u8, text: []const u8 };

pub const Data = union(enum) {
 //response-data   = "*" SP (resp-cond-state / resp-cond-bye /
 //                  mailbox-data / message-data / capability-data /
 //                  enable-data) CRLF
//resp-cond-state = ("OK" / "NO" / "BAD") SP resp-text
//                   ; Status condition
//resp-cond-bye   = "BYE" SP resp-text
//
    .STATE = []const u8,
    .BYE = []const u8,
    .MAILBOX,
    .MESSAGE,
    .CAPABILITY,
    .ENABLE,
    pub fn parse() !void{}
};

const Type = enum { DONE, CONTINUE, DATA };
const Response = union(Type) {
    DATA: Data,
    CONTINUE: Continue,
    DONE: Done,
};

const ResponseID = struct {
    type: Type,
    id: u32,
};

const Error = error{
    InvalidID,
    InvalidTag,
};

const init: Responses = .{ .continue_resp = .empty, .data_resp = .empty, .done_resp = .empty };
pub fn deinit(self: *Responses, allocator: std.mem.Allocator) void {
    self.continue_resp.deinit(allocator);
    self.data_resp.deinit(allocator);
    self.done_resp.deinit(allocator);
}

pub fn add_response(self: *Responses, resp: Response, allocator: std.mem.Allocator) !ResponseID {
    const resps = switch (resp.tag) {
        .CONTINUE => self.continue_resp,
        .DATA => self.data_resp,
        .DONE => self.done_resp,
    };
    const id = self.get_next_slot(resp.tag) catch {
        const new: ResponseID = .{ .id = resps.len, .type = resp.tag };
        try resps.append(allocator, new);
        return new;
    };

    resps[id.id] = switch (resp) {
        .CONTINUE => |r| r,
        .DATA => |r| r,
        .DONE => |r| r,
    };

    return id;
}
pub fn rm_response(self: *Responses, id: ResponseID) Error.InvalidID!void {
    const resps = switch (id.type) {
        .CONTINUE => self.continue_resp,
        .DATA => self.data_resp,
        .DONE => self.done_resp,
    };
    if (id.id < resps.items.len) return Error.InvalidID;
    resps.items[id.id] = null;
}
pub fn get_response(self: *Responses, id: ResponseID) Error.InvalidID!Response {
    const resps = switch (id.type) {
        .CONTINUE => self.continue_resp,
        .DATA => self.data_resp,
        .DONE => self.done_resp,
    };
    if (id.id < resps.items.len) return Error.InvalidID;
    return resps[id.id] orelse Error.InvalidID;
}
pub fn get_response_tag(self: *Responses, tag: Tag) Error.InvalidTag!Done {
    for (self.done_resp.items) |resp| {
        if (resp and resp.?.tag.level == tag.level and resp.?.tag.id == tag.id) return resp;
    }
    return Error.InvalidTag;
}
pub fn get_responses_untagged(self: *Responses, state: Data.State, allocator: std.mem.Allocator) ![]Data {
    var list = std.ArrayList(Data).empty;
    for (self.data_resp.items) |resp| {
        if ((resp and resp.?.state == state) or state.untagged == .ANY) try list.append(allocator, resp);
    }
    return try list.toOwnedSlice(allocator);
}

fn get_next_slot(self: *Responses, resp_type: Type) error{NoSlotAvailable}!ResponseID {
    const resps = switch (resp_type) {
        .CONTINUE => self.continue_resp,
        .DATA => self.data_resp,
        .DONE => self.done_resp,
    };
    for (resps.items, 0..) |resp, i| if (!resp) return .{ .id = i, .type = resp_type };
    return error.NoSlotAvailable;
}

const ParseError = error{
    InvalidFormat,
    UnrecognizedStatus,
};
pub fn parse_respone(resp: []const u8) !Response {
    return switch (resp[0]) {
        '+' => parse_continue(resp),
        '*' => parse_data(resp),
        _ => parse_done(resp),
    };
}
fn parse_continue(resp: []const u8) !Continue {
    var iter = std.mem.splitAny(u8, resp[2..], " ");

    const resp_text = iter.next() orelse return ParseError.InvalidFormat;
    var resp_text_code: ?[]const u8 = null;
    var text: ?[]const u8 = null;
    if (resp_text[0] == '[' and resp_text[resp_text.len - 1] == ']') {
        resp_text_code = resp_text;
        text = iter.next() orelse return ParseError.InvalidFormat;
    } else {
        //base64          = *(4base64-char) [base64-terminal]
        text = resp_text;
    }

    return .{
        .resp_text_code = resp_text_code,
        .text = text,
    };
}
fn parse_data(resp: []const u8) !Data {
    var iter = std.mem.splitAny(u8, resp[2..], " ");
    const status_or_utag = iter.next() orelse return ParseError.InvalidFormat;

    const status: ?Status = parse_status(status_or_utag) catch null;
    const untagged: ?UntaggedExpected = .parse(status_or_utag) catch null;
    const data = iter.next() orelse return ParseError.InvalidFormat;

    return .{ .data = data, .state = if (status) .{ .status = status.? } else .{ .untagged = untagged.? } };
}
fn parse_done(resp: []const u8) !Done {
    const tag = try Tag.from_string(resp[0..4]);
    var iter = std.mem.splitAny(u8, resp[4..], " ");

    const status_str = iter.next() orelse return ParseError.InvalidFormat;
    const status: Status = try parse_status(status_str);

    const text_or_code: []const u8 = iter.next() orelse return ParseError.InvalidFormat;

    var resp_text_code: ?[]const u8 = null;
    var text: ?[]const u8 = null;
    if (text_or_code[0] == '[' and text_or_code[text_or_code.len - 1] == ']') {
        resp_text_code = text_or_code;
        text = iter.next() orelse ParseError.InvalidFormat;
    } else {
        text = iter.next() orelse ParseError.InvalidFormat;
    }

    return .{
        .tag = tag,
        .status = status,
        .resp_code = resp_text_code,
        .text = text,
    };
}

fn parse_status(data: []const u8) !Status {
    if (std.mem.eql(u8, data, "OK")) return .OK;
    if (std.mem.eql(u8, data, "NO")) return .NO;
    if (std.mem.eql(u8, data, "BAD")) return .BAD;
    return ParseError.UnrecognizedStatus;
}

//Make some dumb test
test "parse done response" {
    const response = try parse_respone("* 23 FETCH (FLAGS (\Seen \Answered) UID 482 ENVELOPE (\"Mon, 30 Sep 2024 10:15:42 -0500\" \"Meeting Reminder\" ((\"Alice Example\" NIL \"alice\" \"example.com\")) ((\"Alice Example\" NIL \"alice\" \"example.com\")) ((\"Alice Example\" NIL \"alice\" \"example.com\")) ((\"Bob Example\" NIL \"bob\" \"example.org\")) NIL NIL NIL \"<msgid123@example.com>\"))");
    response.DATA.state.untagged
}
test "parse data response" {
    parse_respone(resp: []const u8)
}
test "parse continue response" {
    parse_respone(resp: []const u8)
}
