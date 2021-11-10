const std = @import("std");
usingnamespace std.c;
const builtin = @import("builtin");
const os = std.os;
const mem = std.mem;
const Stat = std.fs.File.Stat;
const Kind = std.fs.File.Kind;
const StatError = std.fs.File.StatError;
const errno = os.errno;
const zeroes = mem.zeroes;

pub extern "c" fn chmod([*c]const u8, mode_t) c_int;
pub extern "c" fn fchmod(std.c.fd_t, mode_t) c_int;
pub extern "c" fn umask(mode_t) mode_t;
pub extern "c" fn fchmodat(c_int, [*c]const u8, mode_t, c_int) c_int;
pub extern "c" fn fchown(std.c.fd_t, std.c.uid_t, std.c.gid_t) c_int;
pub extern "c" fn lstat([*c]const u8, [*c]libc_stat) c_int;
pub extern "c" fn lstat64([*c]const u8, [*c]libc_stat) c_int;
