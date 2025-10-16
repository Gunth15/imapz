const std = @import("std");
const ParseError = error{
    InvalidList,
    InvalidFormat,
};
pub const Atom = []u8;
pub const List = []Type;
pub const Type = union(enum) {
    //Data can be in several forms and can be in multiple forms

    //atom: consists of one or more non-special chracters
    atom: Atom,

    //Number consits of one or more digit characters and represents a numberic value
    number: u32,

    //String two forms
    //1.sychronizing literal form(general form of string)
    // prefix-quoted with an octet count in the form
    // of an open brace ("{"), the number of octets, a close brace ("}"),
    // and a CRLF
    // CLRF is is immediately followed by the octet data
    // client MUST wait to receive a command continuation request before
    // sending the octet data (and the remainder of the command).

    //2. quoted string form, avoids overhead of processing literal, but has limitations on what chracters can be used
    //Unicode quoted string excluding CRLF, UTF-8, with doulbe quote (<">) at the end
    //Sequence Set and UID set(set containing UID OR seq-nums)
    //Seq-set can aslo use range such as "5:50"
    //Seq set can aslo use special symbol "*" to represent max sequence nuber in mailbox.
    //seq-set nver containers UIDs

    //the non-synchronizing literal is an alternative form of synchronizing
    //literal and may be used from client to server anywhere a
    //synchronizing literal is permitted.  The non-synchronizing literal
    //form MUST NOT be sent from server to client.  The non-synchronizing
    //literal is distinguished from the synchronizing literal by having a
    //plus ("+") between the octet count and the closing brace ("}").  The
    //server does not generate a command continuation request in response
    //to a non-synchronizing literal, and clients are not required to wait
    // before sending the octets of a non-synchronizing literal.  Unless
    //otherwise specified in an IMAP extension, non-synchronizing literals
    //MUST NOT be larger than 4096 octets.  Any literal larger than 4096
    //bytes MUST be sent as a synchronizing literal.  (Non-synchronizing
    //literals defined in this document are the same as non-synchronizing
    //literals defined by the LITERAL- extension from [RFC7888].  See that
    //document for details on how to handle invalid non-synchronizing
    //literals longer than 4096 octets and for interaction with other IMAP
    //extensions.)
    string: []u8,

    //Parenthesized List: Data structures are represented as paranthesized list
    //() is empty list, you can even nest list inside list
    //data items delimited by space and bounded by set of parenthses
    list: List,

    //NIL: Represents non-existance of data item.
    //NIL is never used for atoms Ex. mailbox named NIL which uses the "astring" syntax is a atom and string.
    //Conversely a addr-name uses "nstring" sytax, so it can be NIL or a string, but not a atom
    NIL,
    pub fn parse(data: []u8, allocator: std.mem.Allocator) ParseError!Type {
        if (data[0] == '\"' and data[data.len - 1] == '\"') return .{ .string = data[1 .. data.len - 2] };

        const upper_copy = try std.ascii.allocUpperString(allocator, data);
        defer allocator.free(upper_copy);
        if (std.mem.eql(u8, upper_copy, "NIL")) return .NIL;

        return .{ .number = std.fmt.parseInt(u32, data, 10) catch {
            if (is_atom(data)) return .{ .atom = data };
            return ParseError.InvalidFormat;
        } };
    }
};

pub fn to_string(atom: Atom) []u8 {
    return @as([]u8, atom);
}

fn is_atom(data: []u8) bool {
    for (data) |char| {
        if (std.ascii.isControl(char)) return false;
        switch (char) {
            '%', '*', '(', ')', '{', ' ', '\"', '\\', ']' => return false,
            _ => continue,
        }
    }
    return true;
}

//Literals are not handled here
//literal         = "{" number64 ["+"] "}" CRLF *CHAR8
//                  ; <number64> represents the number of CHAR8s.
//                  ; A non-synchronizing literal is distinguished
//                  ; from a synchronizing literal by the presence of
//                  ; "+" before the closing "}".
//                  ; Non-synchronizing literals are not allowed when
//                  ; sent from server to the client.
//List are also not handled here
// NOTE: IDK what this does
//8-Bit and Binary Strings
//  8-bit binary & textual mail supported through [MIME-IMB] content transfer encoding
//  MUST accept and MAY transmit text in quoted-strings as long as it does not contain
//  NUL, CR, or LF
//  Unencoded binary strings are not permitted
//  unless returned in a <literal8> in response to a
//  BINARY.PEEK[<section-binary>]<<partial>> or BINARY[<section-binary>]<<partial>> FETCH data item.
//  A "binary string" is any string with NUL characters.  A string with a
//  excessive amount of CTL characters MAY also be considered to be binary.
//  Unless returned in response to BINARY.PEEK[...]/BINARY[...]
//  FETCH, client and server implementations MUST encode binary data into
//  a textual form, such as base64, before transmitting the data.
