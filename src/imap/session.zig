//Port 143 for plain text(usually not supported)
//Port 993 for TLS(implicit TLS for IMAP)
const ImapSession = @This();
stream: net.Stream,
state: State,

//Interaction
//Initial greetting then
//Clinet -> server data -> server completion result response
//All Interactions are lines(strings that in with CRLF)
//Clinet/Server either reads lines or sequence of octet followed by line

const net = @import("std").net;

const State = enum {
    GREETING,
    NOAUTH,
    AUTH,
    SELECTED,
    LOGOUT,
};

pub fn connect(address: []const u8) ImapSession {}
pub fn auth(user: []const u8, pass: []const u8) ImapSession {}
