const std = @import("std");

// The AutoHotkey compiler owns build_options_pgo.zig.  This build script must
// always import that one file as the single `build_options` module; the file
// itself selects either `struct {}` or generated_user_shortcuts.zig.
pub fn build(b: *std.Build) void {
    const target_profile = b.option([]const u8, "target_profile", "Windows target: x64 or x86") orelse "x64";
    if (!std.mem.eql(u8, target_profile, "x64") and !std.mem.eql(u8, target_profile, "x86"))
        std.debug.panic("target_profile must be x64 or x86, got '{s}'", .{target_profile});
    const cpu_arch: std.Target.Cpu.Arch = if (std.mem.eql(u8, target_profile, "x86")) .x86 else .x86_64;
    const target = b.resolveTargetQuery(.{
        .cpu_arch = cpu_arch,
        .os_tag = .windows,
        .abi = .gnu,
    });
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast });
    const mode = b.option([]const u8, "mode", "Build mode: dll or pgo-ir") orelse "dll";
    if (!std.mem.eql(u8, mode, "dll") and !std.mem.eql(u8, mode, "pgo-ir"))
        std.debug.panic("mode must be dll or pgo-ir, got '{s}'", .{mode});
    const output_name = b.option([]const u8, "output_name", "Installed output filename") orelse "QMKCore.dll";
    const build_options_path = b.option([]const u8, "build_options_path", "Build-options wrapper path") orelse "build_options_pgo.zig";
    const lto = b.option(bool, "lto", "Enable full link-time optimization") orelse true;
    const omit_frame_pointer = b.option(bool, "omit_frame_pointer", "Omit frame pointers") orelse true;
    const single_threaded = b.option(bool, "single_threaded", "Build as single-threaded") orelse true;
    const stack_check = b.option(bool, "stack_check", "Enable stack checks") orelse false;
    const unwind_tables = b.option(bool, "unwind_tables", "Emit unwind tables") orelse false;

    const root = b.createModule(.{
        .root_source_file = b.path("QMKCore.zig"),
        .target = target,
        .optimize = optimize,
        .strip = true,
        .single_threaded = single_threaded,
        .stack_check = stack_check,
        .unwind_tables = if (unwind_tables) .sync else .none,
        .omit_frame_pointer = omit_frame_pointer,
    });
    root.addImport("build_options", b.createModule(.{
        .root_source_file = b.path(build_options_path),
        .target = target,
        .optimize = optimize,
    }));
    root.linkSystemLibrary("ntdll", .{});
    root.linkSystemLibrary("user32", .{});
    root.linkSystemLibrary("kernel32", .{});

    const core = b.addLibrary(.{
        .name = "QMKCore",
        .root_module = root,
        .linkage = .dynamic,
    });
    core.lto = if (lto) .full else .none;

    const install = if (std.mem.eql(u8, mode, "pgo-ir"))
        b.addInstallFile(core.getEmittedLlvmIr(), output_name)
    else
        b.addInstallFile(core.getEmittedBin(), output_name);
    const step = b.step(mode, if (std.mem.eql(u8, mode, "pgo-ir")) "Emit QMKCore LLVM IR" else "Build QMKCore DLL");
    step.dependOn(&install.step);
    b.default_step = step;
}
