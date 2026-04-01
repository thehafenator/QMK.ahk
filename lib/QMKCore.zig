//! QMK Core Interception — Zig implementation
//! Safe for MemoryModule in-memory loading: no CRT, no global constructors,
//! no exceptions, no TLS, no hidden startup code.
//!
//! Build:
//! zig build-lib -dynamic -target x86_64-windows-gnu -O ReleaseFast \
//! -fno-libc -femit-bin=QMKCore.dll QMKCore.zig
//!
//! All deps are kernel32/user32 (always present) plus interception, which is
//! injected at runtime via QMK_SetInterceptionCallbacks — no import-table
//! dependency on interception.dll.
const std = @import("std");
const windows = std.os.windows;
// ============================================================================
// Section 1 — Windows API declarations
// ============================================================================
const BOOL = windows.BOOL;
const DWORD = windows.DWORD;
const HANDLE = windows.HANDLE;
const TRUE: BOOL = 1;
const INPUT_KEYBOARD: u32 = 1;
const KEYEVENTF_KEYUP: u32 = 0x0002;
const MAPVK_VK_TO_VSC: u32 = 0;
const AHK_SENDLEVEL_2: usize = 0xFFC3D44B;
const MB_OK: u32 = 0;
const MB_ICONINFORMATION: u32 = 0x40;
const MB_TOPMOST: u32 = 0x00040000;
const MB_SETFOREGROUND: u32 = 0x00010000;
// x86_64 INPUT struct is 40 bytes; offsets documented inline on InputSlot below.
const INPUT_STRUCT_SIZE: i32 = 40;
// Generic VK codes used when sending modifier keys
const VK_CONTROL: u16 = 0x11;
const VK_MENU: u16 = 0x12;
const VK_SHIFT: u16 = 0x10;
const VK_LWIN: u16 = 0x5B;
const VK_LCONTROL: u16 = 0xA2;
const VK_LSHIFT: u16 = 0xA0;
const VK_LMENU: u16 = 0xA4;
// ============================================================================
// Section 10B — Compile-time default key table (replaces AHK-side vkMap loop)
// ============================================================================

// Each entry: { vk: i32, name: []const u8 }
// ASCII names only — registerVK's copyKeyName widens them to u16 at runtime.
const KeyEntry = struct { vk: i32, name: []const u8 };
const DEFAULT_KEYS = [_]KeyEntry{
    // Letters
    .{ .vk = 65, .name = "a" },        .{ .vk = 66, .name = "b" },
    .{ .vk = 67, .name = "c" },        .{ .vk = 68, .name = "d" },
    .{ .vk = 69, .name = "e" },        .{ .vk = 70, .name = "f" },
    .{ .vk = 71, .name = "g" },        .{ .vk = 72, .name = "h" },
    .{ .vk = 73, .name = "i" },        .{ .vk = 74, .name = "j" },
    .{ .vk = 75, .name = "k" },        .{ .vk = 76, .name = "l" },
    .{ .vk = 77, .name = "m" },        .{ .vk = 78, .name = "n" },
    .{ .vk = 79, .name = "o" },        .{ .vk = 80, .name = "p" },
    .{ .vk = 81, .name = "q" },        .{ .vk = 82, .name = "r" },
    .{ .vk = 83, .name = "s" },        .{ .vk = 84, .name = "t" },
    .{ .vk = 85, .name = "u" },        .{ .vk = 86, .name = "v" },
    .{ .vk = 87, .name = "w" },        .{ .vk = 88, .name = "x" },
    .{ .vk = 89, .name = "y" },        .{ .vk = 90, .name = "z" },
    // Digits
    .{ .vk = 48, .name = "0" },        .{ .vk = 49, .name = "1" },
    .{ .vk = 50, .name = "2" },        .{ .vk = 51, .name = "3" },
    .{ .vk = 52, .name = "4" },        .{ .vk = 53, .name = "5" },
    .{ .vk = 54, .name = "6" },        .{ .vk = 55, .name = "7" },
    .{ .vk = 56, .name = "8" },        .{ .vk = 57, .name = "9" },
    // Punctuation / OEM
    .{ .vk = 219, .name = "[" },       .{ .vk = 221, .name = "]" },
    .{ .vk = 186, .name = ";" },       .{ .vk = 222, .name = "'" },
    .{ .vk = 188, .name = "," },       .{ .vk = 190, .name = "." },
    .{ .vk = 191, .name = "/" },       .{ .vk = 220, .name = "\\" },
    .{ .vk = 192, .name = "`" },       .{ .vk = 189, .name = "-" },
    .{ .vk = 187, .name = "=" },
    // Control keys
          .{ .vk = 32, .name = "Space" },
    .{ .vk = 9, .name = "Tab" },       .{ .vk = 13, .name = "Enter" },
    .{ .vk = 8, .name = "Backspace" }, .{ .vk = 46, .name = "Delete" },
    .{ .vk = 45, .name = "Insert" },   .{ .vk = 36, .name = "Home" },
    .{ .vk = 35, .name = "End" },      .{ .vk = 33, .name = "PgUp" },
    .{ .vk = 34, .name = "PgDn" },     .{ .vk = 38, .name = "Up" },
    .{ .vk = 40, .name = "Down" },     .{ .vk = 37, .name = "Left" },
    .{ .vk = 39, .name = "Right" },    .{ .vk = 27, .name = "Esc" },
    .{ .vk = 20, .name = "CapsLock" }, .{ .vk = 145, .name = "ScrollLock" },
    .{ .vk = 144, .name = "NumLock" },
    // Modifier VKs (used by QMK_SetupModifier etc.)
    .{ .vk = 162, .name = "LCtrl" },
    .{ .vk = 163, .name = "RCtrl" },   .{ .vk = 160, .name = "LShift" },
    .{ .vk = 161, .name = "RShift" },  .{ .vk = 164, .name = "LAlt" },
    .{ .vk = 165, .name = "RAlt" },    .{ .vk = 91, .name = "LWin" },
    .{ .vk = 92, .name = "RWin" },
    // Function keys
        .{ .vk = 112, .name = "F1" },
    .{ .vk = 113, .name = "F2" },      .{ .vk = 114, .name = "F3" },
    .{ .vk = 115, .name = "F4" },      .{ .vk = 116, .name = "F5" },
    .{ .vk = 117, .name = "F6" },      .{ .vk = 118, .name = "F7" },
    .{ .vk = 119, .name = "F8" },      .{ .vk = 120, .name = "F9" },
    .{ .vk = 121, .name = "F10" },     .{ .vk = 122, .name = "F11" },
    .{ .vk = 123, .name = "F12" },
};

// Widen a comptime ASCII slice into a stack u16 buffer and call registerVK.
// This is the only place we pay the widening cost — once, at init, not on every keystroke.
fn registerDefaultKeys() void {
    inline for (DEFAULT_KEYS) |entry| {
        var wide: [KN_LEN:0]u16 = [_:0]u16{0} ** KN_LEN;
        inline for (entry.name, 0..) |c, i| {
            wide[i] = c; // ASCII ≤ 127 is identical in UTF-16
        }
        registerVK(entry.vk, &wide);
    }
}
extern "kernel32" fn GetProcessHeap() callconv(.winapi) HANDLE;
extern "kernel32" fn HeapAlloc(h: HANDLE, flags: DWORD, bytes: usize) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn HeapFree(h: HANDLE, flags: DWORD, mem: ?*anyopaque) callconv(.winapi) BOOL;
extern "kernel32" fn HeapReAlloc(h: HANDLE, flags: DWORD, mem: *anyopaque, bytes: usize) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn QueryPerformanceCounter(lp: *i64) callconv(.winapi) BOOL;
extern "kernel32" fn QueryPerformanceFrequency(lp: *i64) callconv(.winapi) BOOL;
extern "kernel32" fn MapVirtualKeyW(code: u32, mapType: u32) callconv(.winapi) u32;
extern "kernel32" fn Sleep(ms: u32) callconv(.winapi) void;
extern "kernel32" fn CreateThread(attr: ?*anyopaque, stack: usize, fn_: *const fn (?*anyopaque) callconv(.winapi) u32, param: ?*anyopaque, flags: u32, id: ?*u32) callconv(.winapi) ?HANDLE;
extern "kernel32" fn CloseHandle(h: HANDLE) callconv(.winapi) BOOL;
extern "kernel32" fn WaitForSingleObject(h: HANDLE, dwMilliseconds: DWORD) callconv(.winapi) DWORD;
extern "kernel32" fn CreateEventW(lpEventAttributes: ?*anyopaque, bManualReset: BOOL, bInitialState: BOOL, lpName: ?[*:0]const u16) callconv(.winapi) ?HANDLE;
extern "kernel32" fn SetEvent(hEvent: HANDLE) callconv(.winapi) BOOL;
extern "user32" fn SendInput(n: u32, inputs: [*]const u8, cbSize: i32) callconv(.winapi) u32;
extern "user32" fn MessageBoxW(hwnd: ?*anyopaque, text: [*:0]const u16, cap: [*:0]const u16, utype: u32) callconv(.winapi) i32;
extern "ntdll" fn NtQueryTimerResolution(
    MinimumResolution: *u32,
    MaximumResolution: *u32,
    CurrentResolution: *u32,
) callconv(.winapi) windows.NTSTATUS;
extern "kernel32" fn VirtualLock(lpAddress: ?*anyopaque, dwSize: usize) callconv(.winapi) BOOL;
extern "kernel32" fn GetCurrentProcess() callconv(.winapi) HANDLE;
extern "kernel32" fn SetProcessWorkingSetSize(hProcess: HANDLE, dwMinimumWorkingSetSize: usize, dwMaximumWorkingSetSize: usize) callconv(.winapi) BOOL;
// ============================================================================
// Section 2 — Interception API (injected at runtime, no static import)
// ============================================================================
const InterceptionContext = ?*anyopaque;
const InterceptionDevice = i32;
const InterceptionKeyStroke = extern struct {
    code: u16,
    state: u16,
    information: u32,
};
const IKEY_DOWN: u16 = 0x00;
const IKEY_UP: u16 = 0x01;
const IKEY_E0: u16 = 0x02;
var fp_create_context: ?*const fn () callconv(.c) InterceptionContext = null;
var fp_destroy_context: ?*const fn (InterceptionContext) callconv(.c) void = null;
var fp_is_keyboard: ?*const fn (InterceptionDevice) callconv(.c) i32 = null;
var fp_send: ?*const fn (InterceptionContext, InterceptionDevice, [*]const InterceptionKeyStroke, u32) callconv(.c) i32 = null;
inline fn interception_create_context() InterceptionContext {
    return if (fp_create_context) |f| f() else null;
}
inline fn interception_destroy_context(ctx: InterceptionContext) void {
    if (fp_destroy_context) |f| f(ctx);
}
inline fn interception_is_keyboard(dev: InterceptionDevice) i32 {
    return if (fp_is_keyboard) |f| f(dev) else 0;
}
inline fn interception_send(ctx: InterceptionContext, dev: InterceptionDevice, stroke: [*]const InterceptionKeyStroke, n: u32) i32 {
    return if (fp_send) |f| f(ctx, dev, stroke, n) else 0;
}
// ============================================================================
// Section 3 — Heap allocator (Windows HeapAlloc/Free/ReAlloc, no CRT)
// ============================================================================
fn winHeapAlloc(_: *anyopaque, len: usize, _: std.mem.Alignment, _: usize) ?[*]u8 {
    const ptr = HeapAlloc(GetProcessHeap(), 0, len) orelse return null;
    return @ptrCast(ptr);
}
fn winHeapResize(_: *anyopaque, buf: []u8, _: std.mem.Alignment, new_len: usize, _: usize) bool {
    return new_len <= buf.len; // shrink-in-place only; growth falls back to alloc+copy
}
fn winHeapRemap(_: *anyopaque, buf: []u8, _: std.mem.Alignment, new_len: usize, _: usize) ?[*]u8 {
    const p = HeapReAlloc(GetProcessHeap(), 0, buf.ptr, new_len) orelse return null;
    return @ptrCast(p);
}
fn winHeapFree(_: *anyopaque, buf: []u8, _: std.mem.Alignment, _: usize) void {
    _ = HeapFree(GetProcessHeap(), 0, buf.ptr);
}
const g_winHeapVTable = std.mem.Allocator.VTable{
    .alloc = winHeapAlloc,
    .resize = winHeapResize,
    .remap = winHeapRemap,
    .free = winHeapFree,
};
var gAlloc = std.mem.Allocator{ .ptr = undefined, .vtable = &g_winHeapVTable };
// ============================================================================
// Section 4 — Profiling
// ============================================================================
const PROF_MAX_SAMPLES: usize = 1000;
const ProfRing = struct {
    buf: [PROF_MAX_SAMPLES]f64 = [_]f64{0} ** PROF_MAX_SAMPLES,
    len: usize = 0,
    head: usize = 0,
    fn append(self: *ProfRing, v: f64) void {
        self.buf[self.head] = v;
        self.head = (self.head + 1) % PROF_MAX_SAMPLES;
        if (self.len < PROF_MAX_SAMPLES) self.len += 1;
    }
    fn items(self: *ProfRing) []f64 {
        return self.buf[0..self.len];
    }
    fn clear(self: *ProfRing) void {
        self.len = 0;
        self.head = 0;
    }
};

const TimingStats = struct {
    min: f64 = 0,
    median: f64 = 0,
    avg: f64 = 0,
    p95: f64 = 0,
    max: f64 = 0,
    count: i32 = 0,
    fn calculate(self: *TimingStats, ring: *ProfRing) void {
        const src = ring.items();
        if (src.len == 0) {
            self.* = .{};
            return;
        }
        var sorted: [PROF_MAX_SAMPLES]f64 = undefined;
        @memcpy(sorted[0..src.len], src);
        std.mem.sort(f64, sorted[0..src.len], {}, std.sort.asc(f64));
        self.count = @intCast(src.len);
        self.min = sorted[0];
        self.max = sorted[src.len - 1];
        var sum: f64 = 0;
        for (sorted[0..src.len]) |v| sum += v;
        self.avg = sum / @as(f64, @floatFromInt(self.count));
        self.median = sorted[@as(usize, @intCast(@divTrunc(self.count, 2)))];
        self.p95 = sorted[@as(usize, @intFromFloat(@as(f64, @floatFromInt(self.count)) * 0.95))];
    }
};

const ProfilingData = struct {
    keyDownProcessing: ProfRing = .{},
    keyUpProcessing: ProfRing = .{},
    directSendProcessing: ProfRing = .{},
    kernelInjection: ProfRing = .{},
    sendInputProcessing: ProfRing = .{},
    keyDownStats: TimingStats = .{},
    keyUpStats: TimingStats = .{},
    directSendStats: TimingStats = .{},
    kernelStats: TimingStats = .{},
    sendInputStats: TimingStats = .{},
    fn calculateAllStats(self: *ProfilingData) void {
        self.keyDownStats.calculate(&self.keyDownProcessing);
        self.keyUpStats.calculate(&self.keyUpProcessing);
        self.directSendStats.calculate(&self.directSendProcessing);
        self.kernelStats.calculate(&self.kernelInjection);
        self.sendInputStats.calculate(&self.sendInputProcessing);
    }
};

var g_profiling: ProfilingData = .{};
// Very cheap when profiling is off
inline fn profStart() i64 {
    if (!g_profilingEnabled) return 0;
    var c: i64 = 0;
    _ = QueryPerformanceCounter(&c);
    return c;
}
inline fn profRecord(ring: *ProfRing, start: i64) void {
    if (!g_profilingEnabled or start == 0) return;
    var end: i64 = 0;
    _ = QueryPerformanceCounter(&end);
    const delta = @as(f64, @floatFromInt(end - start)) * g_qpcToUs;
    ring.append(delta);
}
// ============================================================================
// Section 5 — Constants, limits, string helpers
// ============================================================================
const VK_COUNT = 512;
const KN_LEN = 32; // max wide chars in a key name
const TID_LEN = 80; // max wide chars in a timer ID
const RING_SIZE = 128; // SendInput ring buffer slots
const ACTIVE_MOD_MAX = 8;
const KEY_TIMERS_MAX = 8;
// Hot-path flat array capacities — sized with headroom; overflow silently drops.
const KB_MAX = 32; // simultaneously buffered keys
const ORD_MAX = 32; // key order ring
const ACT_MAX = 32; // active timer hashes
const PCB_MAX = 32; // pending callbacks
const PTM_MAX = 32; // pending timers
const IGN_MAX = 16; // ignored keys
const KDT_MAX = 32; // key-down time tracking
const KUT_MAX = 32; // key-up time tracking
fn wlen(s: [*:0]const u16) usize {
    var i: usize = 0;
    while (s[i] != 0) i += 1;
    return i;
}
fn weqASCII(wide: [*:0]const u16, ascii: []const u8) bool {
    for (ascii, 0..) |c, i| if (wide[i] != c) return false;
    return wide[ascii.len] == 0;
}
fn copyKeyName(dest: *[KN_LEN]u16, src: [*:0]const u16) void {
    @memset(dest, 0);
    var i: usize = 0;
    while (src[i] != 0 and i < KN_LEN - 1) : (i += 1) dest[i] = src[i];
}
fn keyNameEq(a: *const [KN_LEN]u16, b: [*:0]const u16) bool {
    var i: usize = 0;
    while (i < KN_LEN) : (i += 1) {
        const bi: u16 = if (b[i] == 0) 0 else b[i];
        if (a[i] != bi) return false;
        if (a[i] == 0) return true;
    }
    return true;
}
fn wcpyS(dst: [*]u16, dstLen: usize, src: [*:0]const u16) void {
    var i: usize = 0;
    while (src[i] != 0 and i < dstLen - 1) : (i += 1) dst[i] = src[i];
    dst[i] = 0;
}
fn timerHash(id: []const u16) u64 {
    return std.hash.Wyhash.hash(0, std.mem.sliceAsBytes(id));
}
fn timerHashZ(id: [*:0]const u16) u64 {
    return timerHash(id[0..wlen(id)]);
}
fn buildTid(dest: *[TID_LEN]u16, pk: *const [KN_LEN]u16, sep: []const u8, sk: *const [KN_LEN]u16) u64 {
    @memset(dest, 0);
    var pos: usize = 0;
    var j: usize = 0;
    while (pk[j] != 0 and pos < TID_LEN - 1) : ({
        pos += 1;
        j += 1;
    }) dest[pos] = pk[j];
    for (sep) |c| {
        if (pos >= TID_LEN - 1) break;
        dest[pos] = @as(u16, c);
        pos += 1;
    }
    j = 0;
    while (sk[j] != 0 and pos < TID_LEN - 1) : ({
        pos += 1;
        j += 1;
    }) dest[pos] = sk[j];
    return timerHash(dest[0..pos]);
}
// ============================================================================
// Section 6 — Data structures
// ============================================================================
const ActionType = enum(u8) { undecided = 0, tap = 1, hold = 2, modifier_used = 3, none = 4 };
const MOD_CTRL: i8 = 0;
const MOD_ALT: i8 = 1;
const MOD_SHIFT: i8 = 2;
const MOD_WIN: i8 = 3;
const MOD_NONE: i8 = -1;
// Set when this key has already been sent as a modifier-triggered key at least
// once during the current hold. Allows the multi-mod duration guard to be
// skipped on repeat without interfering with the repeat thread.
const FLAG_SEND_MODIFIED_REPEAT: u16 = 0x0400;
const FLAG_RELEASED: u16 = 0x0001;
const FLAG_INTERFERING: u16 = 0x0002;
const FLAG_COMBO_TRIG: u16 = 0x0004;
const FLAG_MOD_PRESSED: u16 = 0x0008;
const FLAG_IS_MOD: u16 = 0x0010;
const FLAG_MOD_ACT: u16 = 0x0020;
const FLAG_MOD_TRIG: u16 = 0x0040;
const FLAG_COMBO_RPT: u16 = 0x0080;
const FLAG_QUIET: u16 = 0x0100;

// Set on a buffered modifier-role key the moment any other key is pressed while
// it is held undecided.  Prevents the hold callback from firing even if the key
// is eventually held past the hold threshold — the key did not occur in
// isolation so it was not a deliberate hold.  Does not affect tap, combo, or
// modifier-activation paths.  Naturally scoped to one press lifetime because
// KeyData is zero-initialised on every new keypress.
const FLAG_CONTAMINATED: u16 = 0x0200;
const KeyData = struct {
    downTime: f64 = 0,
    releaseTime: f64 = 0,
    sameModPartnerVK: i32 = 0,
    sameModTidHash: u64 = 0,
    tidHashes: [KEY_TIMERS_MAX]u64 = [_]u64{0} ** KEY_TIMERS_MAX,
    tidCount: u8 = 0,
    actionType: ActionType = .undecided,
    flags: u16 = 0,
    inline fn f(self: KeyData, mask: u16) bool {
        return (self.flags & mask) != 0;
    }
    inline fn sf(self: *KeyData, mask: u16) void {
        self.flags |= mask;
    }
    inline fn cf(self: *KeyData, mask: u16) void {
        self.flags &= ~mask;
    }
    inline fn bf(self: *KeyData, mask: u16, v: bool) void {
        if (v) self.sf(mask) else self.cf(mask);
    }
    inline fn isReleased(self: KeyData) bool {
        return self.f(FLAG_RELEASED);
    }
    inline fn hasInterferingKeys(self: KeyData) bool {
        return self.f(FLAG_INTERFERING);
    }
    inline fn comboTriggered(self: KeyData) bool {
        return self.f(FLAG_COMBO_TRIG);
    }
    inline fn modifierPressed(self: KeyData) bool {
        return self.f(FLAG_MOD_PRESSED);
    }
    inline fn isModifier(self: KeyData) bool {
        return self.f(FLAG_IS_MOD);
    }
    inline fn modifierActivated(self: KeyData) bool {
        return self.f(FLAG_MOD_ACT);
    }
    inline fn modifierTriggered(self: KeyData) bool {
        return self.f(FLAG_MOD_TRIG);
    }
    inline fn inComboRepeatMode(self: KeyData) bool {
        return self.f(FLAG_COMBO_RPT);
    }
    inline fn inQuietPeriod(self: KeyData) bool {
        return self.f(FLAG_QUIET);
    }
    inline fn isContaminated(self: KeyData) bool {
        return self.f(FLAG_CONTAMINATED);
    }
    inline fn inSendModifiedRepeatMode(self: KeyData) bool {
        return self.f(FLAG_SEND_MODIFIED_REPEAT);
    }
    fn addTidHash(self: *KeyData, h: u64) void {
        if (self.tidCount < KEY_TIMERS_MAX) {
            self.tidHashes[self.tidCount] = h;
            self.tidCount += 1;
        }
    }
};
const PendingCallback = struct {
    callbackId: i32,
    key1: [64]u16 = [_]u16{0} ** 64,
    key2: [8]u16 = [_]u16{0} ** 8,
    type_: i32,
    vk: i32,
    modifierMask: u16,
};
const PendingTimer = struct {
    timerId: [TID_LEN]u16 = [_]u16{0} ** TID_LEN,
    tidHash: u64 = 0,
    delay: i32,
    timerType: i32,
    primaryKey: [KN_LEN]u16 = [_]u16{0} ** KN_LEN,
    secondaryKey: [KN_LEN]u16 = [_]u16{0} ** KN_LEN,
    captureTime: f64,
};
// Exported result struct — layout must match AHK side exactly.
const KeyEventResult = extern struct {
    directCallbacksProcessed: i32,
    slowCallbacksCount: i32,
    timersCount: i32,
};
// ============================================================================
// Section 7 — Global state
// ============================================================================
// --- QPC timer ---
var g_qpcFreq: i64 = 0;
var g_qpcToMs: f64 = 0; // 1_000.0 / g_qpcFreq
var g_qpcToUs: f64 = 0; // 1_000_000.0 / g_qpcFreq
var g_timerInit: bool = false;
// --- Interception ---
var g_ictx: InterceptionContext = null;
var g_idev: InterceptionDevice = 0;
var g_useKernel: bool = true;
var g_profilingEnabled: bool = false; // on by default
// Cached conjunction of (g_useKernel && g_ictx != null && g_idev > 0).
// Written only in QMK_Init / QMK_InitInterception / QMK_DestroyInterception /
// QMK_ToggleKernelInjection. Never recomputed on the keystroke hot path.
var g_interceptionReady: bool = false;
// --- Double-tap repeat ---
var g_repeatHandle: ?HANDLE = null;
var g_repeatActive: i32 = 0; // atomic
var g_repeatVK: i32 = 0; // atomic
// --- Async SendInput Thread State ---
const ASYNC_RING_SIZE = 1024;
var g_async_ring: [ASYNC_RING_SIZE]InputSlot = undefined;
var g_async_head: u32 = 0;
var g_async_tail: u32 = 0;
var g_async_event: ?HANDLE = null;
var g_async_thread: ?HANDLE = null;
var g_async_active: i32 = 0;
// --- Key registry (flat; O(1) VK→index via g_vkToRegIdx) ---
var g_keyVKs: [VK_COUNT]i32 = [_]i32{0} ** VK_COUNT;
var g_keyNames: [VK_COUNT][KN_LEN]u16 = undefined; // zeroed in QMK_Init
var g_modTypes: [VK_COUNT]i8 = [_]i8{MOD_NONE} ** VK_COUNT;
var g_keyCount: u32 = 0;
var g_vkToRegIdx: [VK_COUNT]i16 = [_]i16{-1} ** VK_COUNT;
// --- Key buffer (parallel arrays + O(1) VK→slot via g_kbIdx) ---
var g_kbVK: [KB_MAX]i32 = [_]i32{0} ** KB_MAX;
var g_kbData: [KB_MAX]KeyData = [_]KeyData{.{}} ** KB_MAX;
var g_kbLen: usize = 0;
var g_kbIdx: [VK_COUNT]i16 = [_]i16{-1} ** VK_COUNT;
// --- Key order (ring buffer so ordRemoveFirst is O(1)) ---
var g_keyOrder: [ORD_MAX]i32 = [_]i32{0} ** ORD_MAX;
var g_ordHead: usize = 0;
var g_ordLen: usize = 0;
// --- Active timers (flat set of hashes) ---
var g_timerHashes: [ACT_MAX]u64 = [_]u64{0} ** ACT_MAX;
var g_timerLen: usize = 0;
// --- Pending callbacks / timers ---
var g_pendingCBs: [PCB_MAX]PendingCallback = undefined;
var g_pendingCBsLen: usize = 0;
var g_pendingTimers: [PTM_MAX]PendingTimer = undefined;
var g_pendingTimersLen: usize = 0;
// --- Ignored keys ---
var g_ignoredKeys: [IGN_MAX]i32 = [_]i32{0} ** IGN_MAX;
var g_ignoredKeysLen: usize = 0;
// --- Key-down / key-up time tracking (for double-tap detection) ---
var g_kdtVK: [KDT_MAX]i32 = [_]i32{0} ** KDT_MAX;
var g_kdtTime: [KDT_MAX]f64 = [_]f64{0} ** KDT_MAX;
var g_kdtLen: usize = 0;
var g_kutVK: [KUT_MAX]i32 = [_]i32{0} ** KUT_MAX;
var g_kutTime: [KUT_MAX]f64 = [_]f64{0} ** KUT_MAX;
var g_kutLen: usize = 0;
// --- Registration maps (written at setup time, never on hot path) ---
var g_holdCallbacks: std.AutoHashMapUnmanaged(i32, i32) = .{};
var g_comboCallbacks: std.AutoHashMapUnmanaged(u64, i32) = .{};
var g_instantComboCallbacks: std.AutoHashMapUnmanaged(u64, i32) = .{};
var g_comboPrimary: std.AutoHashMapUnmanaged(i32, void) = .{};
var g_instantComboPrimary: std.AutoHashMapUnmanaged(i32, void) = .{};
var g_comboSet: std.AutoHashMapUnmanaged(u64, void) = .{};
var g_instantComboSet: std.AutoHashMapUnmanaged(u64, void) = .{};
var g_internalCombos: std.AutoHashMapUnmanaged(u64, InternalRemap) = .{};
var g_internalChords: std.AutoHashMapUnmanaged(u64, InternalChord) = .{};
var g_externalChords: std.AutoHashMapUnmanaged(u64, ExternalChord) = .{}; // chord key → {callbackId, keyCount}
// O(1) bitset mirrors for hasCombo / hasInstantCombo primary checks
var g_comboPrimaryBits: [VK_COUNT / 8]u8 = [_]u8{0} ** (VK_COUNT / 8);
var g_instantComboPrimaryBits: [VK_COUNT / 8]u8 = [_]u8{0} ** (VK_COUNT / 8);
const InternalRemap = extern struct { targetVK: i32, modMask: u16, isInstant: bool };
const InternalChord = extern struct { targetVK: i32, modMask: u16, keyCount: u8 };
const ExternalChord = extern struct { callbackId: i32, keyCount: u8 };
// --- Active modifiers ---
var g_activeMods: [ACTIVE_MOD_MAX]i32 = [_]i32{0} ** ACTIVE_MOD_MAX;
var g_activeModCount: i32 = 0;
var g_activeModMask: u16 = 0;
// --- Misc runtime state ---
var g_modBitmask: i32 = 0;
var g_lastKeyTime: f64 = 0;
var g_typingMode: bool = false;
var g_unrelModCount: i32 = 0;
var g_activeModKeyCnt: i32 = 0;
// --- Config (Defaults below, overridden by QMK_SetUserConfig if called) ---
var g_SingleKeyHoldThreshold: f64 = 175.0;
var g_MaxHoldThreshold: f64 = 1000.0;
var g_MaxBufferSize: i32 = 50;
var g_ComboQuietDuration: f64 = 200.0;
var g_ModifierThreshold: f64 = 1000.0;
var g_MaxThresholdSupress: bool = true;
var g_DoubleTapThreshold: f64 = 200.0;
var g_RepeatInitialDelay: i32 = 300;
var g_RepeatInterval: i32 = 20;

// --- SendInput ring buffer ---
// Typed struct matches x86_64 Windows INPUT ABI exactly (40 bytes).
// [0..4] type [4..8] pad [8..10] wVk [10..12] wScan [12..16] dwFlags
// [16..20] time [20..24] pad [24..32] dwExtraInfo [32..40] union pad
const InputSlot = extern struct {
    type_: u32 = INPUT_KEYBOARD,
    _pad0: u32 = 0,
    wVk: u16 = 0,
    wScan: u16 = 0,
    dwFlags: u32 = 0,
    time: u32 = 0,
    _pad1: u32 = 0,
    dwExtraInfo: u64 = AHK_SENDLEVEL_2,
    _pad2: u64 = 0,
};
comptime {
    if (@sizeOf(InputSlot) != 40) @compileError("InputSlot size mismatch");
}
var g_ring: [RING_SIZE]InputSlot = undefined;
var g_ringCount: usize = 0;
var g_strokeBatch: [RING_SIZE]InterceptionKeyStroke = undefined;
// Scan-code cache: populated on first use per VK, never recomputed.
var g_scCache: [VK_COUNT]u16 = [_]u16{0} ** VK_COUNT;
var g_e0Cache: [VK_COUNT / 8]u8 = [_]u8{0} ** (VK_COUNT / 8);
var g_comboMatrix: [VK_COUNT][VK_COUNT]bool = [_][VK_COUNT]bool{[_]bool{false} ** VK_COUNT} ** VK_COUNT;
var g_instantComboMatrix: [VK_COUNT][VK_COUNT]bool = [_][VK_COUNT]bool{[_]bool{false} ** VK_COUNT} ** VK_COUNT;
// ============================================================================
// Section 8 — Flat-array helpers (all inline, no heap allocation on hot path)
// ============================================================================
// --- Key buffer (O(1) via g_kbIdx) ---
inline fn kbFind(vk: i32) ?usize {
    if (vk < 0 or vk >= VK_COUNT) return null;
    const i = g_kbIdx[@intCast(vk)];
    return if (i < 0) null else @intCast(i);
}
inline fn kbGet(vk: i32) ?*KeyData {
    return if (kbFind(vk)) |i| &g_kbData[i] else null;
}
inline fn kbPut(vk: i32, kd: KeyData) void {
    if (vk < 0 or vk >= VK_COUNT) return;
    const ex = g_kbIdx[@intCast(vk)];
    if (ex >= 0) {
        g_kbData[@intCast(ex)] = kd;
        return;
    }
    if (g_kbLen >= KB_MAX) return;
    const slot = g_kbLen;
    g_kbVK[slot] = vk;
    g_kbData[slot] = kd;
    g_kbIdx[@intCast(vk)] = @intCast(slot);
    g_kbLen += 1;
}
inline fn kbRemove(vk: i32) void {
    if (vk < 0 or vk >= VK_COUNT) return;
    const i = g_kbIdx[@intCast(vk)];
    if (i < 0) return;
    const idx: usize = @intCast(i);
    g_kbIdx[@intCast(vk)] = -1;
    g_kbLen -= 1;
    if (idx != g_kbLen) {
        const mv = g_kbVK[g_kbLen];
        g_kbVK[idx] = mv;
        g_kbData[idx] = g_kbData[g_kbLen];
        if (mv >= 0 and mv < VK_COUNT) g_kbIdx[@intCast(mv)] = @intCast(idx);
    }
}
inline fn kbContains(vk: i32) bool {
    if (vk < 0 or vk >= VK_COUNT) return false;
    return g_kbIdx[@intCast(vk)] >= 0;
}
inline fn kbCount() usize {
    return g_kbLen;
}
inline fn kbClear() void {
    for (0..g_kbLen) |i| {
        const v = g_kbVK[i];
        if (v >= 0 and v < VK_COUNT) g_kbIdx[@intCast(v)] = -1;
    }
    g_kbLen = 0;
}
// --- Key order ring (ordRemoveFirst is O(1)) ---
inline fn ordAt(i: usize) i32 {
    return g_keyOrder[(g_ordHead + i) % ORD_MAX];
}
inline fn ordAppend(vk: i32) void {
    if (g_ordLen >= ORD_MAX) return;
    g_keyOrder[(g_ordHead + g_ordLen) % ORD_MAX] = vk;
    g_ordLen += 1;
}
inline fn ordRemoveFirst() void {
    if (g_ordLen == 0) return;
    g_ordHead = (g_ordHead + 1) % ORD_MAX;
    g_ordLen -= 1;
}
inline fn ordRemoveAt(rel: usize) void {
    if (rel >= g_ordLen) return;
    var j = rel;
    while (j < g_ordLen - 1) : (j += 1)
        g_keyOrder[(g_ordHead + j) % ORD_MAX] = g_keyOrder[(g_ordHead + j + 1) % ORD_MAX];
    g_ordLen -= 1;
}
inline fn ordClear() void {
    g_ordHead = 0;
    g_ordLen = 0;
}
// --- Active timers ---
inline fn timerAdd(h: u64) void {
    for (0..g_timerLen) |i| if (g_timerHashes[i] == h) return;
    if (g_timerLen >= ACT_MAX) return;
    g_timerHashes[g_timerLen] = h;
    g_timerLen += 1;
}
inline fn timerRemove(h: u64) void {
    for (0..g_timerLen) |i| {
        if (g_timerHashes[i] == h) {
            g_timerLen -= 1;
            g_timerHashes[i] = g_timerHashes[g_timerLen];
            return;
        }
    }
}
inline fn timerClear() void {
    g_timerLen = 0;
}
// --- Pending callbacks / timers ---
inline fn pcbAppend(cb: PendingCallback) void {
    if (g_pendingCBsLen >= PCB_MAX) return;
    g_pendingCBs[g_pendingCBsLen] = cb;
    g_pendingCBsLen += 1;
}
inline fn pcbClear() void {
    g_pendingCBsLen = 0;
}
inline fn ptmAppend(pt: PendingTimer) void {
    if (g_pendingTimersLen >= PTM_MAX) return;
    g_pendingTimers[g_pendingTimersLen] = pt;
    g_pendingTimersLen += 1;
}
inline fn ptmClear() void {
    g_pendingTimersLen = 0;
}
// --- Ignored keys ---
inline fn ignAdd(vk: i32) void {
    if (g_ignoredKeysLen >= IGN_MAX) return;
    g_ignoredKeys[g_ignoredKeysLen] = vk;
    g_ignoredKeysLen += 1;
}
inline fn ignRemove(idx: usize) void {
    if (idx >= g_ignoredKeysLen) return;
    for (idx..g_ignoredKeysLen - 1) |i| g_ignoredKeys[i] = g_ignoredKeys[i + 1];
    g_ignoredKeysLen -= 1;
}
inline fn ignClear() void {
    g_ignoredKeysLen = 0;
}
// --- Key-down / key-up time tracking ---
inline fn kdtPut(vk: i32, t: f64) void {
    for (0..g_kdtLen) |i| {
        if (g_kdtVK[i] == vk) {
            g_kdtTime[i] = t;
            return;
        }
    }
    if (g_kdtLen >= KDT_MAX) return;
    g_kdtVK[g_kdtLen] = vk;
    g_kdtTime[g_kdtLen] = t;
    g_kdtLen += 1;
}
inline fn kdtGet(vk: i32) ?f64 {
    for (0..g_kdtLen) |i| if (g_kdtVK[i] == vk) return g_kdtTime[i];
    return null;
}
inline fn kdtRemove(vk: i32) void {
    for (0..g_kdtLen) |i| {
        if (g_kdtVK[i] == vk) {
            g_kdtLen -= 1;
            g_kdtVK[i] = g_kdtVK[g_kdtLen];
            g_kdtTime[i] = g_kdtTime[g_kdtLen];
            return;
        }
    }
}
inline fn kdtClear() void {
    g_kdtLen = 0;
}
inline fn kutPut(vk: i32, t: f64) void {
    for (0..g_kutLen) |i| {
        if (g_kutVK[i] == vk) {
            g_kutTime[i] = t;
            return;
        }
    }
    if (g_kutLen >= KUT_MAX) return;
    g_kutVK[g_kutLen] = vk;
    g_kutTime[g_kutLen] = t;
    g_kutLen += 1;
}
inline fn kutGet(vk: i32) ?f64 {
    for (0..g_kutLen) |i| if (g_kutVK[i] == vk) return g_kutTime[i];
    return null;
}
inline fn kutRemove(vk: i32) void {
    for (0..g_kutLen) |i| {
        if (g_kutVK[i] == vk) {
            g_kutLen -= 1;
            g_kutVK[i] = g_kutVK[g_kutLen];
            g_kutTime[i] = g_kutTime[g_kutLen];
            return;
        }
    }
}
inline fn kutClear() void {
    g_kutLen = 0;
}
// --- Combo primary bitsets (O(1) hasCombo pre-check) ---
inline fn comboPrimaryBitSet(vk: i32) void {
    if (vk < 0 or vk >= VK_COUNT) return;
    const u: u32 = @intCast(vk);
    g_comboPrimaryBits[u / 8] |= @as(u8, 1) << @intCast(u % 8);
}
inline fn instantComboPrimaryBitSet(vk: i32) void {
    if (vk < 0 or vk >= VK_COUNT) return;
    const u: u32 = @intCast(vk);
    g_instantComboPrimaryBits[u / 8] |= @as(u8, 1) << @intCast(u % 8);
}
inline fn comboPrimaryBitTest(vk: i32) bool {
    if (vk < 0 or vk >= VK_COUNT) return false;
    const u: u32 = @intCast(vk);
    return (g_comboPrimaryBits[u / 8] & (@as(u8, 1) << @intCast(u % 8))) != 0;
}
inline fn instantComboPrimaryBitTest(vk: i32) bool {
    if (vk < 0 or vk >= VK_COUNT) return false;
    const u: u32 = @intCast(vk);
    return (g_instantComboPrimaryBits[u / 8] & (@as(u8, 1) << @intCast(u % 8))) != 0;
}
// ============================================================================
// Section 9 — Timer helpers
// ============================================================================
fn initTimer() void {
    if (g_timerInit) return;
    _ = QueryPerformanceFrequency(&g_qpcFreq);
    g_qpcToMs = 1_000.0 / @as(f64, @floatFromInt(g_qpcFreq));
    g_qpcToUs = 1_000_000.0 / @as(f64, @floatFromInt(g_qpcFreq));
    g_timerInit = true;
}
fn getTime() f64 {
    var c: i64 = 0;
    _ = QueryPerformanceCounter(&c);
    return @as(f64, @floatFromInt(c)) * g_qpcToMs;
}
// ============================================================================
// Section 10 — Key registry
// ============================================================================
// Fast version - uses reverse lookup when possible
fn getVKFromKN(kn: *const [KN_LEN]u16) i32 {
    // First try fast path: if this name was registered via VK, we can find it faster
    for (0..g_keyCount) |i| {
        if (std.mem.eql(u16, &g_keyNames[i], kn)) {
            return g_keyVKs[i];
        }
    }
    return 0;
}
fn getVKFromName(name: [*:0]const u16) i32 {
    if (name[0] == 0) return 0;
    for (0..g_keyCount) |i| {
        const reg = &g_keyNames[i];
        var j: usize = 0;
        while (j < KN_LEN) : (j += 1) {
            const rc = reg[j];
            const nc = name[j];
            if (rc != nc) break;
            if (rc == 0) return g_keyVKs[i];
        }
    }
    return 0;
}
fn registerVK(vk: i32, name: [*:0]const u16) void {
    if (vk >= 0 and vk < VK_COUNT) {
        const ex = g_vkToRegIdx[@intCast(vk)];
        if (ex >= 0) {
            copyKeyName(&g_keyNames[@intCast(ex)], name);
            return;
        }
    }
    if (g_keyCount >= VK_COUNT) return;
    const idx = g_keyCount;
    g_keyVKs[idx] = vk;
    copyKeyName(&g_keyNames[idx], name);
    g_modTypes[idx] = MOD_NONE;
    g_keyCount += 1;
    if (vk >= 0 and vk < VK_COUNT) g_vkToRegIdx[@intCast(vk)] = @intCast(idx);
}
fn getNameFromVK(vk: i32) ?*const [KN_LEN]u16 {
    if (vk < 0 or vk >= VK_COUNT) return null;
    const idx = g_vkToRegIdx[@intCast(vk)];
    return if (idx >= 0) &g_keyNames[@intCast(idx)] else null;
}
fn getModTypeForVK(vk: i32) i8 {
    if (vk < 0 or vk >= VK_COUNT) return MOD_NONE;
    const idx = g_vkToRegIdx[@intCast(vk)];
    return if (idx < 0) MOD_NONE else g_modTypes[@intCast(idx)];
}
fn setModTypeForVK(vk: i32, mt: i8) void {
    if (vk < 0 or vk >= VK_COUNT) return;
    const idx = g_vkToRegIdx[@intCast(vk)];
    if (idx >= 0) g_modTypes[@intCast(idx)] = mt;
}
fn parseModTypeName(name: [*:0]const u16) i8 {
    if (weqASCII(name, "Ctrl")) return MOD_CTRL;
    if (weqASCII(name, "Alt")) return MOD_ALT;
    if (weqASCII(name, "Shift")) return MOD_SHIFT;
    if (weqASCII(name, "Win")) return MOD_WIN;
    return MOD_NONE;
}
fn getSysModBit(name: [*:0]const u16) i32 {
    if (weqASCII(name, "LCtrl")) return 0x01;
    if (weqASCII(name, "RCtrl")) return 0x02;
    if (weqASCII(name, "LShift")) return 0x04;
    if (weqASCII(name, "RShift")) return 0x08;
    if (weqASCII(name, "LAlt")) return 0x10;
    if (weqASCII(name, "RAlt")) return 0x20;
    if (weqASCII(name, "LWin")) return 0x40;
    if (weqASCII(name, "RWin")) return 0x80;
    return 0;
}
fn parseModifierMask(mods: [*:0]const u16) u16 {
    var mask: u16 = 0;
    var i: usize = 0;
    while (mods[i] != 0) : (i += 1) {
        switch (mods[i]) {
            '^' => mask |= 0x01,
            '!' => mask |= 0x02,
            '+' => mask |= 0x04,
            '#' => mask |= 0x08,
            else => {},
        }
    }
    return mask;
}
fn makeComboKey(primary: i32, secondary: i32) u64 {
    return (@as(u64, @intCast(primary)) << 32) | @as(u64, @intCast(@as(u32, @bitCast(secondary))));
}
// ============================================================================
// Section 11 — Active modifier helpers
// ============================================================================
fn activeModContains(vk: i32) bool {
    for (0..@intCast(g_activeModCount)) |i| if (g_activeMods[i] == vk) return true;
    return false;
}
fn activeModAdd(vk: i32) void {
    if (activeModContains(vk) or g_activeModCount >= ACTIVE_MOD_MAX) return;

    g_activeMods[@intCast(g_activeModCount)] = vk;
    g_activeModCount += 1;

    switch (getModTypeForVK(vk)) {
        MOD_CTRL => g_activeModMask |= 0x01,
        MOD_ALT => g_activeModMask |= 0x02,
        MOD_SHIFT => g_activeModMask |= 0x04,
        MOD_WIN => g_activeModMask |= 0x08,
        else => {},
    }
}

fn activeModRemove(vk: i32) void {
    var i: usize = 0;
    while (i < @as(usize, @intCast(g_activeModCount))) : (i += 1) {
        if (g_activeMods[i] == vk) {
            switch (getModTypeForVK(vk)) {
                MOD_CTRL => g_activeModMask &= ~@as(u16, 0x01),
                MOD_ALT => g_activeModMask &= ~@as(u16, 0x02),
                MOD_SHIFT => g_activeModMask &= ~@as(u16, 0x04),
                MOD_WIN => g_activeModMask &= ~@as(u16, 0x08),
                else => {},
            }
            g_activeModCount -= 1;
            g_activeMods[i] = g_activeMods[@intCast(g_activeModCount)];
            return;
        }
    }
}
fn activeModClear() void {
    g_activeModCount = 0;
    g_activeModMask = 0;
}
fn countUnreleasedModifiers() i32 {
    return g_unrelModCount;
}
fn buildModMaskFromActive() u16 {
    return g_activeModMask;
}
// ============================================================================
// Section 12 — Timer management
// ============================================================================
fn cancelTimer(hash: u64) void {
    timerRemove(hash);
}
fn cancelTimerZ(id: [*:0]const u16) void {
    cancelTimer(timerHashZ(id));
}
fn cancelKeyTimers(vk: i32) void {
    const kd = kbGet(vk) orelse return;
    for (kd.tidHashes[0..kd.tidCount]) |h| timerRemove(h);
    kd.tidCount = 0;
}
fn removeFromKeyOrder(vk: i32) void {
    for (0..g_ordLen) |i| {
        if (ordAt(i) == vk) {
            ordRemoveAt(i);
            return;
        }
    }
}
fn queueCallback(callbackId: i32, key1: *const [KN_LEN]u16, key2: [*:0]const u16, type_: i32) void {
    var cb = PendingCallback{ .callbackId = callbackId, .type_ = type_, .vk = 0, .modifierMask = 0 };
    @memcpy(cb.key1[0..KN_LEN], key1);
    wcpyS(&cb.key2, 8, key2);
    for (0..g_keyCount) |i|
        if (keyNameEq(&g_keyNames[i], @ptrCast(&cb.key1))) {
            cb.vk = g_keyVKs[i];
            break;
        };
    cb.modifierMask = parseModifierMask(@ptrCast(&cb.key2));
    // type_ == 0 is a hold callback.  If the key was contaminated (another key
    // was pressed while it was buffered undecided) it was not a deliberate solo
    // hold — silently drop it here regardless of which code path called us.
    if (type_ == 0) {
        if (kbGet(cb.vk)) |kd| {
            if (kd.isContaminated()) return;
        }
    }
    pcbAppend(cb);
}
fn queueCallbackEmpty(callbackId: i32, type_: i32) void {
    const empty: [KN_LEN]u16 = [_]u16{0} ** KN_LEN;
    const emptyZ: [1]u16 = [_]u16{0};
    queueCallback(callbackId, &empty, @ptrCast(&emptyZ), type_);
}
fn queueTimer(tidBuf: *const [TID_LEN]u16, tidHash: u64, delay: i32, timerType: i32, pk: *const [KN_LEN]u16, sk: *const [KN_LEN]u16, captureTime: f64) void {
    timerAdd(tidHash);
    var pt = PendingTimer{ .tidHash = tidHash, .delay = delay, .timerType = timerType, .captureTime = captureTime };
    @memcpy(&pt.timerId, tidBuf);
    @memcpy(&pt.primaryKey, pk);
    @memcpy(&pt.secondaryKey, sk);
    ptmAppend(pt);
    const pkVK = getVKFromKN(pk);
    if (pkVK != 0) {
        if (kbGet(pkVK)) |kd| kd.addTidHash(tidHash);
    }
    const skVK = getVKFromKN(sk);
    if (skVK != 0 and skVK != pkVK) {
        if (kbGet(skVK)) |kd| kd.addTidHash(tidHash);
    }
}
// ============================================================================
// Section 13 — Scan-code cache & SendInput ring
// ============================================================================
inline fn scCacheIsE0(vk: u16) bool {
    return (g_e0Cache[vk / 8] & (@as(u8, 1) << @intCast(vk % 8))) != 0;
}
inline fn scCacheSetE0(vk: u16) void {
    g_e0Cache[vk / 8] |= (@as(u8, 1) << @intCast(vk % 8));
}
// ---------------------------------------------------------------------------
// Compile-time scan-code table for standard US-QWERTY layout.
// Covers every VK in DEFAULT_KEYS. scLookup() checks this first — zero
// MapVirtualKeyW calls at runtime for any key in this table.
// Keys not in the table (sc == 0) fall through to the runtime cache path.
// ---------------------------------------------------------------------------
const ScEntry = struct { sc: u16, e0: bool };
const QWERTY_SC: [256]ScEntry = blk: {
    var t = [_]ScEntry{.{ .sc = 0, .e0 = false }} ** 256;
    // Letters A-Z
    t[0x41] = .{ .sc = 0x1E, .e0 = false }; // A
    t[0x42] = .{ .sc = 0x30, .e0 = false }; // B
    t[0x43] = .{ .sc = 0x2E, .e0 = false }; // C
    t[0x44] = .{ .sc = 0x20, .e0 = false }; // D
    t[0x45] = .{ .sc = 0x12, .e0 = false }; // E
    t[0x46] = .{ .sc = 0x21, .e0 = false }; // F
    t[0x47] = .{ .sc = 0x22, .e0 = false }; // G
    t[0x48] = .{ .sc = 0x23, .e0 = false }; // H
    t[0x49] = .{ .sc = 0x17, .e0 = false }; // I
    t[0x4A] = .{ .sc = 0x24, .e0 = false }; // J
    t[0x4B] = .{ .sc = 0x25, .e0 = false }; // K
    t[0x4C] = .{ .sc = 0x26, .e0 = false }; // L
    t[0x4D] = .{ .sc = 0x32, .e0 = false }; // M
    t[0x4E] = .{ .sc = 0x31, .e0 = false }; // N
    t[0x4F] = .{ .sc = 0x18, .e0 = false }; // O
    t[0x50] = .{ .sc = 0x19, .e0 = false }; // P
    t[0x51] = .{ .sc = 0x10, .e0 = false }; // Q
    t[0x52] = .{ .sc = 0x13, .e0 = false }; // R
    t[0x53] = .{ .sc = 0x1F, .e0 = false }; // S
    t[0x54] = .{ .sc = 0x14, .e0 = false }; // T
    t[0x55] = .{ .sc = 0x16, .e0 = false }; // U
    t[0x56] = .{ .sc = 0x2F, .e0 = false }; // V
    t[0x57] = .{ .sc = 0x11, .e0 = false }; // W
    t[0x58] = .{ .sc = 0x2D, .e0 = false }; // X
    t[0x59] = .{ .sc = 0x15, .e0 = false }; // Y
    t[0x5A] = .{ .sc = 0x2C, .e0 = false }; // Z
    // Digits 0-9
    t[0x30] = .{ .sc = 0x0B, .e0 = false }; // 0
    t[0x31] = .{ .sc = 0x02, .e0 = false }; // 1
    t[0x32] = .{ .sc = 0x03, .e0 = false }; // 2
    t[0x33] = .{ .sc = 0x04, .e0 = false }; // 3
    t[0x34] = .{ .sc = 0x05, .e0 = false }; // 4
    t[0x35] = .{ .sc = 0x06, .e0 = false }; // 5
    t[0x36] = .{ .sc = 0x07, .e0 = false }; // 6
    t[0x37] = .{ .sc = 0x08, .e0 = false }; // 7
    t[0x38] = .{ .sc = 0x09, .e0 = false }; // 8
    t[0x39] = .{ .sc = 0x0A, .e0 = false }; // 9
    // OEM / punctuation
    t[0xDB] = .{ .sc = 0x1A, .e0 = false }; // [ VK_OEM_4
    t[0xDD] = .{ .sc = 0x1B, .e0 = false }; // ] VK_OEM_6
    t[0xBA] = .{ .sc = 0x27, .e0 = false }; // ; VK_OEM_1
    t[0xDE] = .{ .sc = 0x28, .e0 = false }; // ' VK_OEM_7
    t[0xBC] = .{ .sc = 0x33, .e0 = false }; // , VK_OEM_COMMA
    t[0xBE] = .{ .sc = 0x34, .e0 = false }; // . VK_OEM_PERIOD
    t[0xBF] = .{ .sc = 0x35, .e0 = false }; // / VK_OEM_2
    t[0xDC] = .{ .sc = 0x2B, .e0 = false }; // \ VK_OEM_5
    t[0xC0] = .{ .sc = 0x29, .e0 = false }; // ` VK_OEM_3
    t[0xBD] = .{ .sc = 0x0C, .e0 = false }; // - VK_OEM_MINUS
    t[0xBB] = .{ .sc = 0x0D, .e0 = false }; // = VK_OEM_PLUS
    // Control / navigation
    t[0x20] = .{ .sc = 0x39, .e0 = false }; // Space
    t[0x09] = .{ .sc = 0x0F, .e0 = false }; // Tab
    t[0x0D] = .{ .sc = 0x1C, .e0 = false }; // Enter
    t[0x08] = .{ .sc = 0x0E, .e0 = false }; // Backspace
    t[0x2E] = .{ .sc = 0x53, .e0 = true }; // Delete
    t[0x2D] = .{ .sc = 0x52, .e0 = true }; // Insert
    t[0x24] = .{ .sc = 0x47, .e0 = true }; // Home
    t[0x23] = .{ .sc = 0x4F, .e0 = true }; // End
    t[0x21] = .{ .sc = 0x49, .e0 = true }; // PgUp
    t[0x22] = .{ .sc = 0x51, .e0 = true }; // PgDn
    t[0x26] = .{ .sc = 0x48, .e0 = true }; // Up
    t[0x28] = .{ .sc = 0x50, .e0 = true }; // Down
    t[0x25] = .{ .sc = 0x4B, .e0 = true }; // Left
    t[0x27] = .{ .sc = 0x4D, .e0 = true }; // Right
    t[0x1B] = .{ .sc = 0x01, .e0 = false }; // Escape
    t[0x14] = .{ .sc = 0x3A, .e0 = false }; // CapsLock
    t[0x91] = .{ .sc = 0x46, .e0 = false }; // ScrollLock
    t[0x90] = .{ .sc = 0x45, .e0 = true }; // NumLock
    // Modifiers
    t[0xA2] = .{ .sc = 0x1D, .e0 = false }; // LCtrl
    t[0xA3] = .{ .sc = 0x1D, .e0 = true }; // RCtrl
    t[0xA0] = .{ .sc = 0x2A, .e0 = false }; // LShift
    t[0xA1] = .{ .sc = 0x36, .e0 = false }; // RShift
    t[0xA4] = .{ .sc = 0x38, .e0 = false }; // LAlt
    t[0xA5] = .{ .sc = 0x38, .e0 = true }; // RAlt
    t[0x5B] = .{ .sc = 0x5B, .e0 = true }; // LWin
    t[0x5C] = .{ .sc = 0x5C, .e0 = true }; // RWin
    // Function keys F1-F12
    t[0x70] = .{ .sc = 0x3B, .e0 = false }; // F1
    t[0x71] = .{ .sc = 0x3C, .e0 = false }; // F2
    t[0x72] = .{ .sc = 0x3D, .e0 = false }; // F3
    t[0x73] = .{ .sc = 0x3E, .e0 = false }; // F4
    t[0x74] = .{ .sc = 0x3F, .e0 = false }; // F5
    t[0x75] = .{ .sc = 0x40, .e0 = false }; // F6
    t[0x76] = .{ .sc = 0x41, .e0 = false }; // F7
    t[0x77] = .{ .sc = 0x42, .e0 = false }; // F8
    t[0x78] = .{ .sc = 0x43, .e0 = false }; // F9
    t[0x79] = .{ .sc = 0x44, .e0 = false }; // F10
    t[0x7A] = .{ .sc = 0x57, .e0 = false }; // F11
    t[0x7B] = .{ .sc = 0x58, .e0 = false }; // F12
    break :blk t;
};

fn scLookup(vk: u16) u16 {
    if (vk == 0 or vk >= VK_COUNT) return 0;

    // Fast path: check the comptime QWERTY table first — no MapVirtualKeyW,
    // no cache write, just a direct indexed load from .rodata.
    const ct = QWERTY_SC[vk];
    if (ct.sc != 0) {
        if (ct.e0 and !scCacheIsE0(vk)) scCacheSetE0(vk);
        return ct.sc;
    }

    // Slow path: runtime cache, then MapVirtualKeyW for anything not in the
    // comptime table (non-QWERTY keys, dynamically registered VKs, etc.).
    if (g_scCache[vk] != 0) return g_scCache[vk];
    var nvk = vk;
    if (vk == VK_CONTROL) nvk = VK_LCONTROL;
    if (vk == VK_SHIFT) nvk = VK_LSHIFT;
    if (vk == VK_MENU) nvk = VK_LMENU;
    const sc: u32 = MapVirtualKeyW(nvk, MAPVK_VK_TO_VSC);
    if (sc == 0) return 0;
    g_scCache[vk] = @intCast(sc & 0xFFFF);
    if (nvk == 0xA5 or nvk == 0xA3 or nvk == 0x5B or nvk == 0x5C or nvk == 0x5D or
        (nvk >= 0x21 and nvk <= 0x28) or nvk == 0x2D or nvk == 0x2E or nvk == 0x6F)
        scCacheSetE0(vk);
    return g_scCache[vk];
}
inline fn ringReset() void {
    g_ringCount = 0;
}
fn ringAddKey(vk: u16, flags: u32) void {
    if (g_ringCount >= RING_SIZE) return;
    // Pre-populate wScan so both ringSend paths can use it directly.
    g_ring[g_ringCount] = .{ .wVk = vk, .wScan = scLookup(vk), .dwFlags = flags };
    g_ringCount += 1;
}
fn ringSend() void {
    if (g_ringCount == 0) return;
    if (g_interceptionReady) {
        var batchLen: u32 = 0;
        const count = g_ringCount;
        for (0..count) |i| {
            const slot = g_ring[i];
            if (slot.wScan == 0) continue;
            var state: u16 = if ((slot.dwFlags & KEYEVENTF_KEYUP) != 0) IKEY_UP else IKEY_DOWN;
            if (scCacheIsE0(slot.wVk)) state |= IKEY_E0;
            g_strokeBatch[batchLen] = .{
                .code = slot.wScan,
                .state = state,
                .information = @intCast(AHK_SENDLEVEL_2 & 0xFFFF_FFFF),
            };
            batchLen += 1;
        }
        if (batchLen > 0) {
            if (fp_send) |f| {
                _ = f(g_ictx, g_idev, g_strokeBatch[0..batchLen].ptr, batchLen);
            }
        }
    } else {
        // --- ASYNC SENDINPUT PATH ---
        for (0..g_ringCount) |i| {
            var slot = g_ring[i];
            if ((slot.dwFlags & 0x0008) == 0) {
                slot.dwFlags |= 0x0008;
                if (scCacheIsE0(slot.wVk)) slot.dwFlags |= 0x0001;
            }
            // Push to the lock-free ring
            const head = @atomicLoad(u32, &g_async_head, .acquire);
            g_async_ring[head % ASYNC_RING_SIZE] = slot;
            @atomicStore(u32, &g_async_head, head +% 1, .release);
        }
        // Wake the background thread instantly
        if (g_async_event) |ev| {
            _ = SetEvent(ev);
        }
    }
    g_ringCount = 0;
}
// ============================================================================
// Section 14 — Key send helpers
// ============================================================================
fn sendKeyDirect(vk: i32, modifierMask: u16) void {
    if (vk == 0) return;
    const profT = profStart();
    defer profRecord(&g_profiling.directSendProcessing, profT);
    if (modifierMask == 0) {
        // Fast path: single key, no modifiers
        ringReset();
        ringAddKey(@intCast(vk), 0);
        ringAddKey(@intCast(vk), KEYEVENTF_KEYUP);
        ringSend();
        return;
    }
    ringReset();
    if (modifierMask & 0x01 != 0) ringAddKey(VK_CONTROL, 0);
    if (modifierMask & 0x02 != 0) ringAddKey(VK_MENU, 0);
    if (modifierMask & 0x04 != 0) ringAddKey(VK_SHIFT, 0);
    if (modifierMask & 0x08 != 0) ringAddKey(VK_LWIN, 0);
    ringAddKey(@intCast(vk), 0);
    ringAddKey(@intCast(vk), KEYEVENTF_KEYUP);
    if (modifierMask & 0x08 != 0) ringAddKey(VK_LWIN, KEYEVENTF_KEYUP);
    if (modifierMask & 0x04 != 0) ringAddKey(VK_SHIFT, KEYEVENTF_KEYUP);
    if (modifierMask & 0x02 != 0) ringAddKey(VK_MENU, KEYEVENTF_KEYUP);
    if (modifierMask & 0x01 != 0) ringAddKey(VK_CONTROL, KEYEVENTF_KEYUP);
    ringSend();
}
// Send a single key down+up with NO modifier wrapping.
// Used for chord repeat (a+s held, l repeating): the physical keys are still
// in the driver so modifiers are already logically down. Re-wrapping them on
// every repeat causes a flicker/race that makes the chord drop under battery.
fn sendKeyOnly(vk: i32) void {
    if (vk == 0) return;
    ringReset();
    ringAddKey(@intCast(vk), 0);
    ringAddKey(@intCast(vk), KEYEVENTF_KEYUP);
    ringSend();
}
// Send keyVK with whatever modifiers are currently active.
// Checks g_internalCombos before sending so internal remaps take effect here too.
fn sendModifiedKey(keyVK: i32) void {
    const mask = buildModMaskFromActive();
    if (g_internalCombos.get(makeComboKey(keyVK, 0))) |remap| {
        sendKeyDirect(remap.targetVK, remap.modMask | mask);
        return;
    }
    sendKeyDirect(keyVK, mask);
    queueCallbackEmpty(-4, 4);
}
// ============================================================================
// Section 15 — Repeat thread
// ============================================================================
fn repeatThreadProc(_: ?*anyopaque) callconv(.winapi) u32 {
    const vk = @atomicLoad(i32, &g_repeatVK, .acquire);
    sendKeyDirect(vk, 0);
    var slept: i32 = 0;
    while (@atomicLoad(i32, &g_repeatActive, .acquire) != 0 and slept < g_RepeatInitialDelay) {
        Sleep(10);
        slept += 10;
    }
    while (@atomicLoad(i32, &g_repeatActive, .acquire) != 0) {
        sendKeyDirect(@atomicLoad(i32, &g_repeatVK, .acquire), 0);
        Sleep(@intCast(g_RepeatInterval));
    }
    return 0;
}
fn stopRepeatThread() void {
    @atomicStore(i32, &g_repeatActive, 0, .release);
    if (g_repeatHandle) |h| {
        _ = CloseHandle(h);
        g_repeatHandle = null;
    }
}
// ============================================================================
// Section 15B — Async SendInput Thread
// ============================================================================
fn asyncSendThreadProc(_: ?*anyopaque) callconv(.winapi) u32 {
    var local_batch: [128]InputSlot = undefined;

    while (@atomicLoad(i32, &g_async_active, .acquire) != 0) {
        _ = WaitForSingleObject(g_async_event.?, 500);
        if (@atomicLoad(i32, &g_async_active, .acquire) == 0) break;

        var head = @atomicLoad(u32, &g_async_head, .acquire);
        var tail = @atomicLoad(u32, &g_async_tail, .acquire);
        while (tail != head) {
            var batch_count: u32 = 0;
            while (tail != head and batch_count < 128) {
                local_batch[batch_count] = g_async_ring[tail % ASYNC_RING_SIZE];
                tail +%= 1;
                batch_count += 1;
            }
            @atomicStore(u32, &g_async_tail, tail, .release);
            if (batch_count > 0) {
                _ = SendInput(batch_count, @ptrCast(&local_batch[0]), INPUT_STRUCT_SIZE);
            }
            head = @atomicLoad(u32, &g_async_head, .acquire);
        }
    }
    return 0;
}
// ============================================================================
// Section 16 — Combo helpers
// ============================================================================
inline fn hasCombo(primary: i32, secondary: i32) bool {
    if (primary < 0 or primary >= VK_COUNT or secondary < 0 or secondary >= VK_COUNT) return false;
    return g_comboMatrix[@intCast(primary)][@intCast(secondary)];
}
inline fn hasInstantCombo(primary: i32, secondary: i32) bool {
    if (primary < 0 or primary >= VK_COUNT or secondary < 0 or secondary >= VK_COUNT) return false;
    return g_instantComboMatrix[@intCast(primary)][@intCast(secondary)];
}
// Fire a combo immediately. Checks g_internalCombos first; only calls AHK if
// no internal remap exists.
// Fire a combo immediately.
fn triggerComboImmediate(pkVK: i32, skVK: i32, pk: *const [KN_LEN]u16, sk: *const [KN_LEN]u16, skName: *const [KN_LEN]u16) void {
    _ = skName; // silence unused parameter warning
    const pkIt = kbGet(pkVK) orelse return;
    if (pkIt.isReleased()) return;
    var tidBuf: [TID_LEN]u16 = [_]u16{0} ** TID_LEN;
    cancelTimer(buildTid(&tidBuf, pk, "*", sk));
    pkIt.sf(FLAG_COMBO_TRIG | FLAG_COMBO_RPT);
    if (kbGet(skVK)) |skIt| {
        skIt.sf(FLAG_COMBO_TRIG);
        if (skIt.isModifier() and !skIt.isReleased()) g_unrelModCount -= 1;
        _ = kbRemove(skVK);
        removeFromKeyOrder(skVK);
    }
    const ck = makeComboKey(pkVK, skVK);
    if (g_internalCombos.get(ck)) |remap| {
        sendKeyDirect(remap.targetVK, remap.modMask);
        return;
    }
    if (g_comboCallbacks.get(ck)) |cbId|
        queueCallback(cbId, pk, @as([*:0]const u16, &[_:0]u16{0}), 1)
    else if (g_instantComboCallbacks.get(ck)) |cbId|
        queueCallback(cbId, pk, @as([*:0]const u16, &[_:0]u16{0}), 2);
}
// Instant combos fire as soon as the secondary key is pressed (no hold wait).
// Instant combos fire as soon as the secondary key is pressed
fn triggerInstantCombo(pkVK: i32, pk: *const [KN_LEN]u16, sk: *const [KN_LEN]u16, skName: *const [KN_LEN]u16) void {
    _ = skName; // silence unused parameter warning
    const pkIt = kbGet(pkVK) orelse return;
    if (pkIt.isReleased()) return;
    pkIt.sf(FLAG_COMBO_TRIG | FLAG_COMBO_RPT);
    if (pkIt.isModifier()) {
        pkIt.sf(FLAG_MOD_ACT | FLAG_MOD_TRIG);
        activeModAdd(pkVK);
    }
    const skVK = getVKFromKN(sk);
    if (skVK == 0) return;
    const ck = makeComboKey(pkVK, skVK);
    if (g_internalCombos.get(ck)) |remap| {
        sendKeyDirect(remap.targetVK, remap.modMask);
        return;
    }
    if (g_instantComboCallbacks.get(ck)) |cbId|
        queueCallback(cbId, pk, @as([*:0]const u16, &[_:0]u16{0}), 2);
}
// Timer-type 0: fire combo after quiet-period check.
fn triggerComboWithQuietCheck(pk: *const [KN_LEN]u16, sk: *const [KN_LEN]u16, captureTime: f64) void {
    const profT = profStart();
    defer profRecord(&g_profiling.kernelInjection, profT);
    const currentTime = getTime();
    if ((currentTime - g_lastKeyTime) >= g_ComboQuietDuration) {
        var allReleased = true;
        for (0..g_kbLen) |i| {
            if (!g_kbData[i].isReleased()) {
                allReleased = false;
                break;
            }
        }
        if (allReleased and kbCount() > 0) {
            processQueue();
            if (kbCount() > 0) {
                kbClear();
                ordClear();
                activeModClear();
                timerClear();
            }
            return;
        }
    }
    const pkVK = getVKFromKN(pk);
    if (pkVK == 0) return;
    const pkIt = kbGet(pkVK) orelse return;
    if (pkIt.isReleased()) return;
    if (g_lastKeyTime > captureTime and g_lastKeyTime - captureTime > 50) return;
    const skVK = getVKFromKN(sk);
    if (skVK == 0) return;
    const skNameRef = getNameFromVK(skVK) orelse sk;
    triggerComboImmediate(pkVK, skVK, pk, sk, skNameRef);
}
// Timer-type 1: same-modifier threshold fired.
fn sameModifierThreshold(pk: *const [KN_LEN]u16, sk: *const [KN_LEN]u16) void {
    const profT = profStart();
    defer profRecord(&g_profiling.sendInputProcessing, profT);
    var tidBuf: [TID_LEN]u16 = [_]u16{0} ** TID_LEN;
    cancelTimer(buildTid(&tidBuf, pk, "*retroMod*", sk));
    const pkVK = getVKFromKN(pk);
    if (pkVK == 0) return;
    const skVK = getVKFromKN(sk);
    if (skVK == 0) return;
    const pkIt = kbGet(pkVK) orelse return;
    if (pkIt.isReleased() or pkIt.modifierActivated() or pkIt.modifierTriggered()) return;
    const skIt = kbGet(skVK) orelse return;
    if (skIt.isReleased()) return;
    activeModAdd(pkVK);
    pkIt.sf(FLAG_MOD_ACT | FLAG_MOD_TRIG);
    sendModifiedKey(skVK);
    // sendKeyDirect sent modifier down+up as a complete pair — clear MOD_ACT so
    // the next keypress doesn't re-enter the active-mod path and so key-up
    // doesn't emit a spurious extra modifier-up stroke.
    pkIt.cf(FLAG_MOD_ACT);
    pkIt.actionType = .modifier_used;
    activeModRemove(pkVK);
    _ = kbRemove(skVK);
    removeFromKeyOrder(skVK);
    processQueue();
}
// Timer-type 2: retroactive combo trigger.
fn retroTriggerCombo(pk: *const [KN_LEN]u16, sk: *const [KN_LEN]u16) void {
    const profT = profStart();
    defer profRecord(&g_profiling.sendInputProcessing, profT);
    if (g_pendingTimersLen == 0) return; // no
    var tidBuf: [TID_LEN]u16 = [_]u16{0} ** TID_LEN;
    cancelTimer(buildTid(&tidBuf, pk, "*retroCombo*", sk));
    const pkVK = getVKFromKN(pk);
    if (pkVK == 0) return;
    const skVK = getVKFromKN(sk);
    if (skVK == 0) return;
    const pkIt = kbGet(pkVK) orelse return;
    if (pkIt.isReleased() or pkIt.comboTriggered() or pkIt.modifierActivated()) return;
    const skIt = kbGet(skVK) orelse return;
    if (!skIt.isReleased()) return;
    pkIt.sf(FLAG_COMBO_TRIG | FLAG_COMBO_RPT); // Add the receipt flag here too!
    const ck = makeComboKey(pkVK, skVK);
    if (g_internalCombos.get(ck)) |remap| {
        sendKeyDirect(remap.targetVK, remap.modMask);
        _ = kbRemove(skVK);
        removeFromKeyOrder(skVK);
        processQueue();
        return;
    }
    if (g_comboCallbacks.get(ck)) |cbId|
        queueCallback(cbId, pk, @as([*:0]const u16, &[_:0]u16{0}), 1);
    _ = kbRemove(skVK);
    removeFromKeyOrder(skVK);
    processQueue();
}
// Timer-type 3: retroactive modifier activation.
fn retroActivateModifier(pk: *const [KN_LEN]u16, sk: *const [KN_LEN]u16) void {
    const profT = profStart();
    defer profRecord(&g_profiling.sendInputProcessing, profT);
    var tidBuf: [TID_LEN]u16 = [_]u16{0} ** TID_LEN;
    cancelTimer(buildTid(&tidBuf, pk, "*retroMod*", sk));
    const pkVK = getVKFromKN(pk);
    if (pkVK == 0) return;
    const skVK = getVKFromKN(sk);
    if (skVK == 0) return;
    const pkIt = kbGet(pkVK) orelse return;
    if (pkIt.isReleased() or pkIt.modifierActivated() or pkIt.modifierTriggered()) return;
    const skIt = kbGet(skVK) orelse return;
    if (!skIt.isReleased()) return;
    activeModAdd(pkVK);
    pkIt.sf(FLAG_MOD_ACT | FLAG_MOD_TRIG);
    sendModifiedKey(skVK);
    // sendKeyDirect sent modifier down+up as a complete pair — clear MOD_ACT so
    // the next keypress doesn't re-enter the active-mod path and so key-up
    // doesn't emit a spurious extra modifier-up stroke.
    pkIt.cf(FLAG_MOD_ACT);
    pkIt.actionType = .modifier_used;
    activeModRemove(pkVK);
    _ = kbRemove(skVK);
    removeFromKeyOrder(skVK);
    processQueue();
}
// ============================================================================
// Section 17 — processQueue
// ============================================================================
fn processQueue() void {
    // Remove stale active modifiers (keys that left the buffer without cleanup)
    {
        var toDelete: [ACTIVE_MOD_MAX]i32 = undefined;
        var tdCount: usize = 0;
        for (0..@intCast(g_activeModCount)) |i|
            if (!kbContains(g_activeMods[i])) {
                toDelete[tdCount] = g_activeMods[i];
                tdCount += 1;
            };
        for (toDelete[0..tdCount]) |vk| activeModRemove(vk);
    }
    while (g_ordLen > 0) {
        const firstVK = ordAt(0);
        const keyData = kbGet(firstVK) orelse {
            ordRemoveFirst();
            continue;
        };
        if (!keyData.isReleased()) break;
        // Resolve undecided action
        if (keyData.actionType == .undecided) {
            if (keyData.isModifier() and keyData.modifierActivated() and !keyData.modifierTriggered()) {
                var hasOtherUnrel = false;
                var anyUsed = false;
                var hasUnreleased = false;
                var wasQuickStack = false;
                for (0..g_kbLen) |i| {
                    const pvk = g_kbVK[i];
                    const pd = &g_kbData[i];
                    if (pvk != firstVK) {
                        if (pd.isModifier() and !pd.isReleased() and pd.modifierActivated()) hasOtherUnrel = true;
                        if (!pd.isReleased()) hasUnreleased = true;
                    }
                    if ((pd.isModifier() and pd.modifierActivated() and pd.modifierTriggered()) or pd.comboTriggered())
                        anyUsed = true;
                    if (!wasQuickStack and pvk != firstVK and
                        (keyData.releaseTime - keyData.downTime) < g_SingleKeyHoldThreshold and
                        pd.isModifier() and pd.isReleased() and
                        @abs(pd.downTime - keyData.downTime) < g_ModifierThreshold and
                        @abs(pd.releaseTime - keyData.releaseTime) < g_SingleKeyHoldThreshold and
                        (pd.releaseTime - pd.downTime) < g_SingleKeyHoldThreshold)
                        wasQuickStack = true;
                }
                if (hasOtherUnrel) break;
                // If another modifier was held simultaneously with this one (quick chord),
                // treat both as modifier_used rather than emitting spurious taps.
                if (!anyUsed and !hasUnreleased) {
                    var hadSimultaneousMod = false;
                    for (0..g_kbLen) |i| {
                        const pd = &g_kbData[i];
                        if (g_kbVK[i] != firstVK and pd.isModifier() and pd.isReleased() and
                            @abs(pd.downTime - keyData.downTime) < g_SingleKeyHoldThreshold and
                            @abs(pd.releaseTime - keyData.releaseTime) < g_SingleKeyHoldThreshold)
                        {
                            hadSimultaneousMod = true;
                            break;
                        }
                    }
                    if (hadSimultaneousMod) {
                        keyData.actionType = .modifier_used;
                        // also mark the sibling
                        for (0..g_kbLen) |i| {
                            const pd = &g_kbData[i];
                            if (g_kbVK[i] != firstVK and pd.isModifier() and pd.isReleased() and
                                @abs(pd.downTime - keyData.downTime) < g_SingleKeyHoldThreshold)
                                pd.actionType = .modifier_used;
                        }
                        continue; // skip to next ordAt(0)
                    }
                }
                keyData.actionType = if (wasQuickStack and !anyUsed and !hasUnreleased) .tap else if (!anyUsed and !keyData.modifierActivated()) blk2: {
                    // Two modifiers pressed+released together with nothing else
                    // (e.g. a+s alone): suppress spurious taps so neither fires
                    // its hold or tap action.
                    var hadSiblingMod = false;
                    for (0..g_kbLen) |si| {
                        const spd = &g_kbData[si];
                        if (g_kbVK[si] != firstVK and spd.isModifier() and spd.isReleased() and
                            @abs(spd.downTime - keyData.downTime) < g_SingleKeyHoldThreshold and
                            @abs(spd.releaseTime - keyData.releaseTime) < g_SingleKeyHoldThreshold)
                        {
                            hadSiblingMod = true;
                            break;
                        }
                    }
                    break :blk2 if (hadSiblingMod) .modifier_used else .tap;
                } else .modifier_used;
            }
            if (keyData.actionType == .undecided and !keyData.isModifier()) {
                var needWait = false;
                for (0..g_kbLen) |i| {
                    const evk = g_kbVK[i];
                    const ekd = &g_kbData[i];
                    if (!ekd.isReleased() and ekd.downTime < keyData.downTime) {
                        if (ekd.modifierTriggered() or ekd.comboTriggered()) continue;
                        if ((ekd.isModifier() and !ekd.modifierActivated()) or
                            (hasCombo(evk, firstVK) and !ekd.modifierActivated()) or
                            hasInstantCombo(evk, firstVK))
                        {
                            needWait = true;
                            break;
                        }
                    }
                }
                if (needWait) break;
                const dur = keyData.releaseTime - keyData.downTime;
                if (keyData.modifierPressed()) {
                    keyData.actionType = .none;
                } else {
                    const hasHold = g_holdCallbacks.contains(firstVK);
                    keyData.actionType = if (hasHold and dur > g_MaxHoldThreshold)
                        (if (g_MaxThresholdSupress) .none else .tap)
                    else if (!hasHold and !keyData.hasInterferingKeys()) .tap else if (keyData.hasInterferingKeys() or dur < g_SingleKeyHoldThreshold or !hasHold) .tap else .hold;
                }
            }
        }
        const actionCopy = keyData.actionType;
        const comboTrigCpy = keyData.comboTriggered();
        const keyDownTime = keyData.downTime;
        ordRemoveFirst();
        _ = kbRemove(firstVK);
        if (comboTrigCpy or actionCopy == .modifier_used or actionCopy == .none) continue;
        const firstName = getNameFromVK(firstVK) orelse continue;
        if (actionCopy == .tap) {
            // Build modifier prefix from long-held modifiers
            var pfx: [8]u16 = [_]u16{0} ** 8;
            var seen: u8 = 0;
            var pi: usize = 0;
            for (0..g_kbLen) |i| {
                const evk = g_kbVK[i];
                const ekd = &g_kbData[i];
                if (ekd.downTime >= keyDownTime) continue;
                if (ekd.downTime + g_ModifierThreshold > keyDownTime) continue;
                switch (getModTypeForVK(evk)) {
                    MOD_CTRL => {
                        if (seen & 0x01 == 0 and pi < 7) {
                            seen |= 0x01;
                            pfx[pi] = '^';
                            pi += 1;
                        }
                    },
                    MOD_ALT => {
                        if (seen & 0x02 == 0 and pi < 7) {
                            seen |= 0x02;
                            pfx[pi] = '!';
                            pi += 1;
                        }
                    },
                    MOD_SHIFT => {
                        if (seen & 0x04 == 0 and pi < 7) {
                            seen |= 0x04;
                            pfx[pi] = '+';
                            pi += 1;
                        }
                    },
                    MOD_WIN => {
                        if (seen & 0x08 == 0 and pi < 7) {
                            seen |= 0x08;
                            pfx[pi] = '#';
                            pi += 1;
                        }
                    },
                    else => {},
                }
            }
            queueCallback(-4, firstName, @ptrCast(&pfx), 4);
        } else if (actionCopy == .hold) {
            // A contaminated key was held past the threshold but another key was
            // pressed while it was buffered — not a deliberate solo hold.  Skip
            // the hold callback entirely; the key simply disappears (modifier_used
            // semantics without emitting anything).
            if (keyData.isContaminated()) continue;
            if (g_holdCallbacks.get(firstVK)) |cbId|
                queueCallback(cbId, firstName, @ptrCast(&[_:0]u16{0}), 0)
            else
                queueCallback(-4, firstName, @ptrCast(&[_:0]u16{0}), 4);
        }
    }
}
// ============================================================================
// Section 18 — bufferKeyDown
// ============================================================================
fn bufferKeyDown(keyName: [*:0]const u16) void {
    const profT = profStart();
    defer profRecord(&g_profiling.keyDownProcessing, profT);
    const currentTime = getTime();
    const keyVK = getVKFromName(keyName);
    if (keyVK == 0) return;
    const nameRef = getNameFromVK(keyVK) orelse return;
    // Evict stale released entry so duplicate-key path doesn't suppress kdtPut.
    if (kbGet(keyVK)) |ex| {
        if (ex.isReleased()) {
            _ = kbRemove(keyVK);
            removeFromKeyOrder(keyVK);
        }
    }
    // Double-tap repeat check
    if (g_unrelModCount == 0) {
        if (kutGet(keyVK)) |upTime| {
            var otherHeld = false;
            for (0..g_kbLen) |i| {
                if (!g_kbData[i].isReleased()) {
                    otherHeld = true;
                    break;
                }
            }
            if (currentTime - upTime < g_DoubleTapThreshold and !otherHeld) {
                kutRemove(keyVK);
                stopRepeatThread();
                @atomicStore(i32, &g_repeatVK, keyVK, .release);
                @atomicStore(i32, &g_repeatActive, 1, .release);
                g_repeatHandle = CreateThread(null, 0, repeatThreadProc, null, 0, null);
                if (getModTypeForVK(keyVK) != MOD_NONE and g_unrelModCount > 0) g_unrelModCount -= 1;
                _ = kbRemove(keyVK);
                removeFromKeyOrder(keyVK);
                return;
            }
            kutRemove(keyVK);
        }
    } else {
        kutRemove(keyVK);
    }
    kdtPut(keyVK, currentTime);
    const inQuietPeriod = (currentTime - g_lastKeyTime) < g_ComboQuietDuration;
    if (!inQuietPeriod) g_typingMode = false;
    g_lastKeyTime = currentTime;
    const modType = getModTypeForVK(keyVK);
    const isModKey = (modType != MOD_NONE);
    // Stamp FLAG_CONTAMINATED on every modifier-role key that is currently
    // buffered and undecided.  We do this here — before any early-return path —
    // so it covers the held-past-threshold path, the intentional-chord path, the
    // active-mod path, and every other shortcut that would otherwise bypass the
    // universal fallthrough stamp we had before.  Only non-modifier keypresses
    // contaminate; modifier+modifier stacking is handled by its own logic.
    if (!isModKey) {
        for (0..g_kbLen) |_csi| {
            const _ekd = &g_kbData[_csi];
            if (_ekd.isModifier() and !_ekd.isReleased() and
                _ekd.actionType == .undecided and
                g_kbVK[_csi] != keyVK)
            {
                _ekd.sf(FLAG_CONTAMINATED);
            }
        }
    }
    for (g_ignoredKeys[0..g_ignoredKeysLen]) |iv| if (iv == keyVK) return;
    const sysBit = getSysModBit(keyName);
    if (sysBit != 0) {
        g_modBitmask |= sysBit;
        return;
    }
    if (g_modBitmask > 0) return;
    const keyExists = kbContains(keyVK);
    const unrelMods = countUnreleasedModifiers();
    // Single combined pass: compute hasNonModKeys AND check instant combos.
    var hasNonModKeys = false;
    var instantTriggered = false;
    for (0..g_kbLen) |i| {
        const evk = g_kbVK[i];
        const ekd = &g_kbData[i];
        if (ekd.isReleased()) continue;
        if (!ekd.isModifier()) hasNonModKeys = true;
        if (!instantTriggered and hasInstantCombo(evk, keyVK)) {
            const pkName = getNameFromVK(evk) orelse continue;
            triggerInstantCombo(evk, pkName, nameRef, nameRef);
            instantTriggered = true;
        }
        if (hasNonModKeys and instantTriggered) break;
    }
    if (instantTriggered) return;
    // PRIORITY 1.2: INTERNAL / EXTERNAL CHORDS
    // Fires before the intentional-chord path so an explicit 3-key remap wins.
    // Internal chord held keys are marked but NOT removed so the trigger key
    // can be pressed again while primary keys remain held (repeat support).
    // External chords guard against OS key-repeat by checking kbContains.
    if (g_internalChords.count() > 0 or g_externalChords.count() > 0) {
        var heldVKs: [5]i32 = [_]i32{0} ** 5;
        var heldCount: usize = 0;
        for (0..g_kbLen) |i| {
            const ekd = &g_kbData[i];
            if (!ekd.isReleased() and heldCount < 5) {
                heldVKs[heldCount] = g_kbVK[i];
                heldCount += 1;
            }
        }
        if (heldCount >= 1 and heldCount <= 4) {
            // ── NEW: early repeat handling for internal chords ──
            // When the trigger key is already in the buffer (autorepeat while
            // primaries are still held) we build the chord key from the *current*
            // held set only. This gives exactly the same ck that was registered
            // (e.g. asl → heldCount=3). The old path built len=4 and missed the
            // lookup, falling through to normal modifier handling → ^+l spam.
            if (kbContains(keyVK)) {
                var chordVKsRepeat: [5]i32 = [_]i32{0} ** 5;
                var rLen: usize = 0;
                for (heldVKs[0..heldCount]) |v| {
                    chordVKsRepeat[rLen] = v;
                    rLen += 1;
                }
                // sort for canonical lookup
                var si: usize = 0;
                while (si < rLen - 1) : (si += 1) {
                    var sj: usize = 0;
                    while (sj < rLen - si - 1) : (sj += 1) {
                        if (chordVKsRepeat[sj] > chordVKsRepeat[sj + 1]) {
                            const tmp = chordVKsRepeat[sj];
                            chordVKsRepeat[sj] = chordVKsRepeat[sj + 1];
                            chordVKsRepeat[sj + 1] = tmp;
                        }
                    }
                }
                var ckRepeat: u64 = @as(u64, @intCast(chordVKsRepeat[0])) | (@as(u64, @intCast(chordVKsRepeat[1])) << 16);
                if (rLen >= 3) ckRepeat |= (@as(u64, @intCast(chordVKsRepeat[2])) << 32);
                if (rLen >= 4) ckRepeat |= (@as(u64, @intCast(chordVKsRepeat[3])) << 48);
                if (rLen >= 5) ckRepeat ^= @as(u64, @intCast(chordVKsRepeat[4]));
                if (g_internalChords.get(ckRepeat)) |chord| {
                    if (chord.keyCount == @as(u8, @intCast(rLen))) {
                        sendKeyDirect(chord.targetVK, chord.modMask);
                        return;
                    }
                }
            }
            // ── original first-press path (unchanged) ──
            var chordVKs: [5]i32 = [_]i32{0} ** 5;
            var chordLen: usize = 0;
            for (heldVKs[0..heldCount]) |v| {
                chordVKs[chordLen] = v;
                chordLen += 1;
            }
            chordVKs[chordLen] = keyVK;
            chordLen += 1;
            var si: usize = 0;
            while (si < chordLen - 1) : (si += 1) {
                var sj: usize = 0;
                while (sj < chordLen - si - 1) : (sj += 1) {
                    if (chordVKs[sj] > chordVKs[sj + 1]) {
                        const tmp = chordVKs[sj];
                        chordVKs[sj] = chordVKs[sj + 1];
                        chordVKs[sj + 1] = tmp;
                    }
                }
            }
            var ck: u64 = @as(u64, @intCast(chordVKs[0])) | (@as(u64, @intCast(chordVKs[1])) << 16);
            if (chordLen >= 3) ck |= (@as(u64, @intCast(chordVKs[2])) << 32);
            if (chordLen >= 4) ck |= (@as(u64, @intCast(chordVKs[3])) << 48);
            if (chordLen >= 5) ck ^= @as(u64, @intCast(chordVKs[4]));
            if (g_internalChords.get(ck)) |chord| {
                if (chord.keyCount == @as(u8, @intCast(chordLen))) {
                    // FIRST PRESS path (unchanged)
                    for (heldVKs[0..heldCount]) |v| cancelKeyTimers(v);
                    for (heldVKs[0..heldCount]) |v| {
                        activeModRemove(v);
                        if (kbGet(v)) |kd| {
                            // FIX: Stamp FLAG_COMBO_RPT on the held keys so they delete cleanly!
                            kd.sf(FLAG_COMBO_TRIG | FLAG_COMBO_RPT | FLAG_MOD_ACT | FLAG_MOD_TRIG);
                            kd.actionType = .modifier_used;
                        }
                    }
                    var ndTrig = KeyData{};
                    ndTrig.downTime = currentTime;
                    // FIX: Ensure trigger key also gets it
                    ndTrig.sf(FLAG_COMBO_TRIG | FLAG_COMBO_RPT);
                    kbPut(keyVK, ndTrig);
                    ordAppend(keyVK);
                    sendKeyDirect(chord.targetVK, chord.modMask);
                    queueCallbackEmpty(-4, 4);
                    return;
                }
            } else if (g_externalChords.get(ck)) |extChord| {
                if (extChord.keyCount == @as(u8, @intCast(chordLen))) {
                    if (kbContains(keyVK)) return;
                    for (heldVKs[0..heldCount]) |v| cancelKeyTimers(v);
                    for (heldVKs[0..heldCount]) |v| {
                        activeModRemove(v);
                        if (kbGet(v)) |kd| kd.sf(FLAG_COMBO_TRIG | FLAG_MOD_ACT | FLAG_MOD_TRIG);
                    }
                    queueCallback(extChord.callbackId, nameRef, @ptrCast(&[_:0]u16{0}), 5);
                    return;
                }
            }
        }
    }
    // ============================================================================
    // PRIORITY 1.5: INTENTIONAL CHORD (2+ clean unreleased mods + incoming key)
    // We now skip the immediate send when the incoming key is itself a modifier.
    // Pure modifier stacks (as, asf, etc.) will no longer fire on key-down.
    // They will only fire on the final lift via the proactive blocks in KeyUp.
    // This eliminates the repeated ^s while holding as, and the weird ^s/^ +s mix.
    var cleanUnrelMods: i32 = 0;
    for (0..g_kbLen) |i| {
        const ekd = &g_kbData[i];
        if (ekd.isModifier() and !ekd.isReleased() and !ekd.hasInterferingKeys()) cleanUnrelMods += 1;
    }
    // If 2+ clean modifier keys are held and a non-modifier arrives, this is an
    // intentional chord regardless of whether we were recently typing.
    // Clear g_typingMode here so previous typing doesn't block the shortcut.
    if (cleanUnrelMods >= 2 and !isModKey) g_typingMode = false;
    if (cleanUnrelMods >= 2 and !hasNonModKeys and !g_typingMode and !isModKey) {
        // Do NOT fire intentional chord if the held modifier pair is a known
        // prefix of a registered external chord (e.g. a+d while a+d+k is
        // registered). We must wait for the trigger key, not send ^#d immediately.
        var isExternalChordPrefix = false;
        if (g_externalChords.count() > 0) {
            // Collect held modifier VKs
            var heldModVKs: [5]i32 = [_]i32{0} ** 5;
            var hmCount: usize = 0;
            for (0..g_kbLen) |i| {
                const ekd = &g_kbData[i];
                if (ekd.isModifier() and !ekd.isReleased() and !ekd.hasInterferingKeys() and hmCount < 5) {
                    heldModVKs[hmCount] = g_kbVK[i];
                    hmCount += 1;
                }
            }
            // Check every registered external chord — if its VKs are a superset
            // of the currently held mods, we are waiting for the trigger key.
            var ecIt = g_externalChords.iterator();
            outer: while (ecIt.next()) |entry| {
                const chordKey = entry.key_ptr.*;
                const ec = entry.value_ptr.*;
                if (@as(usize, ec.keyCount) <= hmCount) continue; // chord is same size or smaller, not a prefix
                // Decode the chord's VKs from the packed key
                var ecVKs: [5]i32 = [_]i32{0} ** 5;
                ecVKs[0] = @intCast(chordKey & 0xFFFF);
                ecVKs[1] = @intCast((chordKey >> 16) & 0xFFFF);
                if (ec.keyCount >= 3) ecVKs[2] = @intCast((chordKey >> 32) & 0xFFFF);
                if (ec.keyCount >= 4) ecVKs[3] = @intCast((chordKey >> 48) & 0xFFFF);
                // Check all held mods are present in this chord's VK list
                for (heldModVKs[0..hmCount]) |hv| {
                    var found = false;
                    for (ecVKs[0..ec.keyCount]) |ev| if (ev == hv) {
                        found = true;
                        break;
                    };
                    if (!found) continue :outer;
                }
                isExternalChordPrefix = true;
                break;
            }
        }
        if (!isExternalChordPrefix) {
            var isSameModPartner = false;
            if (isModKey) {
                for (0..g_kbLen) |i| {
                    if (g_kbData[i].isModifier() and !g_kbData[i].isReleased() and
                        getModTypeForVK(g_kbVK[i]) == modType)
                    {
                        isSameModPartner = true;
                        break;
                    }
                }
            }
            if (!isModKey or isSameModPartner) {
                for (0..g_kbLen) |i| {
                    const ekd = &g_kbData[i];
                    if (ekd.isModifier() and !ekd.isReleased() and
                        !ekd.modifierActivated() and !ekd.hasInterferingKeys())
                        cancelKeyTimers(g_kbVK[i]);
                }
                var seen2: u8 = 0;
                var modMask: u16 = 0;
                for (0..g_kbLen) |i| {
                    const evk = g_kbVK[i];
                    const ekd = &g_kbData[i];
                    if (!ekd.isModifier() or ekd.isReleased() or ekd.hasInterferingKeys()) continue;
                    switch (getModTypeForVK(evk)) {
                        MOD_CTRL => {
                            if (seen2 & 0x01 == 0) {
                                seen2 |= 0x01;
                                modMask |= 0x01;
                            }
                        },
                        MOD_ALT => {
                            if (seen2 & 0x02 == 0) {
                                seen2 |= 0x02;
                                modMask |= 0x02;
                            }
                        },
                        MOD_SHIFT => {
                            if (seen2 & 0x04 == 0) {
                                seen2 |= 0x04;
                                modMask |= 0x04;
                            }
                        },
                        MOD_WIN => {
                            if (seen2 & 0x08 == 0) {
                                seen2 |= 0x08;
                                modMask |= 0x08;
                            }
                        },
                        else => {},
                    }
                }
                sendKeyDirect(keyVK, modMask);
                queueCallbackEmpty(-4, 4);
                // sendKeyDirect sent a complete mod↓ key↓ key↑ mod↑ pair.
                // Mark as modifier_used so processQueue skips tap/hold — but do NOT
                // set FLAG_MOD_ACT, which would cause HOMEROW MODIFIER RELEASE to
                // send a second spurious modifier key-up on release.
                for (0..g_kbLen) |i| {
                    const ekd = &g_kbData[i];
                    if (ekd.isModifier() and !ekd.isReleased()) {
                        ekd.sf(FLAG_MOD_TRIG);
                        ekd.actionType = .modifier_used;
                    }
                }
                return;
            }
        } // end if (!isExternalChordPrefix)
    }
    // Quiet period contamination
    if (inQuietPeriod) {
        const hasBypass: bool = blk: {
            if (g_unrelModCount >= 1 and !isModKey) break :blk true;
            if (g_unrelModCount >= 2 and isModKey) break :blk true;
            if (isModKey and g_unrelModCount == 0) break :blk true;
            for (0..g_kbLen) |i| {
                const evk = g_kbVK[i];
                const ekd = &g_kbData[i];
                if (!ekd.isReleased()) {
                    if (hasCombo(evk, keyVK) or hasInstantCombo(evk, keyVK)) break :blk true;
                    if (isModKey and ekd.isModifier()) break :blk true;
                }
            }
            break :blk false;
        };
        if (!hasBypass) {
            if (!isModKey) g_typingMode = true;
            timerClear();
            for (0..g_kbLen) |i| {
                const ekd = &g_kbData[i];
                ekd.sf(FLAG_INTERFERING);
                ekd.sameModTidHash = 0;
                ekd.tidCount = 0;
            }
            var nd = KeyData{};
            nd.downTime = currentTime;
            nd.sf(FLAG_INTERFERING | FLAG_QUIET);
            nd.bf(FLAG_IS_MOD, isModKey);
            kbPut(keyVK, nd);
            ordAppend(keyVK);
            if (g_ordLen > @as(usize, @intCast(g_MaxBufferSize))) {
                const f = ordAt(0);
                ordRemoveFirst();
                _ = kbRemove(f);
            }
            return;
        }
    }
    // PRIORITY 2: COMBO REPEAT MODE
    if (unrelMods < 2) {
        var otherUnrel: i32 = 0;
        for (0..g_kbLen) |i| {
            const ekd = &g_kbData[i];
            if (ekd.isModifier() and !ekd.isReleased() and !ekd.inComboRepeatMode()) otherUnrel += 1;
        }
        if (otherUnrel == 0) {
            for (0..g_kbLen) |i| {
                const evk = g_kbVK[i];
                const ekd = &g_kbData[i];
                if (ekd.inComboRepeatMode() and !ekd.isReleased() and hasCombo(evk, keyVK)) {
                    const pkN = getNameFromVK(evk) orelse continue;
                    triggerComboImmediate(evk, keyVK, pkN, nameRef, nameRef);
                    return;
                }
            }
        }
    }
    // DUPLICATE KEY
    if (keyExists) {
        if (!isModKey) g_typingMode = true;
        const shouldContaminate = hasNonModKeys or !isModKey or g_typingMode;
        if (shouldContaminate) {
            timerClear();
            for (0..g_kbLen) |i| {
                const ekd = &g_kbData[i];
                if (g_unrelModCount >= 1 and ekd.isModifier() and !ekd.isReleased()) continue;
                ekd.sf(FLAG_INTERFERING);
                ekd.sameModTidHash = 0;
                ekd.tidCount = 0;
            }
        }
        var nd2 = KeyData{};
        nd2.downTime = currentTime;
        nd2.bf(FLAG_INTERFERING, shouldContaminate);
        nd2.bf(FLAG_IS_MOD, isModKey);
        nd2.bf(FLAG_QUIET, inQuietPeriod);
        kbPut(keyVK, nd2);
        ordAppend(keyVK);
        if (g_ordLen > @as(usize, @intCast(g_MaxBufferSize))) {
            const f = ordAt(0);
            ordRemoveFirst();
            _ = kbRemove(f);
        }
        return;
    }
    // PRIORITY 3: REGULAR COMBOS (non-instant)
    // True retro-combo style:
    // - On secondary down: do nothing, just mark primary and let both keys stay buffered
    // - On secondary up: if primary is still held → fire combo once
    // No retro timer is scheduled for normal combos anymore. This eliminates double-firing.
    if (unrelMods < 2) {
        for (0..g_kbLen) |i| {
            const evk = g_kbVK[i]; // primary
            const ekd = &g_kbData[i];
            if (!ekd.isReleased() and !ekd.hasInterferingKeys() and hasCombo(evk, keyVK)) {
                const pkN = getNameFromVK(evk) orelse continue;
                const ck = makeComboKey(evk, keyVK);
                const primaryElapsed = currentTime - ekd.downTime;

                const isInternalInstant = if (g_internalCombos.get(ck)) |remap| remap.isInstant else false;

                if (isInternalInstant) {
                    triggerComboImmediate(evk, keyVK, pkN, nameRef, nameRef);
                    return;
                } else if (primaryElapsed >= g_SingleKeyHoldThreshold) {
                    // Primary already long-held → fire immediately and stop.
                    // Do NOT fall through — the secondary must not be buffered
                    // or the retro check on its release will fire a second send.
                    triggerComboImmediate(evk, keyVK, pkN, nameRef, nameRef);
                    return;
                } else {
                    // Normal retro case: mark primary so we can detect it on secondary release.
                    // Fall through so the secondary key gets buffered normally.
                    if (kbGet(evk)) |primaryKey| {
                        primaryKey.sf(FLAG_COMBO_TRIG);
                    }
                }
            }
        }
    }
    // ACTIVE HOMEROW MODIFIERS
    if (g_activeModCount > 0) {
        if (g_activeModCount == 1) {
            const modVK = g_activeMods[0];
            if (kbGet(modVK)) |md| {
                if (!md.isReleased()) {
                    if (hasInstantCombo(modVK, keyVK)) {
                        const pkN = getNameFromVK(modVK) orelse return;
                        triggerInstantCombo(modVK, pkN, nameRef, nameRef);
                        return;
                    }
                    if (hasCombo(modVK, keyVK)) {
                        const pkN = getNameFromVK(modVK) orelse return;
                        triggerComboImmediate(modVK, keyVK, pkN, nameRef, nameRef);
                        return;
                    }
                }
            }
        }
        // Held-past-threshold keys
        for (0..g_kbLen) |i| {
            const evk = g_kbVK[i];
            const ekd = &g_kbData[i];
            if (ekd.isReleased() or (currentTime - ekd.downTime) < g_SingleKeyHoldThreshold) continue;
            if (hasCombo(evk, keyVK)) {
                const pkN = getNameFromVK(evk) orelse continue;
                triggerComboImmediate(evk, keyVK, pkN, nameRef, nameRef);
                return;
            }
        }
        if (isModKey) {
            for (0..@intCast(g_activeModCount)) |i| {
                const amod = g_activeMods[i];
                if (kbGet(amod)) |amd| {
                    if (!amd.isReleased() and hasCombo(amod, keyVK)) {
                        const pkN = getNameFromVK(amod) orelse continue;
                        triggerComboImmediate(amod, keyVK, pkN, nameRef, nameRef);
                        return;
                    }
                }
            }
            var modTypeActive = false;
            for (0..@intCast(g_activeModCount)) |i|
                if (getModTypeForVK(g_activeMods[i]) == modType) {
                    modTypeActive = true;
                    break;
                };
            if (modTypeActive) {
                sendModifiedKey(keyVK);
                // sendKeyDirect already sent modifier down+up as a complete pair.
                // Clear FLAG_MOD_ACT and remove from g_activeMods so that the next
                // keypress does not re-enter this path, and so key-up does not send
                // a second spurious modifier-up stroke via HOMEROW MODIFIER RELEASE.
                for (0..@as(usize, @intCast(g_activeModCount))) |ai| {
                    if (kbGet(g_activeMods[ai])) |amd| {
                        amd.sf(FLAG_MOD_TRIG);
                        amd.cf(FLAG_MOD_ACT);
                        amd.actionType = .modifier_used;
                    }
                }
                activeModClear();
                return;
            }
            activeModAdd(keyVK);
            if (kbGet(keyVK)) |ex| {
                ex.sf(FLAG_IS_MOD | FLAG_MOD_ACT);
            } else {
                var nd4 = KeyData{};
                nd4.downTime = currentTime;
                nd4.sf(FLAG_IS_MOD | FLAG_MOD_ACT);
                nd4.bf(FLAG_QUIET, inQuietPeriod);
                kbPut(keyVK, nd4);
                ordAppend(keyVK);
            }
            return;
        }
        sendModifiedKey(keyVK);
        for (0..@as(usize, @intCast(g_activeModCount))) |ai| {
            if (kbGet(g_activeMods[ai])) |amd| {
                amd.sf(FLAG_MOD_TRIG);
                amd.cf(FLAG_MOD_ACT);
                amd.actionType = .modifier_used;
            }
        }
        activeModClear();
        return;
    }
    // HELD PAST THRESHOLD (no active mods)
    if (unrelMods < 2) {
        for (0..g_kbLen) |i| {
            const evk = g_kbVK[i];
            const ekd = &g_kbData[i];
            if (ekd.isReleased() or (currentTime - ekd.downTime) < g_SingleKeyHoldThreshold) continue;
            if (hasInstantCombo(evk, keyVK)) {
                const pkN = getNameFromVK(evk) orelse continue;
                triggerInstantCombo(evk, pkN, nameRef, nameRef);
                return;
            }
            if (ekd.isModifier()) {
                if (hasCombo(evk, keyVK)) {
                    const pkN = getNameFromVK(evk) orelse continue;
                    triggerComboImmediate(evk, keyVK, pkN, nameRef, nameRef);
                    return;
                }
                if (!isModKey) {
                    activeModAdd(evk);
                    ekd.sf(FLAG_MOD_ACT);
                    sendModifiedKey(keyVK);
                    // sendKeyDirect sent modifier down+up as a complete pair.
                    // Clean up so the modifier doesn't re-fire on every subsequent
                    // keypress and so key-up doesn't emit a spurious extra modifier-up.
                    ekd.cf(FLAG_MOD_ACT);
                    ekd.sf(FLAG_MOD_TRIG);
                    ekd.actionType = .modifier_used;
                    activeModRemove(evk);
                    return;
                }
            }
        }
    }
    // SAME-MODIFIER KEYS
    if (isModKey) {
        if (unrelMods >= 2) {
            for (0..g_kbLen) |i| {
                const evk = g_kbVK[i];
                const ekd = &g_kbData[i];
                if (!ekd.isModifier() or ekd.isReleased()) continue;
                if (getModTypeForVK(evk) == modType) {
                    for (0..g_kbLen) |j| {
                        const e2 = &g_kbData[j];
                        if (e2.isModifier() and !e2.isReleased()) {
                            cancelKeyTimers(g_kbVK[j]);
                            activeModAdd(g_kbVK[j]);
                            e2.sf(FLAG_MOD_ACT | FLAG_MOD_TRIG);
                        }
                    }
                    sendModifiedKey(keyVK);
                    // sendKeyDirect sent every modifier down+up as a complete pair.
                    // Clear FLAG_MOD_ACT on all of them and drain g_activeMods so
                    // subsequent keypresses don't re-enter this block and so key-up
                    // doesn't emit a second spurious modifier-up per key.
                    for (0..g_kbLen) |jj| {
                        const e3 = &g_kbData[jj];
                        if (e3.isModifier() and !e3.isReleased()) {
                            e3.cf(FLAG_MOD_ACT);
                            e3.actionType = .modifier_used;
                        }
                    }
                    activeModClear();
                    return;
                }
            }
        }
        if (unrelMods < 2) {
            for (0..g_kbLen) |i| {
                const evk = g_kbVK[i];
                const ekd = &g_kbData[i];
                if (!ekd.isModifier() or ekd.isReleased() or ekd.modifierActivated()) continue;
                if (getModTypeForVK(evk) != modType) continue;
                const timeDiff = currentTime - ekd.downTime;
                if (timeDiff < g_SingleKeyHoldThreshold) {
                    var nd5 = KeyData{};
                    nd5.downTime = currentTime;
                    nd5.sf(FLAG_IS_MOD);
                    nd5.sameModPartnerVK = evk;
                    nd5.bf(FLAG_QUIET, inQuietPeriod);
                    kbPut(keyVK, nd5);
                    ordAppend(keyVK);
                    const remaining = @as(i32, @intFromFloat(g_SingleKeyHoldThreshold - timeDiff));
                    const pkN = getNameFromVK(evk) orelse return;
                    var tidBuf: [TID_LEN]u16 = [_]u16{0} ** TID_LEN;
                    const tidH = buildTid(&tidBuf, pkN, "_sameMod_", nameRef);
                    ekd.sameModTidHash = tidH;
                    queueTimer(&tidBuf, tidH, remaining, 1, pkN, nameRef, 0);
                    return;
                }
                activeModAdd(evk);
                ekd.sf(FLAG_MOD_ACT | FLAG_MOD_TRIG);
                sendModifiedKey(keyVK);
                // sendKeyDirect sent modifier down+up as a complete pair.
                ekd.cf(FLAG_MOD_ACT);
                ekd.actionType = .modifier_used;
                activeModRemove(evk);
                return;
            }
        }
    }
    // UNIVERSAL FALLTHROUGH — add key to buffer
    var nd6 = KeyData{};
    nd6.downTime = currentTime;
    nd6.bf(FLAG_IS_MOD, isModKey);
    nd6.bf(FLAG_QUIET, inQuietPeriod);
    kbPut(keyVK, nd6);
    ordAppend(keyVK);
    if (g_ordLen > @as(usize, @intCast(g_MaxBufferSize))) {
        const f = ordAt(0);
        ordRemoveFirst();
        _ = kbRemove(f);
    }
    if (isModKey) g_unrelModCount += 1;
}
// ============================================================================
// Section 19 — bufferKeyUp
// ============================================================================
fn bufferKeyUp(keyName: [*:0]const u16) void {
    const profT = profStart();
    defer profRecord(&g_profiling.keyUpProcessing, profT);
    const currentTime = getTime();
    const keyVK = getVKFromName(keyName);
    if (keyVK == 0) return;
    const nameRef = getNameFromVK(keyVK) orelse return;
    // Repeat thread active for this key — stop it and bail
    if (@atomicLoad(i32, &g_repeatActive, .acquire) != 0 and
        @atomicLoad(i32, &g_repeatVK, .acquire) == keyVK)
    {
        stopRepeatThread();
        kdtRemove(keyVK);
        kutRemove(keyVK);
        activeModRemove(keyVK);
        _ = kbRemove(keyVK);
        removeFromKeyOrder(keyVK);
        return;
    }
    // Double-tap tracking
    if (kdtGet(keyVK)) |dt| {
        const dur = currentTime - dt;
        const effUnrel = if (getModTypeForVK(keyVK) != MOD_NONE) g_unrelModCount - 1 else g_unrelModCount;
        if (dur < g_DoubleTapThreshold and effUnrel == 0) kutPut(keyVK, currentTime) else kutRemove(keyVK);
        kdtRemove(keyVK);
    }
    const modType = getModTypeForVK(keyVK);
    const isModKey = (modType != MOD_NONE);
    for (g_ignoredKeys[0..g_ignoredKeysLen], 0..) |iv, idx|
        if (iv == keyVK) {
            ignRemove(idx);
            return;
        };
    const keyIt = kbGet(keyVK) orelse return;
    activeModRemove(keyVK);
    const sysBit = getSysModBit(keyName);
    if (sysBit != 0) {
        g_modBitmask &= ~sysBit;
        return;
    }
    if (g_modBitmask > 0) return;
    const keyData = keyIt;
    keyData.sf(FLAG_RELEASED);
    keyData.releaseTime = currentTime;
    const duration = currentTime - keyData.downTime;
    if (keyData.isModifier() and g_unrelModCount > 0) g_unrelModCount -= 1;
    cancelKeyTimers(keyVK);

    // In bufferKeyUp, replace the existing comboTriggered() early-out:

    // In bufferKeyUp, replace the existing comboTriggered() early-out:
    if (keyData.comboTriggered()) {
        if (keyData.inComboRepeatMode()) {
            _ = kbRemove(keyVK);
            removeFromKeyOrder(keyVK);
            processQueue(); // FIX: Added processQueue so the keyboard never stalls
            return;
        }
        keyData.cf(FLAG_COMBO_TRIG);
    }

    // FIX: Move the Consumed Guard HERE so it catches ALL keys, not just modifiers!
    if (keyData.actionType == .modifier_used) {
        _ = kbRemove(keyVK);
        removeFromKeyOrder(keyVK);
        processQueue();
        return;
    }
    // Clear same-mod timer for partner (both directions)
    if (keyData.sameModPartnerVK != 0) {
        if (kbGet(keyData.sameModPartnerVK)) |pt| {
            if (pt.sameModTidHash != 0) {
                cancelTimer(pt.sameModTidHash);
                pt.sameModTidHash = 0;
            }
        }
    }
    // RETRO COMBO CHECK ON SECONDARY RELEASE
    // Fires the combo only when the secondary key is released, and only if:
    // - the primary is still held down
    // - we haven't already fired this combo
    if (!keyData.isModifier() and duration < g_SingleKeyHoldThreshold and !keyData.comboTriggered()) {
        for (0..g_kbLen) |i| {
            const pvk = g_kbVK[i];
            const pkd = &g_kbData[i];
            if (pkd.isReleased() or !pkd.comboTriggered()) continue;

            if (hasCombo(pvk, keyVK)) {
                const pkN = getNameFromVK(pvk) orelse continue;
                triggerComboImmediate(pvk, keyVK, pkN, nameRef, nameRef);
                keyData.sf(FLAG_COMBO_TRIG);
                pkd.sf(FLAG_COMBO_TRIG);
                return;
            }
        }
    }
    for (0..g_kbLen) |i| {
        const ekd = &g_kbData[i];
        if (ekd.sameModPartnerVK == keyVK and !ekd.isReleased()) {
            if (keyData.sameModTidHash != 0) {
                cancelTimer(keyData.sameModTidHash);
                keyData.sameModTidHash = 0;
            }
            break;
        }
    }
    // PROACTIVE SINGLE-MOD
    // Fires on any short-duration key release when exactly one modifier is held
    // before it. Handles both non-modifier keys (f up while a held → ^f) and
    // modifier keys of a different type (s=Shift up while a=Ctrl held → ^s).
    // ============================================================================
    // Section 19 — bufferKeyUp (PROACTIVE SINGLE-MOD / LIFT-TRIGGER)
    // ============================================================================
    // ---  (PROACTIVE SINGLE-MOD / LIFT-TRIGGER)
    if (duration < g_SingleKeyHoldThreshold) { // We why do we want this to only happen between ~175 ms of the first key (modifer down) and the second key (modifier or non-modifier) up? 1. Prevents accidental triggers when quickly tapping keys. 2. Ensures that the modifier is still logically held when the second key is released, so sendKeyDirect can detect it and build the correct modified output (e.g. ^s instead of just s).
        var singleModVK: i32 = 0;
        var unrelModsBeforeKey: usize = 0;

        for (0..g_kbLen) |i| {
            const evk = g_kbVK[i];
            const ekd = &g_kbData[i];
            if (!ekd.isModifier() or ekd.isReleased()) continue;
            if (ekd.downTime >= keyData.downTime) continue;
            unrelModsBeforeKey += 1;
            singleModVK = evk; // keep overwriting — last one wins, count is what matters
        }

        // Only fire when there is exactly one older unreleased modifier.
        // If there are 2+ the multi-mod proactive block below will handle it
        // and build the correct combined mask (e.g. ^! for Ctrl+Alt).
        if (unrelModsBeforeKey != 1) singleModVK = 0;

        if (singleModVK != 0) {
            const interactionDuration = currentTime - kbGet(singleModVK).?.downTime;

            if (interactionDuration < 1500.0) {
                const isDiffTypeMod = !isModKey or getModTypeForVK(singleModVK) != modType;

                if (isDiffTypeMod and !hasCombo(singleModVK, keyVK) and !hasInstantCombo(singleModVK, keyVK)) {

                    // 1. Build the modifier mask for sendKeyDirect
                    var modMask: u16 = 0;
                    switch (getModTypeForVK(singleModVK)) {
                        MOD_CTRL => modMask = 0x01,
                        MOD_ALT => modMask = 0x02,
                        MOD_SHIFT => modMask = 0x04,
                        MOD_WIN => modMask = 0x08,
                        else => {},
                    }

                    // 2. TRIGGER SHORTCUT
                    // sendKeyDirect emits: mod↓ key↓ key↑ mod↑ — a complete balanced pair.
                    // Do NOT send an extra mod↑ after this; a double key-up with no
                    // matching key-down confuses the interception driver and leaves Ctrl
                    // (or whichever modifier) stuck logically down.
                    sendKeyDirect(keyVK, modMask);
                    queueCallbackEmpty(-4, 4);

                    // 3. POISON THE STACK (pre-remove pass)
                    activeModRemove(singleModVK);
                    cancelKeyTimers(singleModVK);

                    keyData.actionType = .modifier_used;
                    cancelKeyTimers(keyVK);

                    // 4. CLEANUP
                    // NOTE: kbRemove uses swap-with-last compaction, so any pointer
                    // previously obtained via kbGet(singleModVK) may now point at the
                    // wrong slot.  We therefore remove keyVK first, then re-fetch
                    // singleModVK by VK index and re-apply the poison flags so the
                    // key-up handler for the modifier key sees them correctly.
                    _ = kbRemove(keyVK);
                    removeFromKeyOrder(keyVK);

                    // 4. Re-poison singleModVK after the compaction.
                    // FLAG_COMBO_TRIG is enough to trigger the comboTriggered() early-out
                    // in bufferKeyUp so the modifier key exits cleanly without firing hold.
                    // Do NOT set FLAG_MOD_ACT here — that flag means "a physical modifier
                    // key-up stroke must be sent on release", which is false because
                    // sendKeyDirect already closed the Ctrl↓/Ctrl↑ pair.  Setting it
                    // creates an inconsistency with g_activeMods (which had the key
                    // removed in step 3) that accumulates across rapid repeated presses
                    // and eventually corrupts the logical modifier state.
                    if (kbGet(singleModVK)) |sm| {
                        sm.actionType = .modifier_used;
                        sm.sf(FLAG_MOD_TRIG | FLAG_COMBO_TRIG);
                        sm.cf(FLAG_MOD_ACT); // ensure it is clear — sendKeyDirect closed the pair
                    }

                    // Ensure the bitmask is updated before processing the rest of the queue
                    g_modBitmask = 0; // Or calculate properly if other physical mods are down

                    processQueue();
                    return;
                }
            }
        }
    }
    // PROACTIVE MULTI-MOD
    if (duration < g_SingleKeyHoldThreshold or keyData.inSendModifiedRepeatMode()) {
        var quickMods: [8]i32 = undefined;
        var qmCount: usize = 0;

        for (0..g_kbLen) |i| {
            const evk = g_kbVK[i];
            const ekd = &g_kbData[i];
            if (!ekd.isModifier() or ekd.isReleased() or ekd.downTime >= keyData.downTime) continue;

            const timeDiff = keyData.downTime - ekd.downTime;
            const isQuickChord = timeDiff < g_ModifierThreshold;
            const isEstablished = timeDiff >= g_SingleKeyHoldThreshold or ekd.actionType == .modifier_used;

            if ((isQuickChord or isEstablished) and qmCount < 8) {
                quickMods[qmCount] = evk;
                qmCount += 1;
            }
        }

        if (qmCount >= 2) {
            var hasComboAny = false;
            for (quickMods[0..qmCount]) |qvk| {
                if (hasCombo(qvk, keyVK) or hasInstantCombo(qvk, keyVK)) {
                    hasComboAny = true;
                    break;
                }
            }

            if (!hasComboAny and !keyData.comboTriggered() and !keyData.modifierTriggered()) {
                for (quickMods[0..qmCount]) |qvk| cancelKeyTimers(qvk);

                var seen3: u8 = 0;
                var multiModMask: u16 = 0;
                for (quickMods[0..qmCount]) |qvk| {
                    switch (getModTypeForVK(qvk)) {
                        MOD_CTRL => if (seen3 & 0x01 == 0) {
                            seen3 |= 0x01;
                            multiModMask |= 0x01;
                        },
                        MOD_ALT => if (seen3 & 0x02 == 0) {
                            seen3 |= 0x02;
                            multiModMask |= 0x02;
                        },
                        MOD_SHIFT => if (seen3 & 0x04 == 0) {
                            seen3 |= 0x04;
                            multiModMask |= 0x04;
                        },
                        MOD_WIN => if (seen3 & 0x08 == 0) {
                            seen3 |= 0x08;
                            multiModMask |= 0x08;
                        },
                        else => {},
                    }
                }

                for (quickMods[0..qmCount]) |qvk| {
                    if (kbGet(qvk)) |qm| {
                        qm.sf(FLAG_MOD_TRIG);
                        if (qm.actionType != .modifier_used) {
                            qm.cf(FLAG_MOD_ACT);
                            qm.actionType = .modifier_used;
                        }
                    }
                }

                keyData.sf(FLAG_SEND_MODIFIED_REPEAT);
                sendKeyDirect(keyVK, multiModMask);
                _ = kbRemove(keyVK);
                removeFromKeyOrder(keyVK);
                return;
            }
        }
        // } // end PROACTIVE MULTI-MOD guard

        // MULTI-MOD CHORD (2+ unreleased mods older than this key, internal remap path)
        // var quickMods: [8]i32 = undefined;
        // var qmCount: usize = 0;
        for (0..g_kbLen) |i| {
            const evk = g_kbVK[i];
            const ekd = &g_kbData[i];
            if (!ekd.isModifier() or ekd.isReleased() or ekd.downTime >= keyData.downTime) continue;
            if ((keyData.downTime - ekd.downTime) < g_ModifierThreshold and qmCount < 8) {
                quickMods[qmCount] = evk;
                qmCount += 1;
            }
        }
        if (qmCount >= 2) {
            var hasComboAny = false;
            for (quickMods[0..qmCount]) |qvk|
                if (hasCombo(qvk, keyVK) or hasInstantCombo(qvk, keyVK)) {
                    hasComboAny = true;
                    break;
                };
            if (!hasComboAny and !keyData.comboTriggered() and !keyData.modifierTriggered()) {
                for (quickMods[0..qmCount]) |qvk| cancelKeyTimers(qvk);
                var seen4: u8 = 0;
                var chordModMask: u16 = 0;
                for (quickMods[0..qmCount]) |qvk| {
                    switch (getModTypeForVK(qvk)) {
                        MOD_CTRL => if (seen4 & 0x01 == 0) {
                            seen4 |= 0x01;
                            chordModMask |= 0x01;
                        },
                        MOD_ALT => if (seen4 & 0x02 == 0) {
                            seen4 |= 0x02;
                            chordModMask |= 0x02;
                        },
                        MOD_SHIFT => if (seen4 & 0x04 == 0) {
                            seen4 |= 0x04;
                            chordModMask |= 0x04;
                        },
                        MOD_WIN => if (seen4 & 0x08 == 0) {
                            seen4 |= 0x08;
                            chordModMask |= 0x08;
                        },
                        else => {},
                    }
                }
                for (quickMods[0..qmCount]) |qvk| {
                    cancelKeyTimers(qvk);
                    if (kbGet(qvk)) |kd| {
                        kd.sf(FLAG_MOD_TRIG);
                        kd.cf(FLAG_MOD_ACT);
                        kd.actionType = .modifier_used;
                    }
                }
                cancelKeyTimers(keyVK);
                sendKeyDirect(keyVK, chordModMask);
                _ = kbRemove(keyVK);
                removeFromKeyOrder(keyVK);
                return;
            }
        }
    }
    // HOMEROW MODIFIER RELEASE
    if (keyData.isModifier()) {
        if (keyData.modifierActivated()) {
            // Send the correct modifier VK key-up (not the homerow key's own VK).
            // sendKeyDirect/sendModifiedKey always send complete down+up pairs and
            // clear FLAG_MOD_ACT immediately, so they never reach here with it set.
            // The only remaining case: key was stacked live as a modifier (modifier
            // down was sent as a real VK_CONTROL etc.) and is now being released.
            const modVK: u16 = switch (getModTypeForVK(keyVK)) {
                MOD_CTRL => VK_CONTROL,
                MOD_ALT => VK_MENU,
                MOD_SHIFT => VK_SHIFT,
                MOD_WIN => VK_LWIN,
                else => 0,
            };
            if (modVK != 0) {
                ringReset();
                ringAddKey(modVK, KEYEVENTF_KEYUP);
                ringSend();
            }
            activeModRemove(keyVK);
            keyData.cf(FLAG_MOD_ACT | FLAG_MOD_TRIG);
        }

        // If we already fired a combo and marked this as used,
        // we are done with this key. Clean up and exit.
        if (keyData.actionType == .modifier_used) {
            _ = kbRemove(keyVK);
            removeFromKeyOrder(keyVK);
            processQueue();
            return;
        }
        if (duration < g_SingleKeyHoldThreshold) {
            var totalUnrel: i32 = 1;
            var otherModsHeld: [8]i32 = undefined;
            var omhCount: usize = 0;
            for (0..g_kbLen) |i| {
                const evk = g_kbVK[i];
                const ekd = &g_kbData[i];
                if (evk == keyVK or ekd.isReleased()) continue;
                totalUnrel += 1;
                if (ekd.isModifier() and ekd.modifierActivated() and omhCount < 8) {
                    otherModsHeld[omhCount] = evk;
                    omhCount += 1;
                }
            }
            if (omhCount == 0) {
                for (0..g_kbLen) |i| {
                    const evk = g_kbVK[i];
                    const ekd = &g_kbData[i];
                    if (evk == keyVK or ekd.isReleased() or !ekd.isModifier()) continue;
                    if (isModKey and getModTypeForVK(evk) == modType) continue;
                    if (isModKey) continue;
                    const elapsed = currentTime - ekd.downTime;
                    if (elapsed >= g_SingleKeyHoldThreshold and !ekd.modifierActivated()) {
                        if (hasCombo(evk, keyVK) or hasInstantCombo(evk, keyVK)) continue;
                        if (ekd.releaseTime > 0) continue;
                        activeModAdd(evk);
                        ekd.sf(FLAG_MOD_ACT | FLAG_MOD_TRIG);
                        if (omhCount < 8) {
                            otherModsHeld[omhCount] = evk;
                            omhCount += 1;
                        }
                    }
                }
            }
            if (omhCount > 0) {
                if (totalUnrel == 2 and omhCount == 1) {
                    const heldVK = otherModsHeld[0];
                    if (hasCombo(heldVK, keyVK) or hasInstantCombo(heldVK, keyVK)) {
                        const pkN = getNameFromVK(heldVK) orelse {
                            processQueue();
                            return;
                        };
                        triggerComboImmediate(heldVK, keyVK, pkN, nameRef, nameRef);
                        return;
                    }
                }
                for (otherModsHeld[0..omhCount]) |mv| if (kbGet(mv)) |mm| mm.sf(FLAG_MOD_TRIG);
                sendModifiedKey(keyVK);
                _ = kbRemove(keyVK);
                removeFromKeyOrder(keyVK);
                return;
            }
            // Same-type modifier chaining
            for (0..g_kbLen) |i| {
                const evk = g_kbVK[i];
                const ekd = &g_kbData[i];
                if (evk == keyVK or !ekd.isModifier() or !ekd.isReleased()) continue;
                if (ekd.downTime >= keyData.downTime) continue;
                if (getModTypeForVK(evk) != modType) continue;
                if ((keyData.downTime - ekd.downTime) < g_ModifierThreshold) {
                    if (!activeModContains(evk)) {
                        activeModAdd(evk);
                        ekd.sf(FLAG_MOD_ACT);
                    }
                    ekd.sf(FLAG_MOD_TRIG);
                    sendModifiedKey(keyVK);
                    _ = kbRemove(keyVK);
                    removeFromKeyOrder(keyVK);
                    return;
                }
            }
        }
        // Re-fetch (pointer may be invalidated by removals above)
        const kdR = kbGet(keyVK) orelse {
            processQueue();
            return;
        };
        if (duration < g_SingleKeyHoldThreshold and kdR.modifierActivated() and !kdR.modifierTriggered()) {
            var smCount: usize = 0;
            for (0..g_kbLen) |i| {
                const evk = g_kbVK[i];
                const ekd = &g_kbData[i];
                if (evk == keyVK) continue;
                if (ekd.isModifier() and ekd.modifierActivated() and !ekd.modifierTriggered() and
                    !ekd.isReleased() and @abs(ekd.downTime - kdR.downTime) < g_ModifierThreshold) smCount += 1;
            }
            if (smCount > 0) {
                processQueue();
                return;
            }
            kdR.actionType = .tap;
            processQueue();
            return;
        }
        const kdF = kbGet(keyVK) orelse {
            processQueue();
            return;
        };
        if (kdF.comboTriggered() or kdF.modifierTriggered()) {
            kdF.actionType = .modifier_used;
            processQueue();
            return;
        }
        if (kdF.modifierActivated() and !kdF.modifierTriggered()) {
            processQueue();
            return;
        }
        if (kdF.inQuietPeriod() and !kdF.modifierTriggered() and !kdF.comboTriggered()) {
            kdF.actionType = .tap;
            processQueue();
            return;
        }
        if (kdF.hasInterferingKeys() or duration < g_SingleKeyHoldThreshold) {
            kdF.actionType = .tap;
            processQueue();
            return;
        }
        if (duration > g_MaxHoldThreshold) {
            kdF.actionType = if (g_MaxThresholdSupress) .none else .tap;
            processQueue();
            return;
        }
        // If another key was pressed while this modifier-role key was buffered
        // undecided, it was not a deliberate solo hold — suppress the hold callback.
        if (kdF.isContaminated()) {
            kdF.actionType = .modifier_used;
            processQueue();
            return;
        }
        kdF.actionType = if (g_holdCallbacks.contains(keyVK)) .hold else .tap;
        processQueue();
        return;
    }
    // Skip retro paths if any other homerow modifier is still held
    for (0..g_kbLen) |i| {
        const evk = g_kbVK[i];
        const ekd = &g_kbData[i];
        if (evk != keyVK and ekd.isModifier() and !ekd.isReleased()) {
            processQueue();
            return;
        }
    }
    // RETROACTIVE MODIFIER ACTIVATION
    if (!keyData.comboTriggered() and !keyData.modifierPressed()) {
        var mta: [8]i32 = undefined;
        var mtaCount: usize = 0;
        for (0..g_kbLen) |i| {
            const evk = g_kbVK[i];
            const ekd = &g_kbData[i];
            if (!ekd.isModifier() or ekd.isReleased()) continue;
            if (hasCombo(evk, keyVK) or hasInstantCombo(evk, keyVK)) continue;
            if ((currentTime - ekd.downTime) < g_SingleKeyHoldThreshold) continue;
            if (mtaCount < 8) {
                mta[mtaCount] = evk;
                mtaCount += 1;
            }
        }
        if (mtaCount > 0) {
            for (mta[0..mtaCount]) |mv| {
                if (!activeModContains(mv)) {
                    activeModAdd(mv);
                    if (kbGet(mv)) |mm| mm.sf(FLAG_MOD_ACT);
                }
                if (kbGet(mv)) |mm| mm.sf(FLAG_MOD_TRIG);
            }
            sendModifiedKey(keyVK);
            _ = kbRemove(keyVK);
            removeFromKeyOrder(keyVK);
            return;
        }
    }
    // RETROACTIVE TIMER SCHEDULING
    if (!keyData.hasInterferingKeys()) {
        var unrelCount: i32 = 0;
        for (0..g_kbLen) |i| {
            if (!g_kbData[i].isReleased() and g_kbVK[i] != keyVK) unrelCount += 1;
        }
        if (unrelCount == 1) {
            for (0..g_kbLen) |i| {
                const evk = g_kbVK[i];
                const ekd = &g_kbData[i];
                if (ekd.isReleased() or ekd.downTime >= keyData.downTime) continue;
                if (!hasCombo(evk, keyVK) or hasInstantCombo(evk, keyVK)) continue;
                if ((currentTime - ekd.downTime) >= g_SingleKeyHoldThreshold) continue;
                // Primary was already marked in bufferKeyDown — retro check on secondary
                // release will handle it; don't schedule a timer that fires a second send.
                if (ekd.comboTriggered()) continue;
                const rem = @as(i32, @intFromFloat(g_SingleKeyHoldThreshold - (currentTime - ekd.downTime)));
                const pkN = getNameFromVK(evk) orelse continue;
                var tidBuf: [TID_LEN]u16 = [_]u16{0} ** TID_LEN;
                const tidH = buildTid(&tidBuf, pkN, "_retroCombo_", nameRef);
                queueTimer(&tidBuf, tidH, rem, 2, pkN, nameRef, 0);
            }
        }
        for (0..g_kbLen) |i| {
            const evk = g_kbVK[i];
            const ekd = &g_kbData[i];
            if (!ekd.isModifier() or ekd.isReleased() or ekd.modifierActivated()) continue;
            if (hasCombo(evk, keyVK) or hasInstantCombo(evk, keyVK)) continue;
            if ((currentTime - ekd.downTime) >= g_SingleKeyHoldThreshold) continue;
            const rem = @as(i32, @intFromFloat(g_SingleKeyHoldThreshold - (currentTime - ekd.downTime)));
            const pkN = getNameFromVK(evk) orelse continue;
            var tidBuf: [TID_LEN]u16 = [_]u16{0} ** TID_LEN;
            const tidH = buildTid(&tidBuf, pkN, "_retroMod_", nameRef);
            queueTimer(&tidBuf, tidH, rem, 3, pkN, nameRef, 0);
        }
    }
    // FAST PATH — short unambiguous tap
    if (duration < g_SingleKeyHoldThreshold and !keyData.hasInterferingKeys() and !keyData.comboTriggered()) {
        if (!g_holdCallbacks.contains(keyVK) and !g_comboPrimary.contains(keyVK) and !g_instantComboPrimary.contains(keyVK)) {
            keyData.actionType = .tap;
            cancelKeyTimers(keyVK);
            processQueue();
            return;
        }
    }
    processQueue();
}
// ============================================================================
// Section 20 — DLL exports: lifecycle & configuration
// ============================================================================
var g_is_initialized: bool = false;
// Set to true the first time QMK_SetUserConfig is called. Prevents the
// post-warmup defaults in QMK_SetInterceptionCallbacks from overwriting
// user settings in any call-order scenario.
var g_userConfigApplied: bool = false;

export fn QMK_SetInterceptionCallbacks(
    createCtx: ?*const fn () callconv(.c) InterceptionContext,
    destroyCtx: ?*const fn (InterceptionContext) callconv(.c) void,
    send: ?*const fn (InterceptionContext, InterceptionDevice, [*]const InterceptionKeyStroke, u32) callconv(.c) i32,
    isKeyboard: ?*const fn (InterceptionDevice) callconv(.c) i32,
) callconv(.c) void {
    fp_create_context = createCtx;
    fp_destroy_context = destroyCtx;
    fp_send = send;
    fp_is_keyboard = isKeyboard;

    // --- 1. SILENT MEMORY INITIALIZATION ---
    if (!g_is_initialized) {
        initTimer();

        kbClear();
        ordClear();
        @memset(&g_kbIdx, -1);
        @memset(&g_comboPrimaryBits, 0);
        @memset(&g_instantComboPrimaryBits, 0);

        g_holdCallbacks.clearRetainingCapacity();
        g_comboCallbacks.clearRetainingCapacity();
        g_instantComboCallbacks.clearRetainingCapacity();
        g_comboPrimary.clearRetainingCapacity();
        g_instantComboPrimary.clearRetainingCapacity();
        g_comboSet.clearRetainingCapacity();
        g_instantComboSet.clearRetainingCapacity();
        g_internalCombos.clearRetainingCapacity();
        g_internalChords.clearRetainingCapacity();
        g_externalChords.clearRetainingCapacity();

        timerClear();
        ignClear();
        pcbClear();
        ptmClear();
        kdtClear();
        kutClear();
        activeModClear();

        for (&g_keyNames) |*n| @memset(n, 0);
        @memset(&g_vkToRegIdx, -1);
        @memset(&g_scCache, 0);
        @memset(&g_e0Cache, 0);

        g_keyCount = 0;
        g_modBitmask = 0;
        g_lastKeyTime = 0;
        g_typingMode = false;
        g_unrelModCount = 0;
        g_activeModKeyCnt = 0;

        // Pre-warm the exact capacity needed for the AHK script
        g_holdCallbacks.ensureTotalCapacity(gAlloc, 64) catch {};
        g_comboCallbacks.ensureTotalCapacity(gAlloc, 256) catch {};
        g_comboSet.ensureTotalCapacity(gAlloc, 256) catch {};
        g_instantComboCallbacks.ensureTotalCapacity(gAlloc, 32) catch {};
        g_instantComboSet.ensureTotalCapacity(gAlloc, 32) catch {};
        g_internalCombos.ensureTotalCapacity(gAlloc, 64) catch {};
        g_externalChords.ensureTotalCapacity(gAlloc, 64) catch {};
        g_internalChords.ensureTotalCapacity(gAlloc, 32) catch {};
        g_comboPrimary.ensureTotalCapacity(gAlloc, 64) catch {};
        g_instantComboPrimary.ensureTotalCapacity(gAlloc, 32) catch {};

        registerDefaultKeys();

        // Pre-populate the runtime scan-code cache for any registered key not
        // covered by the comptime QWERTY_SC table. For all DEFAULT_KEYS this
        // is a near-free comptime-table hit; it only matters for non-QWERTY
        // VKs that a user may have registered dynamically.
        inline for (DEFAULT_KEYS) |entry| {
            _ = scLookup(@intCast(entry.vk));
        }

        // Pre-fault all ring and batch buffer pages into physical memory.
        @memset(std.mem.asBytes(&g_ring), 0);
        @memset(std.mem.asBytes(&g_async_ring), 0);
        @memset(std.mem.asBytes(&g_strokeBatch), 0);

        // Profiling defaults to off during warmup so no noise is recorded.
        // It is turned on below, after all warmup is complete, so it is
        // on by default if the user never calls QMK_SetUserConfig.
        // If they do, QMK_SetUserConfig overwrites it immediately after.
        g_profilingEnabled = false;
        g_profiling = .{};

        g_is_initialized = true;
    }
    g_interceptionReady = false;
    if (CreateThread(null, 0, initInterceptionThreadProc, null, 0, null)) |hThread| {
        _ = CloseHandle(hThread);
    }
    if (g_async_thread == null) {
        g_async_event = CreateEventW(null, 0, 0, null);
        @atomicStore(i32, &g_async_active, 1, .release);
        g_async_thread = CreateThread(null, 0, asyncSendThreadProc, null, 0, null);
    }
    // --- 4. SENDINPUT WARMUP ---
    // Now that the async thread is live, prime user32.dll, win32k.sys, and
    // the ring-buffer dispatch path. g_interceptionReady is false here so
    // ringSend always takes the async SendInput path — exactly what we want.
    // VK 0xFF is unassigned and produces no visible output in any application.
    {
        var i: u32 = 0;
        while (i < 3) : (i += 1) {
            ringReset();
            ringAddKey(0xFF, 0);
            ringAddKey(0xFF, KEYEVENTF_KEYUP);
            ringSend();
        }
    }
    // All warmup is done. Clear noise from the stats counter.
    g_profiling = .{};
    // Apply defaults only if the user hasn't already called QMK_SetUserConfig.
    // If they have, their settings take precedence and we must not overwrite them.
    if (!g_userConfigApplied) {
        g_profilingEnabled = true;
        // g_interceptionReady is already governed by g_useKernel (default true)
        // and will be flipped on by initInterceptionThreadProc once the driver
        // is confirmed present, so no explicit set is needed here.
    }
}
fn initInterceptionThreadProc(_: ?*anyopaque) callconv(.winapi) u32 {
    // 1. Create the context
    if (g_ictx == null) g_ictx = interception_create_context();
    var found_dev: InterceptionDevice = 0;
    // 2. Do the slow hardware poll
    if (g_ictx != null) {
        var i: InterceptionDevice = 1;
        while (i <= 11) : (i += 1) {
            if (interception_is_keyboard(i) != 0) {
                found_dev = i;
                break;
            }
        }
    }
    // 3. Update globals
    g_idev = found_dev;
    g_useKernel = (g_idev > 0);
    // 4. Flip the switch to enable Kernel routing in ringSend
    g_interceptionReady = (g_useKernel and g_ictx != null and g_idev > 0);

    // 5. Interception warmup — now that g_interceptionReady is set, prime the
    //    kernel driver's send path before any real keystroke can arrive.
    //    VK 0xFF (unassigned) is silently dropped by all applications.
    //    Three iterations warm:
    //      - the Interception driver's IRP dispatch queue
    //      - the ringSend encode loop that builds InterceptionKeyStroke structs
    //      - the fp_send indirect call site's branch predictor and i-cache
    //    If the driver wasn't found (SendInput fallback mode), g_interceptionReady
    //    is false and ringSend takes the async path — already warmed in DllMain —
    //    so this block is a cheap no-op (ringReset + early return from ringSend).
    {
        var i: u32 = 0;
        while (i < 3) : (i += 1) {
            ringReset();
            ringAddKey(0xFF, 0); // key down  (VK 0xFF: unassigned)
            ringAddKey(0xFF, KEYEVENTF_KEYUP); // key up
            ringSend();
        }
    }

    // 6. Clear warmup noise from the profiling counters so it is never visible
    //    in the report. Do NOT touch g_profilingEnabled here — QMK_SetUserConfig
    //    runs concurrently on the main thread and owns that flag. Overwriting it
    //    here would race against (and silently undo) the user's config.
    g_profiling = .{};

    // Returning 0 cleanly and permanently terminates this thread.
    return 0;
}
// applyConfig: 0 = store only, 1 = apply now (pass 0 during setup, 1 to activate)
// useKernel: 1 = interception (default), 0 = SendInput fallback
// profilingOn: 1 = enabled (default), 0 = disabled
export fn QMK_SetUserConfig(
    ApplyConfig: i32,
    UseInterception: i32,
    ProfilingEnabled: i32,
    SingleKeyHoldThreshold: f64,
    MaxHoldThreshold: f64,
    MaxThresholdSuppress: i32,
    MaxBufferSize: i32,
    ComboQuietDuration: f64,
    ModifierThreshold: f64,
    DoubleTapThreshold: f64,
    RepeatInitialDelay: i32,
    RepeatInterval: i32,
) callconv(.c) void {
    if (ApplyConfig == 0) return;

    g_userConfigApplied = true; // lock out post-warmup defaults from QMK_SetInterceptionCallbacks
    g_useKernel = (UseInterception != 0);
    g_interceptionReady = g_useKernel and g_ictx != null and g_idev > 0;
    g_profilingEnabled = (ProfilingEnabled != 0);

    // --- TIMING & BUFFER CAPS ---
    // @min sets the ceiling (maximum), @max sets the floor (minimum).
    // Capped between 50ms and 1000ms
    g_SingleKeyHoldThreshold = @min(1000.0, @max(50.0, SingleKeyHoldThreshold));
    // Capped between 300ms and 2000ms
    g_MaxHoldThreshold = @min(2000.0, @max(300.0, MaxHoldThreshold));
    // Capped between 5 and 100 slots
    g_MaxBufferSize = @min(100, @max(5, MaxBufferSize));
    // Capped between 0ms and 2000ms
    g_ComboQuietDuration = @min(2000.0, @max(0.0, ComboQuietDuration));
    // Capped between 0ms and 1000ms
    g_ModifierThreshold = @min(1000.0, @max(0.0, ModifierThreshold));
    // Capped between 100ms and 600ms
    g_DoubleTapThreshold = @min(600.0, @max(100.0, DoubleTapThreshold));
    // Uncapped / boolean flags
    g_MaxThresholdSupress = (MaxThresholdSuppress != 0);
    // --- REPEAT SAFETY CAPS ---
    // Prevent OS-crashing tight loops
    g_RepeatInitialDelay = @max(50, RepeatInitialDelay);
    g_RepeatInterval = @max(5, RepeatInterval);
}

export fn QMK_DestroyInterception() callconv(.c) void {
    if (g_ictx) |ctx| {
        interception_destroy_context(ctx);
        g_ictx = null;
    }
    g_idev = 0;
    g_interceptionReady = false;
}
export fn QMK_ToggleKernelInjection() callconv(.c) void {
    g_useKernel = !g_useKernel;
    g_interceptionReady = g_useKernel and g_ictx != null and g_idev > 0;
    const onMsg = [_:0]u16{ 'K', 'e', 'r', 'n', 'e', 'l', ' ', 'I', 'n', 'j', 'e', 'c', 't', 'i', 'o', 'n', ' ', 'E', 'N', 'A', 'B', 'L', 'E', 'D', 0 };
    const offMsg = [_:0]u16{ 'K', 'e', 'r', 'n', 'e', 'l', ' ', 'I', 'n', 'j', 'e', 'c', 't', 'i', 'o', 'n', ' ', 'D', 'I', 'S', 'A', 'B', 'L', 'E', 'D', 0 };
    const cap = [_:0]u16{ 'Q', 'M', 'K', ' ', 'K', 'e', 'r', 'n', 'e', 'l', ' ', 'I', 'n', 'j', 'e', 'c', 't', 'i', 'o', 'n', 0 };
    _ = MessageBoxW(null, if (g_useKernel) &onMsg else &offMsg, &cap, MB_OK | MB_ICONINFORMATION | MB_TOPMOST | MB_SETFOREGROUND);
}
export fn QMK_EmergencyReset() callconv(.c) void {
    // Release any logically stuck modifiers in the OS before clearing local state.
    QMK_ReleaseStuckModifiers();
    kbClear();
    ordClear();
    activeModClear();
    timerClear();
    kdtClear();
    kutClear();
    g_modBitmask = 0;
    g_lastKeyTime = 0;
    g_typingMode = false;
    pcbClear();
    ptmClear();
    g_unrelModCount = 0;
    g_activeModKeyCnt = 0;
}
// Release any modifier that is logically held (FLAG_MOD_ACT set) but whose
// physical key is no longer in the buffer — i.e. the key-up was missed.
// Sends the correct modifier VK key-up (not the homerow key's VK) so the OS
// sees a clean release. Safe to call from AHK on any suspicious stuck-key event.
export fn QMK_ReleaseStuckModifiers() callconv(.c) void {
    // First pass: for any key still in the buffer with FLAG_MOD_ACT set and
    // physically released, send the modifier key-up and clear the flag.
    for (0..g_kbLen) |i| {
        const ekd = &g_kbData[i];
        if (!ekd.modifierActivated()) continue;
        const modVK: u16 = switch (getModTypeForVK(g_kbVK[i])) {
            MOD_CTRL => VK_CONTROL,
            MOD_ALT => VK_MENU,
            MOD_SHIFT => VK_SHIFT,
            MOD_WIN => VK_LWIN,
            else => 0,
        };
        if (modVK != 0) {
            ringReset();
            ringAddKey(modVK, KEYEVENTF_KEYUP);
            ringSend();
        }
        ekd.cf(FLAG_MOD_ACT | FLAG_MOD_TRIG);
    }
    // Second pass: send key-up for every modifier type that has an entry in
    // g_activeMods but is no longer physically in the key buffer.
    const modVKs = [_]u16{ VK_CONTROL, VK_MENU, VK_SHIFT, VK_LWIN };
    const modTypes = [_]i8{ MOD_CTRL, MOD_ALT, MOD_SHIFT, MOD_WIN };
    for (modVKs, modTypes) |mvk, mt| {
        var found = false;
        for (0..@intCast(g_activeModCount)) |j| {
            if (getModTypeForVK(g_activeMods[j]) == mt) {
                found = true;
                break;
            }
        }
        if (found) {
            ringReset();
            ringAddKey(mvk, KEYEVENTF_KEYUP);
            ringSend();
        }
    }
    activeModClear();
    g_unrelModCount = 0;
}
export fn QMK_ForceResetModifiers() callconv(.c) void {
    activeModClear();
    g_modBitmask = 0;
    var toDelete: [VK_COUNT]i32 = undefined;
    var tdCount: usize = 0;
    for (0..g_kbLen) |i| if (g_kbData[i].isModifier()) {
        toDelete[tdCount] = g_kbVK[i];
        tdCount += 1;
    };
    for (toDelete[0..tdCount]) |vk| {
        _ = kbRemove(vk);
        removeFromKeyOrder(vk);
    }
    const emptyName: [KN_LEN]u16 = [_]u16{0} ** KN_LEN;
    queueCallback(-99, &emptyName, @ptrCast(&[_:0]u16{0}), 99);
    g_unrelModCount = 0;
    g_activeModKeyCnt = 0;
}
// ============================================================================
// Section 21 — DLL exports: registration
// ============================================================================
export fn QMK_RegisterVK(vk: i32, keyName: [*:0]const u16) callconv(.c) void {
    registerVK(vk, keyName);
}
export fn QMK_SetupModifier(key: [*:0]const u16, modName: [*:0]const u16) callconv(.c) void {
    const vk = getVKFromName(key);
    if (vk == 0) return;
    const mt = parseModTypeName(modName);
    setModTypeForVK(vk, mt);
    for (0..g_keyCount) |i| if (g_keyVKs[i] == vk) {
        g_modTypes[i] = mt;
        break;
    };
}
export fn QMK_SetupHold(key: [*:0]const u16, callbackId: i32) callconv(.c) void {
    const vk = getVKFromName(key);
    if (vk == 0) return;
    g_holdCallbacks.put(gAlloc, vk, callbackId) catch {};
}
export fn QMK_SetupCombo(pk: [*:0]const u16, sk: [*:0]const u16, callbackId: i32) callconv(.c) void {
    const pkVK = getVKFromName(pk);
    const skVK = getVKFromName(sk);
    if (pkVK == 0 or skVK == 0) return;

    const ck = makeComboKey(pkVK, skVK);
    g_comboCallbacks.put(gAlloc, ck, callbackId) catch {};
    g_comboPrimary.put(gAlloc, pkVK, {}) catch {};
    comboPrimaryBitSet(pkVK);

    // Precompute for O(1) lookup
    if (pkVK < VK_COUNT and skVK < VK_COUNT) {
        g_comboMatrix[@intCast(pkVK)][@intCast(skVK)] = true;
    }
}
export fn QMK_SetupInstantCombo(pk: [*:0]const u16, sk: [*:0]const u16, callbackId: i32) callconv(.c) void {
    const pkVK = getVKFromName(pk);
    const skVK = getVKFromName(sk);
    if (pkVK == 0 or skVK == 0) return;
    const ck = makeComboKey(pkVK, skVK);
    g_instantComboCallbacks.put(gAlloc, ck, callbackId) catch {};
    g_instantComboPrimary.put(gAlloc, pkVK, {}) catch {};
    instantComboPrimaryBitSet(pkVK);
    if (pkVK < VK_COUNT and skVK < VK_COUNT) {
        g_instantComboMatrix[@intCast(pkVK)][@intCast(skVK)] = true;
    }
}
// Internal combos bypass AHK entirely — Zig sends the remapped key directly.
// Also registers in g_comboCallbacks with sentinel -1 so hasCombo() returns true
// and routes through triggerComboImmediate where the internal check fires first.
// Internal combos (non-instant)
export fn QMK_SetupInternalCombo(pk: [*:0]const u16, sk: [*:0]const u16, modstr: [*:0]const u16, target: [*:0]const u16) callconv(.c) void {
    const pkVK = getVKFromName(pk);
    const skVK = getVKFromName(sk);
    if (pkVK == 0 or skVK == 0) return;
    const targetVK = getVKFromName(target);
    if (targetVK == 0) return;

    const mask = parseModifierMask(modstr);
    const ck = makeComboKey(pkVK, skVK);

    g_internalCombos.put(gAlloc, ck, .{ .targetVK = targetVK, .modMask = mask, .isInstant = false }) catch {};
    g_comboCallbacks.put(gAlloc, ck, -1) catch {}; // sentinel

    g_comboPrimary.put(gAlloc, pkVK, {}) catch {};
    comboPrimaryBitSet(pkVK);

    // <<< ADD THIS LINE >>>
    if (pkVK < VK_COUNT and skVK < VK_COUNT) {
        g_comboMatrix[@intCast(pkVK)][@intCast(skVK)] = true;
    }
}

// Internal instant combos
export fn QMK_SetupInternalInstantCombo(pk: [*:0]const u16, sk: [*:0]const u16, modstr: [*:0]const u16, target: [*:0]const u16) callconv(.c) void {
    const pkVK = getVKFromName(pk);
    const skVK = getVKFromName(sk);
    if (pkVK == 0 or skVK == 0) return;
    const targetVK = getVKFromName(target);
    if (targetVK == 0) return;

    const mask = parseModifierMask(modstr);
    const ck = makeComboKey(pkVK, skVK);

    g_internalCombos.put(gAlloc, ck, .{ .targetVK = targetVK, .modMask = mask, .isInstant = true }) catch {};
    g_instantComboCallbacks.put(gAlloc, ck, -1) catch {};

    g_instantComboPrimary.put(gAlloc, pkVK, {}) catch {};
    instantComboPrimaryBitSet(pkVK);

    // <<< ADD THIS LINE >>>
    if (pkVK < VK_COUNT and skVK < VK_COUNT) {
        g_instantComboMatrix[@intCast(pkVK)][@intCast(skVK)] = true;
    }
}
// 3- or 4-key chord → single internal remap. Keys are sorted at registration
// so lookup order is always canonical regardless of call order.
export fn QMK_SetupInternalChord(k1: [*:0]const u16, k2: [*:0]const u16, k3: [*:0]const u16, k4: [*:0]const u16, modstr: [*:0]const u16, target: [*:0]const u16) callconv(.c) void {
    const vk1 = getVKFromName(k1);
    const vk2 = getVKFromName(k2);
    const vk3 = getVKFromName(k3);
    const vk4 = getVKFromName(k4);
    if (vk1 == 0 or vk2 == 0) return;
    const targetVK = getVKFromName(target);
    if (targetVK == 0) return;
    const mask = parseModifierMask(modstr);
    var vks: [4]i32 = [_]i32{0} ** 4;
    var vkCount: usize = 0;
    if (vk1 != 0) {
        vks[vkCount] = vk1;
        vkCount += 1;
    }
    if (vk2 != 0) {
        vks[vkCount] = vk2;
        vkCount += 1;
    }
    if (vk3 != 0) {
        vks[vkCount] = vk3;
        vkCount += 1;
    }
    if (vk4 != 0) {
        vks[vkCount] = vk4;
        vkCount += 1;
    }
    var si: usize = 0;
    while (si < vkCount - 1) : (si += 1) {
        var sj: usize = 0;
        while (sj < vkCount - si - 1) : (sj += 1)
            if (vks[sj] > vks[sj + 1]) {
                const t = vks[sj];
                vks[sj] = vks[sj + 1];
                vks[sj + 1] = t;
            };
    }
    var chordKey: u64 = @as(u64, @intCast(vks[0])) | (@as(u64, @intCast(vks[1])) << 16);
    if (vkCount >= 3) chordKey |= (@as(u64, @intCast(vks[2])) << 32);
    if (vkCount >= 4) chordKey |= (@as(u64, @intCast(vks[3])) << 48);
    g_internalChords.put(gAlloc, chordKey, .{ .targetVK = targetVK, .modMask = mask, .keyCount = @intCast(vkCount) }) catch {};
}
// External chord: queues a PendingCallback (type 5) with the given callbackId so AHK can handle it.
// Pass "" for k4/k5 when registering fewer than 5 keys.
export fn QMK_SetupChord(k1: [*:0]const u16, k2: [*:0]const u16, k3: [*:0]const u16, k4: [*:0]const u16, k5: [*:0]const u16, callbackId: i32) callconv(.c) void {
    const vk1 = getVKFromName(k1);
    const vk2 = getVKFromName(k2);
    const vk3 = getVKFromName(k3);
    const vk4 = getVKFromName(k4);
    const vk5 = getVKFromName(k5);
    if (vk1 == 0 or vk2 == 0) return;
    var vks: [5]i32 = [_]i32{0} ** 5;
    var vkCount: usize = 0;
    if (vk1 != 0) {
        vks[vkCount] = vk1;
        vkCount += 1;
    }
    if (vk2 != 0) {
        vks[vkCount] = vk2;
        vkCount += 1;
    }
    if (vk3 != 0) {
        vks[vkCount] = vk3;
        vkCount += 1;
    }
    if (vk4 != 0) {
        vks[vkCount] = vk4;
        vkCount += 1;
    }
    if (vk5 != 0) {
        vks[vkCount] = vk5;
        vkCount += 1;
    }
    var si: usize = 0;
    while (si < vkCount - 1) : (si += 1) {
        var sj: usize = 0;
        while (sj < vkCount - si - 1) : (sj += 1)
            if (vks[sj] > vks[sj + 1]) {
                const t = vks[sj];
                vks[sj] = vks[sj + 1];
                vks[sj + 1] = t;
            };
    }
    var chordKey: u64 = @as(u64, @intCast(vks[0])) | (@as(u64, @intCast(vks[1])) << 16);
    if (vkCount >= 3) chordKey |= (@as(u64, @intCast(vks[2])) << 32);
    if (vkCount >= 4) chordKey |= (@as(u64, @intCast(vks[3])) << 48);
    if (vkCount >= 5) chordKey ^= @as(u64, @intCast(vks[4]));
    g_externalChords.put(gAlloc, chordKey, .{ .callbackId = callbackId, .keyCount = @intCast(vkCount) }) catch {};
}
export fn QMK_RegisterCombo(primary: i32, secondary: i32, combotype: i32) callconv(.c) void {
    const ck = makeComboKey(primary, secondary);
    if (combotype == 1) g_instantComboSet.put(gAlloc, ck, {}) catch {} else g_comboSet.put(gAlloc, ck, {}) catch {};
}
// ============================================================================
// Section 22 — DLL exports: keystroke processing
// ============================================================================
export fn QMK_KeyDown(key: [*:0]const u16) callconv(.c) void {
    bufferKeyDown(key);
}
export fn QMK_KeyUp(key: [*:0]const u16) callconv(.c) void {
    bufferKeyUp(key);
}
// Combined hot-path entry: processes the event, fast-paths unmodified type-4
// taps directly through Zig without an AHK round-trip, then fills the result
// struct so AHK knows what (if anything) still needs handling.
export fn QMK_ProcessKeyEvent(key: [*:0]const u16, isDown: i32, result: *KeyEventResult) callconv(.c) void {
    if (isDown != 0) bufferKeyDown(key) else bufferKeyUp(key);
    result.directCallbacksProcessed = 0;
    if (g_pendingCBsLen > 0) {
        var processed: i32 = 0;
        var slowIdx: usize = 0;
        for (g_pendingCBs[0..g_pendingCBsLen]) |cb| {
            if (cb.type_ == 4 and cb.modifierMask == 0 and cb.vk != 0) {
                sendKeyDirect(cb.vk, 0);
                processed += 1;
            } else {
                g_pendingCBs[0..g_pendingCBsLen][slowIdx] = cb;
                slowIdx += 1;
            }
        }
        g_pendingCBsLen = slowIdx;
        result.directCallbacksProcessed = processed;
    }
    result.slowCallbacksCount = @intCast(g_pendingCBsLen);
    result.timersCount = @intCast(g_pendingTimersLen);
}
export fn QMK_TimerFired(timerId: [*:0]const u16, timerType: i32, pk: [*:0]const u16, sk: [*:0]const u16, captureTime: f64) callconv(.c) void {
    cancelTimerZ(timerId);
    var pkBuf: [KN_LEN]u16 = [_]u16{0} ** KN_LEN;
    var skBuf: [KN_LEN]u16 = [_]u16{0} ** KN_LEN;
    copyKeyName(&pkBuf, pk);
    copyKeyName(&skBuf, sk);
    switch (timerType) {
        0 => triggerComboWithQuietCheck(&pkBuf, &skBuf, captureTime),
        1 => sameModifierThreshold(&pkBuf, &skBuf),
        2 => retroTriggerCombo(&pkBuf, &skBuf),
        3 => retroActivateModifier(&pkBuf, &skBuf),
        else => {},
    }
}
// ============================================================================
// Section 23 — DLL exports: query / utility
// ============================================================================
export fn QMK_GetTime() callconv(.c) f64 {
    return getTime();
}
export fn QMK_GetPendingCallbackCount() callconv(.c) i32 {
    return @intCast(g_pendingCBsLen);
}
export fn QMK_GetPendingCallback(idx: i32, cbId: *i32, k1: [*]u16, k2: [*]u16, cbtype: *i32) callconv(.c) i32 {
    if (idx < 0 or @as(usize, @intCast(idx)) >= g_pendingCBsLen) return 0;
    const cb = &g_pendingCBs[@intCast(idx)];
    cbId.* = cb.callbackId;
    cbtype.* = cb.type_;
    var i: usize = 0;
    while (i < KN_LEN and cb.key1[i] != 0) : (i += 1) k1[i] = cb.key1[i];
    k1[i] = 0;
    var j: usize = 0;
    while (j < 7 and cb.key2[j] != 0) : (j += 1) k2[j] = cb.key2[j];
    k2[j] = 0;
    return 1;
}
export fn QMK_ClearPendingCallbacks() callconv(.c) void {
    pcbClear();
}
export fn QMK_GetPendingTimerCount() callconv(.c) i32 {
    return @intCast(g_pendingTimersLen);
}
export fn QMK_GetPendingTimer(idx: i32, tid: [*]u16, delay: *i32, timertype: *i32, pk: [*]u16, sk: [*]u16, ct: *f64) callconv(.c) i32 {
    if (idx < 0 or @as(usize, @intCast(idx)) >= g_pendingTimersLen) return 0;
    const t = &g_pendingTimers[@intCast(idx)];
    var i: usize = 0;
    while (i < TID_LEN and t.timerId[i] != 0) : (i += 1) tid[i] = t.timerId[i];
    tid[i] = 0;
    delay.* = t.delay;
    timertype.* = t.timerType;
    ct.* = t.captureTime;
    var j: usize = 0;
    while (j < KN_LEN and t.primaryKey[j] != 0) : (j += 1) pk[j] = t.primaryKey[j];
    pk[j] = 0;
    var k: usize = 0;
    while (k < KN_LEN and t.secondaryKey[k] != 0) : (k += 1) sk[k] = t.secondaryKey[k];
    sk[k] = 0;
    return 1;
}
export fn QMK_ClearPendingTimers() callconv(.c) void {
    ptmClear();
}
export fn QMK_GetModifierBitmask() callconv(.c) i32 {
    return g_modBitmask;
}
export fn QMK_GetActiveModifierCount() callconv(.c) i32 {
    return g_activeModCount;
}
export fn QMK_IsDirectSendEnabled() callconv(.c) bool {
    return true;
}
export fn QMK_AnyPhysicalModifier() callconv(.c) bool {
    return g_modBitmask > 0;
}
export fn QMK_NoModifiersHeld() callconv(.c) bool {
    if (g_activeModCount > 0 or g_unrelModCount > 0) return false;
    for (0..g_kbLen) |i| {
        const vk = g_kbVK[i];
        if (!g_kbData[i].isReleased() and (g_comboPrimary.contains(vk) or g_instantComboPrimary.contains(vk)))
            return false;
    }
    return true;
}
export fn QMK_HasCombo(primary: i32, secondary: i32) callconv(.c) bool {
    return g_comboSet.contains(makeComboKey(primary, secondary));
}
export fn QMK_HasInstantCombo(primary: i32, secondary: i32) callconv(.c) bool {
    return g_instantComboSet.contains(makeComboKey(primary, secondary));
}
export fn QMK_ProcessCallbacksDirect() callconv(.c) i32 {
    if (g_pendingCBsLen == 0) return 0;
    var processed: i32 = 0;
    var slowIdx: usize = 0;
    for (g_pendingCBs[0..g_pendingCBsLen]) |cb| {
        if ((cb.type_ == 3 or cb.type_ == 4) and cb.vk != 0) {
            sendKeyDirect(cb.vk, cb.modifierMask);
            processed += 1;
        } else {
            g_pendingCBs[0..g_pendingCBsLen][slowIdx] = cb;
            slowIdx += 1;
        }
    }
    g_pendingCBsLen = slowIdx;
    return processed;
}
export fn QMK_SendKeyDirectFromDLL(vk: i32, modifierMask: i32) callconv(.c) void {
    sendKeyDirect(vk, @intCast(@as(u32, @bitCast(modifierMask)) & 0xFFFF));
}
// ============================================================================
// Section 24 — DLL exports: profiling
// ============================================================================
export fn QMK_ToggleProfilingEnabled() callconv(.c) void {
    g_profilingEnabled = !g_profilingEnabled;
    const onMsg = [_:0]u16{ 'P', 'r', 'o', 'f', 'i', 'l', 'i', 'n', 'g', ' ', 'E', 'N', 'A', 'B', 'L', 'E', 'D', 0 };
    const offMsg = [_:0]u16{ 'P', 'r', 'o', 'f', 'i', 'l', 'i', 'n', 'g', ' ', 'D', 'I', 'S', 'A', 'B', 'L', 'E', 'D', 0 };
    const cap = [_:0]u16{ 'Q', 'M', 'K', ' ', 'P', 'r', 'o', 'f', 'i', 'l', 'i', 'n', 'g', 0 };
    _ = MessageBoxW(null, if (g_profilingEnabled) &onMsg else &offMsg, &cap, MB_OK | MB_ICONINFORMATION | MB_TOPMOST | MB_SETFOREGROUND);
}
export fn QMK_ShowProfilingReport() callconv(.c) void {
    const cap = [_:0]u16{ 'Q', 'M', 'K', ' ', 'P', 'r', 'o', 'f', 'i', 'l', 'i', 'n', 'g', ' ', 'R', 'e', 'p', 'o', 'r', 't', 0 };

    if (!g_profilingEnabled) {
        const dis = [_:0]u16{ 'P', 'r', 'o', 'f', 'i', 'l', 'i', 'n', 'g', ' ', 'i', 's', ' ', 'D', 'I', 'S', 'A', 'B', 'L', 'E', 'D', '.', '\n', '\n', 'U', 's', 'e', ' ', 'Q', 'M', 'K', '_', 'T', 'o', 'g', 'g', 'l', 'e', 'P', 'r', 'o', 'f', 'i', 'l', 'i', 'n', 'g', 'E', 'n', 'a', 'b', 'l', 'e', 'd', '(', ')', ' ', 'f', 'i', 'r', 's', 't', '.', 0 };
        _ = MessageBoxW(null, &dis, &cap, MB_OK | MB_ICONINFORMATION | MB_TOPMOST | MB_SETFOREGROUND);
        return;
    }
    g_profiling.calculateAllStats();
    var buf8: [8192]u8 = undefined;
    var pos: usize = 0;
    const aStr = struct {
        fn f(b: []u8, p: *usize, s: []const u8) void {
            for (s) |c| {
                if (p.* < b.len - 1) {
                    b[p.*] = c;
                    p.* += 1;
                }
            }
        }
    }.f;
    const aFlt = struct {
        fn f(b: []u8, p: *usize, val: f64) void {
            const whole: i64 = @intFromFloat(@trunc(val));
            const frac: i64 = @intFromFloat(@trunc(@abs(val - @trunc(val)) * 100.0));
            var tmp: [32]u8 = undefined;
            var ti: usize = 32;
            var n: u64 = if (whole < 0) @intCast(-whole) else @intCast(whole);
            if (n == 0) {
                ti -= 1;
                tmp[ti] = '0';
            } else {
                while (n > 0) {
                    ti -= 1;
                    tmp[ti] = @intCast('0' + n % 10);
                    n /= 10;
                }
            }
            if (whole < 0) {
                ti -= 1;
                tmp[ti] = '-';
            }
            for (tmp[ti..32]) |c| {
                if (p.* < b.len - 1) {
                    b[p.*] = c;
                    p.* += 1;
                }
            }
            if (p.* < b.len - 1) {
                b[p.*] = '.';
                p.* += 1;
            }
            var f2: u64 = @intCast(if (frac < 0) -frac else frac);
            var fd: [2]u8 = undefined;
            fd[1] = @intCast('0' + f2 % 10);
            f2 /= 10;
            fd[0] = @intCast('0' + f2 % 10);
            for (fd) |c| {
                if (p.* < b.len - 1) {
                    b[p.*] = c;
                    p.* += 1;
                }
            }
        }
    }.f;

    const aInt = struct {
        fn f(b: []u8, p: *usize, val: i32) void {
            var tmp: [16]u8 = undefined;
            var ti: usize = 16;
            var n: u32 = if (val < 0) @intCast(-val) else @intCast(val);
            if (n == 0) {
                ti -= 1;
                tmp[ti] = '0';
            } else {
                while (n > 0) {
                    ti -= 1;
                    tmp[ti] = @intCast('0' + n % 10);
                    n /= 10;
                }
            }
            if (val < 0) {
                ti -= 1;
                tmp[ti] = '-';
            }
            for (tmp[ti..16]) |c| {
                if (p.* < b.len - 1) {
                    b[p.*] = c;
                    p.* += 1;
                }
            }
        }
    }.f;

    const wStat = struct {
        fn f(b: []u8, p: *usize, name: []const u8, s: TimingStats, sa: fn ([]u8, *usize, []const u8) void, sf2: fn ([]u8, *usize, f64) void, si2: fn ([]u8, *usize, i32) void) void {
            if (s.count == 0) return;
            sa(b, p, name);
            sa(b, p, ":\n Samples: ");
            si2(b, p, s.count);
            sa(b, p, "\n Min: ");
            sf2(b, p, s.min);
            sa(b, p, " us (");
            sf2(b, p, s.min / 1000.0);
            sa(b, p, " ms)\n");
            sa(b, p, " Median: ");
            sf2(b, p, s.median);
            sa(b, p, " us (");
            sf2(b, p, s.median / 1000.0);
            sa(b, p, " ms)\n");
            sa(b, p, " Avg: ");
            sf2(b, p, s.avg);
            sa(b, p, " us (");
            sf2(b, p, s.avg / 1000.0);
            sa(b, p, " ms)\n");
            sa(b, p, " P95: ");
            sf2(b, p, s.p95);
            sa(b, p, " us (");
            sf2(b, p, s.p95 / 1000.0);
            sa(b, p, " ms)\n");
            sa(b, p, " Max: ");
            sf2(b, p, s.max);
            sa(b, p, " us (");
            sf2(b, p, s.max / 1000.0);
            sa(b, p, " ms)\n\n");
        }
    }.f;

    aStr(&buf8, &pos, "=== QMK Performance Profiling Report ===\n\n");
    wStat(&buf8, &pos, "KeyDown Processing", g_profiling.keyDownStats, aStr, aFlt, aInt);
    wStat(&buf8, &pos, "KeyUp Processing", g_profiling.keyUpStats, aStr, aFlt, aInt);
    wStat(&buf8, &pos, "Direct Send", g_profiling.directSendStats, aStr, aFlt, aInt);
    wStat(&buf8, &pos, "Kernel Injection", g_profiling.kernelStats, aStr, aFlt, aInt);
    wStat(&buf8, &pos, "SendInput Fallback", g_profiling.sendInputStats, aStr, aFlt, aInt);
    const kd = g_profiling.keyDownStats;
    const ds = g_profiling.directSendStats;
    if (kd.count > 0 and ds.count > 0) {
        const ft = TimingStats{ .min = kd.min + ds.min, .median = kd.median + ds.median, .avg = kd.avg + ds.avg, .p95 = kd.p95 + ds.p95, .max = kd.max + ds.max, .count = @min(kd.count, ds.count) };
        wStat(&buf8, &pos, "Total Keystroke Latency", ft, aStr, aFlt, aInt);
    }
    // Kernel Injection status
    aStr(&buf8, &pos, "Kernel Injection: ");
    if (g_interceptionReady) {
        aStr(&buf8, &pos, "ENABLED (Interception driver)\n");
    } else {
        aStr(&buf8, &pos, "DISABLED (SendInput fallback)\n");
    }
    // Windows Timer Resolution
    aStr(&buf8, &pos, "\nWindows Timer Resolution: ");
    var curRes: u32 = 0;
    var minRes: u32 = 0;
    var maxRes: u32 = 0;
    const status = NtQueryTimerResolution(&minRes, &maxRes, &curRes);
    // Check status: 0 is STATUS_SUCCESS
    // Using @intFromEnum because windows.NTSTATUS is usually an enum
    if (@intFromEnum(status) == 0) {
        const res_ms = @as(f64, @floatFromInt(curRes)) / 10000.0;
        aFlt(&buf8, &pos, res_ms);
        aStr(&buf8, &pos, " ms\n");
    } else {
        aStr(&buf8, &pos, "Error querying resolution\n");
    }
    // Convert to wide string and show
    var wide: [8192:0]u16 = std.mem.zeroes([8192:0]u16);
    for (buf8[0..pos], 0..) |c, i| {
        wide[i] = c;
    }
    _ = MessageBoxW(null, &wide, &cap, MB_OK | MB_ICONINFORMATION);
}
export fn QMK_DebugInternalCombos() callconv(.c) void {
    const cap = [_:0]u16{ 'Q', 'M', 'K', ' ', 'I', 'n', 't', 'e', 'r', 'n', 'a', 'l', ' ', 'C', 'o', 'm', 'b', 'o', 's', 0 };
    var buf: [1024:0]u16 = [_:0]u16{0} ** 1024;
    var pos: usize = 0;
    const header = "Internal Combos: ";
    for (header) |c| {
        if (pos < 1023) {
            buf[pos] = c;
            pos += 1;
        }
    }
    var count = g_internalCombos.count();
    var tmp: [16]u8 = undefined;
    var ti: usize = 15;
    if (count == 0) {
        tmp[ti] = '0';
        ti -= 1;
    } else {
        while (count > 0) : (count /= 10) {
            tmp[ti] = @as(u8, @intCast('0' + count % 10));
            ti -= 1;
        }
    }
    for (tmp[ti + 1 .. 16]) |c| {
        if (pos < 1023) {
            buf[pos] = c;
            pos += 1;
        }
    }
    const nl = "\n";
    for (nl) |c| {
        if (pos < 1023) {
            buf[pos] = c;
            pos += 1;
        }
    }
    var it = g_internalCombos.iterator();
    while (it.next()) |entry| {
        const ck = entry.key_ptr.*;
        const pkN = getNameFromVK(@as(i32, @intCast(ck >> 32))) orelse continue;
        const skN = getNameFromVK(@as(i32, @intCast(ck & 0xFFFFFFFF))) orelse continue;
        for (pkN) |c| {
            if (c == 0) break;
            if (pos < 1023) {
                buf[pos] = c;
                pos += 1;
            }
        }
        for (" + ") |c| {
            if (pos < 1023) {
                buf[pos] = c;
                pos += 1;
            }
        }
        for (skN) |c| {
            if (c == 0) break;
            if (pos < 1023) {
                buf[pos] = c;
                pos += 1;
            }
        }
        for (nl) |c| {
            if (pos < 1023) {
                buf[pos] = c;
                pos += 1;
            }
        }
    }
    _ = MessageBoxW(null, &buf, &cap, MB_OK | MB_TOPMOST | MB_SETFOREGROUND);
}
export fn QMK_ViewSettings() callconv(.c) void {
    const cap = [_:0]u16{ 'Q', 'M', 'K', ' ', 'S', 'e', 't', 't', 'i', 'n', 'g', 's', 0 };

    var buf8: [4096]u8 = undefined;
    var pos: usize = 0;

    const aStr = struct {
        fn f(b: []u8, p: *usize, s: []const u8) void {
            for (s) |c| {
                if (p.* < b.len - 1) {
                    b[p.*] = c;
                    p.* += 1;
                }
            }
        }
    }.f;

    const aFlt = struct {
        fn f(b: []u8, p: *usize, val: f64) void {
            const whole: i64 = @intFromFloat(@trunc(val));
            const frac: i64 = @intFromFloat(@trunc(@abs(val - @trunc(val)) * 100.0));
            var tmp: [32]u8 = undefined;
            var ti: usize = 32;
            var n: u64 = if (whole < 0) @intCast(-whole) else @intCast(whole);
            if (n == 0) {
                ti -= 1;
                tmp[ti] = '0';
            } else {
                while (n > 0) {
                    ti -= 1;
                    tmp[ti] = @intCast('0' + n % 10);
                    n /= 10;
                }
            }
            if (whole < 0) {
                ti -= 1;
                tmp[ti] = '-';
            }
            for (tmp[ti..32]) |c| {
                if (p.* < b.len - 1) {
                    b[p.*] = c;
                    p.* += 1;
                }
            }
            if (p.* < b.len - 1) {
                b[p.*] = '.';
                p.* += 1;
            }
            var f2: u64 = @intCast(if (frac < 0) -frac else frac);
            var fd: [2]u8 = undefined;
            fd[1] = @intCast('0' + f2 % 10);
            f2 /= 10;
            fd[0] = @intCast('0' + f2 % 10);
            for (fd) |c| {
                if (p.* < b.len - 1) {
                    b[p.*] = c;
                    p.* += 1;
                }
            }
        }
    }.f;

    const aInt = struct {
        fn f(b: []u8, p: *usize, val: i32) void {
            var tmp: [16]u8 = undefined;
            var ti: usize = 16;
            var n: u32 = if (val < 0) @intCast(-val) else @intCast(val);
            if (n == 0) {
                ti -= 1;
                tmp[ti] = '0';
            } else {
                while (n > 0) {
                    ti -= 1;
                    tmp[ti] = @intCast('0' + n % 10);
                    n /= 10;
                }
            }
            if (val < 0) {
                ti -= 1;
                tmp[ti] = '-';
            }
            for (tmp[ti..16]) |c| {
                if (p.* < b.len - 1) {
                    b[p.*] = c;
                    p.* += 1;
                }
            }
        }
    }.f;

    const aBool = struct {
        fn f(b: []u8, p: *usize, val: bool, sa: fn ([]u8, *usize, []const u8) void) void {
            sa(b, p, if (val) "true" else "false");
        }
    }.f;
    aStr(&buf8, &pos, "=== QMK Current Settings ===\n\n");
    aStr(&buf8, &pos, "-- Timing --\n");
    aStr(&buf8, &pos, "singleKeyHoldThreshold:  ");
    aFlt(&buf8, &pos, g_SingleKeyHoldThreshold);
    aStr(&buf8, &pos, " ms\n");
    aStr(&buf8, &pos, "maxHoldThreshold:        ");
    aFlt(&buf8, &pos, g_MaxHoldThreshold);
    aStr(&buf8, &pos, " ms\n");
    aStr(&buf8, &pos, "comboQuietDuration:      ");
    aFlt(&buf8, &pos, g_ComboQuietDuration);
    aStr(&buf8, &pos, " ms\n");
    aStr(&buf8, &pos, "modifierThreshold:       ");
    aFlt(&buf8, &pos, g_ModifierThreshold);
    aStr(&buf8, &pos, " ms\n");
    aStr(&buf8, &pos, "doubleTapThreshold:      ");
    aFlt(&buf8, &pos, g_DoubleTapThreshold);
    aStr(&buf8, &pos, " ms\n");
    aStr(&buf8, &pos, "\n-- Repeat --\n");
    aStr(&buf8, &pos, "repeatInitialDelay:      ");
    aInt(&buf8, &pos, g_RepeatInitialDelay);
    aStr(&buf8, &pos, " ms\n");
    aStr(&buf8, &pos, "repeatInterval:          ");
    aInt(&buf8, &pos, g_RepeatInterval);
    aStr(&buf8, &pos, " ms\n");
    aStr(&buf8, &pos, "\n-- Buffer --\n");
    aStr(&buf8, &pos, "maxBufferSize:           ");
    aInt(&buf8, &pos, g_MaxBufferSize);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "\n-- Flags --\n");
    aStr(&buf8, &pos, "maxThresholdSuppress:    ");
    aBool(&buf8, &pos, g_MaxThresholdSupress, aStr);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "profilingEnabled:        ");
    aBool(&buf8, &pos, g_profilingEnabled, aStr);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "useKernel (interception):");
    aBool(&buf8, &pos, g_useKernel, aStr);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "interceptionReady:       ");
    aBool(&buf8, &pos, g_interceptionReady, aStr);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "\n-- Runtime State --\n");
    aStr(&buf8, &pos, "activeModCount:          ");
    aInt(&buf8, &pos, g_activeModCount);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "unrelModCount:           ");
    aInt(&buf8, &pos, g_unrelModCount);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "bufferedKeyCount:        ");
    aInt(&buf8, &pos, @intCast(g_kbLen));
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "activeTimerCount:        ");
    aInt(&buf8, &pos, @intCast(g_timerLen));
    aStr(&buf8, &pos, "\n");
    var wide: [4096:0]u16 = std.mem.zeroes([4096:0]u16);
    for (buf8[0..pos], 0..) |c, i| wide[i] = c;
    _ = MessageBoxW(null, &wide, &cap, MB_OK | MB_ICONINFORMATION | MB_TOPMOST | MB_SETFOREGROUND);
}
// ============================================================================
// Section 25 — DllMain
// ============================================================================
fn lockDllMemory(hinst: windows.HINSTANCE) void {
    const base = @intFromPtr(hinst);
    // Parse the PE header natively in Zig
    const e_lfanew = @as(*const i32, @ptrFromInt(base + 0x3C)).*;
    const sizeOfImage = @as(*const u32, @ptrFromInt(base + @as(usize, @intCast(e_lfanew)) + 80)).*;
    if (sizeOfImage > 0) {
        // Bump the working set quota
        _ = SetProcessWorkingSetSize(GetCurrentProcess(), 20480000, 40960000);
        // Lock the exact footprint of the DLL
        _ = VirtualLock(hinst, sizeOfImage);
    }
}

export fn DllMain(hinst: windows.HINSTANCE, reason: u32, _: ?*anyopaque) callconv(.winapi) BOOL {
    if (reason == 1) { // DLL_PROCESS_ATTACH
        // Lock the DLL in memory and start the high-resolution timer.
        // All other init is deferred to QMK_SetInterceptionCallbacks, which
        // owns the async thread (needed for ringSend warmup) and the
        // g_is_initialized guard that prevents double-init.
        lockDllMemory(hinst);
        initTimer();
    }
    return TRUE;
}

export fn QMK_ResetForTest() callconv(.c) void {
    g_is_initialized = false;
    g_userConfigApplied = false;
    kbClear();
    ordClear();
    @memset(&g_kbIdx, -1);
    @memset(&g_comboPrimaryBits, 0);
    @memset(&g_instantComboPrimaryBits, 0);
    g_holdCallbacks.clearRetainingCapacity();
    g_comboCallbacks.clearRetainingCapacity();
    g_instantComboCallbacks.clearRetainingCapacity();
    g_comboPrimary.clearRetainingCapacity();
    g_instantComboPrimary.clearRetainingCapacity();
    g_comboSet.clearRetainingCapacity();
    g_instantComboSet.clearRetainingCapacity();
    g_internalCombos.clearRetainingCapacity();
    g_internalChords.clearRetainingCapacity();
    g_externalChords.clearRetainingCapacity();
    for (&g_comboMatrix) |*row| @memset(row, false);
    for (&g_instantComboMatrix) |*row| @memset(row, false);
    timerClear();
    ignClear();
    pcbClear();
    ptmClear();
    kdtClear();
    kutClear();
    activeModClear();
    for (&g_keyNames) |*n| @memset(n, 0);
    @memset(&g_vkToRegIdx, -1);
    @memset(&g_scCache, 0);
    @memset(&g_e0Cache, 0);
    g_keyCount = 0;
    g_modBitmask = 0;
    g_lastKeyTime = 0;
    g_typingMode = false;
    g_unrelModCount = 0;
    g_activeModKeyCnt = 0;
    registerDefaultKeys();
}
