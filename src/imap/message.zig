const std = @import("std");
const Envelope = @import("message/envelope.zig");
const InternalDate = @import("message/internaldate.zig");
const msg_body = @import("message/body.zig");
//UID(u32)+unique validity(u32) = Unique id(u64) of message forever
//UID
uid: u32,
seqnum: u32,
flags: [][]const u8,
//RFC 3501
internaldate: InternalDate,
//RFC822
size: u32,
envelope: Envelope,
body: union(enum) {
    Multi: []msg_body.Body,
    Single: msg_body.Body,
}

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
