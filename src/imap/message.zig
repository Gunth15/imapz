const std = @import("std");
const Iterator = @import("iterator.zig");
const Envelope = @import("message/envelope.zig");
const InternalDate = @import("message/internaldate.zig");
const msg_body = @import("message/body.zig");

const Message = union(enum) {
    FETCH: FetchedMessage,
    //NOTE: Sequence number of message is returned on expunged messages
    EXPUNGE: u32,
    pub const Error = error{
        NoUid,
        InvalidUid,
        NoFetch,
        NoEnvelope,
        NoInternalDate,
    };
    pub fn parse(iter: *Iterator, allocator: std.mem.Allocator) !Message {
        const seq = std.fmt.parseInt(u8, iter.next() orelse return Error.NoUid, 10) catch return Error.InvalidUid;
        if (std.mem.eql(u8, iter.next() orelse return Error.NoFetch, "EXPUNGE")) return .{ .EXPUNGE = seq };
        var msg: FetchedMessage = .{ .seqnum = seq };
        msg_att: while (iter.next()) |tkn| {
            switch (tkn) {
                .OpenList => {
                    //TODO: handle possible errors
                    const atom = try std.fmt.iter.next().?.Atom;
                    if (std.mem.eql(u8, atom, "ENVELOPE")) msg.envelope = try Envelope.parse(&iter);
                    //TODO: handle possible errors
                    if (std.mem.eql(u8, atom, "INTERNALDATE")) msg.internaldate = .from(iter.next().?.String);
                    //TODO: handle possible errors
                    if (std.mem.eql(u8, atom, "RFC822.SIZE")) msg.size = try std.fmt.parseInt(u64, atom, 10);
                    if (std.mem.eql(u8, atom, "BODY") or std.mem.eql(u8, atom, "BODYSTRUCTURE")) {
                        msg.body = try msg_body.Body.parse_iter(iter, allocator);
                        //"BODY" ["STRUCTURE"] SP body
                        //"BODY" section ["<" number ">"] SP nstring
                    }
                    //"BINARY" section-binary SP (nstring / literal8)
                    if (std.mem.eql(u8, atom, "BINARY")) {}
                    //"BINARY.SIZE" section-binary SP number /
                    if (std.mem.eql(u8, atom, "BINARY.SIZE")) {}
                    //"UID" SP uniqueid
                    if (std.mem.eql(u8, atom, "UID")) {}
                },
                .CloseList => break :msg_att,
            }
        }
        return .{ .FETCH = msg };
    }
};

pub const FetchedMessage = struct {
    //UID(u32)+unique validity(u32) = Unique id(u64) of message forever
    //UID
    uid: u32,
    seqnum: u32,
    flags: [][]const u8,
    //RFC 3501
    internaldate: InternalDate,
    //RFC822
    size: u64,
    envelope: Envelope,
    body: union(enum) {
        Multi: struct {
            parts: []msg_body.Body,
            //FIXME: This is not right type
            extension: ?[]const u8,
        },
        //FIXME: Add extnesion to body
        Single: msg_body.Body,
    },
};

//Internal Date Message Attribute

//RFC822.SIZE: Number of octets in message when expressed in [RFC5322] format

//Body structuture: MIME-IMB parsed representation of the body structuture information of message

//Message Texts: Can also fetch diffrent parts of [RFC5322] message along with whole message

// message-data    = nz-number SP ("EXPUNGE" / ("FETCH" SP msg-att))
//
// msg-att         = "(" (msg-att-dynamic / msg-att-static)
//                      *(SP (msg-att-dynamic / msg-att-static)) ")"
//
// msg-att-dynamic = "FLAGS" SP "(" [flag-fetch *(SP flag-fetch)] ")"
//                       ; MAY change for a message
//
//
//flag-fetch      = flag / obsolete-flag-recent
// msg-att-static  = "ENVELOPE" SP envelope /
//                     "INTERNALDATE" SP date-time /
//                     "RFC822.SIZE" SP number64 /
//                     "BODY" ["STRUCTURE"] SP body /
//                     "BODY" section ["<" number ">"] SP nstring /
//                     "BINARY" section-binary SP (nstring / literal8) /
//                     "BINARY.SIZE" section-binary SP number /
//                     "UID" SP uniqueid
//                       ; MUST NOT change for a message
