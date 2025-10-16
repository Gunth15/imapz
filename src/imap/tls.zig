const std = @import("std");
const OS = @import("builtin").target.os.tag;

//TLS interface
pub const Tls = switch (OS) {
    .linux => openssl,
    .freebsd, .macos => libressl,
    .windows => secure_socket,
    else => @compileError("Unsupported OS"),
};

pub const TLSError = error{ LoadCertFailed, ContextFailure, SetCertificateStoreFailure, SetMinTLSVersionFailure, SetCertHostnameFailure, CouldNotCreateSSLObj, CouldNotCreateBIO, SNIHostnameError };

//NOTE: OpenSSL, allocates internally controlled memory
const openssl = struct {
    const openSSl = @cImport({
        @cInclude("openssl/ssl.h");
        @cInclude("openssl/bio.h");
        @cInclude("openssl/err.h");
        @cInclude("stdio.h");
    });

    //NOTE: I only use one CTXT and one SSL obbject, so this is fine.
    //If I used more id, probably do something better for the fields
    ctx: *openSSl.struct_ssl_ctx_st,

    const Self = @This();

    const Options = struct { cafile: ?[]const u8 = null, cadir: ?[]const u8 = null };
    pub fn init(options: Options) TLSError!Self {
        const ctx = openSSl.SSL_CTX_new(openSSl.TLS_method()) orelse {
            return TLSError.ContextFailure;
        };

        openSSl.SSL_CTX_set_verify(ctx, openSSl.SSL_VERIFY_PEER, null);

        if (options.cafile != null) {
            if (openSSl.SSL_CTX_load_verify_locations(ctx, @ptrCast(options.cafile), @ptrCast(options.cadir)) == 0) return TLSError.SetCertificateStoreFailure;
        } else {
            if (openSSl.SSL_CTX_set_default_verify_paths(ctx) == 0) return TLSError.SetCertificateStoreFailure;
        }
        if (openSSl.SSL_CTX_set_min_proto_version(ctx, openSSl.TLS1_2_VERSION) == 0) return TLSError.SetMinTLSVersionFailure;
        return .{
            .ctx = ctx,
        };
    }

    ///Stream connection is moved to SecureConnection
    pub fn upgrade_conn(self: *const Self, conn: std.net.Stream, hostname: []const u8) TLSError!SecureConnection {
        const h: [*c]const u8 = @alignCast(hostname);
        //WARNING: IDK if const works here
        const ssl = openSSl.SSL_new(self.ctx) orelse {
            return TLSError.CouldNotCreateSSLObj;
        };
        const bio = openSSl.BIO_new(openSSl.BIO_s_socket()) orelse {
            return TLSError.CouldNotCreateBIO;
        };

        if (openSSl.BIO_set_fd(bio, conn.handle, openSSl.BIO_CLOSE) <= 0) return TLSError.CouldNotCreateBIO;
        openSSl.SSL_set_bio(ssl, bio, bio);
        if (openSSl.SSL_set_tlsext_host_name(ssl, h) == 0) return TLSError.SNIHostnameError;
        //NOTE: most of the time, hostname for SNI and the one in the cert is the same
        if (openSSl.SSL_set1_host(ssl, h) == 0) return TLSError.SetCertHostnameFailure;

        return .{ .ssl = ssl };
    }

    pub fn dump_errors(file: std.fs.File) !void {
        const fp = openSSl.fdopen(file.handle, "w");
        if (fp == null) {
            return error.FpFailure;
        }
        openSSl.ERR_print_errors_fp(fp.?);
    }

    pub fn deinit(self: *const Self) void {
        openSSl.SSL_CTX_free(self.ctx);
    }
    ///Underlying Socket will close when SecureSocket is closed
    const SecureConnection = struct {
        ssl: *openSSl.struct_ssl_st,

        pub fn handshake(conn: *const SecureConnection) !void {
            //Self signed certs return the Unrecognised CA error
            if (openSSl.SSL_connect(conn.ssl) < 1) return error.UnrecognizedCA;
        }
        pub fn read(conn: *const SecureConnection, buff: []u8) !usize {
            const size = openSSl.SSL_read(conn.ssl, @ptrCast(buff), @intCast(buff.len));
            if (size <= 0 and openSSl.SSL_get_error(conn.ssl, size) != openSSl.SSL_ERROR_ZERO_RETURN) return error.ReadError;
            return @intCast(size);
        }
        pub fn write(conn: *const SecureConnection, buff: []const u8) !usize {
            const size = openSSl.SSL_write(conn.ssl, @ptrCast(buff), @intCast(buff.len));
            if (size <= 0 and openSSl.SSL_get_error(conn.ssl, size) != openSSl.SSL_ERROR_ZERO_RETURN) return error.WriteError;
            return @intCast(size);
        }

        pub fn close(conn: *const SecureConnection) !void {
            if (openSSl.SSL_shutdown(conn.ssl) < 1) return error.ShutdownError;
            openSSl.SSL_free(conn.ssl);
        }

        //returns error as human readable string
        pub fn err(conn: *const SecureConnection) []const u8 {
            if (openSSl.SSL_get_verify_result(conn.ssl) != openSSl.X509_V_OK) {
                const s = openSSl.X509_verify_cert_error_string(openSSl.SSL_get_verify_result(conn.ssl));
                const size = openSSl.strlen(s);
                return s[0..size];
            }
            return "No errors";
        }

        //No reason to have separate read and write interface for this usecase
        pub fn interface(conn: *const SecureConnection, read_buffer: []u8, write_buffer: []u8) WriterReader {
            return .{
                .conn = conn,
                .reader_interface = .{
                    .vtable = &.{
                        .stream = WriterReader.stream,
                    },
                    .buffer = read_buffer,
                    .seek = 0,
                    .end = read_buffer.len,
                },
                .writer_interface = .{
                    .vtable = &.{
                        .drain = WriterReader.drain,
                    },
                    .buffer = write_buffer,
                    .end = 0,
                },
            };
        }

        const WriterReader = struct {
            const ReadError = std.Io.Reader.Error;
            const WriteError = std.Io.Writer.Error;
            conn: *SecureConnection,
            reader_interface: std.Io.Reader,
            writer_interface: std.Io.Writer,
            fn stream(io_r: *std.Io.Reader, io_w: *std.Io.Writer, limit: std.Io.Limit) ReadError!usize {
                const r: WriterReader = @alignCast(@fieldParentPtr("reader_interface", io_r));
                const dest = limit.slice(try io_w.writableSliceGreedy(1));
                const n = r.conn.read(dest) catch return ReadError.ReadFailed;
                io_w.advance(n);
                return n;
            }
            fn drain(io_w: *std.Io.Writer, data: []const []const u8, splat: usize) WriteError!usize {
                try std.debug.assert(data.len == 0);

                const w: WriterReader = @alignCast(@fieldParentPtr("writer_interface", io_w));

                _ = try w.conn.write(io_w.buffer[0..io_w.end]) catch return WriteError.WriteFailed;

                var n = 0;
                for (data[0 .. data.len - 1]) |buff| {
                    n += try w.conn.write(buff) catch return WriteError.WriteFailed;
                }
                for (0..splat) |_| {
                    n += try w.conn.write(data[data.len - 1]) catch return WriteError.WriteFailed;
                }

                io_w.buffer = undefined;
                io_w.end = 0;
                return n;
            }
        };
    };
};

const secure_socket = struct {};

const libressl = struct {};

test "Upgrade connection, handshake, write, and read " {
    switch (OS) {
        .linux => {
            const ctx = try Tls.init(.{ .cafile = "cert.pem" });
            defer ctx.deinit();

            const conn = try std.net.tcpConnectToAddress(.initIp4(.{ 127, 0, 0, 1 }, 4433));
            const s_conn = ctx.upgrade_conn(conn, "localhost") catch |e| {
                const err = std.fs.File.stderr();
                try Tls.dump_errors(err);
                return e;
            };
            defer {
                s_conn.close() catch {
                    std.debug.print("Error occured shutting down connection\n", .{});
                };
            }

            s_conn.handshake() catch |e| {
                const err = std.fs.File.stderr();
                try Tls.dump_errors(err);
                return e;
            };

            _ = s_conn.write("hi\r\n") catch |e| {
                var err = std.fs.File.stderr();
                _ = try err.write("Error while writing to connection: ");
                _ = try err.write(s_conn.err());
                _ = try err.write("\n");
                try Tls.dump_errors(err);
                return e;
            };
        },
        else => @compileError("Not implemented yet"),
    }
}
