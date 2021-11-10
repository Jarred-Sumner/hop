const std = @import("std");
const C = @import("./c.zig");
const Schema = @import("./schema.zig");
const Hop = Schema.Hop;

const string = []const u8;

pub fn cmpStringsAsc(ctx: void, a: string, b: string) bool {
    return std.mem.order(u8, a, b) == .lt;
}

pub fn cmpStringsDesc(ctx: void, a: string, b: string) bool {
    return std.mem.order(u8, a, b) == .gt;
}

const sort_asc = std.sort.asc(u8);
const sort_desc = std.sort.desc(u8);

pub fn sortAsc(in: []string) void {
    std.sort.sort([]const u8, in, {}, cmpStringsAsc);
}

pub fn sortDesc(in: []string) void {
    std.sort.sort([]const u8, in, {}, cmpStringsDesc);
}

const Library = struct {
    pub const magic_bytes = "#!/usr/bin/env hop\n\n";
    const Header = [magic_bytes.len + 5]u8;

    archive: Hop.Archive,
    allocator: *std.mem.Allocator,
    metadata_bytes: []u8,
    fd: ?std.os.fd_t,

    pub const Builder = struct {
        allocator: *std.mem.Allocator,
        files: std.ArrayListUnmanaged(Hop.File),
        metadata_bytes: std.ArrayListUnmanaged(u8),
        destination: std.fs.File = undefined,

        pub fn init(allocator: *std.mem.Allocator) Builder {
            return Builder{
                .allocator = allocator,
                .metadata_bytes = .{},
                .files = std.ArrayListUnmanaged(Hop.File){},
            };
        }

        pub fn start(this: *Builder, file: std.fs.File) !void {
            this.destination = file;
            try file.seekTo(0);

            // Write the header with 0 set as the content offset
            try file.writeAll(magic_bytes ++ [5]u8{ 0, 0, 0, 0, '\n' });
        }

        const FileSorter = struct {
            metadata: []const u8,
            pub fn sortByName(this: FileSorter, lhs: Hop.File, rhs: Hop.File) bool {
                return std.mem.order(u8, this.metadata[lhs.name.off..][0..lhs.name.len], this.metadata[rhs.name.off..][0..rhs.name.len]) == .lt;
            }
        };

        pub fn done(this: *Builder) !Hop.Archive {
            const metadata_offset = @truncate(u32, try this.destination.getPos());

            var sorter = FileSorter{
                .metadata = this.metadata_bytes.items,
            };

            std.sort.sort(Hop.File, this.files.items, sorter, FileSorter.sortByName);

            var name_hashes = try this.allocator.alloc(u32, this.files.items.len);

            for (this.files.items) |file, i| {
                name_hashes[i] = file.name_hash;
            }

            var archive = Hop.Archive{
                .version = 1,
                .files = this.files.items,
                .name_hashes = name_hashes,
                .content_offset = metadata_offset,
                .metadata = this.metadata_bytes.items,
            };

            var schema_writer = Schema.FileWriter.init(this.destination);
            try archive.encode(&schema_writer);

            var header: Header = undefined;
            header[0..magic_bytes.len].* = magic_bytes.*;
            std.mem.writeIntNative(u32, header[magic_bytes.len..][0..4], metadata_offset);
            header[magic_bytes.len..][4] = '\n';
            try this.destination.pwriteAll(&header, 0);

            _ = C.fchmod(
                this.destination.handle,
                // chmod 777
                0000010 | 0000100 | 0000001 | 0001000 | 0000040 | 0000004 | 0000002 | 0000400 | 0000200 | 0000020,
            );

            return archive;
        }

        pub fn appendMetadata(this: *Builder, bytes: []const u8) !Hop.StringPointer {
            const off = @truncate(u32, this.metadata_bytes.items.len);

            // Keep a null ptr at the end of the metadata so that C APIs expecting sentinel ptrs work without copying
            try this.metadata_bytes.appendSlice(this.allocator, bytes);
            try this.metadata_bytes.append(this.allocator, 0);
            return Hop.StringPointer{
                .off = off,
                .len = @truncate(u32, bytes.len),
            };
        }

        pub fn appendContent(this: *Builder, bytes: []const u8) !Hop.StringPointer {
            const off = try this.destination.getPos();
            try this.destination.writeAll(bytes);
            return Hop.StringPointer{
                .off = off,
                .len = bytes.len,
            };
        }

        pub fn appendContentFromDisk(this: *Builder, name: []const u8, in: std.fs.File) !void {
            var stat = try in.stat();

            _ = try this.destination.write("\n");
            const off_in = try this.destination.getPos();
            const written = try std.os.copy_file_range(in.handle, 0, this.destination.handle, off_in, stat.size, 0);
            try this.destination.seekTo(off_in + written);
            const end = try this.destination.getPos();
            try this.appendFileMetadata(name, off_in, end, stat);
            try this.destination.writeAll(&[_]u8{0});
        }

        pub fn appendFileMetadata(this: *Builder, name_buf: []const u8, start_pos: u64, end_pos: u64, stat: std.fs.File.Stat) !void {
            const name = try this.appendMetadata(name_buf);
            try this.files.append(
                this.allocator,
                Hop.File{
                    .name = name,
                    .name_hash = @truncate(u32, std.hash.Wyhash.hash(0, name_buf)),
                    .data = Schema.Hop.StringPointer{ .off = @truncate(u32, start_pos), .len = @truncate(u32, end_pos - start_pos) },
                    .chmod = @truncate(u32, stat.mode),
                    .mtime = @truncate(u32, @intCast(u128, @divFloor(stat.mtime, std.time.ns_per_s))),
                    .ctime = @truncate(u32, @intCast(u128, @divFloor(stat.ctime, std.time.ns_per_s))),
                },
            );
        }

        pub fn appendDirectoryRecursively(this: *Builder, dir: std.fs.Dir) !void {
            var walker = try dir.walk(this.allocator);
            defer walker.deinit();
            while (try walker.next()) |entry_| {
                const entry: std.fs.Dir.Walker.WalkerEntry = entry_;

                if (entry.kind != .File) continue;

                try this.appendContentFromDisk(entry.path, try entry.dir.openFile(entry.basename, .{ .read = true }));
            }
        }
    };

    pub fn extract(this: *Library, dest: std.fs.Dir, comptime verbose: bool) !void {
        for (this.archive.files) |file| {
            var name_slice = this.archive.metadata[file.name.off..][0..file.name.len :0];

            var out = dest.createFileZ(name_slice, .{ .truncate = true }) catch brk: {
                if (std.fs.path.dirname(name_slice)) |dirname| {
                    dest.makePath(dirname) catch |err2| {
                        std.log.err("error: {s} Failed to mkdir {s}\n", .{ @errorName(err2), dirname });
                        continue;
                    };
                }

                break :brk dest.createFileZ(name_slice, .{ .truncate = true }) catch |err2| {
                    std.log.err("error: {s} Failed to create file: {s}\n", .{ @errorName(err2), name_slice });
                    continue;
                };
            };

            const written = try std.os.copy_file_range(this.fd.?, file.data.off, out.handle, 0, file.data.len, 0);
            if (verbose) {
                std.log.info("Extracted file: {s} ({d} bytes)\n", .{ name_slice, written });
            }
        }
    }

    pub fn load(
        fd: std.os.fd_t,
        allocator: *std.mem.Allocator,
    ) !Library {
        var file = std.fs.File{ .handle = fd };

        var header_buf: Header = std.mem.zeroes(Header);
        var header = file.pread(&header_buf, 0) catch |err| {
            std.log.err("Archive is corrupt. Failed to read header: {s}", .{@errorName(err)});
            return err;
        };

        const content_offset = std.mem.readIntNative(u32, header_buf[magic_bytes.len..][0..4]);

        const end = file.getEndPos() catch |err| {
            std.log.err("Unable to get archive end position {s}", .{@errorName(err)});
            return error.IOError;
        };

        if (content_offset == 0 or std.math.maxInt(u32) == content_offset) {
            std.log.err("Archive is corrupt. content_offset {d} is invalid", .{content_offset});
            return error.CorruptArchive;
        }

        if (content_offset >= end) {
            std.log.err("Archive is corrupt. content_offset is {d} greater than end of file", .{content_offset});
            return error.CorruptArchive;
        }

        var metadata_buf = try allocator.alloc(u8, end - content_offset);
        var metadata = file.preadAll(metadata_buf, content_offset) catch |err| {
            std.log.err("Error reading archive metadata {s}", .{@errorName(err)});
            return err;
        };
        var reader = Schema.Reader.init(metadata_buf, allocator);
        var archive = Hop.Archive.decode(&reader) catch |err| {
            std.log.err("Archive is corrupt. Failed to decode archive: {s}", .{@errorName(err)});
            return err;
        };

        return Library{ .fd = fd, .archive = archive, .allocator = allocator, .metadata_bytes = metadata_buf };
    }
};

var input_path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;

pub fn main() anyerror!void {
    var args = try std.process.argsAlloc(std.heap.c_allocator);

    if (args.len < 2) {
        std.log.err("Usage: hop archive.hop or directory\n", .{});
        return;
    }
    adjustUlimit() catch {};

    const hopfile_path_ = brk: {
        for (args) |arg| {
            if (std.mem.eql(u8, std.fs.path.extension(std.mem.span(arg)), ".hop")) break :brk arg;
        }
        break :brk null;
    };

    if (hopfile_path_) |hopfile_path| {
        var archive_file = std.fs.openFileAbsoluteZ(hopfile_path, .{ .read = true }) catch |err| {
            std.log.err("Error opening archive {s}", .{@errorName(err)});
            return err;
        };
        var archive = try Library.load(archive_file.handle, std.heap.c_allocator);

        const print_file = args[args.len - 1].ptr != hopfile_path.ptr;

        if (print_file) {
            var stdout = std.io.getStdOut();
            const filepath = std.mem.trim(u8, std.mem.span(args[args.len - 1]), "/ ");

            const hash = @truncate(u32, std.hash.Wyhash.hash(0, filepath));
            const file_i = std.mem.indexOfScalar(u32, archive.archive.name_hashes, hash) orelse {
                std.log.err("File {s} not found in archive", .{filepath});
                std.os.abort();
            };

            const file = archive.archive.files[file_i];

            _ = std.os.sendfile(stdout.handle, archive_file.handle, file.data.off, file.data.len, &.{}, &.{}, 0) catch |err| {
                std.log.err("Error writing file {s} to stdout: {s}", .{ filepath, @errorName(err) });
                return err;
            };
        } else {
            const dest_path = std.fs.path.basename(hopfile_path[0 .. hopfile_path.len - ".hop".len]);
            var destination_dir = std.fs.cwd().makeOpenPath(dest_path, .{ .iterate = true }) catch |err| brk: {
                break :brk std.fs.cwd().openDir(dest_path, .{ .iterate = true }) catch {
                    std.log.err("Error creating destination directory {s}", .{@errorName(err)});
                    return err;
                };
            };
            archive.extract(destination_dir, true) catch |err| {
                std.log.err("Error extracting archive {s}", .{@errorName(err)});
                return err;
            };
        }
    } else {
        const input_path = args[args.len - 1];

        const realpath = std.os.realpathZ(input_path, &input_path_buf) catch |err| brk: {
            if (err == error.FileNotFound and !std.mem.eql(u8, std.fs.path.extension(std.mem.span(input_path)), ".hop")) {
                const outdir = try std.fs.cwd().makeOpenPath(std.mem.span(input_path), .{ .iterate = true });
                break :brk try std.os.getFdPath(outdir.fd, &input_path_buf);
            }

            std.log.err("Error {s} resolving path: {s}", .{ @errorName(err), std.mem.span(input_path) });
            return err;
        };

        input_path_buf[realpath.len] = 0;
        var realpath_z = input_path_buf[0..realpath.len :0];
        var archive = Library.Builder.init(std.heap.c_allocator);
        var destination_dir = std.fs.openDirAbsoluteZ(realpath_z, .{ .iterate = true }) catch |err| {
            std.log.err("Error creating destination directory {s}", .{@errorName(err)});
            return err;
        };
        var outfile: [std.fs.MAX_PATH_BYTES]u8 = undefined;
        std.mem.copy(u8, &outfile, realpath);
        std.mem.copy(u8, outfile[realpath.len..], ".hop" ++ [_]u8{0});
        var destpath = outfile[0 .. realpath.len + ".hop".len :0];
        var destination_file = std.fs.createFileAbsoluteZ(destpath, .{
            .read = true,
        }) catch |err| {
            std.log.err("Error creating destination directory {s}", .{@errorName(err)});
            return err;
        };
        try archive.start(destination_file);
        try archive.appendDirectoryRecursively(destination_dir);
        const result = try archive.done();
        std.log.info("Archived {d} files comprising {d} bytes", .{ result.files.len, result.content_offset.? });
    }
}

fn adjustUlimit() !void {
    const LIMITS = [_]std.os.rlimit_resource{ std.os.rlimit_resource.STACK, std.os.rlimit_resource.NOFILE };
    inline for (LIMITS) |limit_type, i| {
        const limit = try std.os.getrlimit(limit_type);

        if (limit.cur < limit.max) {
            var new_limit = std.mem.zeroes(std.os.rlimit);
            new_limit.cur = limit.max;
            new_limit.max = limit.max;

            try std.os.setrlimit(limit_type, new_limit);
        }
    }
}
