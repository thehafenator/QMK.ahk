//! Blank compiled-user-shortcuts module used by ordinary Runtime-only builds.
//! The generated module has the same `install` entry point and is supplied as
//! the explicit `user_shortcuts` dependency for a compiled candidate build.

pub const has_compiled_user_shortcuts = false;
pub const build_id = "";
pub const native_row_count: usize = 0;
pub const callback_row_count: usize = 0;

pub fn install(_: anytype) void {}
