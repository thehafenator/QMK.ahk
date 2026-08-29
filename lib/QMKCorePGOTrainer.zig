const std = @import("std");

const win = struct {
    extern "kernel32" fn LoadLibraryA([*:0]const u8) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetProcAddress(?*anyopaque, [*:0]const u8) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn QueryPerformanceCounter(*i64) callconv(.winapi) i32;
    extern "kernel32" fn QueryPerformanceFrequency(*i64) callconv(.winapi) i32;
    extern "kernel32" fn Sleep(u32) callconv(.winapi) void;
    extern "kernel32" fn FreeLibrary(?*anyopaque) callconv(.winapi) i32;
};

const TRAINING_ROUNDS = 500;
const default_training_dll_path: [*:0]const u8 = "QMKTrainingData.dll";
const default_profile_path: [*:0]const u8 = "..\\TrainingData\\qmk_pgo_auto_trainer.profraw";

const FastPathCounters = extern struct {
    kdFastEmpty: u64,
    kdFastRolling: u64,
    kdTaplikeEmpty: u64,
    kdTaplikeRolling: u64,
    kdSoloUnresolved: u64,
    kdPostSolo: u64,
    kdSoloBlockBuffer: u64,
    kdSoloBlockMods: u64,
    kdSoloBlockPrimary: u64,
    kdSoloBlockSpecial: u64,
    kdSoloBlockRepeat: u64,
    kdSoloBlockIgnored: u64,
    kdSoloBlockPhysSys: u64,
    kdOverlapRoll: u64,
    kuSkipAll: u64,
    kuSoloTap: u64,
    kuHeadOldestTap: u64,
    kuHeadOldestTailTap: u64,
    kuPreQueueDrainTap: u64,
    kuHeadOldestHold: u64,
    pqFastTap: u64,
    pqNoUnrelResolve: u64,
    pqHeadOldestResolve: u64,
    pqModResolve: u64,
    pqWaitResolve: u64,
    pqWaitBreak: u64,
    pqSlowResolve: u64,
};

const TimingSnapshot = extern struct {
    keyDownMedian: f64,
    keyDownAvg: f64,
    keyDownP95: f64,
    keyDownCount: i32,
    keyUpMedian: f64,
    keyUpAvg: f64,
    keyUpP95: f64,
    keyUpCount: i32,
    directSendMedian: f64,
    directSendAvg: f64,
    directSendP95: f64,
    directSendCount: i32,
};

const Engine = struct {
    lib: ?*anyopaque,
    resetReplay: *const fn () callconv(.c) void,
    resetProfiling: *const fn () callconv(.c) void,
    setSuppressOutput: *const fn (i32) callconv(.c) void,
    setUserConfig: *const fn (i32, i32, i32, f64, f64, i32, i32, f64, f64, f64, i32, i32) callconv(.c) void,
    process: *const fn (i32, i32) callconv(.c) void,
    getCounters: *const fn (*FastPathCounters) callconv(.c) void,
    getTiming: *const fn (*TimingSnapshot) callconv(.c) void,
    writeReport: *const fn ([*]u8, usize) callconv(.c) usize,
    getPendingCallbacks: *const fn () callconv(.c) i32,
    clearPendingCallbacks: *const fn () callconv(.c) void,
    getPendingTimers: *const fn () callconv(.c) i32,
    clearPendingTimers: *const fn () callconv(.c) void,
    getModifierBitmask: *const fn () callconv(.c) i32,
    getActiveModifierCount: *const fn () callconv(.c) i32,
    getPendingSoloVK: *const fn () callconv(.c) i32,
    getRepeatVK: *const fn () callconv(.c) i32,
    isRepeatActive: *const fn () callconv(.c) i32,
    setupModifiers: *const fn ([*]const u8, u32, [*]const u16, u32) callconv(.c) i32,
    setupContextActions: *const fn ([*]const u8, u32, [*]const u16, u32) callconv(.c) i32,
    setupCombos: *const fn ([*]const u8, u32, [*]const u16, u32) callconv(.c) i32,
    writeLLVMProfileTo: ?*const fn ([*:0]const u8) callconv(.c) i32,
};

const Event = packed struct {
    vk: u8,
    down: bool,
};

const Trace = struct {
    name: []const u8,
    events: []const Event,
};

fn loadFn(comptime T: type, lib: ?*anyopaque, name: [*:0]const u8) T {
    return @ptrCast(win.GetProcAddress(lib, name) orelse {
        std.debug.print("missing export: {s}\n", .{name});
        std.process.exit(1);
    });
}

fn tryLoadFn(comptime T: type, lib: ?*anyopaque, name: [*:0]const u8) ?T {
    const ptr = win.GetProcAddress(lib, name) orelse return null;
    return @ptrCast(ptr);
}

fn loadEngine(path: [*:0]const u8) Engine {
    const lib = win.LoadLibraryA(path) orelse {
        std.debug.print("could not load DLL: {s}\n", .{path});
        std.process.exit(1);
    };
    return .{
        .lib = lib,
        .resetReplay = loadFn(*const fn () callconv(.c) void, lib, "QMK_ResetForReplayBench"),
        .resetProfiling = loadFn(*const fn () callconv(.c) void, lib, "QMK_ResetProfilingData"),
        .setSuppressOutput = loadFn(*const fn (i32) callconv(.c) void, lib, "QMK_SetReplaySuppressOutput"),
        .setUserConfig = loadFn(*const fn (i32, i32, i32, f64, f64, i32, i32, f64, f64, f64, i32, i32) callconv(.c) void, lib, "QMK_SetUserConfig"),
        .process = loadFn(*const fn (i32, i32) callconv(.c) void, lib, "QMK_ProcessKeyEvent"),
        .getCounters = loadFn(*const fn (*FastPathCounters) callconv(.c) void, lib, "QMK_GetFastPathCounters"),
        .getTiming = loadFn(*const fn (*TimingSnapshot) callconv(.c) void, lib, "QMK_GetTimingSnapshot"),
        .writeReport = loadFn(*const fn ([*]u8, usize) callconv(.c) usize, lib, "QMK_WriteProfilingReportAscii"),
        .getPendingCallbacks = loadFn(*const fn () callconv(.c) i32, lib, "QMK_GetPendingCallbackCount"),
        .clearPendingCallbacks = loadFn(*const fn () callconv(.c) void, lib, "QMK_ClearPendingCallbacks"),
        .getPendingTimers = loadFn(*const fn () callconv(.c) i32, lib, "QMK_GetPendingTimerCount"),
        .clearPendingTimers = loadFn(*const fn () callconv(.c) void, lib, "QMK_ClearPendingTimers"),
        .getModifierBitmask = loadFn(*const fn () callconv(.c) i32, lib, "QMK_GetModifierBitmask"),
        .getActiveModifierCount = loadFn(*const fn () callconv(.c) i32, lib, "QMK_GetActiveModifierCount"),
        .getPendingSoloVK = loadFn(*const fn () callconv(.c) i32, lib, "QMK_GetPendingSoloVK"),
        .getRepeatVK = loadFn(*const fn () callconv(.c) i32, lib, "QMK_GetRepeatVK"),
        .isRepeatActive = loadFn(*const fn () callconv(.c) i32, lib, "QMK_IsRepeatActive"),
        .setupModifiers = loadFn(*const fn ([*]const u8, u32, [*]const u16, u32) callconv(.c) i32, lib, "QMK_SetupModifiers"),
        .setupContextActions = loadFn(*const fn ([*]const u8, u32, [*]const u16, u32) callconv(.c) i32, lib, "QMK_SetupContextActions"),
        .setupCombos = loadFn(*const fn ([*]const u8, u32, [*]const u16, u32) callconv(.c) i32, lib, "QMK_SetupCombos"),
        .writeLLVMProfileTo = tryLoadFn(*const fn ([*:0]const u8) callconv(.c) i32, lib, "QMK_WriteLLVMProfileTo"),
    };
}

fn configure(e: Engine) void {
    e.resetReplay();
    e.setSuppressOutput(1);
    e.setUserConfig(1, 0, 1, 150.0, 1000.0, 1, 50, 150.0, 150.0, 300.0, 300, 30);
}

fn runTrace(e: Engine, trace: Trace, rounds: usize) void {
    var r: usize = 0;
    while (r < rounds) : (r += 1) {
        for (trace.events) |ev| e.process(ev.vk, if (ev.down) 1 else 0);
    }
}

fn runHoldAndModSmoke(e: Engine) void {
    const key_a = [_:0]u16{'a'};
    const key_h = [_:0]u16{'h'};
    const mod_ctrl = [_:0]u16{ 'C', 't', 'r', 'l' };

    // Homerow modifier overlap: exercises modifier activation/cleanup branches
    configure(e);
    e.setUserConfig(1, 0, 1, 50.0, 1000.0, 1, 50, 150.0, 50.0, 300.0, 300, 30);
    e.clearPendingCallbacks();
    e.clearPendingTimers();
    setupModifierEntry(e, &key_a, &mod_ctrl);
    var round: usize = 0;
    while (round < 200) : (round += 1) {
        e.process('A', 1);
        win.Sleep(1);
        e.process('S', 1);
        e.process('S', 0);
        e.process('A', 0);
        e.clearPendingCallbacks();
        e.clearPendingTimers();
    }
    std.debug.print("  Training: hold_mod_overlap       200 rounds\n", .{});

    // Hold: exercises hold threshold branches
    configure(e);
    e.setUserConfig(1, 0, 1, 50.0, 1000.0, 1, 50, 150.0, 50.0, 300.0, 300, 30);
    e.clearPendingCallbacks();
    e.clearPendingTimers();
    setupContextActionEntry(e, &key_h, 7777, 0);
    round = 0;
    while (round < 200) : (round += 1) {
        e.process('H', 1);
        win.Sleep(1);
        e.process('H', 0);
        e.clearPendingCallbacks();
        e.clearPendingTimers();
    }
    std.debug.print("  Training: hold_smoke             200 rounds\n", .{});

    // Double-tap repeat: exercises repeat activation/cleanup branches
    configure(e);
    e.setUserConfig(1, 0, 1, 50.0, 1000.0, 1, 50, 150.0, 50.0, 300.0, 300, 30);
    e.clearPendingCallbacks();
    e.clearPendingTimers();
    setupModifierEntry(e, &key_a, &mod_ctrl);
    setupContextActionEntry(e, &key_a, 8888, 1);
    round = 0;
    while (round < 200) : (round += 1) {
        e.process('A', 1);
        e.process('A', 0);
        e.process('A', 1);
        e.process('A', 0);
        e.clearPendingCallbacks();
        e.clearPendingTimers();
    }
    std.debug.print("  Training: doubletap_repeat       200 rounds\n", .{});
}

fn comboStroke(e: Engine, a: u8, b: u8) void {
    e.process(a, 1);
    e.process(b, 1);
    e.process(b, 0);
    e.process(a, 0);
}

fn writeU16LE(buf: []u8, off: usize, value: u16) void {
    buf[off] = @intCast(value & 0xff);
    buf[off + 1] = @intCast(value >> 8);
}

fn writeU32LE(buf: []u8, off: usize, value: u32) void {
    buf[off] = @intCast(value & 0xff);
    buf[off + 1] = @intCast((value >> 8) & 0xff);
    buf[off + 2] = @intCast((value >> 16) & 0xff);
    buf[off + 3] = @intCast((value >> 24) & 0xff);
}

fn writeI32LE(buf: []u8, off: usize, value: i32) void {
    writeU32LE(buf, off, @bitCast(value));
}

fn appendWideZ(pool: *[128]u16, cursor: *u32, text: [*:0]const u16) struct { off: u32, len: u16 } {
    const start = cursor.*;
    var len: u16 = 0;
    while (text[len] != 0 and cursor.* < pool.len) : (len += 1) {
        pool[@intCast(cursor.*)] = text[len];
        cursor.* += 1;
    }
    return .{ .off = start, .len = len };
}

fn writeTextField(record: []u8, field_off: usize, pool: *[128]u16, cursor: *u32, text: [*:0]const u16) void {
    const span = appendWideZ(pool, cursor, text);
    writeU32LE(record, field_off, span.off);
    writeU16LE(record, field_off + 4, span.len);
}

fn setupModifierEntry(e: Engine, key: [*:0]const u16, modifier: [*:0]const u16) void {
    // QMK_SetupModifiers canonical 56-byte record:
    // key pair @0, arity @6, cell kinds @8..10, ints @12..20,
    // text pairs for cells 2..4 @24,32,40.
    // User row represented here: [key, modifier].
    var record = [_]u8{0} ** 56;
    var text = [_]u16{0} ** 128;
    var cursor: u32 = 0;

    writeTextField(record[0..], 0, &text, &cursor, key);
    record[6] = 2; // arity
    record[8] = 1; // cell 2 = text
    writeTextField(record[0..], 24, &text, &cursor, modifier);

    _ = e.setupModifiers(&record, 1, &text, cursor);
}

fn setupContextActionEntry(e: Engine, key: [*:0]const u16, callback_id: i32, action_kind: u8) void {
    // QMK_SetupContextActions canonical 56-byte record:
    // key pair @0, arity @6, actionKind @7, cell kinds @8..10,
    // ints @12..20, text pairs @24,32,40.
    // User row represented here: [key, callback].
    var record = [_]u8{0} ** 56;
    var text = [_]u16{0} ** 128;
    var cursor: u32 = 0;

    writeTextField(record[0..], 0, &text, &cursor, key);
    record[6] = 2; // arity
    record[7] = action_kind;
    record[8] = 2; // cell 2 = callback id
    writeI32LE(record[0..], 12, callback_id);

    _ = e.setupContextActions(&record, 1, &text, cursor);
}

fn setupComboEntry(e: Engine, primary: [*:0]const u16, secondary: [*:0]const u16, callback_id: i32, target: [*:0]const u16, mode: [*:0]const u16, mods: [*:0]const u16) void {
    // QMK_SetupCombos canonical 96-byte record:
    // primary @0, secondary @8, arity @16, cell kinds 3..7 @17..21,
    // ints @24..40, text pairs @48..80.
    //
    // The trainer uses the full contextual positional shape:
    // [primary, secondary, context, action, mode, mods]
    // with global context represented by an empty context string.
    var record = [_]u8{0} ** 96;
    var text = [_]u16{0} ** 128;
    var cursor: u32 = 0;
    const global = [_:0]u16{};

    writeTextField(record[0..], 0, &text, &cursor, primary);
    writeTextField(record[0..], 8, &text, &cursor, secondary);

    record[16] = 6; // arity
    record[17] = 1; // cell 3 = context text
    record[18] = 2; // cell 4 = callback id
    record[19] = 1; // cell 5 = mode text
    record[20] = 1; // cell 6 = modifier text

    writeI32LE(record[0..], 28, callback_id); // cell 4 integer slot
    writeTextField(record[0..], 48, &text, &cursor, &global);
    // Callback text field (@56) intentionally empty.
    writeTextField(record[0..], 64, &text, &cursor, mode);
    writeTextField(record[0..], 72, &text, &cursor, mods);

    // Keep target serialized in the final optional text cell for training
    // compatibility if a future mode uses it; current callback-mode smoke
    // traces do not consume it.
    _ = target;

    _ = e.setupCombos(&record, 1, &text, cursor);
}

fn runComboSmoke(e: Engine) void {
    const key_a = [_:0]u16{'a'};
    const key_s = [_:0]u16{'s'};
    const key_d = [_:0]u16{'d'};
    const key_f = [_:0]u16{'f'};
    const key_j = [_:0]u16{'j'};
    const key_k = [_:0]u16{'k'};
    const key_l = [_:0]u16{'l'};
    const key_p = [_:0]u16{'p'};
    const no_mod = [_:0]u16{};

    // External combo
    configure(e);
    e.clearPendingCallbacks();
    e.clearPendingTimers();
    setupComboEntry(e, &key_a, &key_s, 7101, &no_mod, &no_mod, &no_mod);
    var round: usize = 0;
    while (round < 200) : (round += 1) {
        comboStroke(e, 'A', 'S');
        e.clearPendingCallbacks();
        e.clearPendingTimers();
    }
    std.debug.print("  Training: combo_external         200 rounds\n", .{});

    // Instant combo
    configure(e);
    e.clearPendingCallbacks();
    e.clearPendingTimers();
    const mode_instant = [_:0]u16{ 'i', 'n', 's', 't', 'a', 'n', 't' };
    setupComboEntry(e, &key_d, &key_f, 7102, &no_mod, &mode_instant, &no_mod);
    round = 0;
    while (round < 200) : (round += 1) {
        comboStroke(e, 'D', 'F');
        e.clearPendingCallbacks();
        e.clearPendingTimers();
    }
    std.debug.print("  Training: combo_instant          200 rounds\n", .{});

    // Internal combo
    configure(e);
    e.clearPendingCallbacks();
    e.clearPendingTimers();
    const mode_internal = [_:0]u16{ 'i', 'n', 't', 'e', 'r', 'n', 'a', 'l' };
    setupComboEntry(e, &key_j, &key_k, -1, &key_p, &mode_internal, &no_mod);
    round = 0;
    while (round < 200) : (round += 1) {
        comboStroke(e, 'J', 'K');
        e.clearPendingCallbacks();
        e.clearPendingTimers();
    }
    std.debug.print("  Training: combo_internal         200 rounds\n", .{});

    // Internal instant combo
    configure(e);
    e.clearPendingCallbacks();
    e.clearPendingTimers();
    const mode_internal_instant = [_:0]u16{ 'i', 'n', 't', 'e', 'r', 'n', 'a', 'l', 'i', 'n', 's', 't', 'a', 'n', 't' };
    setupComboEntry(e, &key_l, &key_p, -1, &key_a, &mode_internal_instant, &no_mod);
    round = 0;
    while (round < 200) : (round += 1) {
        comboStroke(e, 'L', 'P');
        e.clearPendingCallbacks();
        e.clearPendingTimers();
    }
    std.debug.print("  Training: combo_internal_inst    200 rounds\n", .{});
}

fn trainTrace(e: Engine, trace: Trace) void {
    configure(e);
    const total_events = trace.events.len * TRAINING_ROUNDS;
    std.debug.print("  Training: {s:<22} events={d} x {d} rounds = {d} total key events\n", .{ trace.name, trace.events.len, TRAINING_ROUNDS, total_events });
    runTrace(e, trace, TRAINING_ROUNDS);
    e.clearPendingCallbacks();
    e.clearPendingTimers();
}

fn addSolo(out: []Event, idx: *usize, vk: u8) void {
    out[idx.*] = .{ .vk = vk, .down = true };
    idx.* += 1;
    out[idx.*] = .{ .vk = vk, .down = false };
    idx.* += 1;
}

fn addRoll(out: []Event, idx: *usize, a: u8, b: u8) void {
    out[idx.*] = .{ .vk = a, .down = true };
    idx.* += 1;
    out[idx.*] = .{ .vk = b, .down = true };
    idx.* += 1;
    out[idx.*] = .{ .vk = a, .down = false };
    idx.* += 1;
    out[idx.*] = .{ .vk = b, .down = false };
    idx.* += 1;
}

fn makeTypingTrace(buf: []Event) Trace {
    const text = "theresomethingaboutthisreplaythatneedstocoverregularfasttypingwithlightoverlapandwithoutshortcutintentionsthegoalistomatchaboutthirtysecondsofroughlyonehundredwpmtyping";
    var idx: usize = 0;
    var i: usize = 0;
    while (i < text.len and idx + 4 < buf.len) {
        const a: u8 = std.ascii.toUpper(text[i]);
        if (i + 1 < text.len and (i % 5 == 1 or i % 7 == 3)) {
            const b: u8 = std.ascii.toUpper(text[i + 1]);
            addRoll(buf, &idx, a, b);
            i += 2;
        } else {
            addSolo(buf, &idx, a);
            i += 1;
        }
    }
    return .{ .name = "typing_mixed_100wpm", .events = buf[0..idx] };
}

fn makeSoloTypingTrace(buf: []Event) Trace {
    const text = "thequickbrownfoxjumpsoverthelazydogthenkeepswritingplainlettersonlywithoutoverlap";
    var idx: usize = 0;
    var cycle: usize = 0;
    while (cycle < 4 and idx + text.len * 2 < buf.len) : (cycle += 1) {
        for (text) |ch| addSolo(buf, &idx, std.ascii.toUpper(ch));
    }
    return .{ .name = "typing_solo_100wpm", .events = buf[0..idx] };
}

fn makeDenseRollTrace(buf: []Event) Trace {
    const text = "arstneioklfdsaqweruiopjklasdfarstneioklfdsaqweruiopjklasdf";
    var idx: usize = 0;
    var cycle: usize = 0;
    while (cycle < 5 and idx + text.len * 4 < buf.len) : (cycle += 1) {
        var i: usize = 0;
        while (i + 1 < text.len and idx + 4 < buf.len) : (i += 2) {
            addRoll(buf, &idx, std.ascii.toUpper(text[i]), std.ascii.toUpper(text[i + 1]));
        }
    }
    return .{ .name = "dense_roll_100wpm", .events = buf[0..idx] };
}

fn makeManualLikeTrace(buf: []Event) Trace {
    const text = "arstneioasdfjklqweruioparstneioasdfjklqweruioparstneioasdfjklqweruiop";
    var idx: usize = 0;
    var i: usize = 0;
    while (i + 3 < text.len and idx + 8 < buf.len) {
        const a: u8 = std.ascii.toUpper(text[i]);
        const b: u8 = std.ascii.toUpper(text[i + 1]);
        const c: u8 = std.ascii.toUpper(text[i + 2]);
        const d: u8 = std.ascii.toUpper(text[i + 3]);
        // Heavy rolling cluster: two post-solo keydowns before the head releases.
        buf[idx] = .{ .vk = a, .down = true };
        idx += 1;
        buf[idx] = .{ .vk = b, .down = true };
        idx += 1;
        buf[idx] = .{ .vk = c, .down = true };
        idx += 1;
        buf[idx] = .{ .vk = a, .down = false };
        idx += 1;
        buf[idx] = .{ .vk = d, .down = true };
        idx += 1;
        buf[idx] = .{ .vk = b, .down = false };
        idx += 1;
        buf[idx] = .{ .vk = c, .down = false };
        idx += 1;
        buf[idx] = .{ .vk = d, .down = false };
        idx += 1;
        i += 4;
    }
    return .{ .name = "manual_like_overlap", .events = buf[0..idx] };
}

fn addCluster4(out: []Event, idx: *usize, a: u8, b: u8, c: u8, d: u8) void {
    out[idx.*] = .{ .vk = a, .down = true };
    idx.* += 1;
    out[idx.*] = .{ .vk = b, .down = true };
    idx.* += 1;
    out[idx.*] = .{ .vk = c, .down = true };
    idx.* += 1;
    out[idx.*] = .{ .vk = a, .down = false };
    idx.* += 1;
    out[idx.*] = .{ .vk = d, .down = true };
    idx.* += 1;
    out[idx.*] = .{ .vk = b, .down = false };
    idx.* += 1;
    out[idx.*] = .{ .vk = c, .down = false };
    idx.* += 1;
    out[idx.*] = .{ .vk = d, .down = false };
    idx.* += 1;
}

fn makeCalibratedTrace(buf: []Event) Trace {
    var idx: usize = 0;
    var cycle: usize = 0;
    while (cycle < 10 and idx + 54 < buf.len) : (cycle += 1) {
        // Roughly models a fast 100 WPM burst: mostly normal typing, frequent
        // two-key rolls, occasional three/four-key overlap, dense home-row keys.
        addSolo(buf, &idx, 'T');
        addSolo(buf, &idx, 'H');
        addRoll(buf, &idx, 'A', 'S');
        addRoll(buf, &idx, 'J', 'K');
        addSolo(buf, &idx, 'E');
        addCluster4(buf, &idx, 'A', 'S', 'D', 'F');
        addRoll(buf, &idx, 'F', 'J');
        addSolo(buf, &idx, 'O');
        addRoll(buf, &idx, 'L', 'K');
        addCluster4(buf, &idx, 'J', 'K', 'L', 'S');
        addSolo(buf, &idx, 'N');
        addRoll(buf, &idx, 'D', 'F');
    }
    return .{ .name = "calibrated_100wpm", .events = buf[0..idx] };
}

fn makeManualProfileTrace(buf: []Event) Trace {
    var idx: usize = 0;
    var cycle: usize = 0;
    while (cycle < 10 and idx + 64 < buf.len) : (cycle += 1) {
        addSolo(buf, &idx, 'T');
        addSolo(buf, &idx, 'H');
        addSolo(buf, &idx, 'E');
        addRoll(buf, &idx, 'T', 'H');
        addRoll(buf, &idx, 'E', 'R');
        addRoll(buf, &idx, 'O', 'U');
        addRoll(buf, &idx, 'A', 'S');
        addRoll(buf, &idx, 'J', 'K');
        addCluster4(buf, &idx, 'T', 'H', 'E', 'R');
        addCluster4(buf, &idx, 'A', 'S', 'D', 'F');
        addSolo(buf, &idx, 'N');
        addRoll(buf, &idx, 'D', 'F');
        addRoll(buf, &idx, 'L', 'K');
    }
    return .{ .name = "manual_profile_mix", .events = buf[0..idx] };
}

fn makeShortcutTrace(buf: []Event) Trace {
    var idx: usize = 0;
    addRoll(buf, &idx, 'A', 'S');
    addRoll(buf, &idx, 'F', 'P');
    addRoll(buf, &idx, 'J', 'K');
    addRoll(buf, &idx, 'D', 'F');
    addSolo(buf, &idx, 'A');
    addSolo(buf, &idx, 'S');
    buf[idx] = .{ .vk = 'A', .down = true };
    idx += 1;
    buf[idx] = .{ .vk = 'S', .down = true };
    idx += 1;
    buf[idx] = .{ .vk = 'L', .down = true };
    idx += 1;
    buf[idx] = .{ .vk = 'L', .down = false };
    idx += 1;
    buf[idx] = .{ .vk = 'S', .down = false };
    idx += 1;
    buf[idx] = .{ .vk = 'A', .down = false };
    idx += 1;
    buf[idx] = .{ .vk = 'A', .down = true };
    idx += 1;
    buf[idx] = .{ .vk = 'S', .down = true };
    idx += 1;
    buf[idx] = .{ .vk = 'D', .down = true };
    idx += 1;
    buf[idx] = .{ .vk = 'F', .down = true };
    idx += 1;
    buf[idx] = .{ .vk = 'F', .down = false };
    idx += 1;
    buf[idx] = .{ .vk = 'D', .down = false };
    idx += 1;
    buf[idx] = .{ .vk = 'S', .down = false };
    idx += 1;
    buf[idx] = .{ .vk = 'A', .down = false };
    idx += 1;
    return .{ .name = "shortcut_smoke", .events = buf[0..idx] };
}

pub fn main(init: std.process.Init.Minimal) void {
    var debug_allocator: std.heap.DebugAllocator(.{}) = .init;
    defer _ = debug_allocator.deinit();
    var args = std.process.Args.Iterator.initAllocator(init.args, debug_allocator.allocator()) catch {
        std.debug.print("could not initialize process argument iterator\n", .{});
        std.process.exit(1);
    };
    defer args.deinit();

    _ = args.next();
    const dll_path_arg = args.next();
    const profile_path_arg = args.next();
    const dll_path: [*:0]const u8 = if (dll_path_arg) |path| path.ptr else default_training_dll_path;
    const profile_path: [*:0]const u8 = if (profile_path_arg) |path| path.ptr else default_profile_path;

    const engine = loadEngine(dll_path);

    var typing_buf: [640]Event = undefined;
    var solo_buf: [720]Event = undefined;
    var dense_roll_buf: [720]Event = undefined;
    var manual_buf: [640]Event = undefined;
    var calibrated_buf: [640]Event = undefined;
    var profile_buf: [720]Event = undefined;
    var shortcut_buf: [128]Event = undefined;
    const typing = makeTypingTrace(&typing_buf);
    const solo_typing = makeSoloTypingTrace(&solo_buf);
    const dense_roll = makeDenseRollTrace(&dense_roll_buf);
    const manual_like = makeManualLikeTrace(&manual_buf);
    const calibrated = makeCalibratedTrace(&calibrated_buf);
    const profile = makeManualProfileTrace(&profile_buf);
    const shortcuts = makeShortcutTrace(&shortcut_buf);

    std.debug.print("QMKCore PGO Trainer — generating branch profile data\n", .{});
    std.debug.print("Output suppressed, {d} rounds per trace\n\n", .{TRAINING_ROUNDS});

    // ~90% of training is pure typing traces (solo, mixed, rolling, overlap)
    trainTrace(engine, solo_typing);
    trainTrace(engine, typing);
    trainTrace(engine, dense_roll);
    trainTrace(engine, manual_like);
    trainTrace(engine, calibrated);
    trainTrace(engine, profile);

    // ~10% shortcut/combo/hold/modifier branch coverage
    trainTrace(engine, shortcuts);
    runHoldAndModSmoke(engine);
    runComboSmoke(engine);

    // The big one: 2 million key events of pure solo typing (a-z + space)
    // This is the most representative of real usage — just fast keydown/keyup pairs
    const SOLO_BURST_EVENTS = 2_000_000;
    const alpha_space = "ABCDEFGHIJKLMNOPQRSTUVWXYZ ";
    configure(engine);
    std.debug.print("\n  Training: solo_burst_2M          {d} key events (a-z + space, down/up)...\n", .{SOLO_BURST_EVENTS});
    var total_events: usize = 0;
    while (total_events < SOLO_BURST_EVENTS) {
        for (alpha_space) |ch| {
            engine.process(@as(i32, ch), 1);
            engine.process(@as(i32, ch), 0);
            total_events += 2;
            if (total_events >= SOLO_BURST_EVENTS) break;
        }
    }
    std.debug.print("  Training: solo_burst_2M          done ({d} actual events)\n", .{total_events});

    // Save profile data exactly like AHK's Ctrl+Alt+F11 does.
    std.debug.print("\nPGO training complete. Saving profile data...\n", .{});
    if (engine.writeLLVMProfileTo) |writeProfile| {
        const result = writeProfile(profile_path);
        if (result == 0) {
            std.debug.print("SUCCESS: profile data saved to {s}\n", .{profile_path});
        } else {
            std.debug.print("ERROR: QMK_WriteLLVMProfileTo returned {d}\n", .{result});
        }
    } else {
        std.debug.print("QMK_WriteLLVMProfileTo not available, relying on process exit flush...\n", .{});
    }
    std.process.exit(0);
}
