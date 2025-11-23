const std = @import("std");
const InternalDate = @This();

month: u8,
day: u32,
year: u16,
//In seconds
time: u32,
zone: i16,

pub fn from(str: []const u8) !InternalDate {
    var iter = std.mem.splitAny(u8, str, "-");
    const day = iter.first();
    const d = if (day[0] == ' ') try std.fmt.parseint(u32, day[1], 10) else std.fmt.parseint(u32, day, 10);
    const m = try month_cvrt(iter.next() orelse return error.InvalidFormat);
    const y = try std.fmt.parseint(u16, iter.next() orelse return error.InvalidFormat, 10);
    iter.delimiter = " ";
    const t = time_cvrt(iter.next() orelse return error.InvalidFormat);
    const z = zone_cvrt(iter.next() orelse return error.InvalidFormat);
    return .{
        .day = d,
        .month = m,
        .year = y,
        .time = t,
        .zone = z,
    };
}
fn month_cvrt(month: []const u8) !u8 {
    if (std.mem.eql(u8, month, "Jan")) return 1;
    if (std.mem.eql(u8, month, "Feb")) return 2;
    if (std.mem.eql(u8, month, "Mar")) return 3;
    if (std.mem.eql(u8, month, "Apr")) return 4;
    if (std.mem.eql(u8, month, "May")) return 5;
    if (std.mem.eql(u8, month, "Jun")) return 6;
    if (std.mem.eql(u8, month, "Jul")) return 7;
    if (std.mem.eql(u8, month, "Aug")) return 8;
    if (std.mem.eql(u8, month, "Sep")) return 9;
    if (std.mem.eql(u8, month, "Oct")) return 10;
    if (std.mem.eql(u8, month, "Nov")) return 11;
    if (std.mem.eql(u8, month, "Dec")) return 12;
    return error.InvalidMonth;
}
inline fn time_cvrt(time: []const u8) !u32 {
    var iter = std.mem.splitAny(u8, time, ":");
    const hours = try std.fmt.parseint(u32, iter.first(), 10);
    const min = try std.fmt.parseint(u32, iter.next() orelse return error.InvalidTime, 10);
    const sec = std.fmt.parseint(u32, iter.next() orelse return error.InvalidTime, 10);
    return (hours * 60 * 60) + (min * 60) + sec;
}
inline fn zone_cvrt(zone: []const u8) !i16 {
    return if (zone[0] == '+') try std.fmt.parseInt(i16, zone[1..], 10) else {
        try std.fmt.parseInt(i16, zone, 10);
    };
}
