const std = @import("std");

const Line = @This();

//Interaction
//Initial greetting then
//Client -> server data -> server completion result response
//All Interactions are lines(strings that in with CRLF)
//Clinet/Server either reads lines or sequence of octet followed by line
reader: std.Io.Reader,
writer: std.Io.Writer,

pub fn init(stream: std.net.Stream, read_buf: []u8, write_buf: []u8) !Line {
    return .{
        .reader = stream.reader(read_buf),
        .writer = stream.writer(write_buf),
    };
}

pub fn write(self: *Line, bytes: []const u8) !usize {
    try self.writer.write(bytes);
}

//writes a whole line and sends the message
pub fn write_and_send_ln(self: *Line, bytes: []const u8) !usize {
    var size = try self.writer.write(bytes);
    size += try self.finish_and_send();
    return size;
}

pub fn finish_and_send(self: *Line) !usize {
    const size = try self.writer.write("\r\n");
    try self.writer.flush();
    return size;
}

//read unitl clrf
pub fn read_until_clrf(self: *Line, allocator: std.mem.Allocator, limit: std.Io.Limit) ![]u8 {
    var line: std.ArrayList(u8) = .empty;
    read_until: while (true) {
        const buf_slice = self.reader.takeDelimiterExclusive('\r') catch |e| {
            switch (e) {
                error.EndofStream => {
                    break :read_until;
                },
                error.StreamTooLong => {
                    self.reader.appendRemaining(allocator, line, limit);
                    continue :read_until;
                },
            }
        };

        const maybe_delim = try self.reader.take(2);
        if (!std.mem.eql(maybe_delim, "\r\n")) {
            try line.appendSlice(allocator, buf_slice);
            try line.appendSlice(allocator, maybe_delim);
            continue :read_until;
        }

        break :read_until;
    }
    return try line.toOwnedSlice(allocator);
}

pub fn read_bytes(self: *Line, allocator: std.mem.Allocator, size: usize) ![]u8 {
    var line: std.ArrayList(u8) = .empty;
    var read: usize = size;
    read_until: while (read > 0) {
        const buf_slice = self.reader.take(read) catch |e| {
            switch (e) {
                error.EndofStream => {
                    break :read_until;
                },
                error.StreamTooLong => {
                    read -= self.reader.bufferedLen();
                    self.reader.appendRemaining(allocator, line, .unlimited);
                    continue :read_until;
                },
            }
        };
        try line.appendSlice(allocator, buf_slice);
        break :read_until;
    }
    return try line.toOwnedSlice(allocator);
}
