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

    const FormatError = error{ NoParamDelimeter, NoClosingParamDelimiter, BadParams, NoMD5, NoId, NoDesc, NoEncoding, NoOctets, InvalidOctetCount };
    pub fn parse(str: []const u8, arena: std.mem.Allocator) !Fields {
        //body-fields     = body-fld-param SP body-fld-id SP body-fld-desc SP
        //                     body-fld-enc SP body-fld-octets
        var iter = Iterator.split(str);
        return parseIter(&iter, arena);
    }
    pub fn parseIter(iter: *Iterator, arena: std.mem.Allocator) !Fields {
        //body-fields     = body-fld-param SP body-fld-id SP body-fld-desc SP
        //                     body-fld-enc SP body-fld-octets
        const params = switch (iter.next() orelse return FormatError.NoParamDelimeter) {
            .ListOpen => try parse_params(iter, arena),
            .Atom => null,
            else => return FormatError.NoParamDelimeter,
        };
        return .{
            //NOTE: Atoms are assumed to be NIL b/c they are nstrings
            .params = params,
            .id = switch (iter.next() orelse return FormatError.NoId) {
                .String => |s| s[1 .. s.len - 1],
                .Atom => null,
                else => return FormatError.NoId,
            },
            .desc = switch (iter.next() orelse return FormatError.NoDesc) {
                .String => |s| s[1 .. s.len - 1],
                .Atom => null,
                else => return FormatError.NoDesc,
            },
            .encoding = switch (iter.next() orelse return FormatError.NoEncoding) {
                .String => |s| s[1 .. s.len - 1],
                else => return FormatError.NoEncoding,
            },
            .octets = switch (iter.next() orelse return FormatError.NoOctets) {
                .Atom => |a| std.fmt.parseInt(u32, a, 10) catch return FormatError.InvalidOctetCount,
                else => return FormatError.NoOctets,
            },
        };
    }
    fn parse_params(iter: *Iterator, arena: std.mem.Allocator) !?[][]const u8 {
        var list: std.ArrayList([]const u8) = .empty;
        while (iter.next()) |t| {
            switch (t) {
                .String => |s| {
                    try list.append(arena, s[1 .. s.len - 1]);
                },
                .ListClose => return list.items,
                else => return FormatError.BadParams,
            }
        }
        return FormatError.NoClosingParamDelimiter;
    }
};

pub const BodyStructure = union(enum) {
    Basic: Basic,
    Msg: Message,
    Text: Text,

    //NOTE: only allocates memory when body-type-msg contains a body.
    //FIXME: Handle null case
    pub fn parse(str: []const u8, arena: std.mem.Allocator) !BodyStructure {
        var iter = Iterator.split(str);
        const media_type = switch (iter.next().?) {
            .String => |s| s[1 .. s.len - 1],
            else => return error.NoMedia,
        };
        if (std.mem.eql(u8, media_type, "MESSAGE")) return .{ .Msg = try Message.parseIter(&iter, arena) };
        if (std.mem.eql(u8, media_type, "TEXT")) return .{ .Text = try Text.parseIter(&iter, arena) };
        return .{ .Basic = try Basic.parseIter(&iter, media_type, arena) };
    }
    pub fn parse_iter(iter: *Iterator, arena: std.mem.Allocator) !BodyStructure {
        const media_type = switch (iter.next().?) {
            .String => |s| s[1 .. s.len - 1],
            else => return error.NoMedia,
        };
        if (std.mem.eql(u8, media_type, "MESSAGE")) return .{ .Msg = try Message.parse(iter.rest(), arena) };
        if (std.mem.eql(u8, media_type, "TEXT")) return .{ .Text = try Text.parse(iter.rest(), arena) };
        return .{ .Basic = try Basic.parseIter(iter, media_type, arena) };
    }
};

//body-type-basic = media-basic SP body-fields
//                       ; MESSAGE subtype MUST NOT be "RFC822" or
//                   ; "GLOBAL"
//media-basic     = ((DQUOTE ("APPLICATION" / "AUDIO" / "IMAGE" /
//                     "FONT" / "MESSAGE" / "MODEL" / "VIDEO" ) DQUOTE)
//                      / string)
//                 SP media-subtype
//media-subtype   = string
//                   ; Defined in [MIME-IMT]
//                 ; FONT defined in [RFC8081].
//                 ; MODEL defined in [RFC2077].
//                 ; Other top-level media types
//                 ; are defined in [MIME-IMT].
//body-fields     = body-fld-param SP body-fld-id SP body-fld-desc SP
//                     body-fld-enc SP body-fld-octets
pub const Basic = struct {
    type: []const u8,
    sub_type: []const u8,
    fields: Fields,

    pub const Error = error{
        NoSub,
        NoMedia,
        BadFieldsFormat,
    };
    pub fn parse(str: []const u8, media_type: []const u8, arena: std.mem.Allocator) !Basic {
        var iter = Iterator.split(str);
        _ = iter.next();
        return .{
            .type = media_type,
            .sub_type = switch (iter.next() orelse return Error.NoSub) {
                .String => |s| s[1 .. s.len - 1],
                else => return Error.NoSub,
            },
            .fields = Fields.parseIter(&iter, arena) catch return Error.BadFieldsFormat,
        };
    }
    pub fn parseIter(iter: *Iterator, media_type: []const u8, arena: std.mem.Allocator) !Basic {
        return .{
            .type = media_type,
            .sub_type = switch (iter.next() orelse return Error.NoSub) {
                .String => |s| s[1 .. s.len - 1],
                else => return Error.NoSub,
            },
            .fields = Fields.parseIter(iter, arena) catch return Error.BadFieldsFormat,
        };
    }
};

//body-type-msg   = media-message SP body-fields SP envelope
//                SP body SP body-fld-lines
//
//WARNING: Assumes body-type is MESSAGE
pub const Message = struct {
    //TYPE=MESSAGE
    media: []const u8,
    fields: Fields,
    envelope: Envelope,
    body: *BodyStructure,
    field_lines: u64,

    pub const Error = error{
        NoMedia,
        BadFieldLines,
        UnabletoAllocateBody,
        BadFieldsFormat,
        BadEnvelopeFormat,
        BadBodyFormat,
    };
    pub fn parse(str: []const u8, arena: std.mem.Allocator) Error!Message {
        var iter = Iterator.split(str);
        return parseIter(&iter, arena);
    }
    pub fn parseIter(iter: *Iterator, arena: std.mem.Allocator) Error!Message {
        const body: *BodyStructure = arena.create(BodyStructure) catch return Error.UnabletoAllocateBody;
        switch (iter.next() orelse return Error.NoMedia) {
            .String => |media| {
                const fields = Fields.parseIter(iter, arena) catch return Error.BadFieldLines;
                const envelope = Envelope.parse(iter, arena) catch return Error.BadEnvelopeFormat;
                body.* = BodyStructure.parse_iter(iter, arena) catch return Error.BadBodyFormat;
                return .{
                    //TYPE=MESSAGE
                    .media = media,
                    .fields = fields,
                    .envelope = envelope,
                    .body = body,
                    .field_lines = std.fmt.parseInt(u64, iter.string() catch return Error.BadFieldLines, 10) catch return Error.BadFieldLines,
                };
            },
            else => return Error.NoMedia,
        }
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
    field_lines: u64,

    pub const Error = error{ NoSub, NoFieldLines, NoMedia, BadFieldLines, BadFields };
    pub fn parse(str: []const u8, arena: std.mem.Allocator) !Text {
        var iter = Iterator.split(str);
        switch (iter.first().?) {
            .String => {
                return .{
                    //TYPE=TEXT
                    .sub_type = switch (iter.next() orelse return Error.NoSub) {
                        .String => |s| s[1 .. s.len - 1],
                        else => return Error.NoSub,
                    },
                    .fields = Fields.parseIter(&iter, arena) catch return Error.BadFields,
                    .field_lines = std.fmt.parseInt(u64, iter.string() catch return Error.NoFieldLines, 10) catch return Error.BadFieldLines,
                };
            },
            else => return error.NoMedia,
        }
    }
    pub fn parseIter(iter: *Iterator, arena: std.mem.Allocator) Error!Text {
        switch (iter.next() orelse return Error.NoMedia) {
            .String => {
                return .{
                    //TYPE=TEXT
                    .sub_type = switch (iter.next() orelse return Error.NoSub) {
                        .String => |s| s[1 .. s.len - 1],
                        else => return Error.NoSub,
                    },
                    .fields = Fields.parseIter(iter, arena) catch return Error.BadFields,
                    .field_lines = std.fmt.parseInt(u64, iter.string() catch return Error.NoFieldLines, 10) catch return Error.BadFieldLines,
                };
            },
            else => return Error.NoMedia,
        }
    }
};

test "Fields.parse parses valid fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Example: ( "charset" "utf-8" ) "id123" "desc" "7BIT" 512
    const input =
        \\("charset" "utf-8") "id123" "desc" "7BIT" 512
    ;

    const f = try Fields.parse(input, allocator);

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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const bad_input =
        \\("name" "utf-8" "id123" "desc" "7BIT" "512"
        // missing closing parenthesis
    ;

    const result = Fields.parse(bad_input, allocator);
    try std.testing.expectError(Fields.FormatError.NoClosingParamDelimiter, result);
}

test "Basic.parse parses simple body type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const input =
        \\"TEXT" "PLAIN" ("charset" "utf-8") "id42" "desc" "7BIT" 128
    ;

    const b = try Basic.parse(input, "TEXT", allocator);

    try std.testing.expectEqualStrings("TEXT", b.type);
    try std.testing.expectEqualStrings("PLAIN", b.sub_type);
    try std.testing.expectEqualStrings("7BIT", b.fields.encoding);
    try std.testing.expectEqual(@as(u32, 128), b.fields.octets);
}

test "Body.parse detects message type delegation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const msg_input =
        \\"MESSAGE" "RFC822" ("name" "value") NIL NIL "7BIT" 1234 ("Mon, 7 Feb 2025 12:00:00 -0800" "Original Subject" (("John Doe" NIL "john" "example.com")) (("John Doe" NIL "john" "example.com")) (("John Doe" NIL "john" "example.com")) (("Jane Smith" NIL "jane" "example.com")) NIL NIL NIL "<msg123@example.com>") ("TEXT" "PLAIN" ("charset" "us-ascii") NIL NIL "7BIT" 567 15) 45
    ;

    const body = try BodyStructure.parse(msg_input, allocator);

    switch (body) {
        .Msg => {}, // ok
        else => return error.WrongVariant,
    }
}

test "Body.parse detects text type delegation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const text_input =
        \\"TEXT" "PLAIN" ("charset" "utf-8") "id" "desc" "7BIT" 99
    ;

    const body = try BodyStructure.parse(text_input, allocator);

    switch (body) {
        .Text => |t| {
            try std.testing.expectEqualStrings("PLAIN", t.sub_type);
            try std.testing.expectEqualStrings("7BIT", t.fields.encoding);
        },
        else => return error.WrongVariant,
    }
}

test "Body.parse detects basic type fallback" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const app_input =
        \\"APPLICATION" "OCTET-STREAM" ("name" "val") "id" "desc" "BASE64" 2048
    ;

    const body = try BodyStructure.parse(app_input, allocator);

    switch (body) {
        .Basic => |b| {
            try std.testing.expectEqualStrings("APPLICATION", b.sub_type);
            try std.testing.expectEqualStrings("OCTET-STREAM", b.type);
        },
        else => return error.WrongVariant,
    }
}

test "Text.parse detects missing field lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const bad_input =
        \\"TEXT" "PLAIN" ("charset" "utf-8") "id" "desc" "7BIT"
        // missing final octet count
    ;

    const result = Text.parse(bad_input, allocator);
    try std.testing.expectError(Text.Error.NoFieldLines, result);
}
