const std = @import("std");
const Envelope = @import("envelope.zig");
const Iterator = @import("../iterator.zig");

const Fields = struct {
    params: ?[][]const u8,
    id: ?[]const u8,
    desc: ?[]const u8,
    //defaults to 7bit
    encoding: []const u8,
    octets: u32,

    const FormatError = error{ NoParamDelimeter, NoMD5, NoId, NoDesc, NoEncoding, NoOctets, InvalidOctetCount };
    pub fn parse(str: []const u8, allocator: std.mem.Allocator) FormatError!Fields {
        var iter = Iterator.split(str);
        //body-fields     = body-fld-param SP body-fld-id SP body-fld-desc SP
        //                     body-fld-enc SP body-fld-octets
        const params = switch (iter.first() orelse FormatError.NoParamDelimeter) {
            .ListOpen => try parse_params(iter, allocator),
            else => return FormatError.NoParamDelimeter,
        };
        return .{
            //NOTE: Atoms are assumed to be NIL b/c they are nstrings
            .params = params,
            .id = switch (iter.next() orelse return FormatError.NoId) {
                .String => |s| s,
                .Atom => null,
                else => return FormatError.NoId,
            },
            .desc = switch (iter.next() orelse return FormatError.NoDesc) {
                .String => |s| s,
                .Atom => null,
                else => return FormatError.NoDesc,
            },
            .encoding = switch (iter.next() orelse return FormatError.NoEncoding) {
                .String => |s| s,
                .Atom => null,
                else => return FormatError.NoEncoding,
            },
            .octets = switch (iter.next() orelse FormatError.NoOctets) {
                .Atom => |a| std.fmt.parseInt(u32, a, 10) catch return FormatError.InvalidOctetCount,
                else => return FormatError.NoOctets,
            },
        };
    }
    fn parse_params(iter: Iterator, allocator: std.mem.Allocator) !?[][]const u8 {
        var list: std.ArrayList([]const u8) = .empty;
        while (iter.next()) |t| {
            switch (t) {
                .String => |s| {
                    try list.append(allocator, s);
                },
                .Atom => null,
                .ListClose => return list.toOwnedSlice(allocator),
                else => FormatError.NoParamDelimeter,
            }
        }
        return FormatError.NoParamDelimeter;
    }
    pub fn deinit(self: *Fields, allocator: std.mem.Allocator) void {
        if (self.params != null) allocator.free(self.params.?);
    }
};

pub const Body = union(enum) {
    Basic: Basic,
    Msg: Message,
    Text: Text,

    //NOTE: only allocates memory when body-type-msg contains a body.
    pub fn parse(str: []const u8, allocator: std.mem.Allocator) !Body {
        const iter = Iterator.split(str);
        const media_type = switch (iter.peek().?) {
            .String => |s| s,
            else => return error.NoMedia,
        };
        if (std.mem.eql(u8, media_type, "MESSAGE")) return .{ .Msg = Message.parse(str, allocator) };
        if (std.mem.eql(u8, media_type, "TEXT")) return .{ .Text = Text.parse(str, allocator) };
        return .{ .Basic = Basic.parse(str, allocator) };
    }
    pub fn parse_iter(iter: Iterator, allocator: std.mem.Allocator) !Body {
        const media_type = switch (iter.peek().?) {
            .String => |s| s,
            else => return error.NoMedia,
        };
        if (std.mem.eql(u8, media_type, "MESSAGE")) return .{ .Msg = Message.parse(iter.rest(), allocator) };
        if (std.mem.eql(u8, media_type, "TEXT")) return .{ .Text = Text.parse(iter.rest(), allocator) };
        return .{ .Basic = Basic.parse(iter.rest(), allocator) };
    }
    pub fn deinit(self: *Body, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .Basic => |b| b.deinit(allocator),
            .Msg => |m| m.deinit(allocator),
            .Text => |t| t.deinit(allocator),
        }
    }
};

//body-type-basic = media-basic SP body-fields
//                       ; MESSAGE subtype MUST NOT be "RFC822" or
//                   ; "GLOBAL"
//media-basic     = ((DQUOTE ("APPLICATION" / "AUDIO" / "IMAGE" /
//                     "FONT" / "MESSAGE" / "MODEL" / "VIDEO" ) DQUOTE)
//                      / string)
//media-subtype   = string
//                   ; Defined in [MIME-IMT]
//                 SP media-subtype
//                 ; FONT defined in [RFC8081].
//                 ; MODEL defined in [RFC2077].
//                 ; Other top-level media types
//                 ; are defined in [MIME-IMT].
//body-fields     = body-fld-param SP body-fld-id SP body-fld-desc SP
//                     body-fld-enc SP body-fld-octets
pub const Basic = struct {
    sub_type: []const u8,
    type: []const u8,
    fields: Fields,

    pub const Error = error{
        NoSub,
        NoMedia,
    };
    pub fn parse(str: []const u8, allocator: std.mem.Allocator) Error!Basic {
        const iter = Iterator.split(str);
        return .{
            .sub_type = switch (iter.first().?) {
                .String => |s| s,
                else => return Error.NoSub,
            },
            .type = switch (iter.next() orelse return Error.NoMedia) {
                .Atom => |a| a,
                .String => |s| s,
                else => return Error.NoMedia,
            },
            .fields = try Fields.parse(iter, allocator),
        };
    }
    pub fn parse_iter(iter: Iterator, allocator: std.mem.Allocator) Error!Basic {
        return .{
            .sub_type = switch (iter.peek() orelse return Error.NoSub) {
                .String => |s| s,
                else => return Error.NoSub,
            },
            .type = switch (iter.peek() orelse return Error.NoMedia) {
                .Atom => |a| a,
                .String => |s| s,
                else => return Error.NoMedia,
            },
            .fields = try Fields.parse(iter, allocator),
        };
    }
    pub fn deinit(self: *Basic, allocator: std.mem.Allocator) void {
        self.fields.deinit(allocator);
    }
};

//body-type-msg   = media-message SP body-fields SP envelope
//                SP body SP body-fld-lines
//
//WARNING: Assumes body-type is MESSAGE
pub const Message = struct {
    //TYPE=MESSAGE
    fields: Fields,
    envelope: Envelope,
    body: *Body,
    field_lines: u32,

    pub const Error = error{ NoMedia, NoFieldLines };
    pub fn parse(str: []const u8, allocator: std.mem.Allocator) Error!Message {
        const iter = Iterator.split(str);
        const body: *Body = try allocator.create(Body);
        switch (iter.first().?) {
            .String => {
                const fields = try Fields.parse(iter, allocator);
                const envelope = try Envelope.parse(iter);
                body.* = Body.parse_iter(iter, allocator);
                return .{
                    //TYPE=MESSAGE
                    .fields = fields,
                    .envelope = envelope,
                    .body = body,
                    .field_lines = iter.next() orelse return Error.NoFieldLines,
                };
            },
            else => return Error.NoMedia,
        }
    }
    pub fn parse_iter(iter: Iterator, allocator: std.mem.Allocator) Error!Message {
        const body: *Body = try allocator.create(Body);
        switch (iter.next() orelse Error.NoMedia) {
            .String => {
                const fields = try Fields.parse(iter, allocator);
                const envelope = try Envelope.parse(iter);
                body.* = Body.parse_iter(iter, allocator);
                return .{
                    //TYPE=MESSAGE
                    .fields = fields,
                    .envelope = envelope,
                    .body = body,
                    .field_lines = iter.next() orelse return Error.NoFieldLines,
                };
            },
            else => return Error.NoMedia,
        }
    }
    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        self.fields.deinit(allocator);
        self.body.deinit(allocator);
    }
};

//body-type-text = media-text SP body-fields SP body-fld-lines
//
//
//WARNING: Assumes body-type is TEXT
pub const Text = struct {
    //TYPE=TEXT
    sub_type: []const u8,
    fields: Fields,
    field_lines: u32,

    pub const Error = error{ NoSub, NoFieldLines, NoMedia };
    pub fn parse(str: []const u8, allocator: std.mem.Allocator) Error!Text {
        const iter = Iterator.split(str);
        switch (iter.first().?) {
            .String => {
                return .{
                    //TYPE=TEXT
                    .sub_type = switch (iter.next() orelse Error.NoSub) {
                        .String => |s| s,
                        else => return Error.NoSub,
                    },
                    .fields = try Fields.parse(iter, allocator),
                    .field_lines = try iter.next() orelse return Error.NoFieldLines,
                };
            },
            else => return error.NoMedia,
        }
    }
    pub fn parse_iter(iter: Iterator, allocator: std.mem.Allocator) Error!Text {
        switch (iter.next() orelse Error.NoMedia) {
            .String => {
                return .{
                    //TYPE=TEXT
                    .sub_type = switch (iter.next() orelse Error.NoSub) {
                        .String => |s| s,
                        else => return Error.NoSub,
                    },
                    .fields = try Fields.parse(iter, allocator),
                    .field_lines = try iter.next() orelse return Error.NoFieldLines,
                };
            },
            else => return Error.NoMedia,
        }
    }
    pub fn deinit(self: *Text, allocator: std.mem.Allocator) void {
        self.fields.deinit(allocator);
    }
};

test "Fields.parse parses valid fields" {
    const gpa = std.testing.allocator;

    // Example: (( "charset" "utf-8" )) "id123" "desc" "7BIT" 512
    const input =
        \\(("charset" "utf-8") "id123" "desc" "7BIT" 512)
    ;

    const f = try Fields.parse(input, gpa);
    defer f.deinit(gpa);

    try std.testing.expect(f.params != null);
    const params = f.params.?;
    try std.testing.expectEqual(@as(usize, 2), params.len);
    try std.testing.expectEqualStrings("charset", params[0]);
    try std.testing.expectEqualStrings("utf-8", params[1]);

    try std.testing.expectEqualStrings("id123", f.id.?);
    try std.testing.expectEqualStrings("desc", f.desc.?);
    try std.testing.expectEqualStrings("7BIT", f.encoding);
    try std.testing.expectEqual(@as(u32, 512), f.octets);
}

test "Fields.parse detects missing closing list" {
    const gpa = std.testing.allocator;

    const bad_input =
        \\(("name" "utf-8" "id123" "desc" "7BIT" 512)
        // missing closing parenthesis
    ;

    const result = Fields.parse(bad_input, gpa);
    try std.testing.expectError(Fields.FormatError.NoParamDelimeter, result);
}

test "Basic.parse parses simple body type" {
    const gpa = std.testing.allocator;

    const input =
        \\("TEXT" "PLAIN" (("charset" "utf-8")) "id42" "desc" "7BIT" 128)
    ;

    const b = try Basic.parse(input, gpa);
    defer b.deinit(gpa);

    try std.testing.expectEqualStrings("TEXT", b.sub_type);
    try std.testing.expectEqualStrings("PLAIN", b.type);
    try std.testing.expectEqualStrings("7BIT", b.fields.encoding);
    try std.testing.expectEqual(@as(u32, 128), b.fields.octets);
}

test "Body.parse detects message type delegation" {
    const gpa = std.testing.allocator;

    const msg_input =
        \\("MESSAGE" "RFC822" (("name" "value")) "id" "desc" "7BIT" 42)
    ;

    const body = try Body.parse(msg_input, gpa);
    defer body.deinit(gpa);

    switch (body) {
        .Msg => {}, // ok
        else => return error.WrongVariant,
    }
}

test "Body.parse detects text type delegation" {
    const gpa = std.testing.allocator;

    const text_input =
        \\("TEXT" "PLAIN" (("charset" "utf-8")) "id" "desc" "7BIT" 99)
    ;

    const body = try Body.parse(text_input, gpa);
    defer body.deinit(gpa);

    switch (body) {
        .Text => |t| {
            try std.testing.expectEqualStrings("PLAIN", t.sub_type);
            try std.testing.expectEqualStrings("7BIT", t.fields.encoding);
        },
        else => return error.WrongVariant,
    }
}

test "Body.parse detects basic type fallback" {
    const gpa = std.testing.allocator;

    const app_input =
        \\("APPLICATION" "OCTET-STREAM" (("name" "val")) "id" "desc" "BASE64" 2048)
    ;

    const body = try Body.parse(app_input, gpa);
    defer body.deinit(gpa);

    switch (body) {
        .Basic => |b| {
            try std.testing.expectEqualStrings("APPLICATION", b.sub_type);
            try std.testing.expectEqualStrings("OCTET-STREAM", b.type);
        },
        else => return error.WrongVariant,
    }
}

test "Text.parse detects missing field lines" {
    const gpa = std.testing.allocator;

    const bad_input =
        \\("TEXT" "PLAIN" (("charset" "utf-8")) "id" "desc" "7BIT")
        // missing final octet count
    ;

    const result = Text.parse(bad_input, gpa);
    try std.testing.expectError(Text.Error.NoFieldLines, result);
}
