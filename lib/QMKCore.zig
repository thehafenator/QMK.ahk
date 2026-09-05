//! QMK Core Interception — Zig implementation
//! Safe for MemoryModule in-memory loading: no CRT, no global constructors,
//! no exceptions, no TLS, no hidden startup code.
//!
//! Build:
//! zig build-lib -dynamic -target x86_64-windows-gnu -O ReleaseFast \
//! --dep build_options -Mroot=QMKCore.zig \
//! -Mbuild_options=build_options_runtime.zig -femit-bin=QMKCore.dll
//!
//! All deps are kernel32/user32 (always present) plus interception, which is
//! injected at runtime via QMK_SetInterceptionCallbacks — no import-table
//! dependency on interception.dll.
//!

const std = @import("std");
const windows = std.os.windows;
const build_options = @import("build_options");
const compiled_shortcuts_test_observability: bool = if (@hasDecl(build_options, "compiled_shortcuts_test_observability"))
    build_options.compiled_shortcuts_test_observability
else
    false;
const microbenchdebug: bool = if (@hasDecl(build_options, "microbenchdebug")) build_options.microbenchdebug else false;
const compile_with_profiling: bool = if (@hasDecl(build_options, "compile_with_profiling")) build_options.compile_with_profiling else false;
const compile_with_pgo: bool = if (@hasDecl(build_options, "compile_with_pgo")) build_options.compile_with_pgo else false;
const has_qmk_shortcuts_build: bool = if (@hasDecl(build_options, "has_qmk_shortcuts")) build_options.has_qmk_shortcuts else false;
const has_qmk_hotstrings_build: bool = if (@hasDecl(build_options, "has_qmk_hotstrings")) build_options.has_qmk_hotstrings else false;
const import_user_shortcuts_build: bool = if (@hasDecl(build_options, "import_user_shortcuts")) build_options.import_user_shortcuts else false;
const has_compiled_user_shortcuts_build: bool = import_user_shortcuts_build;
const compiled_user_shortcuts = if (import_user_shortcuts_build) build_options.user_shortcuts else struct {};

// Generated shortcut source intentionally keeps readable key spellings such
// as "a", ";", and "Backspace".  Lower them once at comptime while loading
// the generated families; runtime storage and event matching remain numeric.
fn precompiledKeyEq(comptime a: []const u8, comptime b: []const u8) bool {
    if (a.len != b.len) return false;
    inline for (b, 0..) |c, i| {
        if (a[i] != c and (a[i] | 0x20) != (c | 0x20)) return false;
    }
    return true;
}

fn precompiledVK(comptime name: []const u8) i32 {
    if (comptime name.len == 1) {
        return switch (name[0]) {
            'a'...'z', 'A'...'Z' => name[0] & 0xDF,
            '0'...'9' => name[0],
            ';' => 0xBA, '=' => 0xBB, ',' => 0xBC, '-' => 0xBD,
            '.' => 0xBE, '/' => 0xBF, '`' => 0xC0, '[' => 0xDB,
            '\\' => 0xDC, ']' => 0xDD, '\'' => 0xDE,
            else => @compileError("unsupported generated shortcut key spelling: " ++ name),
        };
    }
    if (comptime precompiledKeyEq(name, "Escape") or precompiledKeyEq(name, "Esc")) return 0x1B;
    if (comptime precompiledKeyEq(name, "Tab")) return 0x09;
    if (comptime precompiledKeyEq(name, "Enter") or precompiledKeyEq(name, "Return")) return 0x0D;
    if (comptime precompiledKeyEq(name, "Backspace")) return 0x08;
    if (comptime precompiledKeyEq(name, "Space")) return 0x20;
    if (comptime precompiledKeyEq(name, "CapsLock")) return 0x14;
    if (comptime precompiledKeyEq(name, "AppsKey")) return 0x5D;
    if (comptime precompiledKeyEq(name, "Shift")) return 0x10;
    if (comptime precompiledKeyEq(name, "Control") or precompiledKeyEq(name, "Ctrl")) return 0x11;
    if (comptime precompiledKeyEq(name, "PgUp") or precompiledKeyEq(name, "PageUp")) return 0x21;
    if (comptime precompiledKeyEq(name, "PgDn") or precompiledKeyEq(name, "PageDown")) return 0x22;
    if (comptime precompiledKeyEq(name, "PrintScreen") or precompiledKeyEq(name, "PrintScr")) return 0x2C;
    if (comptime precompiledKeyEq(name, "MButton")) return 0x04;
    if (comptime precompiledKeyEq(name, "XButton1")) return 0x05;
    if (comptime precompiledKeyEq(name, "XButton2")) return 0x06;
    if (comptime precompiledKeyEq(name, "ScrollLock")) return 0x91;
    if (comptime precompiledKeyEq(name, "NumLock")) return 0x90;
    if (comptime precompiledKeyEq(name, "Numpad0")) return 0x60;
    if (comptime precompiledKeyEq(name, "Numpad1")) return 0x61;
    if (comptime precompiledKeyEq(name, "Numpad2")) return 0x62;
    if (comptime precompiledKeyEq(name, "Numpad3")) return 0x63;
    if (comptime precompiledKeyEq(name, "Numpad4")) return 0x64;
    if (comptime precompiledKeyEq(name, "Numpad5")) return 0x65;
    if (comptime precompiledKeyEq(name, "Numpad6")) return 0x66;
    if (comptime precompiledKeyEq(name, "Numpad7")) return 0x67;
    if (comptime precompiledKeyEq(name, "Numpad8")) return 0x68;
    if (comptime precompiledKeyEq(name, "Numpad9")) return 0x69;
    if (comptime precompiledKeyEq(name, "NumpadAdd")) return 0x6B;
    if (comptime precompiledKeyEq(name, "NumpadEnter")) return 0x0D;
    if (comptime precompiledKeyEq(name, "Insert")) return 0x2D;
    if (comptime precompiledKeyEq(name, "Delete")) return 0x2E;
    if (comptime precompiledKeyEq(name, "Home")) return 0x24;
    if (comptime precompiledKeyEq(name, "End")) return 0x23;
    if (comptime precompiledKeyEq(name, "Left")) return 0x25;
    if (comptime precompiledKeyEq(name, "Up")) return 0x26;
    if (comptime precompiledKeyEq(name, "Right")) return 0x27;
    if (comptime precompiledKeyEq(name, "Down")) return 0x28;
    if (comptime precompiledKeyEq(name, "LControl") or precompiledKeyEq(name, "LCtrl")) return 0xA2;
    if (comptime precompiledKeyEq(name, "RControl") or precompiledKeyEq(name, "RCtrl")) return 0xA3;
    if (comptime precompiledKeyEq(name, "LShift")) return 0xA0;
    if (comptime precompiledKeyEq(name, "RShift") or precompiledKeyEq(name, "Rshift")) return 0xA1;
    if (comptime precompiledKeyEq(name, "LAlt")) return 0xA4;
    if (comptime precompiledKeyEq(name, "RAlt") or precompiledKeyEq(name, "Ralt")) return 0xA5;
    if (comptime precompiledKeyEq(name, "LWin")) return 0x5B;
    if (comptime precompiledKeyEq(name, "RWin")) return 0x5C;
    if (comptime precompiledKeyEq(name, "F1") or precompiledKeyEq(name, "f1")) return 0x70;
    if (comptime precompiledKeyEq(name, "F2") or precompiledKeyEq(name, "f2")) return 0x71;
    if (comptime precompiledKeyEq(name, "F3") or precompiledKeyEq(name, "f3")) return 0x72;
    if (comptime precompiledKeyEq(name, "F4") or precompiledKeyEq(name, "f4")) return 0x73;
    if (comptime precompiledKeyEq(name, "F5") or precompiledKeyEq(name, "f5")) return 0x74;
    if (comptime precompiledKeyEq(name, "F6") or precompiledKeyEq(name, "f6")) return 0x75;
    if (comptime precompiledKeyEq(name, "F7") or precompiledKeyEq(name, "f7")) return 0x76;
    if (comptime precompiledKeyEq(name, "F8") or precompiledKeyEq(name, "f8")) return 0x77;
    if (comptime precompiledKeyEq(name, "F9") or precompiledKeyEq(name, "f9")) return 0x78;
    if (comptime precompiledKeyEq(name, "F10") or precompiledKeyEq(name, "f10")) return 0x79;
    if (comptime precompiledKeyEq(name, "F11") or precompiledKeyEq(name, "f11")) return 0x7A;
    if (comptime precompiledKeyEq(name, "F12") or precompiledKeyEq(name, "f12")) return 0x7B;
    if (comptime precompiledKeyEq(name, "F13") or precompiledKeyEq(name, "f13")) return 0x7C;
    if (comptime precompiledKeyEq(name, "F14") or precompiledKeyEq(name, "f14")) return 0x7D;
    if (comptime precompiledKeyEq(name, "F15") or precompiledKeyEq(name, "f15")) return 0x7E;
    if (comptime precompiledKeyEq(name, "F16") or precompiledKeyEq(name, "f16")) return 0x7F;
    if (comptime precompiledKeyEq(name, "F17") or precompiledKeyEq(name, "f17")) return 0x80;
    if (comptime precompiledKeyEq(name, "F18") or precompiledKeyEq(name, "f18")) return 0x81;
    if (comptime precompiledKeyEq(name, "F19") or precompiledKeyEq(name, "f19")) return 0x82;
    if (comptime precompiledKeyEq(name, "F20") or precompiledKeyEq(name, "f20")) return 0x83;
    if (comptime precompiledKeyEq(name, "F21") or precompiledKeyEq(name, "f21")) return 0x84;
    if (comptime precompiledKeyEq(name, "F22") or precompiledKeyEq(name, "f22")) return 0x85;
    if (comptime precompiledKeyEq(name, "F23") or precompiledKeyEq(name, "f23")) return 0x86;
    if (comptime precompiledKeyEq(name, "F24") or precompiledKeyEq(name, "f24")) return 0x87;
    @compileError("unsupported generated shortcut key spelling: " ++ name);
}

const ipc = struct {
    pub const RING_CAPACITY: u64 = 256;
    pub const RING_MASK: u64 = RING_CAPACITY - 1;

    pub const IPC_NOOP: i64 = -1;
    pub const IPC_TIMERS_PENDING: i64 = -2;
    pub const IPC_REGISTER_KEYS: i64 = -3;
    pub const IPC_UNREGISTER_KEYS: i64 = -4;
    pub const IPC_EMERGENCY_RESET: i64 = -99;

    pub const InterceptEvent = extern struct {
        scan_code: u16,
        flags: u16,
        state_mask: u32,
        timestamp: u64,
        callback_idx: i64,
    };

    comptime {
        std.debug.assert(@sizeOf(InterceptEvent) == 24);
    }

    pub const SharedRingBuffer = extern struct {
        head: u64 align(64) = 0,
        _pad0: [56]u8 = [_]u8{0} ** 56,

        tail: u64 = 0,
        _pad1: [56]u8 = [_]u8{0} ** 56,

        capacity: u64 = RING_CAPACITY,
        _pad2: [56]u8 = [_]u8{0} ** 56,

        slots: [RING_CAPACITY]InterceptEvent = undefined,
    };

    comptime {
        std.debug.assert(@offsetOf(SharedRingBuffer, "head") == 0x00);
        std.debug.assert(@offsetOf(SharedRingBuffer, "tail") == 0x40);
        std.debug.assert(@offsetOf(SharedRingBuffer, "capacity") == 0x80);
        std.debug.assert(@offsetOf(SharedRingBuffer, "slots") == 0xC0);
    }

    pub const SHARED_MEM_BYTES: u32 = 0xC0 + (@sizeOf(InterceptEvent) * RING_CAPACITY);

    comptime {
        std.debug.assert(SHARED_MEM_BYTES == 6336);
    }
};

const hotstrings = struct {
    pub const MAX_HOTSTRING_TRIGGER_BYTES: usize = 160;
    pub const HOTSTRING_BUFFER_BYTES: usize = 256;
    pub const DEFAULT_END_CHARS = "-()[]{}:;'\"/\\,.?!\n \t";

    pub const HotstringActionKind = enum(u8) {
        paste_withbackup,
        interception_text,
        ahk_callback,
    };

    pub const HotstringOptions = packed struct(u32) {
        case_sensitive: bool = false,
        conform_to_case: bool = true,
        do_backspace: bool = true,
        omit_end_char: bool = false,
        end_char_required: bool = true,
        detect_inside_word: bool = false,
        reset_after_fire: bool = false,
        execute_action: bool = true,
        suspend_exempt: bool = false,
        enabled: bool = true,
        send_raw: u2 = 0,
        send_mode: u2 = 0,
        reserved: u18 = 0,

        pub fn fromBits(bits: u32) HotstringOptions {
            return @bitCast(bits);
        }

        pub fn toBits(self: HotstringOptions) u32 {
            return @bitCast(self);
        }
    };

    pub const HotstringEntry = struct {
        trigger: []const u8,
        replacement: []const u8 = "",
        callback_name: []const u8 = "",
        required_context: u64 = 0,
        forbidden_context: u64 = 0,
        action: HotstringActionKind = .interception_text,
        options: HotstringOptions = .{},
    };

    pub const HotstringMatch = struct {
        entry_index: usize,
        trigger_start: usize,
        trigger_len: usize,
        end_char: u8,
        backspace_count: usize,
        omit_end_char: bool,
    };

    pub const CONTEXT_GLOBAL: u64 = 0;

    pub const HotstringContextBits = struct {
        // Neutral ordinal names preserve the existing bit positions without
        // embedding application, website, or user-specific context labels.
        pub const context_00: u64 = 1 << 0;
        pub const context_01: u64 = 1 << 1;
        pub const context_02: u64 = 1 << 2;
        pub const context_03: u64 = 1 << 3;
        pub const context_04: u64 = 1 << 4;
        pub const context_05: u64 = 1 << 5;
        pub const context_06: u64 = 1 << 6;
        pub const context_07: u64 = 1 << 7;
        pub const context_08: u64 = 1 << 8;
        pub const context_09: u64 = 1 << 9;
        pub const context_10: u64 = 1 << 10;
    };

    pub const HotstringContextState = extern struct {
        active_mask: u64 = CONTEXT_GLOBAL,
        previous_mask: u64 = CONTEXT_GLOBAL,
        generation: u32 = 0,
        reserved: u32 = 0,
    };

    pub const HotstringMatcher = struct {
        buffer: [HOTSTRING_BUFFER_BYTES]u8 = undefined,
        len: usize = 0,
        suppress_collection: bool = false,

        pub fn init() HotstringMatcher {
            return .{};
        }

        pub fn reset(self: *HotstringMatcher) void {
            self.len = 0;
            self.suppress_collection = false;
        }

        pub fn appendCommittedByte(self: *HotstringMatcher, byte: u8) void {
            if (self.suppress_collection) return;
            if (self.len == self.buffer.len) self.trimFront(self.buffer.len / 2);
            self.buffer[self.len] = byte;
            self.len += 1;
        }

        pub fn appendCommittedBytes(self: *HotstringMatcher, bytes: []const u8) void {
            for (bytes) |byte| self.appendCommittedByte(byte);
        }

        pub fn backspaceCommittedChar(self: *HotstringMatcher) void {
            if (self.len > 0) self.len -= 1;
        }

        pub fn finishAfterFire(self: *HotstringMatcher, match: HotstringMatch, entry: HotstringEntry) void {
            switch (entry.action) {
                .paste_withbackup, .interception_text => {
                    self.len = 0;
                    if (entry.options.end_char_required and !match.omit_end_char and match.end_char != 0) {
                        self.appendCommittedByte(match.end_char);
                    }
                },
                .ahk_callback => {
                    if (entry.options.do_backspace) self.len = match.trigger_start;
                },
            }
            if (entry.options.reset_after_fire) self.reset();
        }

        pub fn view(self: *const HotstringMatcher) []const u8 {
            return self.buffer[0..self.len];
        }

        pub fn findMatch(
            self: *const HotstringMatcher,
            entries: []const HotstringEntry,
            context_mask: u64,
        ) ?HotstringMatch {
            return self.findMatchWithEndChars(entries, context_mask, DEFAULT_END_CHARS);
        }

        pub fn findMatchWithEndChars(
            self: *const HotstringMatcher,
            entries: []const HotstringEntry,
            context_mask: u64,
            end_chars: []const u8,
        ) ?HotstringMatch {
            for (entries, 0..) |entry, i| {
                if (entry.trigger.len == 0 or entry.trigger.len > MAX_HOTSTRING_TRIGGER_BYTES) continue;
                if (!entry.options.enabled) continue;
                if (!contextAllows(entry, context_mask)) continue;
                if (self.matchEntry(entry, end_chars)) |matched| {
                    return .{
                        .entry_index = i,
                        .trigger_start = matched.trigger_start,
                        .trigger_len = entry.trigger.len,
                        .end_char = matched.end_char,
                        .backspace_count = if (entry.options.do_backspace) entry.trigger.len + matched.end_len else 0,
                        .omit_end_char = entry.options.omit_end_char and entry.options.end_char_required,
                    };
                }
            }
            return null;
        }

        pub fn findPrecompiledMatch(_: *const HotstringMatcher, _: u64) ?HotstringMatch {
            return null;
        }

        const EntryMatch = struct {
            trigger_start: usize,
            end_char: u8,
            end_len: usize,
        };

        fn matchEntry(self: *const HotstringMatcher, entry: HotstringEntry, end_chars: []const u8) ?EntryMatch {
            const has_end = entry.options.end_char_required;
            if (self.len < entry.trigger.len + @as(usize, if (has_end) 1 else 0)) return null;

            const end_len: usize = if (has_end) 1 else 0;
            const end_char: u8 = if (has_end) self.buffer[self.len - 1] else 0;
            if (has_end and !isEndCharIn(end_char, end_chars)) return null;

            const trigger_end = self.len - end_len;
            const trigger_start = trigger_end - entry.trigger.len;
            const candidate = self.buffer[trigger_start..trigger_end];
            if (!bytesEqual(candidate, entry.trigger, entry.options.case_sensitive)) return null;
            if (!entry.options.detect_inside_word and !self.hasValidStartBoundary(trigger_start)) return null;

            return .{
                .trigger_start = trigger_start,
                .end_char = end_char,
                .end_len = end_len,
            };
        }

        fn trimFront(self: *HotstringMatcher, amount: usize) void {
            const n = @min(amount, self.len);
            if (n == 0) return;
            std.mem.copyForwards(u8, self.buffer[0 .. self.len - n], self.buffer[n..self.len]);
            self.len -= n;
        }

        fn hasValidStartBoundary(self: *const HotstringMatcher, trigger_start: usize) bool {
            if (trigger_start == 0) return true;
            return !isHotstringWordChar(self.buffer[trigger_start - 1]);
        }
    };

    pub fn contextAllows(entry: HotstringEntry, context_mask: u64) bool {
        if ((context_mask & entry.required_context) != entry.required_context) return false;
        if ((context_mask & entry.forbidden_context) != 0) return false;
        return true;
    }

    pub fn isEndChar(byte: u8) bool {
        return std.mem.indexOfScalar(u8, DEFAULT_END_CHARS, byte) != null;
    }

    pub fn isEndCharIn(byte: u8, end_chars: []const u8) bool {
        return std.mem.indexOfScalar(u8, end_chars, byte) != null;
    }

    pub fn isHotstringWordChar(byte: u8) bool {
        return (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or (byte >= '0' and byte <= '9') or byte == '_';
    }

    pub fn asciiLower(byte: u8) u8 {
        return if (byte >= 'A' and byte <= 'Z') byte + 32 else byte;
    }

    pub fn bytesEqual(a: []const u8, b: []const u8, case_sensitive: bool) bool {
        if (a.len != b.len) return false;
        if (case_sensitive) return std.mem.eql(u8, a, b);
        for (a, b) |x, y| {
            if (asciiLower(x) != asciiLower(y)) return false;
        }
        return true;
    }
};
// ============================================================================
// Section 1 — Windows API declarations
// ============================================================================
const BOOL = windows.BOOL;
const DWORD = windows.DWORD;
const INFINITE: u32 = 0xFFFFFFFF;
const WAIT_OBJECT_0: u32 = 0;
const WAIT_TIMEOUT: u32 = 0x00000102;
const HANDLE = windows.HANDLE;
// Zig 0.16 exposes Windows BOOL as c_int for this ABI. Keep these as integer
// constants so the declarations remain valid across the enum-backed and
// c_int-backed std.os.windows variants.
const TRUE: BOOL = switch (@typeInfo(BOOL)) {
    .int => 1,
    .@"enum" => @enumFromInt(1),
    else => @compileError("Windows BOOL must be integer- or enum-backed"),
};
const FALSE: BOOL = switch (@typeInfo(BOOL)) {
    .int => 0,
    .@"enum" => @enumFromInt(0),
    else => @compileError("Windows BOOL must be integer- or enum-backed"),
};
const INPUT_KEYBOARD: u32 = 1;
const KEYEVENTF_KEYUP: u32 = 0x0002;
const KEYEVENTF_UNICODE: u32 = 0x0004;
const MAPVK_VK_TO_VSC: u32 = 0;
const MAPVK_VSC_TO_VK: u32 = 1;
const MAPVK_VSC_TO_VK_EX: u32 = 3;
const AHK_SENDLEVEL_2: usize = 0xFFC3D44B;
const MB_OK: u32 = 0;
const MB_ICONINFORMATION: u32 = 0x40;
const MB_TOPMOST: u32 = 0x00040000;
const MB_SETFOREGROUND: u32 = 0x00010000;
// Thread priority constants
const THREAD_PRIORITY_TIME_CRITICAL: i32 = 15;
const THREAD_PRIORITY_HIGHEST: i32 = 2;
const POLL_WAIT_TIMEOUT_MS: u32 = 0xFFFF_FFFF; // blocking wait
const POLL_AFFINITY_MASK: usize = 0x1;
const ASYNC_AFFINITY_MASK: usize = 0x2;
const INTERNAL_FLAG_REPEAT: u32 = 0x4000_0000;
const GENERIC_WRITE: DWORD = 0x40000000;
const CREATE_ALWAYS: DWORD = 2;
const FILE_ATTRIBUTE_NORMAL: DWORD = 0x00000080;
const GMEM_MOVEABLE: u32 = 0x0002;
const CF_UNICODETEXT: u32 = 13;
const MAX_CLIPBOARD_FORMAT_BACKUPS: usize = 96;
// x86_64 INPUT struct is 40 bytes; offsets documented inline on InputSlot below.
const INPUT_STRUCT_SIZE: i32 = 40;
// Generic VK codes used when sending modifier keys
const VK_CONTROL: u16 = 0x11;
const VK_MENU: u16 = 0x12;
const VK_SHIFT: u16 = 0x10;
const VK_CAPITAL: u16 = 0x14;
const VK_LWIN: u16 = 0x5B;
const VK_RWIN: u16 = 0x5C;
const VK_LCONTROL: u16 = 0xA2;
const VK_RCONTROL: u16 = 0xA3;
const VK_LSHIFT: u16 = 0xA0;
const VK_RSHIFT: u16 = 0xA1;
const VK_LMENU: u16 = 0xA4;
const VK_RMENU: u16 = 0xA5;
const VK_BACK: u16 = 0x08;
const VK_RETURN: u16 = 0x0D;
const VK_SPACE: u16 = 0x20;
const VK_PRIOR: u16 = 0x21;
const VK_NEXT: u16 = 0x22;
const VK_END: u16 = 0x23;
const VK_HOME: u16 = 0x24;
const VK_LEFT: u16 = 0x25;
const VK_UP: u16 = 0x26;
const VK_RIGHT: u16 = 0x27;
const VK_DOWN: u16 = 0x28;
const VK_OEM_COMMA: u16 = 0xBC;
const VK_OEM_PLUS: u16 = 0xBB;
const VK_OEM_PERIOD: u16 = 0xBE;
const VK_OEM_SLASH: u16 = 0xBF;
const CREATE_WAITABLE_TIMER_HIGH_RESOLUTION: u32 = 0x00000002;
const TIMER_ALL_ACCESS: u32 = 0x001F0003;
const WH_KEYBOARD_LL: i32 = 13;
const WM_KEYDOWN: usize = 0x0100;
const WM_KEYUP: usize = 0x0101;
const WM_SYSKEYDOWN: usize = 0x0104;
const WM_SYSKEYUP: usize = 0x0105;
const WM_QUIT: u32 = 0x0012;
const PM_NOREMOVE: u32 = 0x0000;
const GA_ROOT: u32 = 2;
const CONTEXT_MENU_CLASS = [_:0]u16{ '#', '3', '2', '7', '6', '8' };
const LLKHF_EXTENDED: u32 = 0x01;
const LLKHF_INJECTED: u32 = 0x10;
const LLKHF_UP: u32 = 0x80;
const INPUT_BACKEND_AUTO: i32 = 0;
const INPUT_BACKEND_INTERCEPTION: i32 = 1;
const INPUT_BACKEND_LLHOOK: i32 = 2;
const INPUT_BACKEND_AHK_HOTKEYS: i32 = 3;

fn isPassthroughVK(vk: i32) bool {
    if (vk <= 0 or vk >= VK_COUNT or isModVK(vk)) return false;
    return activeRuntimePassthroughs().enabled[@intCast(vk)];
}

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
    .{ .vk = 27, .name = "Escape" },   .{ .vk = 20, .name = "CapsLock" },
    .{ .vk = 145, .name = "ScrollLock" },
    .{ .vk = 144, .name = "NumLock" },
    .{ .vk = 93, .name = "AppsKey" },
    .{ .vk = 166, .name = "Browser_Back" },
    .{ .vk = 167, .name = "Browser_Forward" },
    // Modifier VKs (used by native modifier entry setup).
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
    .{ .vk = 123, .name = "F12" },     .{ .vk = 124, .name = "F13" },
    .{ .vk = 125, .name = "F14" },     .{ .vk = 126, .name = "F15" },
    .{ .vk = 127, .name = "F16" },     .{ .vk = 128, .name = "F17" },
    .{ .vk = 129, .name = "F18" },     .{ .vk = 130, .name = "F19" },
    .{ .vk = 131, .name = "F20" },     .{ .vk = 132, .name = "F21" },
    .{ .vk = 133, .name = "F22" },     .{ .vk = 134, .name = "F23" },
    .{ .vk = 135, .name = "F24" },
    .{ .vk = 96, .name = "Numpad0" },   .{ .vk = 97, .name = "Numpad1" },
    .{ .vk = 98, .name = "Numpad2" },   .{ .vk = 99, .name = "Numpad3" },
    .{ .vk = 100, .name = "Numpad4" },  .{ .vk = 101, .name = "Numpad5" },
    .{ .vk = 102, .name = "Numpad6" },  .{ .vk = 103, .name = "Numpad7" },
    .{ .vk = 104, .name = "Numpad8" },  .{ .vk = 105, .name = "Numpad9" },
    .{ .vk = 107, .name = "NumpadAdd" },
    .{ .vk = 13, .name = "NumpadEnter" },
};

// Widen a comptime ASCII slice into a stack u16 buffer and call registerVK.
// This is the only place we pay the widening cost — once, at init, not on every keystroke.
fn registerDefaultKeys() void {
    inline for (DEFAULT_KEYS) |entry| {
        var wide: [KN_LEN:0]u16 = [_:0]u16{0} ** KN_LEN;
        inline for (entry.name, 0..) |c, i| {
            wide[i] = c; // ASCII = 127 is identical in UTF-16
        }
        registerVK(entry.vk, &wide);
    }
}
fn ensureDefaultKeysRegistered() void {
    if (g_keyCount == 0) registerDefaultKeys();
}

const shortcuts = struct {};

fn shortcutKeyWide(buf: *[KN_LEN:0]u16, text: []const u8) [*:0]const u16 {
    @memset(buf, 0);
    const limit = @min(text.len, KN_LEN - 1);
    for (text[0..limit], 0..) |c, i| {
        buf[i] = c;
    }
    return @ptrCast(buf);
}

fn applyPrecompiledShortcuts() void {
    if (comptime has_compiled_user_shortcuts_build) {
        if (g_precompiledShortcutsApplied) {
            markKeyGateDirty();
            refreshReplayKeyGate();
            return;
        }
        g_precompiledShortcutsLoadStarted = true;
        applyTypedPrecompiledShortcuts();
    }
    markKeyGateDirty();
    refreshReplayKeyGate();
}

// Typed precompiled data is copied into the same private runtime stores used
// by later QMK_Setup registrations.  In particular, hotkeys use the runtime
// ready-index family, so compiled rows precede later runtime rows.  The old
// opaque install(api) artifact is rejected instead of being silently dropped.
fn precompiledContextKind(kind: anytype) u8 {
    if (kind == .global) return RUNTIME_CONTEXT_GLOBAL_KIND;
    if (kind == .menu) return RUNTIME_CONTEXT_MENU_KIND;
    if (kind == .website) return RUNTIME_CONTEXT_URL_KIND;
    if (kind == .title) return RUNTIME_CONTEXT_TITLE_KIND;
    if (kind == .class) return RUNTIME_CONTEXT_CLASS_KIND;
    if (kind == .browser) return RUNTIME_CONTEXT_BROWSER_KIND;
    if (kind == .exe) return RUNTIME_CONTEXT_EXE_KIND;
    if (kind == .compound) return RUNTIME_CONTEXT_COMPOUND_KIND;
    return RUNTIME_CONTEXT_GLOBAL_KIND;
}

fn precompiledThresholdMs(ticks: i64) i32 {
    if (ticks <= 0) return 0;
    return @intCast(@min(ticks, 2000));
}

// The normal runtime setup API reports an existing row as a failed insert so
// callers can detect that their registration was not added.  Precompiled data
// is different: duplicate source rows are harmless because the first row is
// already present.  Treat that case as a successful no-op so one duplicate
// cannot abort and roll back the entire compiled preload.
fn appendPrecompiledHotkey(
    vk: i32,
    mods_required: u16,
    mods_forbidden: u16,
    callback_id: i32,
    hold_callback_id: i32,
    cleanup_callback_id: i32,
    threshold_ms: i32,
    trigger_kind: u8,
    action_kind: u8,
    requested_suppress: bool,
    context_kind: u8,
    context_negated: bool,
    context_text: []const u16,
    option_bits: u32,
    physical_mod_vk: u8,
    physical_mods_required: u8,
    physical_mods_forbidden: u8,
) bool {
    if (runtimeContextPartCount(context_text) > 1) {
        var all_ok = true;
        var contexts = RuntimeContextListIterator{ .raw = context_text };
        while (contexts.next()) |context_part| {
            const context = parseRuntimeContextSpec(context_part);
            all_ok = appendPrecompiledHotkey(
                vk, mods_required, mods_forbidden, callback_id, hold_callback_id,
                cleanup_callback_id, threshold_ms, trigger_kind, action_kind,
                requested_suppress, context.kind, context.negated, context.text,
                option_bits, physical_mod_vk, physical_mods_required,
                physical_mods_forbidden,
            ) and all_ok;
        }
        return all_ok;
    }
    const suspend_exempt = runtimeHotkeySuspendExemptFromOptions(option_bits);
    const threshold_ticks = if (threshold_ms > 0) msToTicksInt(threshold_ms) else 0;
    if (runtimeHotkeyDuplicate(
        vk, mods_required, mods_forbidden, trigger_kind, callback_id,
        hold_callback_id, cleanup_callback_id, threshold_ticks, action_kind,
        suspend_exempt, context_kind, context_negated, context_text,
        physical_mod_vk, physical_mods_required, physical_mods_forbidden,
    )) return true;
    return appendRuntimeHotkey(
        vk, mods_required, mods_forbidden, callback_id, hold_callback_id,
        cleanup_callback_id, threshold_ms, trigger_kind, action_kind,
        requested_suppress, context_kind, context_negated, context_text,
        option_bits, physical_mod_vk, physical_mods_required,
        physical_mods_forbidden,
    );
}

fn precompiledChordDuplicate(raw_in: [5]i32, row_in: RuntimeChord, context_text: []const u16) bool {
    var raw_vks = raw_in;
    if (raw_vks[0] == 0 or raw_vks[1] == 0) return false;
    var row = row_in;
    sortSmall5(&raw_vks, raw_vks.len);
    row.keyCount = 0;
    for (raw_vks) |vk| {
        if (vk == 0) continue;
        if (row.keyCount >= row.vks.len) return false;
        row.vks[@intCast(row.keyCount)] = vk;
        row.keyCount += 1;
    }
    if (row.keyCount < 2) return false;
    row.key = @as(u64, @intCast(row.vks[0])) | (@as(u64, @intCast(row.vks[1])) << 16);
    if (row.keyCount >= 3) row.key |= (@as(u64, @intCast(row.vks[2])) << 32);
    if (row.keyCount >= 4) row.key |= (@as(u64, @intCast(row.vks[3])) << 48);
    if (row.keyCount >= 5) row.key ^= @as(u64, @intCast(row.vks[4]));
    var i: usize = 0;
    while (i < g_runtimeChordsLen) : (i += 1) {
        const existing = g_runtimeChords[i];
        if (existing.key != row.key or existing.contextKind != row.contextKind or existing.contextNegated != row.contextNegated)
            continue;
        if (existing.callbackId != row.callbackId or existing.targetVK != row.targetVK or
            existing.modMask != row.modMask or existing.mode != row.mode or
            existing.suspendExempt != row.suspendExempt)
            continue;
        if (runtimeContextTextEqual(g_runtimeChordTexts[i][0..@as(usize, @intCast(existing.contextLen))], context_text))
            return true;
    }
    return false;
}

fn appendPrecompiledChord(raw_in: [5]i32, row_in: RuntimeChord, context_text: []const u16) bool {
    if (runtimeContextPartCount(context_text) > 1) {
        var all_ok = true;
        var contexts = RuntimeContextListIterator{ .raw = context_text };
        while (contexts.next()) |context_part| {
            const context = parseRuntimeContextSpec(context_part);
            var row = row_in;
            row.contextKind = context.kind;
            row.contextNegated = context.negated;
            all_ok = appendPrecompiledChord(raw_in, row, context.text) and all_ok;
        }
        return all_ok;
    }
    if (precompiledChordDuplicate(raw_in, row_in, context_text)) return true;
    return appendRuntimeChord(raw_in, row_in, context_text);
}

fn appendPrecompiledContextAction(vk: i32, callback_id: i32, action_kind: u8, context_kind: u8, context_negated: bool, context_text: []const u16, suspend_exempt: bool) bool {
    if (runtimeContextPartCount(context_text) > 1) {
        var all_ok = true;
        var contexts = RuntimeContextListIterator{ .raw = context_text };
        while (contexts.next()) |context_part| {
            const context = parseRuntimeContextSpec(context_part);
            all_ok = appendPrecompiledContextAction(vk, callback_id, action_kind, context.kind, context.negated, context.text, suspend_exempt) and all_ok;
        }
        return all_ok;
    }
    if (runtimeContextActionDuplicate(vk, callback_id, action_kind, context_kind, context_negated, context_text, suspend_exempt)) return true;
    return appendRuntimeContextAction(vk, callback_id, action_kind, context_kind, context_negated, context_text, suspend_exempt);
}

fn appendPrecompiledTapHold(vk: i32, tap_callback_id: i32, hold_callback_id: i32, cleanup_callback_id: i32, threshold_ms: i32, context_kind: u8, context_negated: bool, context_text: []const u16, suspend_exempt: bool) bool {
    if (runtimeContextPartCount(context_text) > 1) {
        var all_ok = true;
        var contexts = RuntimeContextListIterator{ .raw = context_text };
        while (contexts.next()) |context_part| {
            const context = parseRuntimeContextSpec(context_part);
            all_ok = appendPrecompiledTapHold(vk, tap_callback_id, hold_callback_id, cleanup_callback_id, threshold_ms, context.kind, context.negated, context.text, suspend_exempt) and all_ok;
        }
        return all_ok;
    }
    if (runtimeTapHoldRegistrationDuplicate(vk, tap_callback_id, hold_callback_id, cleanup_callback_id, threshold_ms, context_kind, context_negated, context_text, suspend_exempt)) return true;
    return appendRuntimeTapHoldRegistration(vk, tap_callback_id, hold_callback_id, cleanup_callback_id, threshold_ms, context_kind, context_negated, context_text, suspend_exempt);
}

fn precompiledHotstringOptionBits(options: anytype, suspend_exempt: bool) u32 {
    var bits: u32 = 0;
    if (options.case_sensitive) bits |= 1 << 0;
    if (options.conform_to_case) bits |= 1 << 1;
    if (options.backspace) bits |= 1 << 2;
    if (options.omit_end_char) bits |= 1 << 3;
    if (options.require_end_char) bits |= 1 << 4;
    if (options.inside_word) bits |= 1 << 5;
    if (options.reset) bits |= 1 << 6;
    if (options.execute) bits |= 1 << 7;
    if (suspend_exempt or options.suspend_exempt) bits |= 1 << 8;
    if (options.enabled) bits |= 1 << 9;
    if (options.send_raw) bits |= 1 << 10;
    bits |= (@as(u32, options.send_mode) & 3) << 12;
    return bits;
}

// Generated Zig literals are emitted as zero-terminated UTF-16 arrays so they
// are safe to inspect as strings. QMKCore's runtime storage, however, stores
// text as a counted slice and owns its terminator separately. Normalize at the
// compiled-data boundary so a terminator is never treated as user text.
fn precompiledU16Span(text: []const u16) []const u16 {
    if (text.len != 0 and text[text.len - 1] == 0)
        return text[0 .. text.len - 1];
    return text;
}

fn appendTypedPrecompiledHotstring(row: anytype) bool {
    if (row.trigger.len == 0 or row.trigger.len > hotstrings.MAX_HOTSTRING_TRIGGER_BYTES) return false;
    if (!ensureRuntimeHotstringCapacity(g_runtimeHotstringLen + 1)) return false;
    const c = row.context;
    const context_text = precompiledU16Span(c.text);
    const non_global = c.kind != .global;
    if (non_global and context_text.len >= RUNTIME_HOTSTRING_CONTEXT_CHARS) return false;
    if (non_global and !ensureRuntimeHotstringContextCapacity(g_hsCtxRowsLen + 1)) return false;

    const slot = g_runtimeHotstringLen;
    const ctx_start = g_hsCtxRowsLen;
    g_runtimeHotstringLen += 1;
    @memset(&g_runtimeHotstringTriggerBytes[slot], 0);
    @memcpy(g_runtimeHotstringTriggerBytes[slot][0..row.trigger.len], row.trigger);

    const option_bits = precompiledHotstringOptionBits(row.options, false);
    const options = hotstrings.HotstringOptions.fromBits(option_bits);
    const action: hotstrings.HotstringActionKind = switch (row.action) {
        .paste_withbackup => .paste_withbackup,
        .interception_text => .interception_text,
        .ahk_callback => .ahk_callback,
    };
    var replacement: []const u8 = "";
    if (row.replacement.len != 0) {
        replacement = utf16ToUtf8Alloc(precompiledU16Span(row.replacement)) catch {
            g_runtimeHotstringLen -= 1;
            return false;
        };
    }
    g_runtimeHotstringEntries[slot] = .{
        .trigger = g_runtimeHotstringTriggerBytes[slot][0..row.trigger.len],
        .replacement = replacement,
        .action = action,
        .options = options,
    };
    g_runtimeHotstringCallbackIds[slot] = if (action == .ahk_callback) precompiledCallbackId(row.callback_id) else -1;
    g_runtimeHotstringSuspendExempt[slot] = options.suspend_exempt;
    g_runtimeHotstringUserEnabled[slot] = options.enabled;
    g_runtimeHotstringCtxStart[slot] = 0;
    g_runtimeHotstringCtxCount[slot] = 0;

    if (non_global) {
        @memset(&g_hsCtxTexts[ctx_start], 0);
        @memcpy(g_hsCtxTexts[ctx_start][0..context_text.len], context_text);
        g_hsCtxRows[ctx_start] = .{
            .contextKind = precompiledContextKind(c.kind),
            .contextNegated = c.negated,
            .contextLen = @intCast(context_text.len),
            .specificityMask = runtimeHotkeySpecificityMask(precompiledContextKind(c.kind), g_hsCtxTexts[ctx_start][0..context_text.len]),
            .allowed = true,
        };
        g_hsCtxRowsLen += 1;
        g_runtimeHotstringCtxStart[slot] = @intCast(ctx_start);
        g_runtimeHotstringCtxCount[slot] = 1;
        g_runtimeHotstringDependencyMask |= g_hsCtxRows[ctx_start].specificityMask;
    }
    g_hsContextIndexDirty = true;
    // A duplicate hotstring is a normal source-level condition: runtime setup
    // skips that row and keeps the other registrations. Do the same for the
    // compiled preload instead of rolling back the entire generated family.
    if (runtimeHotstringDuplicateAt(slot)) {
        rollbackRuntimeHotstring(slot);
        g_hsCtxRowsLen = ctx_start;
        return true;
    }
    if (!commitRuntimeHotstringCallbackExemption(slot)) {
        rollbackRuntimeHotstring(slot);
        g_hsCtxRowsLen = ctx_start;
        return false;
    }
    return true;
}

fn applyTypedPrecompiledShortcuts() void {
    @setEvalBranchQuota(100000);
    if (comptime !@hasDecl(compiled_user_shortcuts, "Compiled_Modifiers") or
        !@hasDecl(compiled_user_shortcuts, "Compiled_Native_Controls") or
        !@hasDecl(compiled_user_shortcuts, "Compiled_Passthroughs") or
        !@hasDecl(compiled_user_shortcuts, "Compiled_Hotkeys") or
        !@hasDecl(compiled_user_shortcuts, "Compiled_Holds") or
        !@hasDecl(compiled_user_shortcuts, "Compiled_Double_Taps") or
        !@hasDecl(compiled_user_shortcuts, "Compiled_Taps") or
        !@hasDecl(compiled_user_shortcuts, "Compiled_Tap_Holds") or
        !@hasDecl(compiled_user_shortcuts, "Compiled_Combos") or
        !@hasDecl(compiled_user_shortcuts, "Compiled_Chords") or
        !@hasDecl(compiled_user_shortcuts, "Compiled_Hotstrings") or
        !@hasDecl(compiled_user_shortcuts, "Compiled_Callbacks") or
        !@hasDecl(compiled_user_shortcuts, "Compiled_Source_Order"))
    {
        @compileError("compiled user shortcuts must expose typed Compiled_* families; legacy install(api) artifact rejected");
    }
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeModifierFamily();
    prepareRuntimePassthroughFamily();
    prepareRuntimeHotkeyFamily();
    prepareRuntimeContextActionFamily();
    prepareRuntimeComboFamily();
    prepareRuntimeChordFamily();
    prepareRuntimeHotstringFamily();
    if (compiled_shortcuts_test_observability) g_precompiledFamilyCounts = [_]u32{0} ** 14;
    var ok = true;
    inline for (compiled_user_shortcuts.Compiled_Native_Controls.panic_exit) |row| {
        if (row.kind != .panic_exit) continue;
        _ = QMK_SetPanicExitHotkey(precompiledVK(row.trigger), row.mods_required, row.mods_forbidden, if (row.enabled) 1 else 0);
    }
    inline for (compiled_user_shortcuts.Compiled_Native_Controls.native_reload) |row| {
        if (row.kind != .native_reload) continue;
        _ = QMK_SetNativeReloadHotkey(precompiledVK(row.trigger), row.mods_required, row.mods_forbidden, if (row.enabled) 1 else 0);
    }
    if (comptime @hasDecl(compiled_user_shortcuts.Compiled_Native_Controls, "toggle_suspend")) {
        inline for (compiled_user_shortcuts.Compiled_Native_Controls.toggle_suspend) |row| {
            if (row.kind != .toggle_suspend) continue;
            _ = QMK_SetNativeSuspendHotkey(precompiledVK(row.trigger), row.mods_required, row.mods_forbidden, if (row.enabled) 1 else 0);
        }
    }
    inline for (compiled_user_shortcuts.Compiled_Modifiers.rows) |row| {
        const c = row.context;
        ok = appendRuntimeModifier(precompiledVK(row.key), row.mod_type, precompiledContextKind(c.kind), c.negated, c.text, row.suspend_exempt) and ok;
    }
    inline for (compiled_user_shortcuts.Compiled_Passthroughs.rows) |row| {
        const c = row.context;
        ok = appendRuntimePassthrough(precompiledVK(row.key), precompiledContextKind(c.kind), c.negated, c.text, row.suspend_exempt) and ok;
    }
    inline for (compiled_user_shortcuts.Compiled_Hotkeys.rows) |row| {
        const c = row.context;
        var callback_id = precompiledCallbackId(row.callback_id);
        const hold_callback_id = precompiledCallbackId(row.hold_callback_id);
        const cleanup_callback_id = precompiledCallbackId(row.cleanup_callback_id);
        // Generated rows carry UTF-16 payloads with a trailing zero.  The
        // empty payload is therefore often emitted as &.{ 0 }, not &.{}.
        // Test the logical span, otherwise every callback row is mistaken for
        // a native payload and its compiled AHK callback ID is discarded.
        const native_payload = precompiledU16Span(row.native_payload);
        if (native_payload.len != 0) {
            const payload_base = appendNativeHotkeyPayloads(native_payload.ptr, @intCast(native_payload.len));
            if (payload_base == NATIVE_PAYLOAD_APPEND_FAILED) {
                ok = false;
            } else {
                callback_id = NATIVE_PAYLOAD_ID_BASE - @as(i32, @intCast(payload_base));
                initNativePasteThread();
            }
        }
        var bits: u32 = 0;
        if (row.suspend_exempt) bits |= 1 << 8;
        ok = appendPrecompiledHotkey(precompiledVK(row.trigger), row.mods_required, row.mods_forbidden, callback_id,
            hold_callback_id, cleanup_callback_id, precompiledThresholdMs(row.threshold_ticks),
            row.trigger_kind, row.action_kind, row.suppress_original, precompiledContextKind(c.kind), c.negated,
            c.text, bits, row.physical_mod_vk, row.physical_mods_required, row.physical_mods_forbidden) and ok;
    }
    inline for (compiled_user_shortcuts.Compiled_Holds.rows) |row| {
        const c = row.context;
        ok = appendPrecompiledContextAction(precompiledVK(row.key), precompiledCallbackId(row.callback_id), 0, precompiledContextKind(c.kind), c.negated, c.text, row.suspend_exempt) and ok;
    }
    inline for (compiled_user_shortcuts.Compiled_Double_Taps.rows) |row| {
        const c = row.context;
        ok = appendPrecompiledContextAction(precompiledVK(row.key), precompiledCallbackId(row.callback_id), 1, precompiledContextKind(c.kind), c.negated, c.text, row.suspend_exempt) and ok;
    }
    inline for (compiled_user_shortcuts.Compiled_Taps.rows) |row| {
        const c = row.context;
        var callback_id = precompiledCallbackId(row.callback_id);
        const hold_callback_id = precompiledCallbackId(row.hold_callback_id);
        const cleanup_callback_id = precompiledCallbackId(row.cleanup_callback_id);
        const native_payload = precompiledU16Span(row.native_payload);
        if (native_payload.len != 0) {
            const payload_base = appendNativeHotkeyPayloads(native_payload.ptr, @intCast(native_payload.len));
            if (payload_base == NATIVE_PAYLOAD_APPEND_FAILED) {
                ok = false;
            } else {
                callback_id = NATIVE_PAYLOAD_ID_BASE - @as(i32, @intCast(payload_base));
                initNativePasteThread();
            }
        }
        var bits: u32 = 0;
        if (row.suspend_exempt) bits |= 1 << 8;
        ok = appendPrecompiledHotkey(precompiledVK(row.trigger), row.mods_required, row.mods_forbidden, callback_id,
            hold_callback_id, cleanup_callback_id, precompiledThresholdMs(row.threshold_ticks),
            row.trigger_kind, row.action_kind, row.suppress_original, precompiledContextKind(c.kind), c.negated,
            c.text, bits, row.physical_mod_vk, row.physical_mods_required, row.physical_mods_forbidden) and ok;
    }
    inline for (compiled_user_shortcuts.Compiled_Tap_Holds.rows) |row| {
        const c = row.context;
        ok = appendPrecompiledTapHold(precompiledVK(row.key), precompiledCallbackId(row.tap_callback_id), precompiledCallbackId(row.hold_callback_id), precompiledCallbackId(row.cleanup_callback_id),
            precompiledThresholdMs(row.threshold_ticks), precompiledContextKind(c.kind), c.negated, c.text, row.suspend_exempt) and ok;
    }
    inline for (. { compiled_user_shortcuts.Compiled_Combos.normal_callback, compiled_user_shortcuts.Compiled_Combos.instant_callback,
        compiled_user_shortcuts.Compiled_Combos.internal_remap, compiled_user_shortcuts.Compiled_Combos.internal_instant_remap }) |family| {
        inline for (family) |source| {
            const c = source.context;
            ok = appendPrecompiledCombo(.{ .primaryVK = precompiledVK(source.primary), .secondaryVK = precompiledVK(source.secondary), .callbackId = precompiledCallbackId(source.callback_id),
                .targetVK = if (source.target.len == 0) 0 else precompiledVK(source.target), .modMask = source.mod_mask, .mode = @intFromEnum(source.mode),
                .contextKind = precompiledContextKind(c.kind), .contextNegated = c.negated, .suspendExempt = source.suspend_exempt,
                .registrationOrder = source.registration_order }, c.text) and ok;
        }
    }
    inline for (. { compiled_user_shortcuts.Compiled_Chords.external_callback }) |family| {
        inline for (family) |source| {
            const c = source.context;
            var lowered_vks: [5]i32 = [_]i32{0} ** 5;
            inline for (source.keys, 0..) |name, index| {
                if (name.len != 0) lowered_vks[index] = precompiledVK(name);
            }
            ok = appendPrecompiledChord(lowered_vks, .{ .vks = lowered_vks, .callbackId = precompiledCallbackId(source.callback_id), .targetVK = if (source.target.len == 0) 0 else precompiledVK(source.target),
                .modMask = source.mod_mask, .mode = 0, .keyCount = 0,
                .contextKind = precompiledContextKind(c.kind), .contextNegated = c.negated, .suspendExempt = source.suspend_exempt }, c.text) and ok;
        }
    }
    inline for (. { compiled_user_shortcuts.Compiled_Chords.internal_remap }) |family| {
        inline for (family) |source| {
            const c = source.context;
            var lowered_vks: [5]i32 = [_]i32{0} ** 5;
            inline for (source.keys, 0..) |name, index| {
                if (name.len != 0) lowered_vks[index] = precompiledVK(name);
            }
            ok = appendPrecompiledChord(lowered_vks, .{ .vks = lowered_vks, .callbackId = precompiledCallbackId(source.callback_id), .targetVK = if (source.target.len == 0) 0 else precompiledVK(source.target),
                .modMask = source.mod_mask, .mode = 1, .keyCount = 0,
                .contextKind = precompiledContextKind(c.kind), .contextNegated = c.negated, .suspendExempt = source.suspend_exempt }, precompiledU16Span(c.text)) and ok;
        }
    }
    var precompiled_hotstring_count: u32 = 0;
    for (compiled_user_shortcuts.Compiled_Hotstrings.rows) |row| {
        const hotstring_count_before = g_runtimeHotstringLen;
        const loaded = appendTypedPrecompiledHotstring(row);
        if (loaded and g_runtimeHotstringLen > hotstring_count_before)
            precompiled_hotstring_count += 1;
        ok = loaded and ok;
    }
    // Do not roll back the entire compiled preload because one source row is
    // malformed or exceeds a family limit.  The append helpers are already
    // transactional per row; rolling back here made a single bad hotstring
    // erase every otherwise-valid hotkey, hold, combo, chord, and hotstring.
    // Keep the successfully appended rows and publish them together below.
    if (!ok) {
        // Valid rows still publish; ensure the final gate rebuild includes
        // every family that did load.
        g_bulkRuntimeKeyGateDirty = true;
    }
    if (compiled_shortcuts_test_observability) {
        g_precompiledFamilyCounts = .{
            @intCast(compiled_user_shortcuts.Compiled_Modifiers.rows.len),
            @intCast(compiled_user_shortcuts.Compiled_Passthroughs.rows.len),
            @intCast(compiled_user_shortcuts.Compiled_Hotkeys.rows.len),
            @intCast(compiled_user_shortcuts.Compiled_Holds.rows.len),
            @intCast(compiled_user_shortcuts.Compiled_Double_Taps.rows.len),
            @intCast(compiled_user_shortcuts.Compiled_Taps.rows.len),
            @intCast(compiled_user_shortcuts.Compiled_Tap_Holds.rows.len),
            @intCast(compiled_user_shortcuts.Compiled_Combos.normal_callback.len +
                compiled_user_shortcuts.Compiled_Combos.internal_remap.len),
            @intCast(compiled_user_shortcuts.Compiled_Combos.instant_callback.len +
                compiled_user_shortcuts.Compiled_Combos.internal_instant_remap.len),
            @intCast(compiled_user_shortcuts.Compiled_Chords.external_callback.len),
            @intCast(compiled_user_shortcuts.Compiled_Chords.internal_remap.len),
            precompiled_hotstring_count,
            @intCast(compiled_user_shortcuts.Compiled_Native_Controls.panic_exit.len),
            @intCast(compiled_user_shortcuts.Compiled_Native_Controls.native_reload.len),
        };
    }
    // Preserve the end of the compiled preload independently from the
    // transaction publish lengths. Runtime setup advances the latter to the
    // new total, but overlay matching must continue to compare only compiled
    // rows against the runtime suffix.
    g_compiledModifiersLen = g_runtimeModifiersLen;
    g_compiledPassthroughsLen = g_runtimePassthroughsLen;
    g_compiledHotkeysLen = g_runtimeHotkeysLen;
    g_compiledContextActionsLen = g_runtimeContextActionsLen;
    g_compiledCombosLen = g_runtimeCombosLen;
    g_compiledInstantCombosLen = g_runtimeInstantCombosLen;
    g_compiledChordsLen = g_runtimeChordsLen;
    g_compiledHotstringsLen = g_runtimeHotstringLen;
    // Compiled hotkeys live in the runtime hotkey rows, so they must take the
    // same context-automaton/index rebuild path as QMK_SetupHotkeys().  The
    // bulk dirty flag alone rebuilds row metadata but leaves the context loop
    // and global index stale, making every compiled hotkey invisible.
    g_runtimeHotkeyContextsDirty = true;
    g_bulkRuntimeHotkeysDirty = true; g_bulkRuntimeModifiersDirty = true; g_bulkRuntimePassthroughsDirty = true;
    g_bulkRuntimeContextActionsDirty = true; g_bulkRuntimeCombosDirty = true; g_bulkRuntimeChordsDirty = true;
    g_bulkRuntimeHotstringsDirty = true; g_bulkRuntimeKeyGateDirty = true;
    requestRuntimePublish(RUNTIME_PUBLISH_SETUP);
    if (@atomicLoad(u32, &g_runtimePublishPendingMask, .acquire) == 0)
        g_precompiledShortcutsApplied = true;
}

const POINT = extern struct {
    x: i32,
    y: i32,
};

const MSG = extern struct {
    hwnd: ?HANDLE,
    message: u32,
    wParam: usize,
    lParam: isize,
    time: DWORD,
    pt: POINT,
};

const KBDLLHOOKSTRUCT = extern struct {
    vkCode: DWORD,
    scanCode: DWORD,
    flags: DWORD,
    time: DWORD,
    dwExtraInfo: usize,
};

extern "kernel32" fn GetProcessHeap() callconv(.winapi) HANDLE;
extern "kernel32" fn HeapAlloc(h: HANDLE, flags: DWORD, bytes: usize) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn HeapFree(h: HANDLE, flags: DWORD, mem: ?*anyopaque) callconv(.winapi) BOOL;
extern "kernel32" fn HeapReAlloc(h: HANDLE, flags: DWORD, mem: *anyopaque, bytes: usize) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GlobalAlloc(uFlags: u32, dwBytes: usize) callconv(.winapi) ?HANDLE;
extern "kernel32" fn GlobalLock(hMem: HANDLE) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GlobalUnlock(hMem: HANDLE) callconv(.winapi) BOOL;
extern "kernel32" fn GlobalFree(hMem: HANDLE) callconv(.winapi) ?HANDLE;
extern "kernel32" fn GlobalSize(hMem: HANDLE) callconv(.winapi) usize;
extern "kernel32" fn QueryPerformanceCounter(lp: *i64) callconv(.winapi) BOOL;
extern "kernel32" fn QueryPerformanceFrequency(lp: *i64) callconv(.winapi) BOOL;
extern "kernel32" fn MapVirtualKeyW(code: u32, mapType: u32) callconv(.winapi) u32;
extern "kernel32" fn MapViewOfFile(hFileMappingObject: HANDLE, dwDesiredAccess: DWORD, dwFileOffsetHigh: DWORD, dwFileOffsetLow: DWORD, dwNumberOfBytesToMap: usize) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetModuleHandleA(lpModuleName: [*:0]const u8) callconv(.winapi) ?HANDLE;
extern "kernel32" fn GetProcAddress(hModule: HANDLE, lpProcName: [*:0]const u8) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn Sleep(ms: u32) callconv(.winapi) void;
extern "kernel32" fn ExitProcess(uExitCode: u32) callconv(.winapi) noreturn;
extern "kernel32" fn GetCommandLineW() callconv(.winapi) [*:0]const u16;
extern "kernel32" fn CreateProcessW(lpApplicationName: ?[*:0]const u16, lpCommandLine: ?[*:0]u16, lpProcessAttributes: ?*anyopaque, lpThreadAttributes: ?*anyopaque, bInheritHandles: BOOL, dwCreationFlags: DWORD, lpEnvironment: ?*anyopaque, lpCurrentDirectory: ?[*:0]const u16, lpStartupInfo: *windows.STARTUPINFOW, lpProcessInformation: *windows.PROCESS.INFORMATION) callconv(.winapi) BOOL;
extern "kernel32" fn OpenProcess(dwDesiredAccess: DWORD, bInheritHandle: BOOL, dwProcessId: DWORD) callconv(.winapi) ?HANDLE;
extern "kernel32" fn QueryFullProcessImageNameW(hProcess: HANDLE, dwFlags: DWORD, lpExeName: [*]u16, lpdwSize: *DWORD) callconv(.winapi) BOOL;
extern "kernel32" fn CreateThread(attr: ?*anyopaque, stack: usize, fn_: *const fn (?*anyopaque) callconv(.winapi) u32, param: ?*anyopaque, flags: u32, id: ?*u32) callconv(.winapi) ?HANDLE;
extern "kernel32" fn CloseHandle(h: HANDLE) callconv(.winapi) BOOL;
extern "kernel32" fn CreateMutexW(lpMutexAttributes: ?*anyopaque, bInitialOwner: BOOL, lpName: ?[*:0]const u16) callconv(.winapi) ?HANDLE;
extern "kernel32" fn ReleaseMutex(hMutex: HANDLE) callconv(.winapi) BOOL;
extern "kernel32" fn WaitForSingleObject(h: HANDLE, dwMilliseconds: DWORD) callconv(.winapi) DWORD;
extern "kernel32" fn CreateEventW(lpEventAttributes: ?*anyopaque, bManualReset: BOOL, bInitialState: BOOL, lpName: ?[*:0]const u16) callconv(.winapi) ?HANDLE;
extern "kernel32" fn SetEvent(hEvent: HANDLE) callconv(.winapi) BOOL;
extern "kernel32" fn ResetEvent(hEvent: HANDLE) callconv(.winapi) BOOL;
extern "kernel32" fn WaitForMultipleObjects(nCount: DWORD, lpHandles: [*]const HANDLE, bWaitAll: BOOL, dwMilliseconds: DWORD) callconv(.winapi) DWORD;
extern "kernel32" fn GetCurrentThread() callconv(.winapi) HANDLE;
extern "kernel32" fn SetThreadPriority(hThread: HANDLE, nPriority: i32) callconv(.winapi) BOOL;
extern "kernel32" fn SetThreadAffinityMask(hThread: HANDLE, dwThreadAffinityMask: usize) callconv(.winapi) usize;
extern "kernel32" fn CreateWaitableTimerExW(lpTimerAttributes: ?*anyopaque, lpTimerName: ?[*:0]const u16, dwFlags: DWORD, dwDesiredAccess: DWORD) callconv(.winapi) ?HANDLE;
extern "kernel32" fn SetWaitableTimer(hTimer: HANDLE, lpDueTime: *const i64, lPeriod: i32, pfnCompletionRoutine: ?*anyopaque, lpArgToCompletionRoutine: ?*anyopaque, fResume: BOOL) callconv(.winapi) BOOL;
extern "kernel32" fn CancelWaitableTimer(hTimer: HANDLE) callconv(.winapi) BOOL;
extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) DWORD;
extern "user32" fn SetWindowsHookExW(idHook: i32, lpfn: *const fn (i32, usize, isize) callconv(.winapi) isize, hmod: ?HANDLE, dwThreadId: DWORD) callconv(.winapi) ?HANDLE;
extern "user32" fn CallNextHookEx(hhk: ?HANDLE, nCode: i32, wParam: usize, lParam: isize) callconv(.winapi) isize;
extern "user32" fn UnhookWindowsHookEx(hhk: HANDLE) callconv(.winapi) BOOL;
extern "user32" fn GetMessageW(lpMsg: *MSG, hWnd: ?HANDLE, wMsgFilterMin: u32, wMsgFilterMax: u32) callconv(.winapi) i32;
extern "user32" fn PeekMessageW(lpMsg: *MSG, hWnd: ?HANDLE, wMsgFilterMin: u32, wMsgFilterMax: u32, wRemoveMsg: u32) callconv(.winapi) BOOL;
extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) BOOL;
extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.winapi) isize;
extern "user32" fn PostThreadMessageW(idThread: DWORD, Msg: u32, wParam: usize, lParam: isize) callconv(.winapi) BOOL;
extern "user32" fn SendInput(n: u32, inputs: [*]const u8, cbSize: i32) callconv(.winapi) u32;
extern "user32" fn VkKeyScanW(ch: u16) callconv(.winapi) i16;
extern "user32" fn keybd_event(vk: u8, scan: u8, flags: u32, extraInfo: usize) callconv(.winapi) void;
extern "user32" fn MessageBoxW(hwnd: ?*anyopaque, text: [*:0]const u16, cap: [*:0]const u16, utype: u32) callconv(.winapi) i32;
extern "user32" fn FindWindowW(lpClassName: ?[*:0]const u16, lpWindowName: ?[*:0]const u16) callconv(.winapi) ?HANDLE;
extern "user32" fn GetForegroundWindow() callconv(.winapi) ?HANDLE;
extern "user32" fn GetAncestor(hWnd: HANDLE, gaFlags: u32) callconv(.winapi) ?HANDLE;
extern "user32" fn GetWindowTextW(hWnd: HANDLE, lpString: [*]u16, nMaxCount: i32) callconv(.winapi) i32;
extern "user32" fn GetClassNameW(hWnd: HANDLE, lpClassName: [*]u16, nMaxCount: i32) callconv(.winapi) i32;
extern "user32" fn GetWindowThreadProcessId(hWnd: HANDLE, lpdwProcessId: *DWORD) callconv(.winapi) DWORD;
extern "user32" fn GetKeyboardState(lpKeyState: [*]u8) callconv(.winapi) BOOL;
extern "user32" fn GetAsyncKeyState(vKey: i32) callconv(.winapi) i16;
extern "user32" fn OpenClipboard(hWndNewOwner: ?HANDLE) callconv(.winapi) BOOL;
extern "user32" fn EmptyClipboard() callconv(.winapi) BOOL;
extern "user32" fn SetClipboardData(uFormat: u32, hMem: HANDLE) callconv(.winapi) ?HANDLE;
extern "user32" fn GetClipboardData(uFormat: u32) callconv(.winapi) ?HANDLE;
extern "user32" fn EnumClipboardFormats(format: u32) callconv(.winapi) u32;
extern "user32" fn IsClipboardFormatAvailable(format: u32) callconv(.winapi) BOOL;
extern "user32" fn CloseClipboard() callconv(.winapi) BOOL;
extern "ntdll" fn NtQueryTimerResolution(
    MinimumResolution: *u32,
    MaximumResolution: *u32,
    CurrentResolution: *u32,
) callconv(.winapi) windows.NTSTATUS;
extern "kernel32" fn VirtualLock(lpAddress: ?*anyopaque, dwSize: usize) callconv(.winapi) BOOL;

const MSGBOX_TEXT_MAX: usize = 8192;
const MSGBOX_CAP_MAX: usize = 128;

const AsyncMessageBoxRequest = struct {
    text: [MSGBOX_TEXT_MAX:0]u16,
    cap: [MSGBOX_CAP_MAX:0]u16,
    flags: u32,
};

fn copyWideZBounded(comptime N: usize, dst: *[N:0]u16, src: [*:0]const u16) void {
    @memset(dst, 0);
    var i: usize = 0;
    while (i + 1 < N and src[i] != 0) : (i += 1) {
        dst[i] = src[i];
    }
    dst[i] = 0;
}

fn asyncMessageBoxThread(param: ?*anyopaque) callconv(.winapi) u32 {
    const raw = param orelse return 0;
    const req: *AsyncMessageBoxRequest = @ptrCast(@alignCast(raw));
    _ = MessageBoxW(null, &req.text, &req.cap, req.flags);
    _ = HeapFree(GetProcessHeap(), 0, raw);
    return 0;
}

fn showMessageBoxAsync(text: [*:0]const u16, cap: [*:0]const u16, flags: u32) void {
    const raw = HeapAlloc(GetProcessHeap(), 0, @sizeOf(AsyncMessageBoxRequest)) orelse {
        _ = MessageBoxW(null, text, cap, flags);
        return;
    };
    const req: *AsyncMessageBoxRequest = @ptrCast(@alignCast(raw));
    copyWideZBounded(MSGBOX_TEXT_MAX, &req.text, text);
    copyWideZBounded(MSGBOX_CAP_MAX, &req.cap, cap);
    req.flags = flags;
    if (CreateThread(null, 0, asyncMessageBoxThread, raw, 0, null)) |thread| {
        _ = CloseHandle(thread);
    } else {
        _ = MessageBoxW(null, &req.text, &req.cap, req.flags);
        _ = HeapFree(GetProcessHeap(), 0, raw);
    }
}
extern "kernel32" fn GetCurrentProcess() callconv(.winapi) HANDLE;
extern "kernel32" fn SetProcessWorkingSetSize(hProcess: HANDLE, dwMinimumWorkingSetSize: usize, dwMaximumWorkingSetSize: usize) callconv(.winapi) BOOL;
extern "kernel32" fn CreateFileA(lpFileName: [*:0]const u8, dwDesiredAccess: DWORD, dwShareMode: DWORD, lpSecurityAttributes: ?*anyopaque, dwCreationDisposition: DWORD, dwFlagsAndAttributes: DWORD, hTemplateFile: ?HANDLE) callconv(.winapi) HANDLE;
extern "kernel32" fn WriteFile(hFile: HANDLE, lpBuffer: [*]const u8, nNumberOfBytesToWrite: DWORD, lpNumberOfBytesWritten: *DWORD, lpOverlapped: ?*anyopaque) callconv(.winapi) BOOL;
extern fn __llvm_profile_get_size_for_buffer() callconv(.c) usize;
extern fn __llvm_profile_write_buffer([*]u8) i32;
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
const InterceptionPredicate = *const fn (InterceptionDevice) callconv(.c) i32;
var fp_set_filter: ?*const fn (InterceptionContext, InterceptionPredicate, u16) callconv(.c) void = null;
var fp_receive: ?*const fn (InterceptionContext, InterceptionDevice, [*]InterceptionKeyStroke, u32) callconv(.c) i32 = null;
var fp_wait_with_timeout: ?*const fn (InterceptionContext, u32) callconv(.c) InterceptionDevice = null;
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
inline fn interception_set_filter(ctx: InterceptionContext, pred: InterceptionPredicate, filter: u16) void {
    if (fp_set_filter) |f| f(ctx, pred, filter);
}
inline fn interception_receive(ctx: InterceptionContext, dev: InterceptionDevice, stroke: [*]InterceptionKeyStroke, n: u32) i32 {
    return if (fp_receive) |f| f(ctx, dev, stroke, n) else 0;
}
inline fn interception_wait_with_timeout(ctx: InterceptionContext, timeout_ms: u32) InterceptionDevice {
    return if (fp_wait_with_timeout) |f| f(ctx, timeout_ms) else 0;
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

const RETIRED_ALLOCATION_MAX: usize = 4096;
var g_retiredEmptyBytes: [0]u8 = .{};
const RetiredAllocation = struct {
    bytes: []u8,
};
const RetiredAllocationNode = struct {
    ptr: ?*anyopaque = null,
    len: usize = 0,
    next: ?*RetiredAllocationNode = null,
};
var g_retiredAllocations: [RETIRED_ALLOCATION_MAX]RetiredAllocation =
    [_]RetiredAllocation{.{ .bytes = g_retiredEmptyBytes[0..] }} ** RETIRED_ALLOCATION_MAX;
var g_retiredAllocationLen: usize = 0;
var g_retiredAllocationOverflowHead: ?*RetiredAllocationNode = null;
var g_retiredAllocationOverflowLen: u32 = 0;
var g_retiredAllocationOverflowDropped: u32 = 0;
var g_retiredAllocationEmergency: []u8 = g_retiredEmptyBytes[0..];
var g_retiredAllocationEmergencyDropped: u32 = 0;
var g_retiredAllocationLock: i32 = 0;

inline fn acquireRetiredAllocationLock() void {
    while (@atomicRmw(i32, &g_retiredAllocationLock, .Xchg, 1, .acq_rel) != 0) {
        Sleep(0);
    }
}

inline fn releaseRetiredAllocationLock() void {
    @atomicStore(i32, &g_retiredAllocationLock, 0, .release);
}

inline fn sliceBytes(comptime T: type, slice: []T) []u8 {
    return @as([*]u8, @ptrCast(slice.ptr))[0 .. slice.len * @sizeOf(T)];
}

fn runtimeCanReclaimRetiredAllocations() bool {
    return (g_retiredAllocationLen != 0 or g_retiredAllocationOverflowHead != null or g_retiredAllocationEmergency.len != 0) and
        g_trackedPhysicalKeysDown == 0 and
        @atomicLoad(i32, &g_hotPathActiveCount, .acquire) == 0 and
        @atomicLoad(i32, &g_setupPublishLock, .acquire) == 0 and
        @atomicLoad(i32, &g_runtimePublishInProgress, .acquire) == 0 and
        @atomicLoad(u32, &g_runtimePublishPendingMask, .acquire) == 0 and
        !g_bulkRuntimeHotkeysDirty and
        !g_bulkRuntimeModifiersDirty and
        !g_bulkRuntimePassthroughsDirty and
        !g_bulkRuntimeContextActionsDirty and
        !g_bulkRuntimeCombosDirty and
        !g_bulkRuntimeChordsDirty and
        !g_bulkRuntimeHotstringsDirty and
        !g_bulkRuntimeKeyGateDirty and
        !g_runtimeHotkeyContextsDirty and
        !g_hsContextIndexDirty and
        @atomicLoad(i32, &g_nativePasteInFlight, .acquire) == 0 and
        @atomicLoad(u32, &g_nativePasteHead, .acquire) == @atomicLoad(u32, &g_nativePasteTail, .acquire);
}

fn reclaimRetiredAllocationsIfSafe() void {
    acquireRetiredAllocationLock();
    defer releaseRetiredAllocationLock();
    if (!runtimeCanReclaimRetiredAllocations()) return;
    if (g_retiredAllocationEmergency.len != 0) {
        gAlloc.free(g_retiredAllocationEmergency);
        g_retiredAllocationEmergency = g_retiredEmptyBytes[0..];
    }
    var i: usize = 0;
    while (i < g_retiredAllocationLen) : (i += 1) {
        if (g_retiredAllocations[i].bytes.len != 0) {
            gAlloc.free(g_retiredAllocations[i].bytes);
            g_retiredAllocations[i].bytes = g_retiredEmptyBytes[0..];
        }
    }
    g_retiredAllocationLen = 0;
    var node = g_retiredAllocationOverflowHead;
    g_retiredAllocationOverflowHead = null;
    g_retiredAllocationOverflowLen = 0;
    while (node) |n| {
        const next = n.next;
        if (n.ptr) |ptr| {
            gAlloc.free(@as([*]u8, @ptrCast(ptr))[0..n.len]);
        }
        _ = HeapFree(GetProcessHeap(), 0, n);
        node = next;
    }
}

fn freeRetiredAllocationsNow() void {
    acquireRetiredAllocationLock();
    defer releaseRetiredAllocationLock();
    if (g_retiredAllocationEmergency.len != 0) {
        gAlloc.free(g_retiredAllocationEmergency);
        g_retiredAllocationEmergency = g_retiredEmptyBytes[0..];
    }
    var i: usize = 0;
    while (i < g_retiredAllocationLen) : (i += 1) {
        if (g_retiredAllocations[i].bytes.len != 0) {
            gAlloc.free(g_retiredAllocations[i].bytes);
            g_retiredAllocations[i].bytes = g_retiredEmptyBytes[0..];
        }
    }
    g_retiredAllocationLen = 0;
    var node = g_retiredAllocationOverflowHead;
    g_retiredAllocationOverflowHead = null;
    g_retiredAllocationOverflowLen = 0;
    while (node) |n| {
        const next = n.next;
        if (n.ptr) |ptr| {
            gAlloc.free(@as([*]u8, @ptrCast(ptr))[0..n.len]);
        }
        _ = HeapFree(GetProcessHeap(), 0, n);
        node = next;
    }
}

fn retireBytes(bytes: []u8) void {
    if (bytes.len == 0) return;
    reclaimRetiredAllocationsIfSafe();
    acquireRetiredAllocationLock();
    defer releaseRetiredAllocationLock();
    if (g_retiredAllocationLen < g_retiredAllocations.len) {
        g_retiredAllocations[g_retiredAllocationLen] = .{ .bytes = bytes };
        g_retiredAllocationLen += 1;
        return;
    }
    if (HeapAlloc(GetProcessHeap(), 0, @sizeOf(RetiredAllocationNode))) |raw_node| {
        const node: *RetiredAllocationNode = @ptrCast(@alignCast(raw_node));
        node.* = .{
            .ptr = bytes.ptr,
            .len = bytes.len,
            .next = g_retiredAllocationOverflowHead,
        };
        g_retiredAllocationOverflowHead = node;
        g_retiredAllocationOverflowLen +%= 1;
        return;
    }
    g_retiredAllocationOverflowDropped +%= 1;
    if (runtimeCanReclaimRetiredAllocations()) {
        gAlloc.free(bytes);
    } else if (g_retiredAllocationEmergency.len == 0) {
        g_retiredAllocationEmergency = bytes;
    } else {
        // Last-resort fail-closed path: leak instead of freeing memory the hot
        // path may still be reading after an overflow-node allocation failure.
        g_retiredAllocationEmergencyDropped +%= 1;
    }
}

fn retireSlice(comptime T: type, slice: []T) void {
    if (slice.len == 0) return;
    retireBytes(sliceBytes(T, slice));
}
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
inline fn profStart() i64 {
    if (!g_profilingEnabled) return 0;
    return @as(i64, @bitCast(rdtsc()));
}
inline fn profRecord(ring: *ProfRing, start: i64) void {
    if (start == 0) return;
    const end = @as(i64, @bitCast(rdtsc()));
    const delta = @as(f64, @floatFromInt(end - start)) * g_qpcToUs;
    ring.append(delta);
}
// ============================================================================
// Section 4B — Per-section delta-timing profiling
// ============================================================================
//
// Scoped profSpan() calls record selected branch bodies or Windows/API calls.
//
// Section ID ranges:
//   0 .. KD_SECTIONS-1          : bufferKeyDown
//   KD_SECTIONS .. KU_BASE+KU_SECTIONS-1 : bufferKeyUp
//   PKE_BASE .. PKE_BASE+PKE_SECTIONS-1  : processKeyEventHot
// ============================================================================
const KD_SECTIONS: usize = 224;
const KU_SECTIONS: usize = 245;
const PKE_SECTIONS: usize = 24;
const PQ_SECTIONS: usize = 64;
const TOTAL_SECTIONS: usize = KD_SECTIONS + KU_SECTIONS + PKE_SECTIONS + PQ_SECTIONS;
const KU_BASE: usize = KD_SECTIONS;
const PKE_BASE: usize = KD_SECTIONS + KU_SECTIONS;
const PQ_BASE: usize = KD_SECTIONS + KU_SECTIONS + PKE_SECTIONS;

const SECT_MAX_SAMPLES: u32 = 1000;
const SectionProfRing = struct {
    buf: [SECT_MAX_SAMPLES]u32 = [_]u32{0} ** SECT_MAX_SAMPLES,
    len: u32 = 0,
    head: u32 = 0,
    fn append(self: *SectionProfRing, v: u32) void {
        self.buf[self.head] = v;
        self.head = (self.head + 1) % SECT_MAX_SAMPLES;
        if (self.len < SECT_MAX_SAMPLES) self.len += 1;
    }
};

var g_sectionRings: [TOTAL_SECTIONS]SectionProfRing =
    [_]SectionProfRing{.{}} ** TOTAL_SECTIONS;

/// Start a per-section timing pass. Returns 0 when profiling is disabled.
inline fn profStartSect() i64 {
    if (comptime !microbenchdebug) return 0;
    if (!g_profilingEnabled) {
        @branchHint(.unlikely);
        return 0;
    }
    return @as(i64, @bitCast(rdtsc()));
}

/// Record a scoped block/call duration in nanoseconds.
/// Use this around branch bodies or Windows/API calls that are worth sampling.
inline fn profSpan(section_id: usize, start: i64) void {
    if (comptime !microbenchdebug) return;
    if (start == 0) {
        @branchHint(.unlikely);
        return;
    }
    if (section_id >= TOTAL_SECTIONS) return;
    var now: i64 = 0;
    now = @as(i64, @bitCast(rdtsc()));
    const delta: i64 = now - start;
    const delta_ns: u32 = @intCast(@min(
        @as(u64, @intFromFloat(@as(f64, @floatFromInt(delta)) * g_qpcToNs)),
        @as(u64, std.math.maxInt(u32)),
    ));
    g_sectionRings[section_id].append(delta_ns);
}

// Extern struct returned per section — matched in bench file.
const SectionStat = extern struct {
    min_ns: u32,
    median_ns: u32,
    p95_ns: u32,
    max_ns: u32,
    count: u32,
};

export fn QMK_ResetSectionData() callconv(.c) void {
    if (comptime !microbenchdebug) return;
    for (&g_sectionRings) |*r| {
        r.len = 0;
        r.head = 0;
    }
}

export fn QMK_GetSectionLayout(out: [*]u32, max_items: u32) callconv(.c) u32 {
    if (max_items < 5) return 0;
    out[0] = @intCast(KD_SECTIONS);
    out[1] = @intCast(KU_SECTIONS);
    out[2] = @intCast(PKE_SECTIONS);
    out[3] = @intCast(PQ_SECTIONS);
    out[4] = @intCast(TOTAL_SECTIONS);
    return 5;
}

export fn QMK_GetSectionStats(out: [*]SectionStat, max_sections: u32) callconv(.c) u32 {
    if (comptime !microbenchdebug) return 0;
    const n: usize = @min(@as(usize, max_sections), TOTAL_SECTIONS);
    for (0..n) |i| {
        const ring = &g_sectionRings[i];
        const count: u32 = ring.len;
        if (count == 0) {
            out[i] = .{ .min_ns = 0, .median_ns = 0, .p95_ns = 0, .max_ns = 0, .count = 0 };
            continue;
        }
        // Copy to stack and sort.
        var tmp: [SECT_MAX_SAMPLES]u32 = undefined;
        @memcpy(tmp[0..count], ring.buf[0..count]);
        // Insertion sort (count <= 1000).
        var si: usize = 1;
        while (si < count) : (si += 1) {
            const key = tmp[si];
            var sj: usize = si;
            while (sj > 0 and tmp[sj - 1] > key) : (sj -= 1) tmp[sj] = tmp[sj - 1];
            tmp[sj] = key;
        }
        const p95_idx: usize = @min(count - 1, (count * 95) / 100);
        out[i] = .{
            .min_ns = tmp[0],
            .median_ns = tmp[count / 2],
            .p95_ns = tmp[p95_idx],
            .max_ns = tmp[count - 1],
            .count = count,
        };
    }
    return @intCast(n);
}

// ============================================================================
// Section 5 — Constants, limits, string helpers
// ============================================================================
const VK_COUNT = 256; // All real Windows VK codes fit in 0-254; was 512 (512 KB combo matrices ? now 128 KB)
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
fn weqASCII(wide: [*:0]const u16, ascii: []const u8) bool {
    for (ascii, 0..) |c, i| if (wide[i] != c) return false;
    return wide[ascii.len] == 0;
}
fn weqASCIIIgnoreCase(wide: [*:0]const u16, ascii: []const u8) bool {
    for (ascii, 0..) |c, i| {
        const wc = wide[i];
        const wl: u16 = if (wc >= 'A' and wc <= 'Z') wc + ('a' - 'A') else wc;
        const ac: u16 = c;
        const al: u16 = if (ac >= 'A' and ac <= 'Z') ac + ('a' - 'A') else ac;
        if (wl != al) return false;
    }
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
fn copyWideZToSlice(dst: []u16, src: [*:0]const u16) void {
    @memset(dst, 0);
    var i: usize = 0;
    while (src[i] != 0 and i < dst.len - 1) : (i += 1) dst[i] = src[i];
}
fn timerHash(id: []const u16) u64 {
    // FNV-1a 64-bit over u8 bytes of the u16 slice. Faster than Wyhash for
    // short strings (=80 u16 chars) because it avoids secret-mixing overhead.
    var h: u64 = 14695981039346656037;
    for (id) |c| {
        h ^= @as(u8, @intCast(c & 0xFF));
        h *%= 1099511628211;
        h ^= @as(u8, @intCast(c >> 8));
        h *%= 1099511628211;
    }
    return h;
}
fn timerHashZ(id: [*:0]const u16) u64 {
    // Inline wlen to avoid the double-pass (wlen then hash).
    var h: u64 = 14695981039346656037;
    var i: usize = 0;
    while (id[i] != 0) : (i += 1) {
        h ^= @as(u8, @intCast(id[i] & 0xFF));
        h *%= 1099511628211;
        h ^= @as(u8, @intCast(id[i] >> 8));
        h *%= 1099511628211;
    }
    return h;
}
fn buildTid(dest: *[TID_LEN]u16, pk: *const [KN_LEN]u16, sep: []const u8, sk: *const [KN_LEN]u16) u64 {
    // No @memset: we only write dest[0..pos] and only hash that range.
    // The tail of dest is irrelevant to both the hash and the caller
    // (PendingTimer zeroes its own timerId at declaration).
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

// ============================================================================
// Phase 1: Precomputed keydown/keyup action classification
// Computed during rebuild_runtime_vk_plan() from static per-key facts only.
// ============================================================================
const KeyDownAction = enum(u8) {
    fallback_slow = 0, // Slow path: may need complex processing
    phys_mod = 1, // Physical modifier
    sys_mod = 2, // System modifier
    strict_plain_fast = 3, // Plain key with no modifiers/holds/secondaries
    taplike_primary_candidate = 4, // May be combo/instant primary but taplike on down
};

const KeyUpAction = enum(u8) {
    fallback_slow = 0, // Slow path: may need complex processing
    phys_mod_up = 1, // Physical modifier release
    sys_mod_up = 2, // System modifier release
    idle_unbuffered_noop_candidate = 3, // Never buffered plain key, likely noop
    repeat_stop_candidate = 4, // May need repeat stop logic
};

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
// Runtime state: the current VK is being treated as an active modifier.
const RUNTIME_CURRENT_VK_IS_ACTIVE_MODIFIER: u16 = 0x0010;
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
const FLAG_CHORD_PENDING: u16 = 0x0800;
// tidHashes split into a parallel array so KeyData stays =32 bytes (2 per cache line).
// The timer id fingerprint data is cold (written once at timer registration, never read on the
// per-keystroke scan loop), so there is no benefit keeping it inside KeyData.
// Access via g_kbTidHashes[slot][0..kd.tidCount] — slot is the same index used by
// g_kbVK / g_kbData, so the lookup is O(1) and requires no pointer arithmetic.
const KEY_TID_HASHES_SENTINEL: u64 = 0;
var g_kbTidHashes: [KB_MAX][KEY_TIMERS_MAX]u64 =
    [_][KEY_TIMERS_MAX]u64{[_]u64{0} ** KEY_TIMERS_MAX} ** KB_MAX;

const KeyData = struct {
    // HOT — 32 bytes total, 2 entries per 64-byte cache line.
    downTime: i64 = 0, // 8 bytes
    releaseTime: i64 = 0, // 8 bytes
    sameModTidHash: u64 = 0, // 8 bytes  (WARM but needed in key-up fast path)
    flags: u16 = 0, // 2 bytes
    actionType: ActionType = .undecided, // 1 byte
    tidCount: u8 = 0, // 1 byte
    sameModPartnerVK: i32 = 0, // 4 bytes
    // tidHashes moved to g_kbTidHashes[slotIndex] — see addTidHash / cancelKeyTimers.
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
// Reads whether this key-data record currently treats its VK as an active modifier.
    inline fn isRuntimeModifier(self: KeyData) bool {
        return self.f(RUNTIME_CURRENT_VK_IS_ACTIVE_MODIFIER);
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
    inline fn chordPending(self: KeyData) bool {
        return self.f(FLAG_CHORD_PENDING);
    }
    inline fn inSendModifiedRepeatMode(self: KeyData) bool {
        return self.f(FLAG_SEND_MODIFIED_REPEAT);
    }
    fn addTidHash(self: *KeyData, h: u64) void {
        // Slot index: derive from pointer position in g_kbData.
        // @intFromPtr arithmetic gives the slot without a search.
        const slot = (@intFromPtr(self) - @intFromPtr(&g_kbData[0])) / @sizeOf(KeyData);
        if (self.tidCount < KEY_TIMERS_MAX and slot < KB_MAX) {
            var i: u8 = 0;
            while (i < self.tidCount) : (i += 1) {
                if (g_kbTidHashes[slot][@intCast(i)] == h) return;
            }
            g_kbTidHashes[slot][self.tidCount] = h;
            self.tidCount += 1;
        }
    }
};
const PendingCallback = struct {
    callbackId: i32,
    key1: [KN_LEN]u16 = [_]u16{0} ** KN_LEN, // was [64] — KN_LEN=32 is the actual max
    key2: [8]u16 = [_]u16{0} ** 8,
    type_: i32,
    vk: i32,
    modifierMask: u16,
};
const RuntimeHotkey = struct {
    triggerVK: i32 = 0,
    modsRequired: u16 = 0,
    modsForbidden: u16 = 0,
    callbackId: i32 = 0,
    holdCallbackId: i32 = -1,
    cleanupCallbackId: i32 = -1,
    thresholdTicks: i64 = 0,
    triggerKind: u8 = 0,
    actionKind: u8 = 0, // 0=normal dispatch, 1=contextual tap resolved on key-up
    suppressOriginal: bool = true,
    contextKind: u8 = 7,
    contextNegated: bool = false,
    contextLen: u16 = 0,
    specificityMask: u8 = 0,
    physicalModVK: u8 = 0,
    physicalModsRequired: u8 = 0,
    physicalModsForbidden: u8 = 0,
    suspendExempt: bool = false,
};
const RuntimeContextAction = struct {
    triggerVK: i32 = 0,
    callbackId: i32 = -1,
    tapCallbackId: i32 = -1,
    holdCallbackId: i32 = -1,
    actionKind: u8 = 0, // 0=hold, 1=double-tap, 2/3=legacy tap/hold parts, 4=complete tap/hold registration
    thresholdTicks: i64 = 0,
    contextKind: u8 = 7,
    contextNegated: bool = false,
    contextLen: u16 = 0,
    specificityMask: u8 = 0,
    suspendExempt: bool = false,
};
const RuntimeModifier = struct {
    vk: i32 = 0,
    modType: i8 = MOD_NONE,
    contextKind: u8 = 7,
    contextNegated: bool = false,
    contextLen: u16 = 0,
    specificityMask: u8 = 0,
    suspendExempt: bool = false,
};
const RuntimePassthrough = struct {
    vk: i32 = 0,
    contextKind: u8 = 7,
    contextNegated: bool = false,
    contextLen: u16 = 0,
    specificityMask: u8 = 0,
    suspendExempt: bool = false,
};
const RuntimeCombo = struct {
    primaryVK: i32 = 0,
    secondaryVK: i32 = 0,
    callbackId: i32 = -1,
    targetVK: i32 = 0,
    modMask: u16 = 0,
    mode: u8 = 0, // 0=normal callback, 1=instant callback, 2=internal, 3=internal instant
    contextKind: u8 = 7,
    contextNegated: bool = false,
    contextLen: u16 = 0,
    specificityMask: u8 = 0,
    suspendExempt: bool = false,
    registrationOrder: u32 = 0,
};
const RuntimeChord = struct {
    key: u64 = 0,
    vks: [5]i32 = [_]i32{0} ** 5,
    callbackId: i32 = -1,
    targetVK: i32 = 0,
    modMask: u16 = 0,
    keyCount: u8 = 0,
    mode: u8 = 0, // 0=callback, 1=internal remap
    contextKind: u8 = 7,
    contextNegated: bool = false,
    contextLen: u16 = 0,
    specificityMask: u8 = 0,
    suspendExempt: bool = false,
};
const PendingTimer = struct {
    timerId: [TID_LEN]u16 = [_]u16{0} ** TID_LEN,
    tidHash: u64 = 0,
    delay: i32,
    timerType: i32,
    primaryKey: [KN_LEN]u16 = [_]u16{0} ** KN_LEN,
    secondaryKey: [KN_LEN]u16 = [_]u16{0} ** KN_LEN,
    captureTime: i64,
};
const SCHED_MAX = 32;
const SchedEntry = struct {
    tidHash: u64 = 0,
    deadline: i64 = 0,
    timerType: i32 = 0,
    primaryKey: [KN_LEN]u16 = [_]u16{0} ** KN_LEN,
    secondaryKey: [KN_LEN]u16 = [_]u16{0} ** KN_LEN,
    captureTime: i64 = 0,
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

// ============================================================================
// Runtime hotkey context state — written by QMK_SetContextState.
// Compiled QMKHotkeys.zig is imported only for explicit compiled-shortcut builds.
// ============================================================================
const HotkeyContextState = extern struct {
    generation: u32 = 0,
    has_context_menu: u8 = 0,
    win_title: [512]u16 = [_]u16{0} ** 512,
    win_exe: [256]u16 = [_]u16{0} ** 256,
    win_class: [256]u16 = [_]u16{0} ** 256,
    url: [512]u16 = [_]u16{0} ** 512,
};

const QMKCoreHotkeyContextState = HotkeyContextState;

const hotkeys = struct {
    pub const HOTKEY_MOD_CTRL: u16 = 0x0001;
    pub const HOTKEY_MOD_ALT: u16 = 0x0002;
    pub const HOTKEY_MOD_SHIFT: u16 = 0x0004;
    pub const HOTKEY_MOD_WIN: u16 = 0x0008;
    pub const HotkeyContextState = QMKCoreHotkeyContextState;
    pub const CompiledHotkey = struct {};
    pub const HOTKEYS = [_]CompiledHotkey{};
    pub const CAPSLOCK_CLEANUP_HOTKEY_INDEX: i32 = -1;
    pub const CAPSLOCK_HOLD_HOTKEY_INDEX: i32 = -1;
    pub const CAPSLOCK_TAP_HOTKEY_INDEX: i32 = -1;
};

pub var g_hotkeyContextState: hotkeys.HotkeyContextState = .{};
var g_contextMenuDigitAccessVK: [10]i32 = [_]i32{0} ** 10;
// Registration facts used by the input hot path. These are deliberately
// separate from the active matching gate: a contextual row may be inactive
// in the last published context, but its VK still needs a cheap synchronous
// foreground-context refresh before matching the current press.
var g_compiledHotkeyGate: [256]bool = [_]bool{false} ** 256;
// The guarded Zig suite supplies a synthetic context directly.  Keep the
// production foreground refresh untouched, but let that suite prevent the
// desktop's unrelated foreground window from overwriting its fixture.
var g_testSuppressForegroundRefresh: bool = false;

// --- QPC timer ---
var g_qpcFreq: i64 = 0;
var g_qpcToMs: f64 = 0; // 1_000.0 / g_qpcFreq
var g_qpcToUs: f64 = 0; // 1_000_000.0 / g_qpcFreq
var g_qpcToNs: f64 = 0; // 1_000_000_000.0 / g_qpcFreq
var g_timerInit: bool = false;
// --- Interception ---
var g_sendCtx: InterceptionContext = null;
var g_sendDev: InterceptionDevice = 0;
var g_captureCtx: InterceptionContext = null;
var g_useKernel: bool = true;
// Global text-paste strategy selected by the AHK settings GUI.
// 0 = interception paste, 1 = interception character send,
// 2 = SendInput paste, 3 = SendInput Unicode characters,
// 4 = Win32 keybd_event (SendEvent semantics) from this DLL.
var g_pasteMode: i32 = 0;
var g_sendModeAuto: bool = true;
var g_profilingEnabled: bool = false; // on by default
var g_suppressOutputForReplay: bool = false;
// Send readiness is independent from capture readiness. The LL hook backend can
// capture in user mode while still sending through Interception when available.
var g_interceptionSendReady: bool = false;
var g_interceptionCaptureReady: bool = false;
var g_pollThreadActive: i32 = 0;
var g_pollStopGeneration: i32 = 0;
var g_interceptionInitActive: i32 = 0;
var g_interceptionInitGeneration: i32 = 0;
var g_interceptionInitThreadGeneration: i32 = 0;
var g_inputBackend: i32 = INPUT_BACKEND_AUTO;
var g_llHookHandle: ?HANDLE = null;
var g_llHookThreadActive: i32 = 0;
var g_llHookStopGeneration: i32 = 0;
var g_llHookThreadId: DWORD = 0;
var g_llHookReady: bool = false;
var g_llHookEventCount: i32 = 0;
var g_llHookLastVK: i32 = 0;
var g_llHookLastScan: i32 = 0;
var g_llHookLastFlags: i32 = 0;
var g_llHookLastIsDown: i32 = 0;
var g_llHookLastMods: u16 = 0;
var g_llHookLastConsumed: i32 = 0;
const INTERCEPTION_FILTER_KEY_NONE: u16 = 0x0000;
const INTERCEPTION_FILTER_KEY_ALL: u16 = 0xFFFF;
// --- Double-tap repeat ---
const RepeatCmd = extern struct {
    op: u32,
    vk: i32,
    id: u64,
    interval_ticks: i64,
    first_deadline: i64,
    first_emit_pending: i32,
};

const RepeatSlot = extern struct {
    cmd: RepeatCmd,
    pad: [64 - @sizeOf(RepeatCmd)]u8,
};

const RP_BOOT: i32 = 0;
const RP_SLEEPING: i32 = 1;
const RP_FIRST_EMIT: i32 = 2;
const RP_ARMED: i32 = 3;
const RP_EMITTING: i32 = 4;
const RP_STOPPING: i32 = 6;
const REPEAT_IDLE_OBSERVE_MS: DWORD = 1;
const REPEAT_ACTION_TAP: i32 = 0;
const REPEAT_ACTION_DIRECT: i32 = 1;
const REPEAT_ACTION_CALLBACK: i32 = 2;

const RepeatState = struct {
    handle: ?HANDLE = null,
    cancel_event: ?HANDLE = null,
    worker_handle: ?HANDLE = null,
    wake_event: ?HANDLE = null,
    timer: ?HANDLE = null,
    worker_active: i32 = 0, // atomic
    active: i32 = 0, // atomic
    vk: i32 = 0, // atomic
    generation: usize = 1, // atomic; invalidates old repeat threads
    next_due: i64 = 0, // atomic QPC tick
    interval: i64 = 0, // atomic QPC ticks
    first_emit_pending: i32 = 0, // atomic
    worker_phase: i32 = RP_BOOT, // atomic
    armed_due: i64 = 0, // atomic QPC tick
    wake_skipped_count: u64 = 0, // atomic, section-bench diagnostics
    action_kind: i32 = REPEAT_ACTION_TAP, // atomic
    action_target_vk: i32 = 0, // atomic
    action_mod_mask: u32 = 0, // atomic
    action_callback_id: i32 = -1, // atomic
    action_callback_type: i32 = 0, // atomic
    action_name_vk: i32 = 0, // atomic
    required_key: u64 = 0, // atomic packed sorted VKs
    required_len: u32 = 0, // atomic
};

var g_repeat = RepeatState{};
var g_repeatEmitCount: u64 = 0; // atomic, replay/stress diagnostics

// --- Async SendInput Thread State ---
const ASYNC_RING_SIZE = 1024;
var g_async_ring: [ASYNC_RING_SIZE]InputSlot align(64) = undefined;
var g_async_head: u32 = 0;
var g_async_tail: u32 = 0;
var g_sendRingLock: i32 = 0;
// Combo callback repeat can append from the repeat worker while the input/AHK
// paths also inspect or drain this staging queue.
var g_pendingCBLock: i32 = 0;
inline fn acquirePendingCBLock() void {
    while (@atomicRmw(i32, &g_pendingCBLock, .Xchg, 1, .acq_rel) != 0) {
        Sleep(0);
    }
}
inline fn releasePendingCBLock() void {
    @atomicStore(i32, &g_pendingCBLock, 0, .release);
}
// Serializes runtime setup/context publishers. The input hot path continues to
// read the last published active banks while the next family is being built.
var g_setupPublishLock: i32 = 0;
var g_setupPublishLockOwnerThreadId: u32 = 0;
var g_setupPublishLockRecursion: u32 = 0;
var g_asyncSendDropCount: u64 = 0;
var g_async_event: ?HANDLE = null;
var g_async_thread: ?HANDLE = null;
var g_async_active: i32 = 0;
// --- Key registry (flat; O(1) VK?index via g_vkToRegIdx) ---
var g_keyVKs: [VK_COUNT]i32 = [_]i32{0} ** VK_COUNT;
var g_keyNames: [VK_COUNT][KN_LEN]u16 = undefined; // zeroed in QMK_Init
var g_modTypes: [VK_COUNT]i8 = [_]i8{MOD_NONE} ** VK_COUNT;
var g_keyCount: u32 = 0;
var g_vkToRegIdx: [VK_COUNT]i16 = [_]i16{-1} ** VK_COUNT;
// --- Key buffer (parallel arrays + O(1) VK?slot via g_kbIdx) ---
var g_kbVK: [KB_MAX]i32 = [_]i32{0} ** KB_MAX;
var g_kbData: [KB_MAX]KeyData = [_]KeyData{.{}} ** KB_MAX;
var g_kbLen: usize = 0;
var g_kbIdx: [VK_COUNT]i16 = [_]i16{-1} ** VK_COUNT;
var g_recentKeyUpCount: i32 = 0;
var g_activeComboPrimaryCount: i32 = 0;
// --- Key order (ring buffer so ordRemoveFirst is O(1)) ---
var g_keyOrder: [ORD_MAX]i32 = [_]i32{0} ** ORD_MAX;
var g_ordHead: usize = 0;
var g_ordLen: usize = 0;
// Reverse index: VK -> absolute slot in the ring.
// -1 = not present.  Maintained by ordAppend, ordRemoveFirst, ordRemoveAt, ordClear.
// Makes removeFromKeyOrder O(1) instead of O(n).
var g_ordIdx: [VK_COUNT]i16 = [_]i16{-1} ** VK_COUNT;
// --- Active timers: fixed flat keyed set ---
// 64-slot table (power of 2), load = ACT_MAX/64 = 50%.
// Sentinel: 0 = empty. Hash values of 0 are remapped to 1 at insert time.
// timerAdd/timerRemove are now O(1) average vs the old O(ACT_MAX) linear scan.
const TIMER_SLOTS: usize = 64;
const TIMER_MASK: u64 = TIMER_SLOTS - 1;
var g_timerSet: [TIMER_SLOTS]u64 = [_]u64{0} ** TIMER_SLOTS;
var g_timerLen: usize = 0;
var g_sched: [SCHED_MAX]SchedEntry = [_]SchedEntry{.{}} ** SCHED_MAX;
var g_schedLen: usize = 0;
var g_schedEvent: ?HANDLE = null;
var g_schedTimer: ?HANDLE = null;
var g_schedThread: ?HANDLE = null;
var g_schedActive: i32 = 0;
// --- Pending callbacks / timers ---
var g_pendingCBs: [PCB_MAX]PendingCallback = undefined;
var g_pendingCBsLen: usize = 0;
const RUNTIME_CALLBACK_EXEMPT_INITIAL_CAP: usize = 8192;
var g_runtimeCallbackSuspendExemptEmpty: [0]bool = .{};
var g_runtimeCallbackSuspendExempt: []bool = g_runtimeCallbackSuspendExemptEmpty[0..];
const RUNTIME_HOTKEY_CONTEXT_CHARS: usize = 256;
const RUNTIME_HOTKEY_INITIAL_CAP: usize = 2048;
const STATIC_HOTKEY_MATCH_CAP: usize = hotkeys.HOTKEYS.len;
const RuntimeHotkeyText = [RUNTIME_HOTKEY_CONTEXT_CHARS]u16;
var g_runtimeHotkeysEmpty: [0]RuntimeHotkey = .{};
var g_runtimeHotkeyContextsEmpty: [0]RuntimeHotkeyText = .{};
var g_runtimeHotkeys: []RuntimeHotkey = g_runtimeHotkeysEmpty[0..];
var g_runtimeHotkeyContexts: []RuntimeHotkeyText = g_runtimeHotkeyContextsEmpty[0..];
var g_runtimeHotkeysCap: usize = 0;
var g_runtimeHotkeysLen: usize = 0;
var g_runtimeHotkeysPublishedLen: usize = 0;
// Published length advances after runtime setup. This separate boundary
// remains fixed at the end of the compiled preload for overlay matching.
var g_compiledHotkeysLen: usize = 0;
var g_runtimeHotkeyGate: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_runtimeContextHotkeyGate: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_runtimeHotkeysSuspended: i32 = 0;
var g_panicExitVK: i32 = 0;
var g_panicExitModsRequired: u16 = 0;
var g_panicExitModsForbidden: u16 = 0xFFFF;
var g_panicExitEnabled: i32 = 0;
var g_nativeReloadVK: i32 = 0;
var g_nativeReloadModsRequired: u16 = 0;
var g_nativeReloadModsForbidden: u16 = 0xFFFF;
var g_nativeReloadEnabled: i32 = 0;
var g_nativeSuspendVK: i32 = 0;
var g_nativeSuspendModsRequired: u16 = 0;
var g_nativeSuspendModsForbidden: u16 = 0xFFFF;
var g_nativeSuspendEnabled: i32 = 0;
var g_nativeSuspendKeyDown: bool = false;
const RUNTIME_CONTEXT_ACTION_CHARS: usize = 256;
const RUNTIME_CONTEXT_ACTION_INITIAL_CAP: usize = 1024;
const RuntimeContextActionText = [RUNTIME_CONTEXT_ACTION_CHARS]u16;
var g_runtimeContextActionsEmpty: [0]RuntimeContextAction = .{};
var g_runtimeContextActionTextsEmpty: [0]RuntimeContextActionText = .{};
var g_runtimeContextActions: []RuntimeContextAction = g_runtimeContextActionsEmpty[0..];
var g_runtimeContextActionTexts: []RuntimeContextActionText = g_runtimeContextActionTextsEmpty[0..];
var g_runtimeContextActionsCap: usize = 0;
var g_runtimeContextActionsLen: usize = 0;
var g_runtimeContextActionsPublishedLen: usize = 0;
var g_compiledContextActionsLen: usize = 0;
var g_runtimeHoldTouched: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_runtimeContextActionGate: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_runtimeDoubleTapTouched: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_runtimeTapHoldTapTouched: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_runtimeTapHoldHoldTouched: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;

const RuntimeContextActionActiveBank = struct {
    hold: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT,
    doubleTap: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT,
    tapHoldTap: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT,
    tapHoldHold: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT,
    tapHoldCleanup: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT,
    tapHoldThreshold: [VK_COUNT]i64 = [_]i64{0} ** VK_COUNT,
    tapHoldTuningSet: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT,
};
var g_runtimeContextActionActiveBanks: [2]RuntimeContextActionActiveBank = .{ .{}, .{} };
var g_activeRuntimeContextActionBank: u32 = 0;

const RUNTIME_MODIFIER_INITIAL_CAP: usize = 256;
var g_runtimeModifiersEmpty: [0]RuntimeModifier = .{};
var g_runtimeModifierTextsEmpty: [0]RuntimeContextActionText = .{};
var g_runtimeModifiers: []RuntimeModifier = g_runtimeModifiersEmpty[0..];
var g_runtimeModifierTexts: []RuntimeContextActionText = g_runtimeModifierTextsEmpty[0..];
var g_runtimeModifiersCap: usize = 0;
var g_runtimeModifiersLen: usize = 0;
var g_runtimeModifiersPublishedLen: usize = 0;
var g_compiledModifiersLen: usize = 0;
var g_runtimeModifierTouched: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_runtimeContextModifierGate: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_runtimeModifierBaseType: [VK_COUNT]i8 = [_]i8{MOD_NONE} ** VK_COUNT;
const RuntimeModifierActiveBank = struct {
    modType: [VK_COUNT]i8 = [_]i8{MOD_NONE} ** VK_COUNT,
};
var g_runtimeModifierActiveBanks: [2]RuntimeModifierActiveBank = .{ .{}, .{} };
var g_activeRuntimeModifierBank: u32 = 0;

const RUNTIME_PASSTHROUGH_INITIAL_CAP: usize = 128;
var g_runtimePassthroughsEmpty: [0]RuntimePassthrough = .{};
var g_runtimePassthroughTextsEmpty: [0]RuntimeContextActionText = .{};
var g_runtimePassthroughs: []RuntimePassthrough = g_runtimePassthroughsEmpty[0..];
var g_runtimePassthroughTexts: []RuntimeContextActionText = g_runtimePassthroughTextsEmpty[0..];
var g_runtimePassthroughsCap: usize = 0;
var g_runtimePassthroughsLen: usize = 0;
var g_runtimePassthroughsPublishedLen: usize = 0;
var g_compiledPassthroughsLen: usize = 0;
const RuntimePassthroughActiveBank = struct {
    enabled: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT,
};
var g_runtimePassthroughActiveBanks: [2]RuntimePassthroughActiveBank = .{ .{}, .{} };
var g_activeRuntimePassthroughBank: u32 = 0;
var g_bulkRuntimePassthroughsDirty: bool = false;
var g_passthroughsPreparedSerial: u32 = 0;

const RUNTIME_COMBO_CONTEXT_CHARS: usize = 256;
const RUNTIME_COMBO_INITIAL_CAP: usize = 1024;
const RuntimeComboText = [RUNTIME_COMBO_CONTEXT_CHARS]u16;
var g_runtimeCombosEmpty: [0]RuntimeCombo = .{};
var g_runtimeComboTextsEmpty: [0]RuntimeComboText = .{};
var g_runtimeCombos: []RuntimeCombo = g_runtimeCombosEmpty[0..];
var g_runtimeComboTexts: []RuntimeComboText = g_runtimeComboTextsEmpty[0..];
var g_runtimeCombosCap: usize = 0;
var g_runtimeCombosLen: usize = 0;
var g_runtimeCombosPublishedLen: usize = 0;
var g_compiledCombosLen: usize = 0;
var g_runtimeInstantCombosEmpty: [0]RuntimeCombo = .{};
var g_runtimeInstantComboTextsEmpty: [0]RuntimeComboText = .{};
var g_runtimeInstantCombos: []RuntimeCombo = g_runtimeInstantCombosEmpty[0..];
var g_runtimeInstantComboTexts: []RuntimeComboText = g_runtimeInstantComboTextsEmpty[0..];
var g_runtimeInstantCombosCap: usize = 0;
var g_runtimeInstantCombosLen: usize = 0;
var g_runtimeInstantCombosPublishedLen: usize = 0;
var g_compiledInstantCombosLen: usize = 0;
var g_runtimeComboPublishedRegistrationSeq: u32 = 0;
var g_runtimeComboRegistrationSeq: u32 = 0;
const RUNTIME_CHORD_CONTEXT_CHARS: usize = 256;
const RUNTIME_CHORD_INITIAL_CAP: usize = 512;
const RuntimeChordText = [RUNTIME_CHORD_CONTEXT_CHARS]u16;
var g_runtimeChordsEmpty: [0]RuntimeChord = .{};
var g_runtimeChordTextsEmpty: [0]RuntimeChordText = .{};
var g_runtimeChords: []RuntimeChord = g_runtimeChordsEmpty[0..];
var g_runtimeChordTexts: []RuntimeChordText = g_runtimeChordTextsEmpty[0..];
var g_runtimeChordsCap: usize = 0;
var g_runtimeChordsLen: usize = 0;
var g_runtimeChordsPublishedLen: usize = 0;
var g_compiledChordsLen: usize = 0;
// Permanent structural hint for contextual chord lookup. This is separate
// from the active chord bank: an inactive contextual chord still needs a
// context refresh before its candidate can be selected.
var g_runtimeChordContextParticipant: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;

const RUNTIME_MOD_BUCKET_COUNT: usize = 16;
const RuntimeHotkeyRange = struct { start: u32 = 0, len: u32 = 0 };
const RuntimeHotkeyReadyIndex = struct {
    ranges: [VK_COUNT][RUNTIME_MOD_BUCKET_COUNT]RuntimeHotkeyRange = [_][RUNTIME_MOD_BUCKET_COUNT]RuntimeHotkeyRange{
        [_]RuntimeHotkeyRange{.{}} ** RUNTIME_MOD_BUCKET_COUNT,
    } ** VK_COUNT,
    sourceIndexes: []u32,
    activeGate: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT,
};
var g_runtimeHotkeySourceEmpty: [0]u32 = .{};
var g_runtimeHotkeyReadyIndexes: [2]RuntimeHotkeyReadyIndex = .{
    .{ .sourceIndexes = g_runtimeHotkeySourceEmpty[0..] },
    .{ .sourceIndexes = g_runtimeHotkeySourceEmpty[0..] },
};
// Permanent global rows. Built when registration changes; published through a
// second bank so the interception thread never reads a half-cleared index.
var g_runtimeGlobalHotkeyIndexes: [2]RuntimeHotkeyReadyIndex = .{
    .{ .sourceIndexes = g_runtimeHotkeySourceEmpty[0..] },
    .{ .sourceIndexes = g_runtimeHotkeySourceEmpty[0..] },
};
var g_activeRuntimeHotkeyReadyIndex: u32 = 0;
var g_activeRuntimeGlobalHotkeyIndex: u32 = 0;
var g_runtimeHotkeyContextsDirty: bool = false;
var g_bulkSetupDepth: u32 = 0;
var g_bulkRuntimeHotkeysDirty: bool = false;
var g_bulkRuntimeModifiersDirty: bool = false;
var g_bulkRuntimeContextActionsDirty: bool = false;
var g_bulkRuntimeCombosDirty: bool = false;
var g_bulkRuntimeChordsDirty: bool = false;
var g_bulkRuntimeHotstringsDirty: bool = false;
var g_bulkRuntimeKeyGateDirty: bool = false;
var g_bulkSetupSerial: u32 = 0;
var g_hotkeysPreparedSerial: u32 = 0;
var g_modifiersPreparedSerial: u32 = 0;
var g_contextActionsPreparedSerial: u32 = 0;
var g_combosPreparedSerial: u32 = 0;
var g_chordsPreparedSerial: u32 = 0;
var g_hotstringsPreparedSerial: u32 = 0;

// Runtime Aho-Corasick indexes. These are built only after registration changes.
// The title and URL are each scanned once per foreground-context update.
const RUNTIME_AC_NODE_INITIAL_CAP: usize = 4096;
const RUNTIME_AC_EDGE_INITIAL_CAP: usize = 4096;
const RUNTIME_AC_NONE_U32: u32 = 0xFFFFFFFF;
const RuntimeAcIndex = struct {
    firstEdge: []u32,
    failure: []u32,
    outputLink: []u32,
    firstOutput: []u32,
    edgeChar: []u16,
    edgeNode: []u32,
    nextEdge: []u32,
    outputHotkey: []u32,
    nextOutput: []u32,
    nodeCount: u32 = 1,
    edgeCount: u32 = 0,
    outputCount: u32 = 0,
    overflowed: bool = false,
};
var g_runtimeAcOutputEmpty: [0]u32 = .{};
var g_runtimeAcU16Empty: [0]u16 = .{};
var g_runtimeTitleAc: RuntimeAcIndex = .{
    .firstEdge = g_runtimeAcOutputEmpty[0..],
    .failure = g_runtimeAcOutputEmpty[0..],
    .outputLink = g_runtimeAcOutputEmpty[0..],
    .firstOutput = g_runtimeAcOutputEmpty[0..],
    .edgeChar = g_runtimeAcU16Empty[0..],
    .edgeNode = g_runtimeAcOutputEmpty[0..],
    .nextEdge = g_runtimeAcOutputEmpty[0..],
    .outputHotkey = g_runtimeAcOutputEmpty[0..],
    .nextOutput = g_runtimeAcOutputEmpty[0..],
};
var g_runtimeWebsiteAc: RuntimeAcIndex = .{
    .firstEdge = g_runtimeAcOutputEmpty[0..],
    .failure = g_runtimeAcOutputEmpty[0..],
    .outputLink = g_runtimeAcOutputEmpty[0..],
    .firstOutput = g_runtimeAcOutputEmpty[0..],
    .edgeChar = g_runtimeAcU16Empty[0..],
    .edgeNode = g_runtimeAcOutputEmpty[0..],
    .nextEdge = g_runtimeAcOutputEmpty[0..],
    .outputHotkey = g_runtimeAcOutputEmpty[0..],
    .nextOutput = g_runtimeAcOutputEmpty[0..],
};
var g_runtimeAcQueue: []u32 = g_runtimeAcOutputEmpty[0..];
var g_runtimeHotkeyBoolEmpty: [0]bool = .{};
var g_runtimeTitleMatched: []bool = g_runtimeHotkeyBoolEmpty[0..];
var g_runtimeWebsiteMatched: []bool = g_runtimeHotkeyBoolEmpty[0..];
var g_runtimeAcFallback: []bool = g_runtimeHotkeyBoolEmpty[0..];

// Compiled hotkeys reuse the same fixed-array Aho-Corasick representation.
// Their title and URL patterns are built once from QMKHotkeys.zig and each
// foreground-context update scans the current title and URL exactly once.
var g_compiledTitleAc: RuntimeAcIndex = .{
    .firstEdge = g_runtimeAcOutputEmpty[0..],
    .failure = g_runtimeAcOutputEmpty[0..],
    .outputLink = g_runtimeAcOutputEmpty[0..],
    .firstOutput = g_runtimeAcOutputEmpty[0..],
    .edgeChar = g_runtimeAcU16Empty[0..],
    .edgeNode = g_runtimeAcOutputEmpty[0..],
    .nextEdge = g_runtimeAcOutputEmpty[0..],
    .outputHotkey = g_runtimeAcOutputEmpty[0..],
    .nextOutput = g_runtimeAcOutputEmpty[0..],
};
var g_compiledWebsiteAc: RuntimeAcIndex = .{
    .firstEdge = g_runtimeAcOutputEmpty[0..],
    .failure = g_runtimeAcOutputEmpty[0..],
    .outputLink = g_runtimeAcOutputEmpty[0..],
    .firstOutput = g_runtimeAcOutputEmpty[0..],
    .edgeChar = g_runtimeAcU16Empty[0..],
    .edgeNode = g_runtimeAcOutputEmpty[0..],
    .nextEdge = g_runtimeAcOutputEmpty[0..],
    .outputHotkey = g_runtimeAcOutputEmpty[0..],
    .nextOutput = g_runtimeAcOutputEmpty[0..],
};
var g_compiledTitleMatched: [STATIC_HOTKEY_MATCH_CAP]bool = [_]bool{false} ** STATIC_HOTKEY_MATCH_CAP;
var g_compiledWebsiteMatched: [STATIC_HOTKEY_MATCH_CAP]bool = [_]bool{false} ** STATIC_HOTKEY_MATCH_CAP;
var g_compiledAcFallback: [STATIC_HOTKEY_MATCH_CAP]bool = [_]bool{false} ** STATIC_HOTKEY_MATCH_CAP;

comptime {
    if (hotkeys.HOTKEYS.len > STATIC_HOTKEY_MATCH_CAP) {
        @compileError("Compiled hotkey count exceeds shared context matcher capacity");
    }
}
var g_directTapVKs: [PCB_MAX]i32 = [_]i32{0} ** PCB_MAX;
var g_directTapLen: usize = 0;
var g_directTapCaptureActive: bool = false;
var g_hotstringKeyUpHadDirectTap: bool = false;
var g_pendingTimers: [PTM_MAX]PendingTimer = undefined;
var g_pendingTimersLen: usize = 0;
// --- Ignored keys ---
var g_keyVKIgnored: [256]bool = [_]bool{false} ** 256;
var g_ignoredKeysLen: usize = 0;
// --- Key-down / key-up time tracking (double-tap detection) ---
// Replaced parallel VK+time arrays (O(n) scan) with VK-indexed flat arrays (O(1)).
// Sentinel: 0.0 == not present. QPC timestamps are never 0 after initTimer().
var g_kdtTime: [VK_COUNT]i64 = [_]i64{0} ** VK_COUNT;
var g_kutTime: [VK_COUNT]i64 = [_]i64{0} ** VK_COUNT;
// --- Registration relation tables ---
// Preserve the existing runtime records/semantics; only backing capacity grows
// during setup. After setup publishes, runtime reads stable array storage.
const CC_INITIAL_SLOTS: usize = 512;
const CcEntry = struct { key: u64 = 0, cbId: i32 = 0 }; // 12 bytes; 12×512 = 6KB
var g_ccTable: []CcEntry = &[_]CcEntry{};
var g_ccLen: usize = 0;
inline fn ccGet(key: u64) ?i32 {
    if (key == 0) return null;
    if (g_ccTable.len == 0) return null;
    const mask: u64 = @intCast(g_ccTable.len - 1);
    var slot: usize = @intCast(key & mask);
    var probe: usize = 0;
    while (probe < g_ccTable.len) : (probe += 1) {
        const e = g_ccTable[slot];
        if (e.key == 0) return null;
        if (e.key == key) return e.cbId;
        slot = (slot + 1) & @as(usize, @intCast(mask));
    }
    return null;
}
fn ccPutInto(table: []CcEntry, key: u64, cbId: i32) bool {
    if (key == 0 or table.len == 0) return false;
    const mask: u64 = @intCast(table.len - 1);
    var slot: usize = @intCast(key & mask);
    var probe: usize = 0;
    while (probe < table.len) : (probe += 1) {
        const e = &table[slot];
        if (e.key == 0 or e.key == key) {
            e.key = key;
            e.cbId = cbId;
            return true;
        }
        slot = (slot + 1) & @as(usize, @intCast(mask));
    }
    return false;
}
fn ccContains(key: u64) bool {
    return ccGet(key) != null;
}
fn ensureCcCapacity(required_entries: usize) bool {
    const required_slots = nextPowerOfTwoAtLeast(@max(CC_INITIAL_SLOTS, required_entries * 2));
    if (g_ccTable.len >= required_slots) return true;
    const new_table = gAlloc.alloc(CcEntry, required_slots) catch return false;
    @memset(new_table, CcEntry{});
    for (g_ccTable) |entry| {
        if (entry.key != 0 and !ccPutInto(new_table, entry.key, entry.cbId)) {
            gAlloc.free(new_table);
            return false;
        }
    }
    const old_table = g_ccTable;
    g_ccTable = new_table;
    retireSlice(CcEntry, old_table);
    return true;
}
fn ccPut(key: u64, cbId: i32) bool {
    if (key == 0) return false;
    const exists = ccContains(key);
    const needed = g_ccLen + if (exists) @as(usize, 0) else 1;
    if (!ensureCcCapacity(needed)) return false;
    if (!ccPutInto(g_ccTable, key, cbId)) return false;
    if (!exists) g_ccLen += 1;
    return true;
}
const ICC_INITIAL_SLOTS: usize = 32;
const IccEntry = struct { key: u64 = 0, cbId: i32 = 0 };
var g_iccTable: []IccEntry = &[_]IccEntry{};
var g_iccLen: usize = 0;
inline fn iccGet(key: u64) ?i32 {
    if (key == 0) return null;
    if (g_iccTable.len == 0) return null;
    const mask: u64 = @intCast(g_iccTable.len - 1);
    var slot: usize = @intCast(key & mask);
    var probe: usize = 0;
    while (probe < g_iccTable.len) : (probe += 1) {
        const e = g_iccTable[slot];
        if (e.key == 0) return null;
        if (e.key == key) return e.cbId;
        slot = (slot + 1) & @as(usize, @intCast(mask));
    }
    return null;
}
fn iccPutInto(table: []IccEntry, key: u64, cbId: i32) bool {
    if (key == 0 or table.len == 0) return false;
    const mask: u64 = @intCast(table.len - 1);
    var slot: usize = @intCast(key & mask);
    var probe: usize = 0;
    while (probe < table.len) : (probe += 1) {
        const e = &table[slot];
        if (e.key == 0 or e.key == key) {
            e.key = key;
            e.cbId = cbId;
            return true;
        }
        slot = (slot + 1) & @as(usize, @intCast(mask));
    }
    return false;
}
fn iccContains(key: u64) bool {
    return iccGet(key) != null;
}
fn ensureIccCapacity(required_entries: usize) bool {
    const required_slots = nextPowerOfTwoAtLeast(@max(ICC_INITIAL_SLOTS, required_entries * 2));
    if (g_iccTable.len >= required_slots) return true;
    const new_table = gAlloc.alloc(IccEntry, required_slots) catch return false;
    @memset(new_table, IccEntry{});
    for (g_iccTable) |entry| {
        if (entry.key != 0 and !iccPutInto(new_table, entry.key, entry.cbId)) {
            gAlloc.free(new_table);
            return false;
        }
    }
    const old_table = g_iccTable;
    g_iccTable = new_table;
    retireSlice(IccEntry, old_table);
    return true;
}
fn iccPut(key: u64, cbId: i32) bool {
    if (key == 0) return false;
    const exists = iccContains(key);
    const needed = g_iccLen + if (exists) @as(usize, 0) else 1;
    if (!ensureIccCapacity(needed)) return false;
    if (!iccPutInto(g_iccTable, key, cbId)) return false;
    if (!exists) g_iccLen += 1;
    return true;
}
const IC_INITIAL_SLOTS: usize = 128;
const IcEntry = struct { key: u64 = 0, val: InternalRemap = .{ .targetVK = 0, .modMask = 0, .isInstant = false } };
var g_icTable: []IcEntry = &[_]IcEntry{};
var g_icLen: usize = 0;
inline fn icGet(key: u64) ?InternalRemap {
    if (key == 0) return null;
    if (g_icTable.len == 0) return null;
    const mask: u64 = @intCast(g_icTable.len - 1);
    var slot: usize = @intCast(key & mask);
    var probe: usize = 0;
    while (probe < g_icTable.len) : (probe += 1) {
        const e = g_icTable[slot];
        if (e.key == 0) return null;
        if (e.key == key) return e.val;
        slot = (slot + 1) & @as(usize, @intCast(mask));
    }
    return null;
}
fn icPutInto(table: []IcEntry, key: u64, val: InternalRemap) bool {
    if (key == 0 or table.len == 0) return false;
    const mask: u64 = @intCast(table.len - 1);
    var slot: usize = @intCast(key & mask);
    var probe: usize = 0;
    while (probe < table.len) : (probe += 1) {
        const e = &table[slot];
        if (e.key == 0 or e.key == key) {
            e.key = key;
            e.val = val;
            return true;
        }
        slot = (slot + 1) & @as(usize, @intCast(mask));
    }
    return false;
}
fn icContains(key: u64) bool {
    return icGet(key) != null;
}
fn ensureIcCapacity(required_entries: usize) bool {
    const required_slots = nextPowerOfTwoAtLeast(@max(IC_INITIAL_SLOTS, required_entries * 2));
    if (g_icTable.len >= required_slots) return true;
    const new_table = gAlloc.alloc(IcEntry, required_slots) catch return false;
    @memset(new_table, IcEntry{});
    for (g_icTable) |entry| {
        if (entry.key != 0 and !icPutInto(new_table, entry.key, entry.val)) {
            gAlloc.free(new_table);
            return false;
        }
    }
    const old_table = g_icTable;
    g_icTable = new_table;
    retireSlice(IcEntry, old_table);
    return true;
}
fn icPut(key: u64, val: InternalRemap) bool {
    if (key == 0) return false;
    const exists = icContains(key);
    const needed = g_icLen + if (exists) @as(usize, 0) else 1;
    if (!ensureIcCapacity(needed)) return false;
    if (!icPutInto(g_icTable, key, val)) return false;
    if (!exists) g_icLen += 1;
    return true;
}
// combo existence matrix: bool[256][256] — single indexed load, 1 instruction.
// 64KB total but only rows for actual primary VKs are ever touched; hardware
// prefetcher handles sequential row access better than software hints.
// Faster than bitset on hot path: no shift/AND/compare, just load+test.
var g_comboMatrix: [VK_COUNT][VK_COUNT]bool = [_][VK_COUNT]bool{[_]bool{false} ** VK_COUNT} ** VK_COUNT;
var g_instantComboMatrix: [VK_COUNT][VK_COUNT]bool = [_][VK_COUNT]bool{[_]bool{false} ** VK_COUNT} ** VK_COUNT;
var g_runtimeComboMatrix: [VK_COUNT][VK_COUNT]bool = [_][VK_COUNT]bool{[_]bool{false} ** VK_COUNT} ** VK_COUNT;
var g_runtimeInstantComboMatrix: [VK_COUNT][VK_COUNT]bool = [_][VK_COUNT]bool{[_]bool{false} ** VK_COUNT} ** VK_COUNT;
var g_runtimeComboCallbackMatrix: [VK_COUNT][VK_COUNT]i32 = [_][VK_COUNT]i32{[_]i32{-1} ** VK_COUNT} ** VK_COUNT;
var g_runtimeInstantComboCallbackMatrix: [VK_COUNT][VK_COUNT]i32 = [_][VK_COUNT]i32{[_]i32{-1} ** VK_COUNT} ** VK_COUNT;
var g_runtimeComboRemapTargetMatrix: [VK_COUNT][VK_COUNT]i32 = [_][VK_COUNT]i32{[_]i32{0} ** VK_COUNT} ** VK_COUNT;
var g_runtimeInstantComboRemapTargetMatrix: [VK_COUNT][VK_COUNT]i32 = [_][VK_COUNT]i32{[_]i32{0} ** VK_COUNT} ** VK_COUNT;
var g_runtimeComboRemapMaskMatrix: [VK_COUNT][VK_COUNT]u16 = [_][VK_COUNT]u16{[_]u16{0} ** VK_COUNT} ** VK_COUNT;
var g_runtimeInstantComboRemapMaskMatrix: [VK_COUNT][VK_COUNT]u16 = [_][VK_COUNT]u16{[_]u16{0} ** VK_COUNT} ** VK_COUNT;
const REL_COMBO: u8 = 0x01;
const REL_INSTANT: u8 = 0x02;
const REL_CHORD2: u8 = 0x04;
const REL_CHORD_PREFIX: u8 = 0x08;
var g_pairRelationMask: [VK_COUNT][VK_COUNT]u8 align(64) =
    [_][VK_COUNT]u8{[_]u8{0} ** VK_COUNT} ** VK_COUNT;
// Primary-has-any-combo: flat bool per VK. Single load replaces bitset shift/AND.
var g_comboPrimaryFlat: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_instantComboPrimaryFlat: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_runtimeComboPrimaryFlat: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_runtimeInstantComboPrimaryFlat: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;

const RuntimeComboActiveBank = struct {
    comboMatrix: [VK_COUNT][VK_COUNT]bool = [_][VK_COUNT]bool{[_]bool{false} ** VK_COUNT} ** VK_COUNT,
    instantMatrix: [VK_COUNT][VK_COUNT]bool = [_][VK_COUNT]bool{[_]bool{false} ** VK_COUNT} ** VK_COUNT,
    comboCallback: [VK_COUNT][VK_COUNT]i32 = [_][VK_COUNT]i32{[_]i32{-1} ** VK_COUNT} ** VK_COUNT,
    instantCallback: [VK_COUNT][VK_COUNT]i32 = [_][VK_COUNT]i32{[_]i32{-1} ** VK_COUNT} ** VK_COUNT,
    comboRemapTarget: [VK_COUNT][VK_COUNT]i32 = [_][VK_COUNT]i32{[_]i32{0} ** VK_COUNT} ** VK_COUNT,
    instantRemapTarget: [VK_COUNT][VK_COUNT]i32 = [_][VK_COUNT]i32{[_]i32{0} ** VK_COUNT} ** VK_COUNT,
    comboRemapMask: [VK_COUNT][VK_COUNT]u16 = [_][VK_COUNT]u16{[_]u16{0} ** VK_COUNT} ** VK_COUNT,
    instantRemapMask: [VK_COUNT][VK_COUNT]u16 = [_][VK_COUNT]u16{[_]u16{0} ** VK_COUNT} ** VK_COUNT,
    comboPrimary: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT,
    instantPrimary: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT,
};
var g_runtimeComboActiveBanks: [2]RuntimeComboActiveBank = .{ .{}, .{} };
var g_activeRuntimeComboBank: u32 = 0;

inline fn activeRuntimeCombos() *const RuntimeComboActiveBank {
    const idx = @atomicLoad(u32, &g_activeRuntimeComboBank, .acquire);
    return &g_runtimeComboActiveBanks[idx];
}

// Chord participant flat: true if this VK is part of any registered chord.
var g_chordParticipantFlat: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
const InternalRemap = extern struct { targetVK: i32, modMask: u16, isInstant: bool };
const ChordHotKind = enum(u8) {
    none = 0,
    internal = 1,
    external = 2,
};
const ChordHotEntry = extern struct {
    key: u64 = 0,
    targetVK: i32 = 0,
    callbackId: i32 = 0,
    modMask: u16 = 0,
    keyCount: u8 = 0,
    kind: u8 = @intFromEnum(ChordHotKind.none),
    flags: u8 = 0,
};
const CHORD_HOT_HAS_4_SUPERSET: u8 = 0x01;
const STATIC_CHORD_HOT_INITIAL_SLOTS: usize = 256;
var g_chordHotEmpty: [0]ChordHotEntry = .{};
var g_chordHotTable: []ChordHotEntry = g_chordHotEmpty[0..];
var g_chordHotLen: usize = 0;
const PendingChord = struct {
    active: bool = false,
    key: u64 = 0,
    triggerVK: i32 = 0,
};
var g_pendingChord: PendingChord = .{};
inline fn chordHotSlotForMask(key: u64, mask: usize) usize {
    var h = key;
    h ^= h >> 33;
    h *%= 0xff51afd7ed558ccd;
    h ^= h >> 33;
    return @intCast(h & @as(u64, @intCast(mask)));
}
inline fn chordGetFast(key: u64) ?ChordHotEntry {
    if (key == 0) return null;
    // Structural chord identity is checked before consulting the
    // context-filtered active chord bank, so a stale context publication
    // cannot turn a valid contextual chord into a non-existent chord.
    prepareStructuralChordContext(key);
    const runtime_chords = activeRuntimeChords();
    if (runtime_chords.hotTable.len != 0) {
        const runtime_mask = runtime_chords.hotTable.len - 1;
        var runtime_slot = chordHotSlotForMask(key, runtime_mask);
        var runtime_probe: usize = 0;
        while (runtime_probe < runtime_chords.hotTable.len) : (runtime_probe += 1) {
            const e = runtime_chords.hotTable[runtime_slot];
            if (e.key == 0) break;
            if (e.key == key) return e;
            runtime_slot = (runtime_slot + 1) & runtime_mask;
        }
    }
    if (g_chordHotTable.len != 0) {
        const static_mask = g_chordHotTable.len - 1;
        var static_slot = chordHotSlotForMask(key, static_mask);
        var static_probe: usize = 0;
        while (static_probe < g_chordHotTable.len) : (static_probe += 1) {
            const e = g_chordHotTable[static_slot];
            if (e.key == 0) return null;
            if (e.key == key) return e;
            static_slot = (static_slot + 1) & static_mask;
        }
    }
    return null;
}
fn chordHotPutInto(table: []ChordHotEntry, entry: ChordHotEntry) bool {
    if (entry.key == 0) return false;
    if (table.len == 0) return false;
    const mask = table.len - 1;
    var slot = chordHotSlotForMask(entry.key, mask);
    var probe: usize = 0;
    while (probe < table.len) : (probe += 1) {
        const e = &table[slot];
        if (e.key == 0) {
            e.* = entry;
            return true;
        }
        if (e.key == entry.key) {
            // Preserve old lookup priority: internal chords win over external
            // chords even if both maps contain the same canonical chord key.
            if (entry.kind == @intFromEnum(ChordHotKind.internal) or
                e.kind != @intFromEnum(ChordHotKind.internal))
            {
                e.* = entry;
            }
            return true;
        }
        slot = (slot + 1) & mask;
    }
    return false;
}
fn ensureStaticChordHotCapacity(required_entries: usize) bool {
    if (g_chordHotTable.len != 0 and required_entries * 2 <= g_chordHotTable.len) return true;
    var desired = if (g_chordHotTable.len == 0) STATIC_CHORD_HOT_INITIAL_SLOTS else g_chordHotTable.len * 2;
    while (required_entries * 2 > desired) : (desired *= 2) {}
    const new_table = gAlloc.alloc(ChordHotEntry, desired) catch return false;
    @memset(new_table, ChordHotEntry{});
    for (g_chordHotTable) |entry| {
        if (entry.key != 0 and !chordHotPutInto(new_table, entry)) {
            gAlloc.free(new_table);
            return false;
        }
    }
    const old_table = g_chordHotTable;
    g_chordHotTable = new_table;
    retireSlice(ChordHotEntry, old_table);
    return true;
}
fn chordHotPut(entry: ChordHotEntry) bool {
    if (entry.key == 0) return false;
    if (!ensureStaticChordHotCapacity(g_chordHotLen + 1)) return false;
    const mask = g_chordHotTable.len - 1;
    var slot = chordHotSlotForMask(entry.key, mask);
    var probe: usize = 0;
    while (probe < g_chordHotTable.len) : (probe += 1) {
        const e = &g_chordHotTable[slot];
        if (e.key == 0) {
            e.* = entry;
            g_chordHotLen += 1;
            recomputeChordHotSupersetFlags(g_chordHotTable);
            return true;
        }
        if (e.key == entry.key) {
            if (entry.kind == @intFromEnum(ChordHotKind.internal) or
                e.kind != @intFromEnum(ChordHotKind.internal))
            {
                e.* = entry;
            }
            recomputeChordHotSupersetFlags(g_chordHotTable);
            return true;
        }
        slot = (slot + 1) & mask;
    }
    return false;
}
// --- Active modifiers ---
// Collection of source VKs currently active as virtual modifiers.
var g_active_virtual_modifiers_by_vk: [ACTIVE_MOD_MAX]i32 = [_]i32{0} ** ACTIVE_MOD_MAX;
// Number of source VKs currently active as virtual modifiers.
var g_active_virtual_modifier_count: i32 = 0;
// Virtual modifier-family mask currently active.
var g_active_virtual_modifiers: u16 = 0;
// O(1) presence test — indexed by VK. Set/cleared by add_active_virtual_modifier/Remove/Clear.
// Replaces the O(ACTIVE_MOD_MAX) linear scan in activeModContains.
var g_activeModPresent: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
// O(1) index lookup — indexed by VK. Stores index in g_active_virtual_modifiers_by_vk array.
// Enables O(1) removal instead of O(n) linear search.
var g_activeModIdx: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT;
// --- Registration presence flags (set at registration, never cleared; O(1) check) ---
// Replaces repeated container count checks on every keydown.
var g_hasInternalChords: bool = false;
var g_hasExternalChords: bool = false;
var g_hasInternalCombos: bool = false;
// Single combined chord flag — avoids OR of two bool loads on the keydown hot path.
var g_hasAnyChord: bool = false;
// Pre-decoded external chord VK arrays — eliminates bit-unpacking of the packed
// chordKey u64 on every keydown's external-chord prefix check.
const EXT_CHORD_CACHE_INITIAL_CAP: usize = 64;
const ExtChordCacheEntry = struct {
    vks: [5]i32 = [_]i32{0} ** 5,
    keyCount: u8 = 0,
    modMask: u16 = 0,
};
var g_extChordCacheEmpty: [0]ExtChordCacheEntry = .{};
var g_extChordCache: []ExtChordCacheEntry = g_extChordCacheEmpty[0..];
var g_extChordCacheLen: usize = 0;
var g_runtimeChordParticipantFlat: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_hasRuntimeInternalChords: bool = false;
var g_hasRuntimeExternalChords: bool = false;
var g_hasRuntimeAnyChord: bool = false;

const RuntimeChordActiveBank = struct {
    hotTable: []ChordHotEntry,
    extCache: []ExtChordCacheEntry,
    extCacheLen: usize = 0,
    participant: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT,
    hasInternal: bool = false,
    hasExternal: bool = false,
    hasAny: bool = false,
};
var g_runtimeChordHotEmpty: [0]ChordHotEntry = .{};
var g_runtimeExtChordCacheEmpty: [0]ExtChordCacheEntry = .{};
var g_runtimeChordActiveBanks: [2]RuntimeChordActiveBank = .{
    .{ .hotTable = g_runtimeChordHotEmpty[0..], .extCache = g_runtimeExtChordCacheEmpty[0..] },
    .{ .hotTable = g_runtimeChordHotEmpty[0..], .extCache = g_runtimeExtChordCacheEmpty[0..] },
};
var g_activeRuntimeChordBank: u32 = 0;

inline fn activeRuntimeChords() *const RuntimeChordActiveBank {
    const idx = @atomicLoad(u32, &g_activeRuntimeChordBank, .acquire);
    return &g_runtimeChordActiveBanks[idx];
}

fn ensureStaticExtChordCacheCapacity(required: usize) bool {
    if (required <= g_extChordCache.len) return true;
    var desired = if (g_extChordCache.len == 0) EXT_CHORD_CACHE_INITIAL_CAP else g_extChordCache.len * 2;
    while (desired < required) : (desired *= 2) {}
    const new_cache = gAlloc.alloc(ExtChordCacheEntry, desired) catch return false;
    if (g_extChordCacheLen != 0) {
        @memcpy(new_cache[0..g_extChordCacheLen], g_extChordCache[0..g_extChordCacheLen]);
    }
    if (desired > g_extChordCacheLen) {
        @memset(new_cache[g_extChordCacheLen..desired], ExtChordCacheEntry{});
    }
    const old_cache = g_extChordCache;
    g_extChordCache = new_cache;
    retireSlice(ExtChordCacheEntry, old_cache);
    return true;
}

// Direct VK ? mod type table. Eliminates the two-hop indirection in getModTypeForVK
// (g_vkToRegIdx[vk] ? g_modTypes[idx]). Single indexed byte load.
// MOD_NONE (-1) = not a modifier. Written during native modifier setup.
var g_modTypeFlat: [VK_COUNT]i8 = [_]i8{MOD_NONE} ** VK_COUNT;
// Flat callback-ID table: g_hcFlat[vk] = callback ID, -1 = not registered.
// Replaces g_holdCallbacks.get() in processQueue's hold dispatch (hot path).
var g_hcFlat: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT;
// Modifier double-tap flat table: g_modDtFlat[vk] = callbackId, -1 = not registered.
// Keyed by the physical modifier VK so L/R callbacks can stay distinct.
var g_modDtFlat: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT;
// Setup-time structural facts for the key gate. Context changes may change the
// active callback ID tables above, but these flags do not change after setup.
var g_holdRegisteredFlat: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_doubleTapRegisteredFlat: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
// Per-VK QPC time when PhysModDown fired for each physical modifier VK.
// Indexed by VK (0..VK_COUNT), so each side (LCtrl/RCtrl etc.) has its own slot.
// Written by QMK_PhysModDown / QMK_PhysModDownVK, read by the poll thread.
var g_modPollDownTime: [VK_COUNT]i64 = [_]i64{0} ** VK_COUNT;
// Per-VK QPC time of the most recent modifier release for side-specific double-tap detection.
var g_modPollLastUpTime: [VK_COUNT]i64 = [_]i64{0} ** VK_COUNT;
// --- Misc runtime state ---
// Physical and Windows-facing modifiers currently active; virtual modifiers are excluded.
var g_active_physical_and_windows_facing_modifiers: i32 = 0;
// Collapsed physical modifier-family mask currently active.
var g_active_physical_modifiers: u16 = 0;
// Cached boolean indicating whether any physical modifier is active.
var g_any_physical_modifiers_active: bool = false;
var g_lastKeyTime: i64 = 0;
var g_typingMode: bool = false;
var g_typingModeUntil: i64 = 0;
const HF_TYPING: u32 = 1 << 0;
const HF_TIMERS: u32 = 1 << 1;
const HF_PENDING_TIMERS: u32 = 1 << 2;
const HF_IGNORED_KEYS: u32 = 1 << 3;
const HF_RECENT_KEYUP: u32 = 1 << 4;
var g_hotFlags: u32 = 0;

// ============================================================================
// FSM-lite: Runtime flags — single word summarising current engine state.
// Hot paths check (g_runtimeFlags & RB_*) == 0 instead of combining 6+
// separate globals every keypress. Maintained incrementally in the same
// helpers that already mutate the underlying counters/flags.
// ============================================================================
// Individual runtime condition bits
const RF_TYPING: u32 = 1 << 0; // g_hotFlags & HF_TYPING
const RF_TIMERS: u32 = 1 << 1; // g_timerLen > 0
const RF_PENDING_TIMERS: u32 = 1 << 2; // g_pendingTimersLen > 0
const RF_IGNORED_KEYS: u32 = 1 << 3; // g_ignoredKeysLen > 0
const RF_RECENT_KEYUP: u32 = 1 << 4; // g_recentKeyUpCount > 0
const RF_KB_NONEMPTY: u32 = 1 << 5; // g_kbLen > 0
const RF_ORD_NONEMPTY: u32 = 1 << 6; // g_ordLen > 0
const RF_ACTIVE_MODS: u32 = 1 << 7; // g_active_virtual_modifier_count > 0
const RF_UNREL_MODS: u32 = 1 << 8; // g_unrelModCount > 0
const RF_PENDING_ROLL: u32 = 1 << 23; // g_pendingRollLen > 0
const RF_PENDING_SOLO: u32 = 1 << 24; // g_pendingSoloVK != 0
const RF_CLEAN_UNREL_MODS: u32 = 1 << 9; // g_cleanUnrelModCount > 0
const RF_SYS_MODS: u32 = 1 << 10; // g_active_physical_and_windows_facing_modifiers != 0
const RF_PHYSICAL_MODS: u32 = 1 << 11; // g_active_physical_modifiers != 0
const RF_UNREL_KEYS: u32 = 1 << 12; // g_unreleasedKeyCount > 0
const RF_UNREL_NONMOD_KEYS: u32 = 1 << 13; // g_unreleasedNonModCount > 0
const RF_ACTIVE_COMBO_PRIMARY: u32 = 1 << 14; // g_activeComboPrimaryCount > 0
const RF_ACTIVE_INSTANT_PRIMARY: u32 = 1 << 15; // g_activeInstantPrimaryCount > 0

// Blocker masks: a fast path is allowed when (g_runtimeFlags & mask) == 0.
// RB_KEYDOWN_EMPTY_FAST: plain key into a fully quiescent, empty buffer.
const RB_KEYDOWN_EMPTY_FAST: u32 =
    RF_TYPING |
    RF_TIMERS |
    RF_PENDING_TIMERS |
    RF_IGNORED_KEYS |
    RF_KB_NONEMPTY |
    RF_ORD_NONEMPTY |
    RF_ACTIVE_MODS |
    RF_UNREL_MODS |
    RF_CLEAN_UNREL_MODS |
    RF_SYS_MODS |
    RF_PHYSICAL_MODS |
    RF_PENDING_ROLL |
    RF_PENDING_SOLO;

const RB_KEYDOWN_QUIET_EMPTY_FAST: u32 =
    RF_TIMERS |
    RF_PENDING_TIMERS |
    RF_IGNORED_KEYS |
    RF_KB_NONEMPTY |
    RF_ORD_NONEMPTY |
    RF_ACTIVE_MODS |
    RF_UNREL_MODS |
    RF_CLEAN_UNREL_MODS |
    RF_SYS_MODS |
    RF_PHYSICAL_MODS |
    RF_PENDING_ROLL |
    RF_PENDING_SOLO;

// RB_KEYDOWN_ROLLING_FAST: plain key rolling into an already-buffered typing run.
const RB_KEYDOWN_ROLLING_FAST: u32 =
    RF_TIMERS |
    RF_PENDING_TIMERS |
    RF_IGNORED_KEYS |
    RF_ACTIVE_MODS |
    RF_UNREL_MODS |
    RF_CLEAN_UNREL_MODS |
    RF_SYS_MODS |
    RF_PHYSICAL_MODS;

// RB_KEYUP_SKIP_ALL: plain key released while no modifiers are relevant.
const RB_KEYUP_SKIP_ALL: u32 =
    RF_ACTIVE_MODS |
    RF_UNREL_MODS |
    RF_SYS_MODS |
    RF_PHYSICAL_MODS;

// Dense-key solo acquisition: no buffered keys, no unreleased state, no active
// modifier/primary/system/physical blockers. This replaces a string of global
// counter loads on the common solo-unresolved keydown path.
const RB_SOLO_UNRESOLVED: u32 =
    RF_IGNORED_KEYS |
    RF_KB_NONEMPTY |
    RF_ORD_NONEMPTY |
    RF_ACTIVE_MODS |
    RF_UNREL_MODS |
    RF_SYS_MODS |
    RF_PHYSICAL_MODS |
    RF_UNREL_KEYS |
    RF_ACTIVE_COMBO_PRIMARY |
    RF_ACTIVE_INSTANT_PRIMARY;

// Pending solo + incoming key can roll cheaply only when no global runtime
// relationship/modifier blocker exists. The pair relation matrix handles the
// key-specific blocker after this mask passes.
const RB_PENDING_PAIR_CLEAN: u32 =
    RF_IGNORED_KEYS |
    RF_ACTIVE_MODS |
    RF_UNREL_MODS |
    RF_SYS_MODS |
    RF_PHYSICAL_MODS |
    RF_ACTIVE_COMBO_PRIMARY |
    RF_ACTIVE_INSTANT_PRIMARY;

var g_runtimeFlags: u32 = 0;

// FSM-lite: unreleased-key counters (avoid buffer scans on hot path).
var g_unreleasedKeyCount: i32 = 0; // all unreleased keys in buffer
var g_unreleasedNonModCount: i32 = 0; // unreleased non-modifier keys
// Active-primary counts mirror the bitsets for cheaper RF_ maintenance.
var g_activeInstantPrimaryCount: i32 = 0;
var g_activeAnyPrimaryCount: i32 = 0;

// Pending-solo slot: the theoretical hot path keeps the first isolated key out
// of the full buffer/order machinery until another event makes ambiguity real.
const PSF_IS_MOD: u16 = 0x0001;
const PSF_QUIET: u16 = 0x0002;
const PSF_DOUBLE_TAP: u16 = 0x0004;
const PSF_INTERFERING: u16 = 0x0008;
const PSF_MODTYPE_SHIFT: u4 = 4;
const PSF_MODTYPE_MASK: u16 = 0x0070;
var g_pendingSoloVK: i32 = 0;
var g_pendingSoloDownTime: i64 = 0;
var g_pendingSoloFlags: u16 = 0;
const PENDING_ROLL_MAX: usize = 4;
var g_pendingRollLen: usize = 0;
var g_pendingRollVKs: [PENDING_ROLL_MAX]i32 = [_]i32{0} ** PENDING_ROLL_MAX;
var g_pendingRollDownTimes: [PENDING_ROLL_MAX]i64 = [_]i64{0} ** PENDING_ROLL_MAX;
var g_pendingRollFlags: [PENDING_ROLL_MAX]u16 = [_]u16{0} ** PENDING_ROLL_MAX;
var g_pendingRollHeadVK: i32 = 0;
var g_pendingRollTailVK: i32 = 0;
var g_pendingRollHeadDownTime: i64 = 0;
var g_pendingRollTailDownTime: i64 = 0;
var g_pendingRollHeadFlags: u16 = 0;
var g_pendingRollTailFlags: u16 = 0;

// Inline helpers to set/clear runtime flag bits.
inline fn rfSet(mask: u32) void {
    g_runtimeFlags |= mask;
}
inline fn rfClear(mask: u32) void {
    g_runtimeFlags &= ~mask;
}
inline fn rfSetIf(mask: u32, cond: bool) void {
    if (cond) rfSet(mask) else rfClear(mask);
}
// AHK-owned shared IPC ring. Zig maps this once during startup and only writes
// event records; AHK resolves and invokes callbacks on its own thread.
var g_ipcRing: ?*ipc.SharedRingBuffer = null;
var g_ipcControlDropCount: u64 = 0;
const WakeByAddressSingleFn = *const fn (Address: *const anyopaque) callconv(.winapi) void;
var g_wakeByAddressSingle: ?WakeByAddressSingleFn = null;
var g_unrelModCount: i32 = 0;
// Count of unreleased modifier keys that are NOT contaminated (hasInterferingKeys == false).
// Maintained alongside g_unrelModCount so the intentional-chord guard (cleanUnrelMods >= 2)
// is a single integer load on the hot path instead of a full buffer scan.
// Incremented in the UNIVERSAL FALLTHROUGH when a virtual modifier enters clean.
// Decremented when a mod key is released OR when FLAG_INTERFERING is stamped on it.
var g_cleanUnrelModCount: i32 = 0;
// Physical key-down truth from event intake. Separate from g_kbData because
// combo/chord logic can remove keys from kb while they are still physically held.
// Four u64 words cover all 256 VKs, so repeat and physical-mod checks read one
// compact bitboard instead of a 256-byte bool table or an OS async query.
// Active-VK bitboard: one bit per VK indicating whether that VK is physically held.
var g_is_vk_held: [4]u64 = [_]u64{0} ** 4;
inline fn physicalKeyDownAt(idx: usize) bool {
    if (idx >= VK_COUNT) return false;
    const word = idx >> 6;
    const bit = @as(u64, 1) << @intCast(idx & 63);
    return (@atomicLoad(u64, &g_is_vk_held[word], .acquire) & bit) != 0;
}
inline fn physicalKeyDownVK(vk: i32) bool {
    if (vk < 0 or vk >= VK_COUNT) return false;
    return physicalKeyDownAt(@intCast(vk));
}
inline fn setPhysicalKeyDownAt(idx: usize, is_down: bool) void {
    if (idx >= VK_COUNT) return;
    const word = idx >> 6;
    const bit = @as(u64, 1) << @intCast(idx & 63);
    if (is_down) {
        _ = @atomicRmw(u64, &g_is_vk_held[word], .Or, bit, .acq_rel);
    } else {
        _ = @atomicRmw(u64, &g_is_vk_held[word], .And, ~bit, .acq_rel);
    }
}
inline fn clearPhysicalKeyDownState() void {
    inline for (0..4) |i| @atomicStore(u64, &g_is_vk_held[i], 0, .release);
}
// Reserved for a future startup-held non-mod quarantine. Runtime safety is
// currently based on exact modifier sync plus real hook/capture key events;
// broad async non-mod scans can suppress legitimate first shortcut presses.
var g_foreignPhysicalKeyDown: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_foreignPhysicalQuarantineArmed: bool = false;
var g_trackedPhysicalKeysDown: u32 = 0;
var g_runtimePublishPendingMask: u32 = 0;
var g_pendingContextChangedMask: u8 = 0;
var g_pendingHotstringContextMask: u64 = 0;
var g_pendingHotstringContextMaskValid: bool = false;
var g_runtimePublishInProgress: i32 = 0;
var g_hotPathActiveCount: i32 = 0;
var g_runtimePublishWorkerActive: i32 = 0;
// Most recent genuine physical up->down transition. Used only to detect whether
// another key was pressed after a hold candidate went down. Autorepeat does not
// update this value because setPhysicalKeyDownState checks was_down first.
var g_lastPhysicalDownVK: i32 = 0;
// Four counters: the number of active physical modifier keys in each category.
var g_active_physical_modifier_key_counts_by_category: [4]u8 = [_]u8{0} ** 4;
// PHYSICAL MODIFIER STATE: g_is_vk_held plus these masks describe the
// user's actual physical modifier keys. Real input events update them first.
// Physical modifier-family values selected for shortcut/native output.
var g_which_physical_modifiers_to_send: u16 = 0;
// Left/right physical modifier-key mask currently active.
var g_lr_active_physical_modifiers: u8 = 0;
// OS VISIBILITY: subset of physically-held LR modifiers whose DOWN Windows
// does not currently own because QMK suppressed or neutralized it.
// Synthetic modifier UP/DOWN events may change this mask, but must never change
// physical truth. Invariant: hiddenFromOsLR is a subset of physicalHeldLR.
// Left/right physical modifier VKs currently hidden from Windows.
var g_physical_modifier_hidden_from_os_lr_mask: u8 = 0;
// HOTKEY OWNERSHIP: suppress-original hotkey trigger DOWN/UP pairing only.
// Unrelated to general modifier OS visibility.
// VKs whose original key-down was consumed and whose key-up must remain paired.
var g_hotkey_consumed_down: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
// Compiled ordinary holds use the shared runtime bank, but an in-flight press
// must keep the callback selected at key-down if the foreground context changes.
var g_contextualTapArmed: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_contextualTapCallbackId: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT;
var g_contextualTapHoldCallbackId: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT;
var g_contextualTapCleanupCallbackId: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT;
var g_contextualTapThreshold: [VK_COUNT]i64 = [_]i64{0} ** VK_COUNT;
var g_contextualTapDownTime: [VK_COUNT]i64 = [_]i64{0} ** VK_COUNT;
// A non-modifier key passed through as a native stroke because a physical
// modifier was held. Its keyup must also be passed through natively, even if
// the modifier is released first.
// VKs whose key-down was forwarded natively to Windows and whose key-up must be paired.
var g_native_passthrough_to_windows: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
// Four u64 words cover all 256 Windows VK values. The active bank contains
// only keys that can match in the current context, including permanent globals.
var g_hotkeyActiveGateBanks: [2][4]u64 = [_][4]u64{[_]u64{0} ** 4} ** 2;
var g_activeHotkeyGateBank: u32 = 0;
var g_tapHoldTapCallbackId: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT;
var g_tapHoldHoldCallbackId: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT;
var g_tapHoldCleanupCallbackId: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT;
var g_tapHoldThreshold: [VK_COUNT]i64 = [_]i64{0} ** VK_COUNT;
var g_tapHoldDownTime: [VK_COUNT]i64 = [_]i64{0} ** VK_COUNT;
var g_tapHoldArmed: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_tapHoldInterrupted: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_tapHoldCallbackQueued: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
// Snapshot the active contextual callbacks when a tap/hold press arms. A
// context-bank swap during the physical press cannot redirect that in-flight
// press to callbacks from a different context.
var g_tapHoldArmedTapCallbackId: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT;
var g_tapHoldArmedHoldCallbackId: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT;
var g_tapHoldArmedCleanupCallbackId: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT;
var g_tapHoldArmedThreshold: [VK_COUNT]i64 = [_]i64{0} ** VK_COUNT;
var g_activeModKeyCnt: i32 = 0;
// Set true by kbRemove when g_active_virtual_modifier_count > 0; cleared by processQueue
// after the stale-modifier sweep. Lets processQueue skip the sweep on the
// vast majority of calls where nothing has changed.
var g_modStackDirty: bool = false;
// --- Config (Defaults below, overridden by QMK_SetUserConfig if called) ---
var g_SingleKeyHoldThreshold: i64 = 0;
var g_MaxHoldThreshold: i64 = 0;
var g_MaxBufferSize: i32 = 50;
var g_QuietPeriodDuration: i64 = 0;
var g_ModifierGestureWindow: i64 = 0;
var g_MaxThresholdSupress: bool = true;
var g_DoubleTapThreshold: i64 = 0;
var g_RepeatInitialDelay: i32 = 300;
var g_RepeatInterval: i32 = 20;
var g_RepeatInitialDelayTicks: i64 = 0;
var g_RepeatIntervalTicks: i64 = 0;
// Physical modifier passthrough controls whether real Ctrl/Alt/Shift/Win
// strokes are exposed to Windows when no QMK hotkey consumes them. Physical
// bitboards remain authoritative either way.
// Controls whether unconsumed physical modifiers remain visible to Windows.
var g_physical_modifier_passthrough: bool = true;

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
var g_ring: [RING_SIZE]InputSlot align(64) = undefined;
var g_ringCount: usize = 0;
var g_strokeBatch: [RING_SIZE]InterceptionKeyStroke align(64) = undefined;
var g_hotstringMatcher: hotstrings.HotstringMatcher = hotstrings.HotstringMatcher.init();
var g_hotstringContextState: hotstrings.HotstringContextState = .{};
const RUNTIME_HOTSTRING_INITIAL_CAP: usize = 4096;
const RuntimeHotstringTrigger = [hotstrings.MAX_HOTSTRING_TRIGGER_BYTES]u8;
var g_runtimeHotstringEntriesEmpty: [0]hotstrings.HotstringEntry = .{};
var g_runtimeHotstringEntries: []hotstrings.HotstringEntry = g_runtimeHotstringEntriesEmpty[0..];
// Context changes build an inactive copy of the runtime entries and atomically
// publish it. Entry indexes remain stable, so callback/payload arrays stay keyed
// by the permanent append-only registration index.
var g_runtimeHotstringActiveEmpty: [0]hotstrings.HotstringEntry = .{};
var g_runtimeHotstringActiveBanks: [2][]hotstrings.HotstringEntry = .{ g_runtimeHotstringActiveEmpty[0..], g_runtimeHotstringActiveEmpty[0..] };
var g_runtimeHotstringActiveLenBanks: [2]usize = .{ 0, 0 };
var g_activeRuntimeHotstringBank: u32 = 0;
const RuntimeHotstringActiveView = struct {
    entries: []const hotstrings.HotstringEntry,
    len: usize,
};
inline fn activeRuntimeHotstrings() RuntimeHotstringActiveView {
    const idx = @atomicLoad(u32, &g_activeRuntimeHotstringBank, .acquire);
    return .{ .entries = g_runtimeHotstringActiveBanks[idx], .len = g_runtimeHotstringActiveLenBanks[idx] };
}
var g_runtimeHotstringTriggerBytesEmpty: [0]RuntimeHotstringTrigger = .{};
var g_runtimeHotstringTriggerBytes: []RuntimeHotstringTrigger = g_runtimeHotstringTriggerBytesEmpty[0..];
var g_runtimeHotstringCallbackIdsEmpty: [0]i32 = .{};
var g_runtimeHotstringCallbackIds: []i32 = g_runtimeHotstringCallbackIdsEmpty[0..];
var g_runtimeHotstringLen: usize = 0;
var g_runtimeHotstringPublishedLen: usize = 0;
var g_compiledHotstringsLen: usize = 0;
var g_runtimeHotstringSuspendExemptEmpty: [0]bool = .{};
var g_runtimeHotstringSuspendExempt: []bool = g_runtimeHotstringSuspendExemptEmpty[0..];
// Runtime hotstring context rows. Contexts are evaluated in Zig on context change,
// never in the AHK callback, so a hotstring whose context does not match is never
// matched or fired in the first place.
const RUNTIME_HOTSTRING_CONTEXT_CHARS: usize = 128;
const RUNTIME_HOTSTRING_CONTEXT_INITIAL_CAP: usize = 4096;
const RuntimeHotstringContextText = [RUNTIME_HOTSTRING_CONTEXT_CHARS]u16;
const RuntimeHotstringContext = struct {
    contextKind: u8 = RUNTIME_CONTEXT_GLOBAL_KIND,
    contextNegated: bool = false,
    contextLen: u16 = 0,
    specificityMask: u8 = 0,
    allowed: bool = true,
};
var g_hsCtxRowsEmpty: [0]RuntimeHotstringContext = .{};
var g_hsCtxTextsEmpty: [0]RuntimeHotstringContextText = .{};
var g_hsCtxRows: []RuntimeHotstringContext = g_hsCtxRowsEmpty[0..];
var g_hsCtxTexts: []RuntimeHotstringContextText = g_hsCtxTextsEmpty[0..];
var g_hsCtxRowsLen: usize = 0;
var g_hsCtxRowsPublishedLen: usize = 0;
var g_runtimeHotstringCtxStartEmpty: [0]u32 = .{};
var g_runtimeHotstringCtxStart: []u32 = g_runtimeHotstringCtxStartEmpty[0..];
var g_runtimeHotstringCtxCountEmpty: [0]u32 = .{};
var g_runtimeHotstringCtxCount: []u32 = g_runtimeHotstringCtxCountEmpty[0..];
// Only context-bound hotstrings live in this index. Global hotstrings can never
// change with context, so a context update must never walk or touch them.
var g_hsContextBoundIdxEmpty: [0]u32 = .{};
var g_hsContextBoundIdx: []u32 = g_hsContextBoundIdxEmpty[0..];
var g_hsContextBoundLen: usize = 0;
var g_hsContextIndexDirty: bool = false;
// User-facing enable state, kept separate so a context recalculation cannot
// resurrect a hotstring the user explicitly disabled.
var g_runtimeHotstringUserEnabledEmpty: [0]bool = .{};
var g_runtimeHotstringUserEnabled: []bool = g_runtimeHotstringUserEnabledEmpty[0..];
var g_runtimeHotstringEndChars: [hotstrings.HOTSTRING_BUFFER_BYTES]u8 = [_]u8{ '-', '(', ')', '[', ']', '{', '}', ':', ';', '\'', '"', '/', '\\', ',', '.', '?', '!', '\n', ' ', '\t' } ++ [_]u8{0} ** (hotstrings.HOTSTRING_BUFFER_BYTES - hotstrings.DEFAULT_END_CHARS.len);
var g_runtimeHotstringEndCharsLen: usize = hotstrings.DEFAULT_END_CHARS.len;
var g_hotstringMouseReset: bool = true;
const ClipboardFormatBackup = struct {
    format: u32 = 0,
    size: usize = 0,
    data: ?*anyopaque = null,
};
var g_hotstringClipboardBackup: [MAX_CLIPBOARD_FORMAT_BACKUPS]ClipboardFormatBackup = [_]ClipboardFormatBackup{.{}} ** MAX_CLIPBOARD_FORMAT_BACKUPS;
var g_hotstringClipboardBackupLen: usize = 0;
var g_hotstringClipboardRestoreGeneration: u32 = 0;
var g_clipboardMutex: ?HANDLE = null;
var g_clipboardOwnerHwnd: ?HANDLE = null;
var g_hotstringCallbackNameWide: [512]u16 = [_]u16{0} ** 512;
var g_shortcutTextWide: [512]u16 = [_]u16{0} ** 512;

fn shortcutTextWide(text: []const u8) [*:0]const u16 {
    const limit = @min(text.len, g_shortcutTextWide.len - 1);
    var i: usize = 0;
    while (i < limit) : (i += 1) {
        g_shortcutTextWide[i] = text[i];
    }
    g_shortcutTextWide[i] = 0;
    return @ptrCast(&g_shortcutTextWide);
}

const PRECOMPILED_CALLBACK_NAME_BYTES: usize = 0;

inline fn hotstringCallbackIndex(source_index: usize) i64 {
    const callback_id: i32 = -@as(i32, @intCast(source_index)) - 1;
    return if (isCompiledZigCallbackId(callback_id)) callback_id else ipc.IPC_NOOP;
}

inline fn hotkeyCallbackIndex(source_index: usize) i64 {
    const callback_id: i32 = @intCast(source_index);
    return if (isCompiledZigCallbackId(callback_id)) callback_id else ipc.IPC_NOOP;
}

inline fn shortcutCallbackIndex(callbackType: i32, callbackId: i32) i64 {
    // Compiled AHK callbacks use a reserved negative ID domain.  Preserve
    // that ID through IPC so AHK can resolve it in the generated callback
    // map.  Only legacy runtime callback encodings are filtered below.
    if (isCompiledZigCallbackId(callbackId)) return callbackId;
    if (callbackId >= 0) return callbackId;
    const callback_base: i32 = if (callbackType == 0 or callbackType == 6) 2 else 1;
    const index_i32 = -callbackId - callback_base;
    if (index_i32 < 0) return ipc.IPC_NOOP;
    return switch (callbackType) {
        0, 1, 2, 5, 6 => ipc.IPC_NOOP,
        else => ipc.IPC_NOOP,
    };
}

// Packed scan-code table: single u16 per VK.
// Layout: bit 15 = E0 flag, bits [7:0] = scan code.
// Replaces the old g_scCache[u16] + g_e0Cache[bitset] pair — one load instead of two.
// Zero means "not yet cached" (safe because scan code 0 is never valid).
var g_scPacked: [VK_COUNT]u16 = [_]u16{0} ** VK_COUNT;
var g_strokeVKCache: [512]i16 = [_]i16{-1} ** 512;
// g_comboMatrix and g_instantComboMatrix declared above as [VK_COUNT][VK_COUNT]bool
// ============================================================================
// Section 7B — KeyGate: per-key metadata for hot-path gating
// ============================================================================

// KeyGate property bits (static semantic properties)
// Static property: this VK has a virtual modifier role.
const KP_HAS_VIRTUAL_MODIFIER_ROLE: u32 = 1 << 0;
// Static property: this VK has a hold callback.
const KP_HAS_HOLD_CALLBACK: u32 = 1 << 1;
// Static property: this VK can be a combo primary.
const KP_CAN_BE_COMBO_PRIMARY: u32 = 1 << 2;
// Static property: this VK can be an instant combo primary.
const KP_CAN_BE_INSTANT_COMBO_PRIMARY: u32 = 1 << 3;
// Static property: this VK can be a combo secondary.
const KP_CAN_BE_COMBO_SECONDARY: u32 = 1 << 4;
// Static property: this VK can be an instant combo secondary.
const KP_CAN_BE_INSTANT_COMBO_SECONDARY: u32 = 1 << 5;
// Static property: this VK can participate in a chord.
const KP_CAN_PARTICIPATE_IN_CHORD: u32 = 1 << 6;
// Static property: this VK participates in Windows-facing modifier processing.
const KP_IS_WINDOWS_FACING_MODIFIER: u32 = 1 << 7;
// Static property: this VK updates physical modifier state.
const KP_IS_PHYSICAL_MODIFIER: u32 = 1 << 8;
const KP_CAN_DOUBLE_TAP: u32 = 1 << 9;

// Keydown section mask bits
const KD_PHYS_MOD: u32 = 1 << 0;
const KD_SYS_MOD: u32 = 1 << 1;
const KD_MOD_CONTAMINATION: u32 = 1 << 3;
const KD_INSTANT_SECONDARY: u32 = 1 << 4;
const KD_COMBO_SECONDARY: u32 = 1 << 5;
const KD_CHORD: u32 = 1 << 6;
const KD_DOUBLE_TAP: u32 = 1 << 7;
const KD_SAME_MOD: u32 = 1 << 8;
const KD_PLAIN_BUFFER: u32 = 1 << 9;
// Gates the "HELD PAST THRESHOLD" buffer scan: keys that are homerow modifiers
// OR can be combo/instant secondaries.  Plain typing keys that are neither
// can never activate a held-mod path so the scan is entirely skippable.
const KD_HELD_MOD: u32 = 1 << 10;
// Gates the "INTENTIONAL CHORD" (2+ clean mods + incoming key) section.
// True for any key that is not itself a physical/system modifier — i.e. every
// key that can arrive as the "trigger" in a modifier-chord shortcut.
const KD_INTENTIONAL_CHORD: u32 = 1 << 11;

// Keydown precompiled path bits stored in KeyGate.kdPlan.
const KDP_PLAIN: u32 = 1 << 0;
const KDP_PHYS_MOD: u32 = 1 << 1;
const KDP_SYS_MOD: u32 = 1 << 2;
const KDP_DOUBLE_TAP: u32 = 1 << 3;
const KDP_MOD_CONTAM: u32 = 1 << 4;
const KDP_INSTANT_SECONDARY: u32 = 1 << 5;
const KDP_COMBO_SECONDARY: u32 = 1 << 6;
const KDP_CHORD: u32 = 1 << 7;
const KDP_INTENTIONAL_CHORD: u32 = 1 << 8;
const KDP_HELD_MOD: u32 = 1 << 9;
const KDP_HELD_MOD_RELEVANT: u32 = KDP_HELD_MOD;
const KDP_SAME_MOD: u32 = 1 << 10;

// Strict early key-down fast path. This means the key itself has no structural
// reason to run bufferKeyDown's combo/chord/mod/secondary sections.
const KDP_SKIP_ALL_BUFFER_DOWN: u32 = 1 << 11;

// Phase 3: Composite gates for real-density fast-path reduction.
// KDP_TAPLIKE_DOWN: key has no modifier, no hold, no secondary roles, no chord.
// Can behave like a taplike key on keydown despite possibly being combo/instant primary.
const KDP_TAPLIKE_DOWN: u32 = 1 << 12;

// KDP_PRIMARY_TAPLIKE_DOWN: may be combo/instant primary but still taplike on keydown.
// Does not assume the key was NOT used as a primary — that decision belongs at keyup.
const KDP_PRIMARY_TAPLIKE_DOWN: u32 = 1 << 13;

// KDP_NEEDS_ACTIVE_PRIMARY_SYNC: gates the active-primary sync path on keydown.
// True only for keys that can actually require active-primary tracking.
const KDP_NEEDS_ACTIVE_PRIMARY_SYNC: u32 = 1 << 14;
// Derived key-down plan state: this VK has a virtual modifier role.
const KDP_HAS_VIRTUAL_MODIFIER_ROLE: u32 = 1 << 15;
const KDP_IS_COMBO_PRIMARY: u32 = 1 << 16;
const KDP_IS_INSTANT_PRIMARY: u32 = 1 << 17;
const KDP_MODTYPE_SHIFT: u5 = 18;
const KDP_MODTYPE_MASK: u32 = 0x7 << KDP_MODTYPE_SHIFT;

inline fn modTypeFromKdPlan(kdPlan: u32) i8 {
    return if ((kdPlan & KDP_HAS_VIRTUAL_MODIFIER_ROLE) != 0)
        @intCast((kdPlan & KDP_MODTYPE_MASK) >> KDP_MODTYPE_SHIFT)
    else
        MOD_NONE;
}

// Keyup section mask bits
const KU_PHYS_MOD: u32 = 1 << 0;
const KU_SYS_MOD: u32 = 1 << 1;
const KU_MODIFIER_LOGIC: u32 = 1 << 2;
const KU_COMBO_SECONDARY: u32 = 1 << 3;
const KU_INSTANT_SECONDARY: u32 = 1 << 4;
const KU_HOLD: u32 = 1 << 5;
const KU_COMBO_PRIMARY: u32 = 1 << 6;
const KU_INSTANT_PRIMARY: u32 = 1 << 7;
const KU_DOUBLE_TAP: u32 = 1 << 8;
const KU_SAME_MOD: u32 = 1 << 9;
const KU_RETRO_TIMER: u32 = 1 << 10;
const KU_FAST_TAP_PLAIN: u32 = 1 << 11;
// Gates the retroactive modifier-activation scan in bufferKeyUp.
// True for non-modifier, non-phys-mod, non-sys-mod keys that are not already
// combo/instant secondaries — i.e. plain buffered keys that may still need a
// retroactive mod applied on their release.
const KU_RETRO_MOD_ACT: u32 = 1 << 12;
// Strict early key-up fast path. This means the key itself has no structural
// reason to run bufferKeyUp's combo/mod/hold/retro sections.
const KU_SKIP_ALL_BUFFER_UP: u32 = 1 << 13;
// Keyup can update active combo/instant-primary bitsets for this VK.
const KU_NEEDS_ACTIVE_PRIMARY_SYNC: u32 = 1 << 14;

// ============================================================================
// Key scan flags (KFS): per-key static scan eligibility bitmask
// Precomputed in rebuild_runtime_vk_plan from static per-key facts only.
// Used to pre-gate static portions of hot if-statements before scan-heavy blocks.
// ============================================================================
const KFS_KD_RELATION_CHECK: u16 = 1 << 0;
const KFS_KD_CHORD_CHECK: u16 = 1 << 1;
const KFS_KD_INTENTIONAL_CHORD: u16 = 1 << 2;
const KFS_KU_RELATION_CHECK: u16 = 1 << 3;
const KFS_KU_RETRO_MOD_CHECK: u16 = 1 << 4;
const KFS_PQ_WAIT_SCAN: u16 = 1 << 5;
const KFS_PQ_MODIFIER_RESOLVE: u16 = 1 << 6;
const KFS_PQ_PREFIX_SCAN: u16 = 1 << 7;

// Precomputed per-key decisions used in processQueue to replace firstProps derivation.
// ============================================================================
// Pending-queue plan state: this VK has a virtual modifier role.
const PQP_HAS_VIRTUAL_MODIFIER_ROLE: u32 = 1 << 0; // key can act as a homerow modifier
const PQP_HAS_HOLD: u32 = 1 << 1; // key has a hold callback
const PQP_CAN_COMBO_SECONDARY: u32 = 1 << 2; // key can be blocked waiting for a combo primary
const PQP_CAN_INSTANT_SECONDARY: u32 = 1 << 3; // key can be blocked waiting for an instant primary
// Set when none of the above bits are set: plain tap-only key with no structural
// reason to enter modifier resolution, needWait scans, or hold classification.
const PQP_PLAIN_NO_HOLD: u32 = 1 << 4;

// Extended plan bits — give processQueue explicit per-section gates.
// Keeps behavior unchanged; only enables more precise branching.

// Key can enter the modifier-activated/triggered resolution block.
// Equivalent to PQP_HAS_VIRTUAL_MODIFIER_ROLE but named for the branch it guards.
const PQP_NEEDS_MODIFIER_RESOLVE: u32 = 1 << 5;

// Key may need to wait on older unreleased keys before it can resolve.
// Set for all non-modifier keys (any can be blocked by an unresolved earlier modifier).
const PQP_NEEDS_WAIT_SCAN: u32 = 1 << 6;

// Key has a hold callback and needs tap-vs-hold duration classification.
const PQP_NEEDS_HOLD_CLASSIFY: u32 = 1 << 7;

// Key can receive a long-held modifier prefix when emitting a tap callback.
// Set for non-modifier keys.
const PQP_CAN_PREFIX_SCAN: u32 = 1 << 8;

// Explicit fast-emit-tap marker. Set for plain keys with no modifier role,
// no hold, no secondary-combo capability — the common normal-typing case.
// Runtime conditions (RF_UNREL_KEYS, RF_ACTIVE_MODS) must also be clear.
const PQP_FAST_EMIT_TAP: u32 = 1 << 9;

// Phase 3: Composite gate for processQueue slow-resolve path.
// Set for any key that cannot take the fast-emit-tap path and needs detailed resolution.
// Gates the multi-step hold/modifier/combo/secondary resolution logic.
const PQP_NEEDS_SLOW_RESOLVE: u32 = 1 << 10;

// Parallel plan array for processQueue — same index space as g_keyGate.
// Written once per rebuild_runtime_vk_plan(), read-only on the hot path.
var g_keyQueuePlan: [VK_COUNT]u32 = [_]u32{0} ** VK_COUNT;

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

const KeyGate = extern struct {
    kdPlan: u32,
    kuMask: u32,
    props: u32,
    kdAction: KeyDownAction,
    kuAction: KeyUpAction,
    scanFlags: u16,
};

comptime {
    if (@sizeOf(KeyGate) != 16) @compileError("KeyGate must stay 16 bytes");
}

var g_keyGate: [VK_COUNT]KeyGate align(64) =
    [_]KeyGate{.{ .kdPlan = 0, .kuMask = 0, .props = 0, .kdAction = .fallback_slow, .kuAction = .fallback_slow, .scanFlags = 0 }} ** VK_COUNT;

const ContextDerivedBank = struct {
    gate: [VK_COUNT]KeyGate = [_]KeyGate{.{ .kdPlan = 0, .kuMask = 0, .props = 0, .kdAction = .fallback_slow, .kuAction = .fallback_slow, .scanFlags = 0 }} ** VK_COUNT,
    queuePlan: [VK_COUNT]u32 = [_]u32{0} ** VK_COUNT,
    scanFlags: [VK_COUNT]u16 = [_]u16{0} ** VK_COUNT,
    pairRelation: [VK_COUNT][VK_COUNT]u8 = [_][VK_COUNT]u8{[_]u8{0} ** VK_COUNT} ** VK_COUNT,
    comboPrimaries: [VK_COUNT][4]u64 = [_][4]u64{.{ 0, 0, 0, 0 }} ** VK_COUNT,
    instantPrimaries: [VK_COUNT][4]u64 = [_][4]u64{.{ 0, 0, 0, 0 }} ** VK_COUNT,
    comboPrimaryList: [VK_COUNT][VK_COUNT]u16 = [_][VK_COUNT]u16{[_]u16{0} ** VK_COUNT} ** VK_COUNT,
    instantPrimaryList: [VK_COUNT][VK_COUNT]u16 = [_][VK_COUNT]u16{[_]u16{0} ** VK_COUNT} ** VK_COUNT,
    comboPrimaryListLen: [VK_COUNT]u16 = [_]u16{0} ** VK_COUNT,
    instantPrimaryListLen: [VK_COUNT]u16 = [_]u16{0} ** VK_COUNT,
    keyModType: [VK_COUNT]i8 = [_]i8{MOD_NONE} ** VK_COUNT,
    holdCallback: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT,
    doubleTapCallback: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT,
};
var g_contextDerivedBanks: [2]ContextDerivedBank = .{ .{}, .{} };
var g_activeContextDerivedBank: u32 = 0;
inline fn activeContextDerived() *const ContextDerivedBank {
    const idx = @atomicLoad(u32, &g_activeContextDerivedBank, .acquire);
    return &g_contextDerivedBanks[idx];
}

// Per-key static scan eligibility bitmask
var g_keyScanFlags: [VK_COUNT]u16 align(64) = [_]u16{0} ** VK_COUNT;

// Cold direct tables — avoid function-call indirection on hot path
// Virtual modifier role metadata assigned to each VK.
var g_vk_modifier_roles: [VK_COUNT]i8 align(64) = [_]i8{MOD_NONE} ** VK_COUNT;
// Windows-facing modifier-family values assigned to each VK.
var g_vk_windows_facing_modifiers: [VK_COUNT]u8 align(64) = [_]u8{0} ** VK_COUNT;
// Physical modifier-family bit assigned to each recognized physical modifier VK.
var g_vk_is_physical_modifier: [VK_COUNT]u8 align(64) = [_]u8{0} ** VK_COUNT;
// Virtual modifier-family mask produced by each key VK.
var g_key_virtual_modifier_mask: [VK_COUNT]u8 align(64) = [_]u8{0} ** VK_COUNT;
// Output VK produced by each virtual modifier role.
var g_virtual_modifier_output_vk: [VK_COUNT]u16 align(64) = [_]u16{0} ** VK_COUNT;
var g_keyModPrefix: [VK_COUNT]u16 align(64) = [_]u16{0} ** VK_COUNT;
var g_keyNamePtr: [VK_COUNT]?*const [KN_LEN]u16 align(64) = [_]?*const [KN_LEN]u16{null} ** VK_COUNT;
var g_keyHoldCallbackId: [VK_COUNT]i32 align(64) = [_]i32{-1} ** VK_COUNT;
var g_keyDoubleTapCallbackId: [VK_COUNT]i32 align(64) = [_]i32{-1} ** VK_COUNT;
// A hold is one logical action for one physical press.  Several resolver
// paths can converge on the same press (the normal queue drain and the
// key-up fast path); keep the IPC emission at one shared choke point so a
// compiled callback cannot be delivered twice.
var g_holdCallbackQueued: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
var g_hotWarmSink: u64 = 0;

// Combo bitset gates: which active primaries can combo with this secondary?
var g_comboPrimariesForSecondary: [VK_COUNT][4]u64 align(64) =
    [_][4]u64{.{ 0, 0, 0, 0 }} ** VK_COUNT;
var g_instantPrimariesForSecondary: [VK_COUNT][4]u64 align(64) =
    [_][4]u64{.{ 0, 0, 0, 0 }} ** VK_COUNT;
var g_comboPrimaryListForSecondary: [VK_COUNT][VK_COUNT]u16 align(64) =
    [_][VK_COUNT]u16{[_]u16{0} ** VK_COUNT} ** VK_COUNT;
var g_instantPrimaryListForSecondary: [VK_COUNT][VK_COUNT]u16 align(64) =
    [_][VK_COUNT]u16{[_]u16{0} ** VK_COUNT} ** VK_COUNT;
var g_comboPrimaryListLenForSecondary: [VK_COUNT]u16 align(64) = [_]u16{0} ** VK_COUNT;
var g_instantPrimaryListLenForSecondary: [VK_COUNT]u16 align(64) = [_]u16{0} ** VK_COUNT;

// Active primary bitsets — updated whenever a primary enters/leaves the buffer
var g_activeComboPrimaryBits: [4]u64 = .{ 0, 0, 0, 0 };
var g_activeInstantPrimaryBits: [4]u64 = .{ 0, 0, 0, 0 };
var g_activeAnyPrimaryBits: [4]u64 = .{ 0, 0, 0, 0 };

inline fn hasActiveComboPrimaryForSecondary(vk: i32) bool {
    if (vk < 0 or vk >= VK_COUNT) return false;
    const s: usize = @intCast(vk);
    const allowed = &activeContextDerived().comboPrimaries[s];
    return ((allowed[0] & g_activeComboPrimaryBits[0]) |
        (allowed[1] & g_activeComboPrimaryBits[1]) |
        (allowed[2] & g_activeComboPrimaryBits[2]) |
        (allowed[3] & g_activeComboPrimaryBits[3])) != 0;
}

inline fn hasActiveInstantPrimaryForSecondary(vk: i32) bool {
    if (vk < 0 or vk >= VK_COUNT) return false;
    const s: usize = @intCast(vk);
    const allowed = &activeContextDerived().instantPrimaries[s];
    return ((allowed[0] & g_activeInstantPrimaryBits[0]) |
        (allowed[1] & g_activeInstantPrimaryBits[1]) |
        (allowed[2] & g_activeInstantPrimaryBits[2]) |
        (allowed[3] & g_activeInstantPrimaryBits[3])) != 0;
}

inline fn comboPrimaryAllowedForSecondary(primary: i32, secondary: i32) bool {
    if (primary < 0 or primary >= VK_COUNT or secondary < 0 or secondary >= VK_COUNT) return false;
    const p: usize = @intCast(primary);
    const allowed = &activeContextDerived().comboPrimaries[@intCast(secondary)];
    return (allowed[p >> 6] & (@as(u64, 1) << @intCast(p & 63))) != 0;
}

inline fn instantPrimaryAllowedForSecondary(primary: i32, secondary: i32) bool {
    if (primary < 0 or primary >= VK_COUNT or secondary < 0 or secondary >= VK_COUNT) return false;
    const p: usize = @intCast(primary);
    const allowed = &activeContextDerived().instantPrimaries[@intCast(secondary)];
    return (allowed[p >> 6] & (@as(u64, 1) << @intCast(p & 63))) != 0;
}

inline fn secondaryAllowsPrimaryFast(primary: i32, secondary: i32, allow_combo: bool, allow_instant: bool) bool {
    if (primary < 0 or primary >= VK_COUNT or secondary < 0 or secondary >= VK_COUNT) return false;
    const p: usize = @intCast(primary);
    const bit = @as(u64, 1) << @intCast(p & 63);
    const word = p >> 6;
    const s: usize = @intCast(secondary);
    if (allow_combo and (activeContextDerived().comboPrimaries[s][word] & bit) != 0) return true;
    if (allow_instant and (activeContextDerived().instantPrimaries[s][word] & bit) != 0) return true;
    return false;
}

inline fn firstUnreleasedInstantPrimaryForSecondary(secondary: i32) i32 {
    if (secondary < 0 or secondary >= VK_COUNT) return 0;
    const s: usize = @intCast(secondary);
    const list = &activeContextDerived().instantPrimaryList[s];
    const len: usize = @intCast(activeContextDerived().instantPrimaryListLen[s]);
    for (list[0..len]) |pv16| {
        const pv: i32 = @intCast(pv16);
        if (kbGet(pv)) |kd| {
            if (!kd.isReleased()) return pv;
        }
    }
    return 0;
}

inline fn firstUnreleasedComboPrimaryForSecondary(secondary: i32, require_combo_triggered: bool) i32 {
    if (secondary < 0 or secondary >= VK_COUNT) return 0;
    const s: usize = @intCast(secondary);
    const list = &activeContextDerived().comboPrimaryList[s];
    const len: usize = @intCast(activeContextDerived().comboPrimaryListLen[s]);
    for (list[0..len]) |pv16| {
        const pv: i32 = @intCast(pv16);
        if (kbGet(pv)) |kd| {
            if (kd.isReleased()) continue;
            if (require_combo_triggered and !kd.comboTriggered()) continue;
            return pv;
        }
    }
    return 0;
}

// Set/clear a VK in a 256-bit (4×u64) bitset
inline fn bitset256Set(bs: *[4]u64, vk: i32) void {
    if (vk < 0 or vk >= VK_COUNT) return;
    const v: usize = @intCast(vk);
    bs[v >> 6] |= @as(u64, 1) << @intCast(v & 63);
}
inline fn bitset256Clear(bs: *[4]u64, vk: i32) void {
    if (vk < 0 or vk >= VK_COUNT) return;
    const v: usize = @intCast(vk);
    bs[v >> 6] &= ~(@as(u64, 1) << @intCast(v & 63));
}
inline fn bitset256Test(bs: *const [4]u64, vk: i32) bool {
    if (vk < 0 or vk >= VK_COUNT) return false;
    const v: usize = @intCast(vk);
    return (bs[v >> 6] & (@as(u64, 1) << @intCast(v & 63))) != 0;
}

// Update active primary bitsets when a key enters/leaves active-primary state
inline fn activeComboPrimaryAdd(vk: i32) void {
    bitset256Set(&g_activeComboPrimaryBits, vk);
}
inline fn activeComboPrimaryRemove(vk: i32) void {
    bitset256Clear(&g_activeComboPrimaryBits, vk);
}
inline fn activeInstantPrimaryAdd(vk: i32) void {
    bitset256Set(&g_activeInstantPrimaryBits, vk);
}
inline fn activeInstantPrimaryRemove(vk: i32) void {
    bitset256Clear(&g_activeInstantPrimaryBits, vk);
}
inline fn activePrimaryBitsClear(vk: i32) void {
    if (g_activeAnyPrimaryCount == 0 and
        g_activeComboPrimaryCount == 0 and
        g_activeInstantPrimaryCount == 0)
    {
        return;
    }
    if (bitset256Test(&g_activeComboPrimaryBits, vk) and g_activeComboPrimaryCount > 0)
        g_activeComboPrimaryCount -= 1;
    if (bitset256Test(&g_activeInstantPrimaryBits, vk) and g_activeInstantPrimaryCount > 0)
        g_activeInstantPrimaryCount -= 1;
    if (bitset256Test(&g_activeAnyPrimaryBits, vk) and g_activeAnyPrimaryCount > 0)
        g_activeAnyPrimaryCount -= 1;
    bitset256Clear(&g_activeAnyPrimaryBits, vk);
    activeComboPrimaryRemove(vk);
    activeInstantPrimaryRemove(vk);
    rfSetIf(RF_ACTIVE_COMBO_PRIMARY, g_activeComboPrimaryCount != 0);
    rfSetIf(RF_ACTIVE_INSTANT_PRIMARY, g_activeInstantPrimaryCount != 0);
}
inline fn activePrimaryBitsSync(vk: i32, kd: KeyData) void {
    const vki: usize = @intCast(vk);
    const gate = &activeContextDerived().gate[vki];
    const kdPlan = gate.kdPlan;
    if ((kdPlan & KDP_NEEDS_ACTIVE_PRIMARY_SYNC) == 0) return;
    const live = !kd.isReleased();
    const shouldCombo = live and (kdPlan & KDP_IS_COMBO_PRIMARY) != 0;
    const shouldInstant = live and (kdPlan & KDP_IS_INSTANT_PRIMARY) != 0;
    const hadCombo = bitset256Test(&g_activeComboPrimaryBits, vk);
    const hadInstant = bitset256Test(&g_activeInstantPrimaryBits, vk);
    const shouldAny = shouldCombo or shouldInstant;
    const hadAny = bitset256Test(&g_activeAnyPrimaryBits, vk);
    if (shouldCombo)
        activeComboPrimaryAdd(vk)
    else
        activeComboPrimaryRemove(vk);
    if (shouldInstant)
        activeInstantPrimaryAdd(vk)
    else
        activeInstantPrimaryRemove(vk);
    if (shouldCombo and !hadCombo) {
        g_activeComboPrimaryCount += 1;
    } else if (!shouldCombo and hadCombo) {
        if (g_activeComboPrimaryCount > 0) g_activeComboPrimaryCount -= 1;
    }
    if (shouldInstant and !hadInstant) {
        g_activeInstantPrimaryCount += 1;
    } else if (!shouldInstant and hadInstant) {
        if (g_activeInstantPrimaryCount > 0) g_activeInstantPrimaryCount -= 1;
    }
    if (shouldAny and !hadAny) {
        bitset256Set(&g_activeAnyPrimaryBits, vk);
        g_activeAnyPrimaryCount += 1;
    } else if (!shouldAny and hadAny) {
        bitset256Clear(&g_activeAnyPrimaryBits, vk);
        if (g_activeAnyPrimaryCount > 0) g_activeAnyPrimaryCount -= 1;
    }
    rfSetIf(RF_ACTIVE_COMBO_PRIMARY, g_activeComboPrimaryCount != 0);
    rfSetIf(RF_ACTIVE_INSTANT_PRIMARY, g_activeInstantPrimaryCount != 0);
}

// Marks a buffered key as released exactly once, decrementing unreleased counters.
// Use this instead of calling kd.sf(FLAG_RELEASED) directly in bufferKeyUp /
// processQueue so that g_unreleasedKeyCount and RF_UNREL_KEYS stay accurate.
// kbRemove() checks !isReleased() before decrementing — if the key is already
// marked released the counter would not be decremented there, causing drift.
inline fn markKeyReleased(vk: i32, kd: *KeyData) void {
    if (kd.isReleased()) return;
    kd.sf(FLAG_RELEASED);
    if (g_unreleasedKeyCount > 0) g_unreleasedKeyCount -= 1;
    _ = vk;
    if (!kd.isRuntimeModifier() and g_unreleasedNonModCount > 0) g_unreleasedNonModCount -= 1;
    rfSetIf(RF_UNREL_KEYS, g_unreleasedKeyCount != 0);
    rfSetIf(RF_UNREL_NONMOD_KEYS, g_unreleasedNonModCount != 0);
}

var g_keyGateDirty: bool = true;

// Called at the end of every registration function (setup path, never hot path).
// Rebuilds immediately so the gate is always fresh by the time any keystroke arrives.
inline fn markKeyGateDirty() void {
    rebuild_runtime_vk_plan();
    g_keyGateDirty = false;
}

// Defensive guard for the startup window: g_keyGateDirty is true until the
// first explicit rebuild.  Call this from setup/init paths only — never from
// the keystroke hot path.  On the hot path the gate is always already fresh
// because every registration function calls markKeyGateDirty() eagerly.
inline fn ensureKeyGateFresh() void {
    if (g_keyGateDirty) {
        @branchHint(.unlikely);
        rebuild_runtime_vk_plan();
        g_keyGateDirty = false;
    }
}

fn warmHotTables() void {
    var s: u64 = 0;
    for (0..VK_COUNT) |row| {
        var col: usize = 0;
        while (col < VK_COUNT) : (col += 64) {
            s +%= g_pairRelationMask[row][col];
        }
    }
    for (0..VK_COUNT) |i| {
        const gate = g_keyGate[i];
        s +%= gate.kdPlan;
        s +%= gate.kuMask;
        s +%= gate.props;
        s +%= @intFromEnum(gate.kdAction);
        s +%= @intFromEnum(gate.kuAction);
        s +%= gate.scanFlags;
        s +%= g_keyScanFlags[i];
        s +%= g_keyQueuePlan[i];
        s +%= g_scPacked[i];
        s +%= @as(u64, @intCast(@as(i32, g_vk_modifier_roles[i]) + 128));
        s +%= g_vk_windows_facing_modifiers[i];
        s +%= g_vk_is_physical_modifier[i];
        s +%= g_key_virtual_modifier_mask[i];
        s +%= g_virtual_modifier_output_vk[i];
        s +%= g_keyModPrefix[i];
        if (g_keyNamePtr[i] != null) s +%= 1;
        if (g_keyHoldCallbackId[i] >= 0) s +%= @intCast(g_keyHoldCallbackId[i]);
        if (g_keyDoubleTapCallbackId[i] >= 0) s +%= @intCast(g_keyDoubleTapCallbackId[i]);
    }
    g_hotWarmSink +%= s;
}

// Rebuilds the derived runtime VK plan from static VK facts.
fn rebuild_runtime_vk_plan() void {
    // Snapshot each already-published runtime overlay once. Context rebuilds are
    // cold-path work; avoid thousands of redundant atomic index loads while
    // constructing the next derived gate.
    const runtime_actions = activeRuntimeContextActions();
    const runtime_modifiers = activeRuntimeModifiers();
    const runtime_combos = activeRuntimeCombos();
    const runtime_chords = activeRuntimeChords();

    var tmpGate: [VK_COUNT]KeyGate =
        [_]KeyGate{.{ .kdPlan = 0, .kuMask = 0, .props = 0, .kdAction = .fallback_slow, .kuAction = .fallback_slow, .scanFlags = 0 }} ** VK_COUNT;
    var tmpScanFlags: [VK_COUNT]u16 = [_]u16{0} ** VK_COUNT;
    var tmpQueuePlan: [VK_COUNT]u32 = [_]u32{0} ** VK_COUNT;
    var tmpComboPrim: [VK_COUNT][4]u64 = [_][4]u64{.{ 0, 0, 0, 0 }} ** VK_COUNT;
    var tmpInstantPrim: [VK_COUNT][4]u64 = [_][4]u64{.{ 0, 0, 0, 0 }} ** VK_COUNT;
    var tmpComboPrimList: [VK_COUNT][VK_COUNT]u16 = [_][VK_COUNT]u16{[_]u16{0} ** VK_COUNT} ** VK_COUNT;
    var tmpInstantPrimList: [VK_COUNT][VK_COUNT]u16 = [_][VK_COUNT]u16{[_]u16{0} ** VK_COUNT} ** VK_COUNT;
    var tmpComboPrimListLen: [VK_COUNT]u16 = [_]u16{0} ** VK_COUNT;
    var tmpInstantPrimListLen: [VK_COUNT]u16 = [_]u16{0} ** VK_COUNT;
    var tmpPairRelationMask: [VK_COUNT][VK_COUNT]u8 =
        [_][VK_COUNT]u8{[_]u8{0} ** VK_COUNT} ** VK_COUNT;
    var tmpKeyModType: [VK_COUNT]i8 = [_]i8{MOD_NONE} ** VK_COUNT;
    var tmpKeySysBit: [VK_COUNT]u8 = [_]u8{0} ** VK_COUNT;
    var tmpKeyPhysBit: [VK_COUNT]u8 = [_]u8{0} ** VK_COUNT;
    var tmpKeyModMask: [VK_COUNT]u8 = [_]u8{0} ** VK_COUNT;
    var tmpKeyModVK: [VK_COUNT]u16 = [_]u16{0} ** VK_COUNT;
    var tmpKeyModPrefix: [VK_COUNT]u16 = [_]u16{0} ** VK_COUNT;
    var tmpKeyNamePtr: [VK_COUNT]?*const [KN_LEN]u16 = [_]?*const [KN_LEN]u16{null} ** VK_COUNT;
    var tmpKeyHoldCallbackId: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT;
    var tmpKeyDoubleTapCallbackId: [VK_COUNT]i32 = [_]i32{-1} ** VK_COUNT;
    for (0..VK_COUNT) |vi| {
        // Cold direct tables (temp-first)
        const runtime_mt = runtime_modifiers.modType[vi];
        const mt = if (runtime_mt != MOD_NONE) runtime_mt else g_modTypeFlat[vi];
        tmpKeyModType[vi] = mt;
        switch (mt) {
            MOD_CTRL => {
                tmpKeyModMask[vi] = 0x01;
                tmpKeyModVK[vi] = VK_CONTROL;
                tmpKeyModPrefix[vi] = '^';
            },
            MOD_ALT => {
                tmpKeyModMask[vi] = 0x02;
                tmpKeyModVK[vi] = VK_MENU;
                tmpKeyModPrefix[vi] = '!';
            },
            MOD_SHIFT => {
                tmpKeyModMask[vi] = 0x04;
                tmpKeyModVK[vi] = VK_SHIFT;
                tmpKeyModPrefix[vi] = '+';
            },
            MOD_WIN => {
                tmpKeyModMask[vi] = 0x08;
                tmpKeyModVK[vi] = VK_LWIN;
                tmpKeyModPrefix[vi] = '#';
            },
            else => {},
        }
        const sb: i32 = g_sysModBitFlat[vi];
        tmpKeySysBit[vi] = if (sb != 0 and sb <= 255) @intCast(sb) else 0;
        tmpKeyPhysBit[vi] = @truncate(g_physModBitTable[vi]);
        const regIdx = g_vkToRegIdx[vi];
        if (regIdx >= 0) tmpKeyNamePtr[vi] = &g_keyNames[@intCast(regIdx)];
        // Compiled callbacks use the reserved negative Zig-callback range.
        // They are still real callbacks and must participate in key-gate
        // construction; checking only >= 0 silently drops compiled holds and
        // double-taps before the queue path can ever see them.
        tmpKeyHoldCallbackId[vi] = if (runtime_actions.hold[vi] >= 0 or isCompiledZigCallbackId(runtime_actions.hold[vi]))
            runtime_actions.hold[vi]
        else
            g_hcFlat[vi];
        tmpKeyDoubleTapCallbackId[vi] = if (runtime_actions.doubleTap[vi] >= 0 or isCompiledZigCallbackId(runtime_actions.doubleTap[vi]))
            runtime_actions.doubleTap[vi]
        else
            g_modDtFlat[vi];

        var props: u32 = 0;
        var kdMask: u32 = 0;
        var kuMask: u32 = 0;

        // Physical modifier
        if (g_physModBitTable[vi] != 0) {
            props |= KP_IS_PHYSICAL_MODIFIER;
            kdMask |= KD_PHYS_MOD;
            kuMask |= KU_PHYS_MOD;
        }

        // System modifier
        if (sb != 0) {
            props |= KP_IS_WINDOWS_FACING_MODIFIER;
            kdMask |= KD_SYS_MOD;
            kuMask |= KU_SYS_MOD;
        }

        // Homerow modifier
        if (mt != MOD_NONE) {
            props |= KP_HAS_VIRTUAL_MODIFIER_ROLE;
            kdMask |= KD_SAME_MOD;
            kuMask |= KU_MODIFIER_LOGIC | KU_SAME_MOD;
        }

        // Hold/double-tap capability is armed from the effective callback. A
        // context-specific registration that is currently inactive must not
        // keep the key on the hold/double-tap path.
        if (tmpKeyHoldCallbackId[vi] >= 0 or isCompiledZigCallbackId(tmpKeyHoldCallbackId[vi])) {
            props |= KP_HAS_HOLD_CALLBACK;
            kuMask |= KU_HOLD;
        }

        if (tmpKeyDoubleTapCallbackId[vi] >= 0 or isCompiledZigCallbackId(tmpKeyDoubleTapCallbackId[vi])) {
            props |= KP_CAN_DOUBLE_TAP;
        }

        // Combo primary
        if (g_comboPrimaryFlat[vi] or runtime_combos.comboPrimary[vi]) {
            props |= KP_CAN_BE_COMBO_PRIMARY;
            kuMask |= KU_COMBO_PRIMARY;
            kuMask |= KU_NEEDS_ACTIVE_PRIMARY_SYNC;
        }

        // Instant primary
        if (g_instantComboPrimaryFlat[vi] or runtime_combos.instantPrimary[vi]) {
            props |= KP_CAN_BE_INSTANT_COMBO_PRIMARY;
            kuMask |= KU_INSTANT_PRIMARY;
            kuMask |= KU_NEEDS_ACTIVE_PRIMARY_SYNC;
        }

        // Combo secondary — scan all primaries that have a combo with this VK
        for (0..VK_COUNT) |pi| {
            if (g_comboMatrix[pi][vi] or runtime_combos.comboMatrix[pi][vi]) {
                tmpPairRelationMask[pi][vi] |= REL_COMBO;
                tmpPairRelationMask[vi][pi] |= REL_COMBO;
                props |= KP_CAN_BE_COMBO_SECONDARY;
                kdMask |= KD_COMBO_SECONDARY;
                kuMask |= KU_COMBO_SECONDARY;
                const pvi: i32 = @intCast(pi);
                bitset256Set(&tmpComboPrim[vi], pvi);
                const li: usize = @intCast(tmpComboPrimListLen[vi]);
                tmpComboPrimList[vi][li] = @intCast(pi);
                tmpComboPrimListLen[vi] += 1;
            }
            if (g_instantComboMatrix[pi][vi] or runtime_combos.instantMatrix[pi][vi]) {
                tmpPairRelationMask[pi][vi] |= REL_INSTANT;
                tmpPairRelationMask[vi][pi] |= REL_INSTANT;
                props |= KP_CAN_BE_INSTANT_COMBO_SECONDARY;
                kdMask |= KD_INSTANT_SECONDARY;
                kuMask |= KU_INSTANT_SECONDARY;
                const pvi: i32 = @intCast(pi);
                bitset256Set(&tmpInstantPrim[vi], pvi);
                const li: usize = @intCast(tmpInstantPrimListLen[vi]);
                tmpInstantPrimList[vi][li] = @intCast(pi);
                tmpInstantPrimListLen[vi] += 1;
            }
        }

        // Chord participant — use precise per-VK table (not "any chord + registered")
        if (g_chordParticipantFlat[vi] or runtime_chords.participant[vi]) {
            props |= KP_CAN_PARTICIPATE_IN_CHORD;
            kdMask |= KD_CHORD;
        }

        // Contamination/retro-mod eligibility is for normal incoming keys, not
        // only configured modifiers/secondaries. Keep this broad so plain keys
        // still interact with undecided/retro modifier state.
        if ((props & (KP_IS_WINDOWS_FACING_MODIFIER | KP_IS_PHYSICAL_MODIFIER)) == 0) {
            kuMask |= KU_RETRO_TIMER;
            kdMask |= KD_DOUBLE_TAP;
            kuMask |= KU_DOUBLE_TAP;
            if ((props & KP_HAS_VIRTUAL_MODIFIER_ROLE) == 0) {
                kdMask |= KD_MOD_CONTAMINATION;
            }
        }

        if ((props & (KP_IS_PHYSICAL_MODIFIER |
            KP_IS_WINDOWS_FACING_MODIFIER |
            KP_HAS_VIRTUAL_MODIFIER_ROLE |
            KP_CAN_BE_COMBO_SECONDARY |
            KP_CAN_BE_INSTANT_COMBO_SECONDARY |
            KP_CAN_PARTICIPATE_IN_CHORD)) == 0)
        {
            kdMask |= KD_PLAIN_BUFFER;
        }

        if ((props & (KP_HAS_HOLD_CALLBACK | KP_CAN_BE_COMBO_PRIMARY | KP_CAN_BE_INSTANT_COMBO_PRIMARY)) == 0) {
            kuMask |= KU_FAST_TAP_PLAIN;
        }

        // Strict structural skip-all key-up eligibility.
        // Do NOT block on KU_RETRO_TIMER / KU_RETRO_MOD_ACT here; those are broad
        // runtime-capability paths. Runtime modifier state is checked in bufferKeyUp.
        if ((props & (KP_HAS_HOLD_CALLBACK |
            KP_HAS_VIRTUAL_MODIFIER_ROLE |
            KP_IS_PHYSICAL_MODIFIER |
            KP_IS_WINDOWS_FACING_MODIFIER |
            KP_CAN_BE_COMBO_PRIMARY |
            KP_CAN_BE_INSTANT_COMBO_PRIMARY |
            KP_CAN_BE_COMBO_SECONDARY |
            KP_CAN_BE_INSTANT_COMBO_SECONDARY |
            KP_CAN_PARTICIPATE_IN_CHORD)) == 0)
        {
            kuMask |= KU_SKIP_ALL_BUFFER_UP;
        }

        // KD_HELD_MOD: gates the "HELD PAST THRESHOLD" buffer scan.
        // Enter only for keys that are homerow modifiers OR can be combo/instant
        // secondaries.  Plain typing keys can never activate that path.
        if ((props & (KP_HAS_VIRTUAL_MODIFIER_ROLE | KP_CAN_BE_COMBO_SECONDARY | KP_CAN_BE_INSTANT_COMBO_SECONDARY)) != 0) {
            kdMask |= KD_HELD_MOD;
        }

        // KD_INTENTIONAL_CHORD: gates the "2+ clean mods + incoming key" shortcut path.
        // Every key that is NOT a physical or system modifier can be a chord trigger.
        if ((props & (KP_IS_PHYSICAL_MODIFIER | KP_IS_WINDOWS_FACING_MODIFIER)) == 0) {
            kdMask |= KD_INTENTIONAL_CHORD;
        }

        // KU_RETRO_MOD_ACT: gates the retroactive modifier-activation scan on key-up.
        // Only keys that are not themselves modifiers/phys-mods/sys-mods and are not
        // already handled by a dedicated combo secondary path need this scan.
        if ((props & (KP_HAS_VIRTUAL_MODIFIER_ROLE | KP_IS_PHYSICAL_MODIFIER | KP_IS_WINDOWS_FACING_MODIFIER)) == 0) {
            kuMask |= KU_RETRO_MOD_ACT;
        }

        // Phase 1: Compute KeyDownAction classification from static properties.
        // Only uses static per-key facts; no runtime state.
        const isTaplikeDown = (props & (KP_HAS_VIRTUAL_MODIFIER_ROLE |
            KP_HAS_HOLD_CALLBACK |
            KP_IS_PHYSICAL_MODIFIER |
            KP_IS_WINDOWS_FACING_MODIFIER |
            KP_CAN_BE_COMBO_SECONDARY |
            KP_CAN_BE_INSTANT_COMBO_SECONDARY |
            KP_CAN_PARTICIPATE_IN_CHORD |
            KP_CAN_DOUBLE_TAP)) == 0;
        const isPrimaryTaplikeDown = isTaplikeDown and
            (props & (KP_CAN_BE_COMBO_PRIMARY | KP_CAN_BE_INSTANT_COMBO_PRIMARY)) != 0;

        var kdAction: KeyDownAction = .fallback_slow;
        if ((props & KP_IS_PHYSICAL_MODIFIER) != 0) {
            kdAction = .phys_mod;
        } else if ((props & KP_IS_WINDOWS_FACING_MODIFIER) != 0) {
            kdAction = .sys_mod;
        } else if ((props & (KP_HAS_VIRTUAL_MODIFIER_ROLE |
            KP_HAS_HOLD_CALLBACK |
            KP_IS_PHYSICAL_MODIFIER |
            KP_IS_WINDOWS_FACING_MODIFIER |
            KP_CAN_BE_COMBO_PRIMARY |
            KP_CAN_BE_INSTANT_COMBO_PRIMARY |
            KP_CAN_BE_COMBO_SECONDARY |
            KP_CAN_BE_INSTANT_COMBO_SECONDARY |
            KP_CAN_PARTICIPATE_IN_CHORD |
            KP_CAN_DOUBLE_TAP)) == 0)
        {
            // Strict plain: no modifier, hold, primary/secondary, chord, or double-tap roles.
            kdAction = .strict_plain_fast;
        } else if (isPrimaryTaplikeDown) {
            // May be combo/instant primary but is still taplike on keydown.
            kdAction = .taplike_primary_candidate;
        }
        // Phase 1: Compute KeyUpAction classification from static properties.
        var kuAction: KeyUpAction = .fallback_slow;
        if ((props & KP_IS_PHYSICAL_MODIFIER) != 0) {
            kuAction = .phys_mod_up;
        } else if ((props & KP_IS_WINDOWS_FACING_MODIFIER) != 0) {
            kuAction = .sys_mod_up;
        } else if ((props & (KP_HAS_VIRTUAL_MODIFIER_ROLE |
            KP_HAS_HOLD_CALLBACK |
            KP_IS_PHYSICAL_MODIFIER |
            KP_IS_WINDOWS_FACING_MODIFIER |
            KP_CAN_BE_COMBO_PRIMARY |
            KP_CAN_BE_INSTANT_COMBO_PRIMARY |
            KP_CAN_BE_COMBO_SECONDARY |
            KP_CAN_BE_INSTANT_COMBO_SECONDARY |
            KP_CAN_PARTICIPATE_IN_CHORD |
            KP_CAN_DOUBLE_TAP)) == 0)
        {
            // Plain key with no structural cleanup complexity.
            kuAction = .idle_unbuffered_noop_candidate;
        } else if ((props & KP_CAN_DOUBLE_TAP) != 0 or (props & (KP_CAN_BE_COMBO_PRIMARY | KP_CAN_BE_INSTANT_COMBO_PRIMARY)) != 0) {
            // May need repeat logic
            kuAction = .repeat_stop_candidate;
        }
        var kdPlan: u32 = 0;
        if ((kdMask & KD_PLAIN_BUFFER) != 0) {
            kdPlan |= KDP_PLAIN | KDP_SKIP_ALL_BUFFER_DOWN;
        }
        if ((props & KP_HAS_VIRTUAL_MODIFIER_ROLE) != 0) {
            kdPlan |= KDP_HAS_VIRTUAL_MODIFIER_ROLE | (@as(u32, @intCast(mt)) << KDP_MODTYPE_SHIFT);
        }
        if ((kdMask & KD_PHYS_MOD) != 0) kdPlan |= KDP_PHYS_MOD;
        if ((kdMask & KD_SYS_MOD) != 0) kdPlan |= KDP_SYS_MOD;
        if ((kdMask & KD_DOUBLE_TAP) != 0) kdPlan |= KDP_DOUBLE_TAP;
        if ((kdMask & KD_MOD_CONTAMINATION) != 0) kdPlan |= KDP_MOD_CONTAM;
        if ((kdMask & KD_INSTANT_SECONDARY) != 0) kdPlan |= KDP_INSTANT_SECONDARY;
        if ((kdMask & KD_COMBO_SECONDARY) != 0) kdPlan |= KDP_COMBO_SECONDARY;
        if ((kdMask & KD_CHORD) != 0) kdPlan |= KDP_CHORD;
        if ((kdMask & KD_INTENTIONAL_CHORD) != 0) kdPlan |= KDP_INTENTIONAL_CHORD;
        if ((kdMask & KD_HELD_MOD) != 0) kdPlan |= KDP_HELD_MOD_RELEVANT;
        if ((kdMask & KD_SAME_MOD) != 0) kdPlan |= KDP_SAME_MOD;
        if (isTaplikeDown) kdPlan |= KDP_TAPLIKE_DOWN;
        if (isPrimaryTaplikeDown) kdPlan |= KDP_PRIMARY_TAPLIKE_DOWN;
        if ((props & KP_CAN_BE_COMBO_PRIMARY) != 0) kdPlan |= KDP_IS_COMBO_PRIMARY;
        if ((props & KP_CAN_BE_INSTANT_COMBO_PRIMARY) != 0) kdPlan |= KDP_IS_INSTANT_PRIMARY;
        if ((kdPlan & (KDP_IS_COMBO_PRIMARY | KDP_IS_INSTANT_PRIMARY)) != 0)
            kdPlan |= KDP_NEEDS_ACTIVE_PRIMARY_SYNC;

        var scanFlags: u16 = 0;
        if ((props & (KP_CAN_BE_COMBO_SECONDARY | KP_CAN_BE_INSTANT_COMBO_SECONDARY)) != 0) scanFlags |= KFS_KD_RELATION_CHECK;
        if ((props & KP_CAN_PARTICIPATE_IN_CHORD) != 0) scanFlags |= KFS_KD_CHORD_CHECK;
        if ((props & (KP_IS_PHYSICAL_MODIFIER | KP_IS_WINDOWS_FACING_MODIFIER)) == 0) scanFlags |= KFS_KD_INTENTIONAL_CHORD;
        if ((props & (KP_CAN_BE_COMBO_SECONDARY | KP_CAN_BE_INSTANT_COMBO_SECONDARY)) != 0) scanFlags |= KFS_KU_RELATION_CHECK;
        if ((props & (KP_HAS_VIRTUAL_MODIFIER_ROLE | KP_IS_PHYSICAL_MODIFIER | KP_IS_WINDOWS_FACING_MODIFIER)) == 0) scanFlags |= KFS_KU_RETRO_MOD_CHECK;
        if ((props & KP_HAS_VIRTUAL_MODIFIER_ROLE) == 0) scanFlags |= KFS_PQ_WAIT_SCAN;
        if ((props & KP_HAS_VIRTUAL_MODIFIER_ROLE) != 0) scanFlags |= KFS_PQ_MODIFIER_RESOLVE;
        if ((props & KP_HAS_VIRTUAL_MODIFIER_ROLE) == 0) scanFlags |= KFS_PQ_PREFIX_SCAN;

        tmpGate[vi] = .{
            .kdPlan = kdPlan,
            .kuMask = kuMask,
            .props = props,
            .kdAction = kdAction,
            .kuAction = kuAction,
            .scanFlags = scanFlags,
        };

        tmpScanFlags[vi] = scanFlags;

        // processQueue plan: precompute which resolution branches can fire for this key.
        var pqPlan: u32 = 0;
        if ((props & KP_HAS_VIRTUAL_MODIFIER_ROLE) != 0) {
            pqPlan |= PQP_HAS_VIRTUAL_MODIFIER_ROLE | PQP_NEEDS_MODIFIER_RESOLVE;
        } else {
            // Non-modifier keys: may wait on older unresolved keys,
            // may receive a long-held modifier prefix on tap emit.
            pqPlan |= PQP_NEEDS_WAIT_SCAN | PQP_CAN_PREFIX_SCAN;
        }
        if ((props & KP_HAS_HOLD_CALLBACK) != 0) pqPlan |= PQP_HAS_HOLD | PQP_NEEDS_HOLD_CLASSIFY;
        if ((props & KP_CAN_BE_COMBO_SECONDARY) != 0) pqPlan |= PQP_CAN_COMBO_SECONDARY;
        if ((props & KP_CAN_BE_INSTANT_COMBO_SECONDARY) != 0) pqPlan |= PQP_CAN_INSTANT_SECONDARY;
        // PQP_FAST_EMIT_TAP / PQP_PLAIN_NO_HOLD: plain non-mod key with no secondary or
        // hold capability — the common typing case — can be emitted directly when the
        // runtime is clean (no unreleased keys, no active mods).
        if ((props & (KP_HAS_VIRTUAL_MODIFIER_ROLE | KP_HAS_HOLD_CALLBACK | KP_CAN_BE_COMBO_SECONDARY | KP_CAN_BE_INSTANT_COMBO_SECONDARY)) == 0)
            pqPlan |= PQP_PLAIN_NO_HOLD | PQP_FAST_EMIT_TAP;
        if ((pqPlan & (PQP_NEEDS_MODIFIER_RESOLVE | PQP_NEEDS_WAIT_SCAN | PQP_NEEDS_HOLD_CLASSIFY)) != 0)
            pqPlan |= PQP_NEEDS_SLOW_RESOLVE;
        tmpQueuePlan[vi] = pqPlan;
    }

    // Exact two-key chord relationships only. Three-key chords that can become
    // a four-key chord use the tiny pending-chord path below; broad prefix
    // marking makes ordinary modifier rolls pay for unrelated larger chords.
    for (g_chordHotTable) |entry| {
        if (entry.key == 0) continue;
        markChordPrefixPairsForEntry(entry, &tmpPairRelationMask);
        if (entry.keyCount != 2) continue;
        if (entry.kind != @intFromEnum(ChordHotKind.internal) and
            entry.kind != @intFromEnum(ChordHotKind.external))
        {
            continue;
        }
        const a: usize = @intCast(entry.key & 0xFFFF);
        const b: usize = @intCast((entry.key >> 16) & 0xFFFF);
        if (a < VK_COUNT and b < VK_COUNT and a != b) {
            tmpPairRelationMask[a][b] |= REL_CHORD2;
            tmpPairRelationMask[b][a] |= REL_CHORD2;
        }
    }
    for (runtime_chords.hotTable) |entry| {
        if (entry.key == 0) continue;
        markChordPrefixPairsForEntry(entry, &tmpPairRelationMask);
        if (entry.keyCount != 2) continue;
        if (entry.kind != @intFromEnum(ChordHotKind.internal) and
            entry.kind != @intFromEnum(ChordHotKind.external))
        {
            continue;
        }
        const a: usize = @intCast(entry.key & 0xFFFF);
        const b: usize = @intCast((entry.key >> 16) & 0xFFFF);
        if (a < VK_COUNT and b < VK_COUNT and a != b) {
            tmpPairRelationMask[a][b] |= REL_CHORD2;
            tmpPairRelationMask[b][a] |= REL_CHORD2;
        }
    }

    // Atomic copy — all tables written from temp to avoid partial state
    @memcpy(g_keyGate[0..], tmpGate[0..]);
    @memcpy(g_pairRelationMask[0..], tmpPairRelationMask[0..]);
    @memcpy(g_comboPrimariesForSecondary[0..], tmpComboPrim[0..]);
    @memcpy(g_instantPrimariesForSecondary[0..], tmpInstantPrim[0..]);
    @memcpy(g_comboPrimaryListForSecondary[0..], tmpComboPrimList[0..]);
    @memcpy(g_instantPrimaryListForSecondary[0..], tmpInstantPrimList[0..]);
    @memcpy(g_comboPrimaryListLenForSecondary[0..], tmpComboPrimListLen[0..]);
    @memcpy(g_instantPrimaryListLenForSecondary[0..], tmpInstantPrimListLen[0..]);
    @memcpy(g_vk_modifier_roles[0..], tmpKeyModType[0..]);
    @memcpy(g_vk_windows_facing_modifiers[0..], tmpKeySysBit[0..]);
    @memcpy(g_vk_is_physical_modifier[0..], tmpKeyPhysBit[0..]);
    @memcpy(g_key_virtual_modifier_mask[0..], tmpKeyModMask[0..]);
    @memcpy(g_virtual_modifier_output_vk[0..], tmpKeyModVK[0..]);
    @memcpy(g_keyModPrefix[0..], tmpKeyModPrefix[0..]);
    @memcpy(g_keyNamePtr[0..], tmpKeyNamePtr[0..]);
    @memcpy(g_keyHoldCallbackId[0..], tmpKeyHoldCallbackId[0..]);
    @memcpy(g_keyDoubleTapCallbackId[0..], tmpKeyDoubleTapCallbackId[0..]);
    @memcpy(g_keyScanFlags[0..], tmpScanFlags[0..]);
    @memcpy(g_keyQueuePlan[0..], tmpQueuePlan[0..]);

    const current_bank = @atomicLoad(u32, &g_activeContextDerivedBank, .acquire);
    const next_bank: u32 = current_bank ^ 1;
    const published = &g_contextDerivedBanks[next_bank];
    @memcpy(published.gate[0..], tmpGate[0..]);
    @memcpy(published.queuePlan[0..], tmpQueuePlan[0..]);
    @memcpy(published.scanFlags[0..], tmpScanFlags[0..]);
    @memcpy(published.pairRelation[0..], tmpPairRelationMask[0..]);
    @memcpy(published.comboPrimaries[0..], tmpComboPrim[0..]);
    @memcpy(published.instantPrimaries[0..], tmpInstantPrim[0..]);
    @memcpy(published.comboPrimaryList[0..], tmpComboPrimList[0..]);
    @memcpy(published.instantPrimaryList[0..], tmpInstantPrimList[0..]);
    @memcpy(published.comboPrimaryListLen[0..], tmpComboPrimListLen[0..]);
    @memcpy(published.instantPrimaryListLen[0..], tmpInstantPrimListLen[0..]);
    @memcpy(published.keyModType[0..], tmpKeyModType[0..]);
    @memcpy(published.holdCallback[0..], tmpKeyHoldCallbackId[0..]);
    @memcpy(published.doubleTapCallback[0..], tmpKeyDoubleTapCallbackId[0..]);
    @atomicStore(u32, &g_activeContextDerivedBank, next_bank, .release);
}

export fn QMK_FinalizeKeyGate() callconv(.c) void {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    requestRuntimePublish(RUNTIME_PUBLISH_KEYGATE);
}

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
inline fn vkIsRegisteredComboPrimary(vk: i32) bool {
    if (vk < 0 or vk >= VK_COUNT) return false;
    return (activeContextDerived().gate[@intCast(vk)].kdPlan & (KDP_IS_COMBO_PRIMARY | KDP_IS_INSTANT_PRIMARY)) != 0;
}
inline fn keyCountsAsActiveComboPrimary(vk: i32, kd: KeyData) bool {
    return !kd.isReleased() and vkIsRegisteredComboPrimary(vk);
}
inline fn kbMarkComboRepeat(vk: i32, kd: *KeyData) void {
    _ = vk;
    kd.sf(FLAG_COMBO_RPT);
}
inline fn kbPut(vk: i32, kd: KeyData) void {
    @setEvalBranchQuota(4000);
    if (vk < 0 or vk >= VK_COUNT) return;
    const ex = g_kbIdx[@intCast(vk)];
    if (ex >= 0) {
        const exi: usize = @intCast(ex);
        g_kbData[exi] = kd;
        activePrimaryBitsSync(vk, kd);
        return;
    }
    if (g_kbLen >= KB_MAX) return;
    const slot = g_kbLen;
    g_kbVK[slot] = vk;
    g_kbData[slot] = kd;
    g_kbIdx[@intCast(vk)] = @intCast(slot);
    g_kbLen += 1;
    activePrimaryBitsSync(vk, kd);
    // FSM-lite: maintain runtime flags
    rfSet(RF_KB_NONEMPTY);
    if (!kd.isReleased()) {
        g_unreleasedKeyCount += 1;
        rfSet(RF_UNREL_KEYS);
        if (!kd.isRuntimeModifier()) {
            g_unreleasedNonModCount += 1;
            rfSet(RF_UNREL_NONMOD_KEYS);
        }
    }
}
inline fn kbRemove(vk: i32) void {
    if (vk < 0 or vk >= VK_COUNT) return;
    const i = g_kbIdx[@intCast(vk)];
    if (i < 0) return;
    const idx: usize = @intCast(i);
    // FSM-lite: maintain unreleased counters before removal
    const removedKd = g_kbData[idx];
    const wasUnreleased = !removedKd.isReleased();
    if (wasUnreleased) {
        g_unreleasedKeyCount -= 1;
        if (!removedKd.isRuntimeModifier()) g_unreleasedNonModCount -= 1;
    }
    g_kbIdx[@intCast(vk)] = -1;
    activePrimaryBitsClear(vk);
    g_kbLen -= 1;
    if (idx != g_kbLen) {
        const mv = g_kbVK[g_kbLen];
        g_kbVK[idx] = mv;
        g_kbData[idx] = g_kbData[g_kbLen];
        g_kbTidHashes[idx] = g_kbTidHashes[g_kbLen]; // keep parallel array in sync
        if (mv >= 0 and mv < VK_COUNT) g_kbIdx[@intCast(mv)] = @intCast(idx);
    }
    // Clear the now-vacated tail slot's tid hashes so stale hashes can't leak.
    @memset(&g_kbTidHashes[g_kbLen], 0);
    // If active mods are live, a removal may have created a stale entry.
    // Flag it so processQueue performs the sweep on the next call.
    if (g_active_virtual_modifier_count > 0) g_modStackDirty = true;
    // FSM-lite: update RF flags after removal
    rfSetIf(RF_KB_NONEMPTY, g_kbLen != 0);
    rfSetIf(RF_UNREL_KEYS, g_unreleasedKeyCount != 0);
    rfSetIf(RF_UNREL_NONMOD_KEYS, g_unreleasedNonModCount != 0);
}
inline fn kbContains(vk: i32) bool {
    if (vk < 0 or vk >= VK_COUNT) return false;
    return g_kbIdx[@intCast(vk)] >= 0;
}
inline fn kbCount() usize {
    return g_kbLen;
}
inline fn pendingSoloActive() bool {
    return g_pendingSoloVK != 0;
}
inline fn pendingSoloClear() void {
    g_pendingSoloVK = 0;
    g_pendingSoloDownTime = 0;
    g_pendingSoloFlags = 0;
    rfClear(RF_PENDING_SOLO);
}
inline fn pendingSoloDeactivate() void {
    g_pendingSoloVK = 0;
    rfClear(RF_PENDING_SOLO);
}
inline fn pendingFlagsWithModType(flags: u16, modType: i8) u16 {
    return if (modType != MOD_NONE)
        flags | PSF_IS_MOD | (@as(u16, @intCast(modType)) << PSF_MODTYPE_SHIFT)
    else
        flags;
}
inline fn pendingFlagsModType(flags: u16) i8 {
    return if ((flags & PSF_IS_MOD) != 0)
        @intCast((flags & PSF_MODTYPE_MASK) >> PSF_MODTYPE_SHIFT)
    else
        MOD_NONE;
}
inline fn pendingSoloStore(vk: i32, downTime: i64, modType: i8, quiet: bool, doubleTap: bool) void {
    g_pendingSoloVK = vk;
    g_pendingSoloDownTime = downTime;
    var flags: u16 = 0;
    flags = pendingFlagsWithModType(flags, modType);
    if (quiet) flags |= PSF_QUIET;
    if (doubleTap) flags |= PSF_DOUBLE_TAP;
    g_pendingSoloFlags = flags;
    rfSet(RF_PENDING_SOLO);
}
inline fn pendingSoloStoreFlags(vk: i32, downTime: i64, flags: u16) void {
    g_pendingSoloVK = vk;
    g_pendingSoloDownTime = downTime;
    g_pendingSoloFlags = flags;
    rfSet(RF_PENDING_SOLO);
}
inline fn pendingSoloMaterialize() void {
    const vk = g_pendingSoloVK;
    if (vk == 0) return;
    const flags = g_pendingSoloFlags;
    var kd = KeyData{};
    kd.downTime = g_pendingSoloDownTime;
    kd.bf(RUNTIME_CURRENT_VK_IS_ACTIVE_MODIFIER, (flags & PSF_IS_MOD) != 0);
    kd.bf(FLAG_QUIET, (flags & PSF_QUIET) != 0);
    kd.bf(FLAG_INTERFERING, (flags & PSF_INTERFERING) != 0);
    pendingSoloDeactivate();
    kbPut(vk, kd);
    ordAppend(vk);
    if ((flags & PSF_IS_MOD) != 0) {
        g_unrelModCount += 1;
        g_cleanUnrelModCount += 1;
        rfSet(RF_UNREL_MODS | RF_CLEAN_UNREL_MODS);
    }
}
inline fn pendingRollActive() bool {
    return g_pendingRollLen != 0;
}
inline fn pendingRollClear() void {
    g_pendingRollLen = 0;
    @memset(&g_pendingRollVKs, 0);
    @memset(&g_pendingRollDownTimes, 0);
    @memset(&g_pendingRollFlags, 0);
    g_pendingRollHeadVK = 0;
    g_pendingRollTailVK = 0;
    g_pendingRollHeadDownTime = 0;
    g_pendingRollTailDownTime = 0;
    g_pendingRollHeadFlags = 0;
    g_pendingRollTailFlags = 0;
    rfClear(RF_PENDING_ROLL);
}
inline fn pendingRollStore(headVK: i32, headDown: i64, headFlags: u16, tailVK: i32, tailDown: i64, tailFlags: u16) void {
    g_pendingRollLen = 2;
    g_pendingRollVKs[0] = headVK;
    g_pendingRollVKs[1] = tailVK;
    g_pendingRollDownTimes[0] = headDown;
    g_pendingRollDownTimes[1] = tailDown;
    g_pendingRollFlags[0] = headFlags | PSF_INTERFERING;
    g_pendingRollFlags[1] = tailFlags | PSF_INTERFERING;
    g_pendingRollHeadVK = headVK;
    g_pendingRollTailVK = tailVK;
    g_pendingRollHeadDownTime = headDown;
    g_pendingRollTailDownTime = tailDown;
    g_pendingRollHeadFlags = headFlags | PSF_INTERFERING;
    g_pendingRollTailFlags = tailFlags | PSF_INTERFERING;
    rfSet(RF_PENDING_ROLL);
}
inline fn pendingRollContains(vk: i32) bool {
    var i: usize = 0;
    while (i < g_pendingRollLen) : (i += 1) {
        if (g_pendingRollVKs[i] == vk) return true;
    }
    return false;
}
inline fn pendingRollCanAppend(vk: i32) bool {
    const rollLen = g_pendingRollLen;
    if (rollLen >= PENDING_ROLL_MAX) return false;
    const vku: usize = @intCast(vk);
    var i: usize = 0;
    while (i < rollLen) : (i += 1) {
        const rollVK = g_pendingRollVKs[i];
        if (rollVK == vk or activeContextDerived().pairRelation[@intCast(rollVK)][vku] != 0) return false;
    }
    return true;
}
inline fn pendingRollAppend(vk: i32, downTime: i64, flags: u16) void {
    if (g_pendingRollLen >= PENDING_ROLL_MAX) return;
    const slot = g_pendingRollLen;
    g_pendingRollVKs[slot] = vk;
    g_pendingRollDownTimes[slot] = downTime;
    g_pendingRollFlags[slot] = flags | PSF_INTERFERING;
    g_pendingRollLen += 1;
    g_pendingRollHeadVK = g_pendingRollVKs[0];
    g_pendingRollHeadDownTime = g_pendingRollDownTimes[0];
    g_pendingRollHeadFlags = g_pendingRollFlags[0];
    rfSet(RF_PENDING_ROLL);
    if (g_pendingRollLen > 1) {
        g_pendingRollTailVK = g_pendingRollVKs[1];
        g_pendingRollTailDownTime = g_pendingRollDownTimes[1];
        g_pendingRollTailFlags = g_pendingRollFlags[1];
    } else {
        g_pendingRollTailVK = 0;
        g_pendingRollTailDownTime = 0;
        g_pendingRollTailFlags = 0;
    }
}
inline fn pendingRollPopHead() void {
    if (g_pendingRollLen == 0) return;
    var i: usize = 1;
    while (i < g_pendingRollLen) : (i += 1) {
        g_pendingRollVKs[i - 1] = g_pendingRollVKs[i];
        g_pendingRollDownTimes[i - 1] = g_pendingRollDownTimes[i];
        g_pendingRollFlags[i - 1] = g_pendingRollFlags[i];
    }
    g_pendingRollLen -= 1;
    g_pendingRollVKs[g_pendingRollLen] = 0;
    g_pendingRollDownTimes[g_pendingRollLen] = 0;
    g_pendingRollFlags[g_pendingRollLen] = 0;
    if (g_pendingRollLen == 0) {
        pendingRollClear();
        return;
    }
    g_pendingRollHeadVK = g_pendingRollVKs[0];
    g_pendingRollHeadDownTime = g_pendingRollDownTimes[0];
    g_pendingRollHeadFlags = g_pendingRollFlags[0];
    if (g_pendingRollLen > 1) {
        g_pendingRollTailVK = g_pendingRollVKs[1];
        g_pendingRollTailDownTime = g_pendingRollDownTimes[1];
        g_pendingRollTailFlags = g_pendingRollFlags[1];
    } else {
        g_pendingRollTailVK = 0;
        g_pendingRollTailDownTime = 0;
        g_pendingRollTailFlags = 0;
    }
}
inline fn pendingRollMaterialize() void {
    const rollLen = g_pendingRollLen;
    const headVK = if (rollLen != 0) g_pendingRollVKs[0] else g_pendingRollHeadVK;
    if (headVK == 0) return;
    var localVKs: [PENDING_ROLL_MAX]i32 = [_]i32{0} ** PENDING_ROLL_MAX;
    var localDowns: [PENDING_ROLL_MAX]i64 = [_]i64{0} ** PENDING_ROLL_MAX;
    var localFlags: [PENDING_ROLL_MAX]u16 = [_]u16{0} ** PENDING_ROLL_MAX;
    var count = rollLen;
    if (count == 0) {
        count = if (g_pendingRollTailVK != 0) 2 else 1;
        localVKs[0] = g_pendingRollHeadVK;
        localDowns[0] = g_pendingRollHeadDownTime;
        localFlags[0] = g_pendingRollHeadFlags;
        if (count > 1) {
            localVKs[1] = g_pendingRollTailVK;
            localDowns[1] = g_pendingRollTailDownTime;
            localFlags[1] = g_pendingRollTailFlags;
        }
    } else {
        var copyI: usize = 0;
        while (copyI < count) : (copyI += 1) {
            localVKs[copyI] = g_pendingRollVKs[copyI];
            localDowns[copyI] = g_pendingRollDownTimes[copyI];
            localFlags[copyI] = g_pendingRollFlags[copyI];
        }
    }
    pendingRollClear();

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const vk = localVKs[i];
        if (vk == 0) continue;
        const flags = localFlags[i];
        var kd = KeyData{};
        kd.downTime = localDowns[i];
        kd.bf(RUNTIME_CURRENT_VK_IS_ACTIVE_MODIFIER, (flags & PSF_IS_MOD) != 0);
        kd.bf(FLAG_QUIET, (flags & PSF_QUIET) != 0);
        kd.bf(FLAG_INTERFERING, (flags & PSF_INTERFERING) != 0);
        kbPut(vk, kd);
        ordAppend(vk);
        if ((flags & PSF_IS_MOD) != 0) {
            g_unrelModCount += 1;
            g_cleanUnrelModCount = 0;
            rfSet(RF_UNREL_MODS);
            rfClear(RF_CLEAN_UNREL_MODS);
        }
    }
}
// E185: Direct tap for pendingRoll head pop without buffer materialization.
// Bypasses kbPut/ordAppend overhead when we just need to trigger tap callback.
inline fn pendingRollTapHeadDirect(suppressHead: bool) void {
    if (g_pendingRollLen == 0) return;
    const headVK = g_pendingRollVKs[0];
    if (headVK == 0) return;

    // Queue direct tap callback for head without buffer materialization
    if (!suppressHead) {
        const headNameRef = &g_keyNames[@intCast(headVK)];
        queueDirectTapCallback(headVK, headNameRef);
    }

    // Pop head from pendingRoll
    pendingRollPopHead();
}
inline fn kbClear() void {
    pendingSoloClear();
    pendingRollClear();
    clearPendingChordRecordOnly();
    for (0..g_kbLen) |i| {
        const v = g_kbVK[i];
        if (v >= 0 and v < VK_COUNT) {
            g_kbIdx[@intCast(v)] = -1;
        }
        @memset(&g_kbTidHashes[i], 0); // clear parallel timer fingerprint array
    }
    g_kbLen = 0;
    g_activeComboPrimaryBits = .{ 0, 0, 0, 0 };
    g_activeInstantPrimaryBits = .{ 0, 0, 0, 0 };
    g_activeAnyPrimaryBits = .{ 0, 0, 0, 0 };
    g_activeComboPrimaryCount = 0;
    // FSM-lite: clear unreleased counters and RF flags
    g_unreleasedKeyCount = 0;
    g_unreleasedNonModCount = 0;
    g_activeInstantPrimaryCount = 0;
    g_activeAnyPrimaryCount = 0;
    rfClear(RF_KB_NONEMPTY | RF_UNREL_KEYS | RF_UNREL_NONMOD_KEYS |
        RF_ACTIVE_COMBO_PRIMARY | RF_ACTIVE_INSTANT_PRIMARY);
}
// --- Key order ring (ordRemoveFirst is O(1), removeFromKeyOrder now O(1) via g_ordIdx) ---
inline fn ordAt(i: usize) i32 {
    return g_keyOrder[(g_ordHead + i) % ORD_MAX];
}
inline fn ordAppend(vk: i32) void {
    if (g_ordLen >= ORD_MAX) return;
    const slot = (g_ordHead + g_ordLen) % ORD_MAX;
    g_keyOrder[slot] = vk;
    g_ordLen += 1;
    if (vk >= 0 and vk < VK_COUNT) g_ordIdx[@intCast(vk)] = @intCast(slot);
    rfSet(RF_ORD_NONEMPTY); // FSM-lite
}
inline fn ordRemoveFirst() void {
    if (g_ordLen == 0) return;
    const vk = g_keyOrder[g_ordHead];
    if (vk >= 0 and vk < VK_COUNT) g_ordIdx[@intCast(vk)] = -1;
    g_ordHead = (g_ordHead + 1) % ORD_MAX;
    g_ordLen -= 1;
    rfSetIf(RF_ORD_NONEMPTY, g_ordLen != 0); // FSM-lite
}
inline fn ordRemoveAt(rel: usize) void {
    if (rel >= g_ordLen) return;
    // Clear the index for the removed entry.
    const removedVK = ordAt(rel);
    if (removedVK >= 0 and removedVK < VK_COUNT) g_ordIdx[@intCast(removedVK)] = -1;
    // Shift entries down and update their indices.
    var j = rel;
    while (j < g_ordLen - 1) : (j += 1) {
        const nv = g_keyOrder[(g_ordHead + j + 1) % ORD_MAX];
        const dst = (g_ordHead + j) % ORD_MAX;
        g_keyOrder[dst] = nv;
        if (nv >= 0 and nv < VK_COUNT) g_ordIdx[@intCast(nv)] = @intCast(dst);
    }
    g_ordLen -= 1;
    rfSetIf(RF_ORD_NONEMPTY, g_ordLen != 0); // FSM-lite
}
inline fn ordClear() void {
    g_ordHead = 0;
    g_ordLen = 0;
    @memset(&g_ordIdx, -1);
    rfClear(RF_ORD_NONEMPTY); // FSM-lite
}
// --- Active timers: O(1) fixed flat keyed set ---
const TOMBSTONE: u64 = 1; // 1 is reserved; real hashes are remapped away from 0/1
inline fn timerNorm(h: u64) u64 {
    // Remap 0 and 1 to avoid colliding with sentinel / tombstone values.
    return if (h < 2) h +% 2 else h;
}
inline fn timerAdd(h: u64) void {
    if (g_timerLen >= ACT_MAX) return;
    const key = timerNorm(h);
    var slot: usize = @intCast(key & TIMER_MASK);
    var probe: usize = 0;
    while (probe < TIMER_SLOTS) : (probe += 1) {
        const v = g_timerSet[slot];
        if (v == 0 or v == TOMBSTONE) { // empty or tombstone — insert here
            g_timerSet[slot] = key;
            g_timerLen += 1;
            g_hotFlags |= HF_TIMERS;
            rfSet(RF_TIMERS); // FSM-lite
            return;
        }
        if (v == key) return; // duplicate — already present
        slot = (slot + 1) & TIMER_MASK;
    }
}
inline fn timerRemove(h: u64) void {
    if (g_timerLen == 0) return;
    const key = timerNorm(h);
    var slot: usize = @intCast(key & TIMER_MASK);
    var probe: usize = 0;
    while (probe < TIMER_SLOTS) : (probe += 1) {
        const v = g_timerSet[slot];
        if (v == 0) return; // empty — key not present
        if (v == key) {
            g_timerSet[slot] = TOMBSTONE;
            g_timerLen -= 1;
            if (g_timerLen == 0) {
                g_hotFlags &= ~HF_TIMERS;
                rfClear(RF_TIMERS); // FSM-lite
            }
            return;
        }
        slot = (slot + 1) & TIMER_MASK;
    }
}
inline fn timerClear() void {
    if (g_timerLen == 0 and g_schedLen == 0) {
        g_hotFlags &= ~HF_TIMERS;
        rfClear(RF_TIMERS); // FSM-lite
        return;
    }
    @memset(&g_timerSet, 0);
    g_timerLen = 0;
    g_hotFlags &= ~HF_TIMERS;
    rfClear(RF_TIMERS); // FSM-lite
    @memset(&g_sched, SchedEntry{});
    g_schedLen = 0;
    if (g_schedEvent) |ev| _ = SetEvent(ev);
}
inline fn timerContains(h: u64) bool {
    if (g_timerLen == 0) return false;
    const key = timerNorm(h);
    var slot: usize = @intCast(key & TIMER_MASK);
    var probe: usize = 0;
    while (probe < TIMER_SLOTS) : (probe += 1) {
        const v = g_timerSet[slot];
        if (v == 0) return false;
        if (v == key) return true;
        slot = (slot + 1) & TIMER_MASK;
    }
    return false;
}
// --- Pending callbacks / timers ---
inline fn pcbAppend(cb: PendingCallback) void {
    if (@atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire) != 0 and cb.callbackId >= 0) {
        const id: usize = @intCast(cb.callbackId);
        if (id >= g_runtimeCallbackSuspendExempt.len or !g_runtimeCallbackSuspendExempt[id]) return;
    }
    acquirePendingCBLock();
    defer releasePendingCBLock();
    if (g_pendingCBsLen >= PCB_MAX) return;
    g_pendingCBs[g_pendingCBsLen] = cb;
    g_pendingCBsLen += 1;
}
inline fn pcbClear() void {
    acquirePendingCBLock();
    defer releasePendingCBLock();
    g_pendingCBsLen = 0;
    g_directTapLen = 0;
}
inline fn directTapAppend(vk: i32) bool {
    if (!g_directTapCaptureActive or g_directTapLen >= PCB_MAX) return false;
    g_directTapVKs[g_directTapLen] = vk;
    g_directTapLen += 1;
    g_hotstringKeyUpHadDirectTap = true;
    return true;
}
inline fn directTapDrain() void {
    const len = g_directTapLen;
    if (len == 0) return;
    g_directTapLen = 0;
    if (len == 1) {
        sendKeyDirect(g_directTapVKs[0], 0);
        return;
    }
    var i: usize = 0;
    while (i < len) : (i += 1) {
        sendKeyDirect(g_directTapVKs[i], 0);
    }
}
inline fn ptmAppend(pt: PendingTimer) void {
    if (g_pendingTimersLen >= PTM_MAX) return;
    g_pendingTimers[g_pendingTimersLen] = pt;
    g_pendingTimersLen += 1;
    g_hotFlags |= HF_PENDING_TIMERS;
    rfSet(RF_PENDING_TIMERS); // FSM-lite
}
inline fn ptmClear() void {
    g_pendingTimersLen = 0;
    g_hotFlags &= ~HF_PENDING_TIMERS;
    rfClear(RF_PENDING_TIMERS); // FSM-lite
}
// --- Ignored keys ---
inline fn ignAdd(vk: i32) void {
    if (vk >= 0 and vk < 256) {
        if (!g_keyVKIgnored[@intCast(vk)]) {
            g_keyVKIgnored[@intCast(vk)] = true;
            g_ignoredKeysLen += 1;
            g_hotFlags |= HF_IGNORED_KEYS;
            rfSet(RF_IGNORED_KEYS); // FSM-lite
        }
    }
}
inline fn ignRemoveVK(vk: i32) void {
    if (vk >= 0 and vk < 256) {
        if (g_keyVKIgnored[@intCast(vk)]) {
            g_keyVKIgnored[@intCast(vk)] = false;
            g_ignoredKeysLen -= 1;
            if (g_ignoredKeysLen == 0) {
                g_hotFlags &= ~HF_IGNORED_KEYS;
                rfClear(RF_IGNORED_KEYS); // FSM-lite
            }
        }
    }
}
inline fn ignClear() void {
    if (g_ignoredKeysLen == 0) return;
    @memset(&g_keyVKIgnored, false);
    g_ignoredKeysLen = 0;
    g_hotFlags &= ~HF_IGNORED_KEYS;
    rfClear(RF_IGNORED_KEYS); // FSM-lite
}
// --- Key-down / key-up time tracking — O(1) VK-indexed ---
inline fn kdtPut(vk: i32, t: i64) void {
    if (vk >= 0 and vk < VK_COUNT) g_kdtTime[@intCast(vk)] = t;
}
inline fn kdtGet(vk: i32) ?i64 {
    if (vk < 0 or vk >= VK_COUNT) return null;
    const t = g_kdtTime[@intCast(vk)];
    if (t == 0) return null;
    return t;
}
inline fn kdtRemove(vk: i32) void {
    if (vk >= 0 and vk < VK_COUNT) g_kdtTime[@intCast(vk)] = 0;
}
inline fn kdtClear() void {
    @memset(&g_kdtTime, 0);
}
inline fn kutPut(vk: i32, t: i64) void {
    if (vk >= 0 and vk < VK_COUNT) {
        const idx: usize = @intCast(vk);
        if (g_kutTime[idx] == 0 and t != 0) {
            g_recentKeyUpCount += 1;
            g_hotFlags |= HF_RECENT_KEYUP;
            rfSet(RF_RECENT_KEYUP); // FSM-lite
        }
        g_kutTime[idx] = t;
    }
}
inline fn kutGet(vk: i32) ?i64 {
    if (vk < 0 or vk >= VK_COUNT) return null;
    const t = g_kutTime[@intCast(vk)];
    return if (t != 0) t else null;
}
inline fn kutRemove(vk: i32) void {
    if (vk >= 0 and vk < VK_COUNT) {
        const idx: usize = @intCast(vk);
        if (g_kutTime[idx] != 0 and g_recentKeyUpCount > 0) {
            g_recentKeyUpCount -= 1;
            if (g_recentKeyUpCount == 0) {
                g_hotFlags &= ~HF_RECENT_KEYUP;
                rfClear(RF_RECENT_KEYUP); // FSM-lite
            }
        }
        g_kutTime[idx] = 0;
    }
}
inline fn kutClear() void {
    @memset(&g_kutTime, 0);
    g_recentKeyUpCount = 0;
    g_hotFlags &= ~HF_RECENT_KEYUP;
    rfClear(RF_RECENT_KEYUP); // FSM-lite
}
// --- Combo primary presence — flat bool, single indexed load ---
inline fn comboPrimaryBitSet(vk: i32) void {
    if (vk >= 0 and vk < VK_COUNT) {
        g_comboPrimaryFlat[@intCast(vk)] = true;
    }
}
inline fn instantComboPrimaryBitSet(vk: i32) void {
    if (vk >= 0 and vk < VK_COUNT) {
        g_instantComboPrimaryFlat[@intCast(vk)] = true;
    }
}
// ============================================================================
// Section 9 — Timer helpers
// ============================================================================
fn initTimer() void {
    if (g_timerInit) return;

    // Calibrate RDTSC
    var qpcFreq: i64 = 0;
    _ = QueryPerformanceFrequency(&qpcFreq);

    var start_qpc: i64 = 0;
    _ = QueryPerformanceCounter(&start_qpc);
    const start_tsc = rdtsc();

    Sleep(50); // 50ms calibration window

    var end_qpc: i64 = 0;
    _ = QueryPerformanceCounter(&end_qpc);
    const end_tsc = rdtsc();

    const qpc_elapsed = end_qpc - start_qpc;
    const tsc_elapsed = end_tsc - start_tsc;

    g_qpcFreq = @as(i64, @intCast((tsc_elapsed * @as(u64, @intCast(qpcFreq))) / @as(u64, @intCast(qpc_elapsed))));

    g_qpcToMs = 1_000.0 / @as(f64, @floatFromInt(g_qpcFreq));
    g_qpcToUs = 1_000_000.0 / @as(f64, @floatFromInt(g_qpcFreq));
    g_qpcToNs = 1_000_000_000.0 / @as(f64, @floatFromInt(g_qpcFreq));

    // Initialize time constants in ticks (ms * qpcFreq / 1000)
    g_QuietPeriodDuration = @divTrunc(200 * g_qpcFreq, 1000);
    g_ModifierGestureWindow = @divTrunc(1000 * g_qpcFreq, 1000);
    g_SingleKeyHoldThreshold = @divTrunc(175 * g_qpcFreq, 1000);
    g_MaxHoldThreshold = @divTrunc(1000 * g_qpcFreq, 1000);
    g_DoubleTapThreshold = @divTrunc(200 * g_qpcFreq, 1000);
    g_RepeatInitialDelayTicks = @divTrunc(@as(i64, g_RepeatInitialDelay) * g_qpcFreq, 1000);
    g_RepeatIntervalTicks = @divTrunc(@as(i64, g_RepeatInterval) * g_qpcFreq, 1000);

    g_timerInit = true;
}

fn getTime() i64 {
    return @as(i64, @bitCast(rdtsc()));
}
inline fn timeFromProfStart(start: i64) i64 {
    return if (start != 0) start else getTime();
}
// ============================================================================
// Section 10 — Key registry
// ============================================================================
// Fast version - delegates to the O(1) flat keyed table.
// Safe: all [KN_LEN]u16 buffers are zero-padded, so kn[KN_LEN-1] == 0 always.
fn getVKFromKN(kn: *const [KN_LEN]u16) i32 {
    return getVKFromName(@as([*:0]const u16, @ptrCast(kn)));
}
// ============================================================================
// Name?VK flat keyed table (replaces the O(n) linear scan in getVKFromName).
// 512-slot open-addressing table; load factor stays < 0.25 for DEFAULT_KEYS.
// Hash: FNV-1a over the first 16 chars as u8 — halved data vs u16 version.
// Written only at registration time (cold path); read on every hot-path call.
// ============================================================================
const NKVK_SLOTS: usize = 512; // power of 2; 512 slots / 256 max VKs = =50% load — fine for open-addressing FNV-1a
const NKVK_MASK: u64 = NKVK_SLOTS - 1;
// Store names as u8 — all key names are ASCII (=127), identical in u8/u16.
// This halves the per-slot storage from 64 bytes to 32 bytes, doubling
// the number of probed entries per cache line.
var g_nkvkName: [NKVK_SLOTS][KN_LEN]u8 = [_][KN_LEN]u8{[_]u8{0} ** KN_LEN} ** NKVK_SLOTS;
var g_nkvkVK: [NKVK_SLOTS]i32 = [_]i32{0} ** NKVK_SLOTS;

inline fn asciiFoldLower8(c: u8) u8 {
    return if (c >= 'A' and c <= 'Z') c + ('a' - 'A') else c;
}

inline fn nameHash(name: [*:0]const u16) u64 {
    // AHK key names are ASCII case-insensitive. Fold to lowercase before
    // hashing so names such as CapsLock, Capslock, and CAPSLOCK share the
    // same registry bucket. This is primarily a setup/parser-time lookup.
    var h: u64 = 14695981039346656037;
    var i: usize = 0;
    while (i < 16 and name[i] != 0) : (i += 1) {
        const c: u8 = @intCast(name[i] & 0xFF);
        h ^= asciiFoldLower8(c);
        h *%= 1099511628211;
    }
    return h;
}

// Compare key names with AHK-compatible ASCII case-insensitive semantics.
inline fn nkvkNameEq(slot: *const [KN_LEN]u8, name: [*:0]const u16) bool {
    var i: usize = 0;
    while (i < KN_LEN) : (i += 1) {
        const sc = slot[i];
        const nc: u8 = if (name[i] == 0) 0 else @intCast(name[i] & 0xFF);
        if (asciiFoldLower8(sc) != asciiFoldLower8(nc)) return false;
        if (sc == 0) return true;
    }
    return true;
}

fn nkvkInsert(vk: i32, name: [*:0]const u16) void {
    var slot: usize = @intCast(nameHash(name) & NKVK_MASK);
    var probe: usize = 0;
    while (probe < NKVK_SLOTS) : (probe += 1) {
        if (g_nkvkName[slot][0] == 0 or nkvkNameEq(&g_nkvkName[slot], name)) {
            // Write as u8 — ASCII =127, low byte is the full value.
            var i: usize = 0;
            while (name[i] != 0 and i < KN_LEN - 1) : (i += 1)
                g_nkvkName[slot][i] = @intCast(name[i] & 0xFF);
            g_nkvkName[slot][i] = 0;
            g_nkvkVK[slot] = vk;
            return;
        }
        slot = (slot + 1) & NKVK_MASK;
    }
    // Table full — should never happen given NKVK_SLOTS >> VK_COUNT
}

fn getVKFromName(name: [*:0]const u16) i32 {
    if (name[0] == 0) return 0;
    var slot: usize = @intCast(nameHash(name) & NKVK_MASK);
    var probe: usize = 0;
    while (probe < NKVK_SLOTS) : (probe += 1) {
        if (g_nkvkName[slot][0] == 0) return 0; // empty slot ? not found
        if (nkvkNameEq(&g_nkvkName[slot], name)) return g_nkvkVK[slot];
        slot = (slot + 1) & NKVK_MASK;
    }
    return 0;
}
fn registerVK(vk: i32, name: [*:0]const u16) void {
    if (vk >= 0 and vk < VK_COUNT) {
        const ex = g_vkToRegIdx[@intCast(vk)];
        if (ex >= 0) {
            copyKeyName(&g_keyNames[@intCast(ex)], name);
            nkvkInsert(vk, name); // keep keyed table in sync on re-registration
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
    nkvkInsert(vk, name); // populate keyed table on first registration
}
fn getNameFromVK(vk: i32) ?*const [KN_LEN]u16 {
    if (vk < 0 or vk >= VK_COUNT) return null;
    const idx = g_vkToRegIdx[@intCast(vk)];
    return if (idx >= 0) &g_keyNames[@intCast(idx)] else null;
}
inline fn ensureNameFromVK(vk: i32, cached: *?*const [KN_LEN]u16) ?*const [KN_LEN]u16 {
    if (cached.*) |name| return name;
    const name = cachedNameFromVK(vk) orelse return null;
    cached.* = name;
    return name;
}
inline fn cachedNameFromVK(vk: i32) ?*const [KN_LEN]u16 {
    if (vk < 0 or vk >= VK_COUNT) return null;
    return g_keyNamePtr[@intCast(vk)];
}
inline fn cachedModType(vk: i32) i8 {
    if (vk < 0 or vk >= VK_COUNT) return MOD_NONE;
    return activeContextDerived().keyModType[@intCast(vk)];
}
fn setModTypeForVK(vk: i32, mt: i8) void {
    if (vk < 0 or vk >= VK_COUNT) return;
    const idx = g_vkToRegIdx[@intCast(vk)];
    if (idx >= 0) g_modTypes[@intCast(idx)] = mt;
    g_modTypeFlat[@intCast(vk)] = mt; // keep flat table in sync
}
fn parseModTypeName(name: [*:0]const u16) i8 {
    if (weqASCIIIgnoreCase(name, "Ctrl")) return MOD_CTRL;
    if (weqASCIIIgnoreCase(name, "Alt")) return MOD_ALT;
    if (weqASCIIIgnoreCase(name, "Shift")) return MOD_SHIFT;
    if (weqASCIIIgnoreCase(name, "Win")) return MOD_WIN;
    return MOD_NONE;
}
fn getVKFromText16(text: []const u16) i32 {
    ensureDefaultKeysRegistered();
    const key_text = stripHotkeyBraces(trimSpaces16(text));
    if (key_text.len == 0) return 0;
    if (equalsAsciiIgnoreCase16(key_text, "SC120")) return 173; // VK_VOLUME_MUTE
    if (equalsAsciiIgnoreCase16(key_text, "SC12E")) return 174; // VK_VOLUME_DOWN
    if (equalsAsciiIgnoreCase16(key_text, "SC130")) return 175; // VK_VOLUME_UP
    if (equalsAsciiIgnoreCase16(key_text, "SC122")) return 179; // VK_MEDIA_PLAY_PAUSE
    var buf: [KN_LEN:0]u16 = [_:0]u16{0} ** KN_LEN;
    const limit = @min(key_text.len, KN_LEN - 1);
    if (limit != 0) @memcpy(buf[0..limit], key_text[0..limit]);
    return getVKFromName(@as([*:0]const u16, @ptrCast(&buf)));
}
fn parseModTypeText16(text: []const u16) i8 {
    if (eqlIgnoreCase16(text, &[_]u16{ 'c', 't', 'r', 'l' })) return MOD_CTRL;
    if (eqlIgnoreCase16(text, &[_]u16{ 'c', 'o', 'n', 't', 'r', 'o', 'l' })) return MOD_CTRL;
    if (eqlIgnoreCase16(text, &[_]u16{ 'a', 'l', 't' })) return MOD_ALT;
    if (eqlIgnoreCase16(text, &[_]u16{ 's', 'h', 'i', 'f', 't' })) return MOD_SHIFT;
    if (eqlIgnoreCase16(text, &[_]u16{ 'w', 'i', 'n' })) return MOD_WIN;
    if (eqlIgnoreCase16(text, &[_]u16{ 'w', 'i', 'n', 'd', 'o', 'w', 's' })) return MOD_WIN;
    return MOD_NONE;
}
// Direct VK ? sysmod bitmask table. Replaces the 8-way weqASCII chain in
// getSysModBit: a single indexed byte load instead of up to 8 string comparisons
// on every keydown/keyup event. Written once at startup (all values are comptime).
// Zero means "not a physical system modifier key".
var g_sysModBitFlat: [VK_COUNT]i32 = blk: {
    var t = [_]i32{0} ** VK_COUNT;
    t[0x11] = 0x01; // Ctrl fallback when a device/mapper reports generic VK_CONTROL
    t[0xA2] = 0x01; // LCtrl
    t[0xA3] = 0x02; // RCtrl
    t[0x10] = 0x04; // Shift fallback when a device/mapper reports generic VK_SHIFT
    t[0xA0] = 0x04; // LShift
    t[0xA1] = 0x08; // RShift
    t[0x12] = 0x10; // Alt fallback when a device/mapper reports generic VK_MENU
    t[0xA4] = 0x10; // LAlt
    t[0xA5] = 0x20; // RAlt
    t[0x5B] = 0x40; // LWin
    t[0x5C] = 0x80; // RWin
    break :blk t;
};

inline fn getSysModBit(vk: i32) i32 {
    if (vk < 0 or vk >= VK_COUNT) return 0;
    return g_sysModBitFlat[@intCast(vk)];
}
inline fn getCollapsedPhysicalModBit(vk: i32) u16 {
    return switch (vk) {
        0x11, 0xA2, 0xA3 => 0x01, // Ctrl, LCtrl, RCtrl
        0x12, 0xA4, 0xA5 => 0x02, // Alt, LAlt, RAlt
        0x10, 0xA0, 0xA1 => 0x04, // Shift, LShift, RShift
        0x5B, 0x5C => 0x08, // LWin, RWin
        else => 0,
    };
}
inline fn runtimeHotkeyDefaultSuppressOriginal(vk: i32, mods_required: u16, physical_mod_vk: u8, requested_suppress: bool) bool {
    // Standalone physical modifiers are observers by default in QMKCore: Ctrl,
    // Shift, Alt, and Win must continue to act as real modifiers for chords
    // such as Ctrl+Backspace, Alt+Tab, and Ctrl+Shift+Esc.
    if (physical_mod_vk == 0 and mods_required == 0 and getCollapsedPhysicalModBit(vk) != 0) {
        return false;
    }
    return requested_suppress;
}
// getSysModBitFromName retained for the one-time registration path (not hot).
fn getSysModBitFromName(name: [*:0]const u16) i32 {
    if (weqASCIIIgnoreCase(name, "LCtrl")) return 0x01;
    if (weqASCIIIgnoreCase(name, "RCtrl")) return 0x02;
    if (weqASCIIIgnoreCase(name, "LShift")) return 0x04;
    if (weqASCIIIgnoreCase(name, "RShift")) return 0x08;
    if (weqASCIIIgnoreCase(name, "LAlt")) return 0x10;
    if (weqASCIIIgnoreCase(name, "RAlt")) return 0x20;
    if (weqASCIIIgnoreCase(name, "LWin")) return 0x40;
    if (weqASCIIIgnoreCase(name, "RWin")) return 0x80;
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
fn parseModifierMaskText16(mods: []const u16) u16 {
    var mask: u16 = 0;
    for (mods) |ch| {
        switch (ch) {
            '^' => mask |= 0x01,
            '!' => mask |= 0x02,
            '+' => mask |= 0x04,
            '#' => mask |= 0x08,
            else => {},
        }
    }
    return mask;
}
fn parseComboModeText16(mode_text: []const u16) u8 {
    const mode = trimSpaces16(mode_text);
    if (mode.len == 0 or equalsAsciiIgnoreCase16(mode, "normal") or equalsAsciiIgnoreCase16(mode, "callback")) return 0;
    if (equalsAsciiIgnoreCase16(mode, "instant")) return 1;
    if (equalsAsciiIgnoreCase16(mode, "internal") or equalsAsciiIgnoreCase16(mode, "sendkeydirect")) return 2;
    if (equalsAsciiIgnoreCase16(mode, "internalinstant") or equalsAsciiIgnoreCase16(mode, "instantinternal") or equalsAsciiIgnoreCase16(mode, "sendkeydirectinstant")) return 3;
    return 255;
}
fn parseChordModeText16(mode_text: []const u16) u8 {
    const mode = trimSpaces16(mode_text);
    if (mode.len == 0 or equalsAsciiIgnoreCase16(mode, "callback") or equalsAsciiIgnoreCase16(mode, "normal")) return 0;
    if (equalsAsciiIgnoreCase16(mode, "internal") or equalsAsciiIgnoreCase16(mode, "remap") or equalsAsciiIgnoreCase16(mode, "sendkeydirect")) return 1;
    return 255;
}
fn makeComboKey(primary: i32, secondary: i32) u64 {
    return (@as(u64, @intCast(primary)) << 32) | @as(u64, @intCast(@as(u32, @bitCast(secondary))));
}
// ============================================================================
// Section 11 — Active modifier helpers
// ============================================================================
fn activeModContains(vk: i32) bool {
    if (vk < 0 or vk >= VK_COUNT) return false;
    return g_activeModPresent[@intCast(vk)]; // O(1) indexed load
}
// Adds one active virtual modifier-role VK and updates derived virtual modifier state.
fn add_active_virtual_modifier(vk: i32) void {
    if (activeModContains(vk) or g_active_virtual_modifier_count >= ACTIVE_MOD_MAX) return;

    g_active_virtual_modifiers_by_vk[@intCast(g_active_virtual_modifier_count)] = vk;
    if (vk >= 0 and vk < VK_COUNT) {
        g_activeModPresent[@intCast(vk)] = true;
        g_activeModIdx[@intCast(vk)] = g_active_virtual_modifier_count;
    }
    g_active_virtual_modifier_count += 1;

    if (vk >= 0 and vk < VK_COUNT)
        g_active_virtual_modifiers |= @intCast(g_key_virtual_modifier_mask[@intCast(vk)]);

    rfSet(RF_ACTIVE_MODS); // FSM-lite
}

// Recomputes active virtual modifier-family state from active modifier-role VKs.
fn rebuild_active_virtual_modifiers() void {
    var mask: u16 = 0;
    var i: usize = 0;
    while (i < @as(usize, @intCast(g_active_virtual_modifier_count))) : (i += 1) {
        const vk = g_active_virtual_modifiers_by_vk[i];
        if (vk >= 0 and vk < VK_COUNT)
            mask |= @as(u16, @intCast(g_key_virtual_modifier_mask[@intCast(vk)]));
    }
    g_active_virtual_modifiers = mask;
    rfSetIf(RF_ACTIVE_MODS, g_active_virtual_modifier_count != 0);
}

// Removes one active virtual modifier-role VK and updates derived state.
fn remove_active_virtual_modifier(vk: i32) void {
    if (vk < 0 or vk >= VK_COUNT) return;
    var idx = g_activeModIdx[@intCast(vk)];
    if (idx < 0 or idx >= g_active_virtual_modifier_count or g_active_virtual_modifiers_by_vk[@intCast(idx)] != vk) {
        idx = -1;
        var scan_i: usize = 0;
        while (scan_i < @as(usize, @intCast(g_active_virtual_modifier_count))) : (scan_i += 1) {
            if (g_active_virtual_modifiers_by_vk[scan_i] == vk) {
                idx = @intCast(scan_i);
                break;
            }
        }
        if (idx < 0) {
            g_activeModPresent[@intCast(vk)] = false;
            g_activeModIdx[@intCast(vk)] = -1;
            rebuild_active_virtual_modifiers();
            return;
        }
    }

    g_active_virtual_modifier_count -= 1;
    if (idx < g_active_virtual_modifier_count) {
        // Move last element to the removed position
        const lastVK = g_active_virtual_modifiers_by_vk[@intCast(g_active_virtual_modifier_count)];
        g_active_virtual_modifiers_by_vk[@intCast(idx)] = lastVK;
        if (lastVK >= 0 and lastVK < VK_COUNT) g_activeModIdx[@intCast(lastVK)] = idx;
    }
    if (vk >= 0 and vk < VK_COUNT) {
        g_activeModPresent[@intCast(vk)] = false;
        g_activeModIdx[@intCast(vk)] = -1;
    }
    rebuild_active_virtual_modifiers();
}
// Clears the active virtual modifier-role collection and derived state.
fn clear_active_virtual_modifiers() void {
    var i: usize = 0;
    while (i < @as(usize, @intCast(g_active_virtual_modifier_count))) : (i += 1) {
        const vk = g_active_virtual_modifiers_by_vk[i];
        if (vk >= 0 and vk < VK_COUNT) {
            g_activeModPresent[@intCast(vk)] = false;
            g_activeModIdx[@intCast(vk)] = -1;
        }
    }
    g_active_virtual_modifier_count = 0;
    g_active_virtual_modifiers = 0;
    rfClear(RF_ACTIVE_MODS); // FSM-lite
}
fn countUnreleasedModifiers() i32 {
    return g_unrelModCount;
}
// Returns the active virtual modifier-family mask.
fn get_active_virtual_modifier_mask() u16 {
    return g_active_virtual_modifiers;
}

fn rebuildUnreleasedModifierCounters() void {
    var unrel: i32 = 0;
    var clean: i32 = 0;
    for (0..g_kbLen) |i| {
        const kd = g_kbData[i];
        if (!kd.isRuntimeModifier() or kd.isReleased() or kd.chordPending()) continue;
        unrel += 1;
        if (!kd.hasInterferingKeys()) clean += 1;
    }
    g_unrelModCount = unrel;
    g_cleanUnrelModCount = clean;
    rfSetIf(RF_UNREL_MODS, g_unrelModCount != 0);
    rfSetIf(RF_CLEAN_UNREL_MODS, g_cleanUnrelModCount != 0);
}

fn schedInsert(entry: SchedEntry) void {
    var i: usize = 0;
    while (i < SCHED_MAX) : (i += 1) {
        if (g_sched[i].tidHash == entry.tidHash) {
            g_sched[i] = entry;
            if (g_schedEvent) |ev| _ = SetEvent(ev);
            return;
        }
    }
    i = 0;
    while (i < SCHED_MAX) : (i += 1) {
        if (g_sched[i].tidHash == 0) {
            g_sched[i] = entry;
            g_schedLen += 1;
            break;
        }
    }
    if (g_schedEvent) |ev| _ = SetEvent(ev);
}

fn schedRemove(hash: u64) void {
    if (g_schedLen == 0) return;
    var removed = false;
    var i: usize = 0;
    while (i < SCHED_MAX) : (i += 1) {
        if (g_sched[i].tidHash == hash) {
            g_sched[i] = .{};
            if (g_schedLen > 0) g_schedLen -= 1;
            removed = true;
        }
    }
    if (removed) {
        if (g_schedEvent) |ev| _ = SetEvent(ev);
    }
}

fn schedEarliest() ?SchedEntry {
    var best: ?SchedEntry = null;
    var i: usize = 0;
    while (i < SCHED_MAX) : (i += 1) {
        if (g_sched[i].tidHash != 0) {
            if (best == null or g_sched[i].deadline < best.?.deadline) best = g_sched[i];
        }
    }
    return best;
}

fn schedEntryStillCurrent(hash: u64, deadline: i64) bool {
    var i: usize = 0;
    while (i < SCHED_MAX) : (i += 1) {
        if (g_sched[i].tidHash == hash and g_sched[i].deadline == deadline) return true;
    }
    return false;
}

fn schedFire(e: SchedEntry) void {
    const hash = e.tidHash;
    var pk = e.primaryKey;
    var sk = e.secondaryKey;
    const tt = e.timerType;
    const ct = e.captureTime;

    if (!timerContains(hash) or !schedEntryStillCurrent(hash, e.deadline)) return;
    cancelTimer(hash);
    clearKeyTimerHash(getVKFromKN(&pk), hash);
    clearKeyTimerHash(getVKFromKN(&sk), hash);

    switch (tt) {
        0 => triggerComboWithQuietCheck(&pk, &sk, ct),
        1 => sameModifierGestureWindowTimer(&pk, &sk),
        2 => retroTriggerCombo(&pk, &sk),
        3 => retroActivateModifier(&pk, &sk),
        else => {},
    }

    acquirePendingCBLock();
    const cbLen = g_pendingCBsLen;
    if (cbLen > 0) {
        var slowIdx: usize = 0;
        var j: usize = 0;
        while (j < cbLen) : (j += 1) {
            const cb = g_pendingCBs[j];
            if (cb.type_ == 4 and cb.modifierMask == 0 and cb.vk != 0) {
                sendKeyDirect(cb.vk, 0);
            } else {
                if (slowIdx != j) g_pendingCBs[slowIdx] = cb;
                slowIdx += 1;
            }
        }
        g_pendingCBsLen = slowIdx;
    }

    releasePendingCBLock();

    if (g_pendingCBsLen > 0) notifyAHK(true, false);
}

fn schedThreadProc(_: ?*anyopaque) callconv(.winapi) u32 {
    // _ = SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);
    _ = SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);

    while (@atomicLoad(i32, &g_schedActive, .acquire) != 0) {
        const entry = schedEarliest();

        if (entry == null) {
            if (g_schedEvent) |ev| {
                _ = WaitForSingleObject(ev, INFINITE);
                _ = ResetEvent(ev);
            }
            continue;
        }

        const now = getTime();
        const delta = entry.?.deadline - now;

        if (delta <= 0) {
            schedFire(entry.?);
            continue;
        }

        const delta_ns = @divTrunc(delta * 1_000_000_000, g_qpcFreq);
        if (delta_ns > 3_000_000) {
            const sleep_ns = delta_ns - 3_000_000;
            if (g_schedTimer) |ht| {
                const due_100ns: i64 = -@divTrunc(sleep_ns, 100);
                _ = SetWaitableTimer(ht, &due_100ns, 0, null, null, FALSE);
                if (g_schedEvent) |ev| {
                    const handles = [_]HANDLE{ ht, ev };
                    _ = WaitForMultipleObjects(2, &handles, FALSE, INFINITE);
                    _ = ResetEvent(ev);
                } else {
                    _ = WaitForSingleObject(ht, INFINITE);
                }
                _ = CancelWaitableTimer(ht);
            } else {
                const sleep_ms: u32 = @intCast(@divTrunc(sleep_ns, 1_000_000));
                if (g_schedEvent) |ev| {
                    _ = WaitForSingleObject(ev, sleep_ms);
                    _ = ResetEvent(ev);
                } else {
                    Sleep(sleep_ms);
                }
            }
        } else if (delta_ns > 50_000) {
            asm volatile ("pause" ::: .{});
        } else {
            var spin_now = getTime();
            while (spin_now < entry.?.deadline) {
                asm volatile ("pause" ::: .{});
                spin_now = getTime();
            }
            schedFire(entry.?);
        }
    }
    return 0;
}

fn initSchedThread() void {
    if (g_schedThread) |th| {
        const wait_result = WaitForSingleObject(th, 0);
        if (wait_result == WAIT_OBJECT_0) {
            _ = CloseHandle(th);
            g_schedThread = null;
            @memset(&g_sched, SchedEntry{});
            g_schedLen = 0;
        } else {
            return;
        }
    }
    if (g_schedEvent == null) g_schedEvent = CreateEventW(null, TRUE, FALSE, null);
    if (g_schedTimer == null) {
        g_schedTimer = CreateWaitableTimerExW(null, null, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
        if (g_schedTimer == null) {
            g_schedTimer = CreateWaitableTimerExW(null, null, 0, TIMER_ALL_ACCESS);
        }
    }
    if (@atomicRmw(i32, &g_schedActive, .Xchg, 1, .acq_rel) == 0) {
        g_schedThread = CreateThread(null, 0, schedThreadProc, null, 0, null);
        if (g_schedThread == null) @atomicStore(i32, &g_schedActive, 0, .release);
    }
}
// ============================================================================
// Section 12 — Timer management
// ============================================================================
fn cancelTimer(hash: u64) void {
    timerRemove(hash);
    schedRemove(hash);
}
fn cancelTimerZ(id: [*:0]const u16) void {
    cancelTimer(timerHashZ(id));
}
fn clearKeyTimerHash(vk: i32, hash: u64) void {
    const idx = kbFind(vk) orelse return;
    const kd = &g_kbData[idx];
    var write: u8 = 0;
    var read: u8 = 0;
    while (read < kd.tidCount) : (read += 1) {
        const h = g_kbTidHashes[idx][@intCast(read)];
        if (h == hash) continue;
        g_kbTidHashes[idx][@intCast(write)] = h;
        write += 1;
    }
    kd.tidCount = write;
    if (kd.sameModTidHash == hash) kd.sameModTidHash = 0;
}
fn cancelKeyTimers(vk: i32) void {
    const idx = kbFind(vk) orelse return;
    const kd = &g_kbData[idx];
    for (g_kbTidHashes[idx][0..kd.tidCount]) |h| {
        timerRemove(h);
        schedRemove(h);
    }
    kd.tidCount = 0;
    if (kd.sameModTidHash != 0) {
        cancelTimer(kd.sameModTidHash);
        kd.sameModTidHash = 0;
    }
}
fn removeFromKeyOrder(vk: i32) void {
    // O(1): g_ordIdx[vk] is the absolute ring slot.
    if (vk < 0 or vk >= VK_COUNT) return;
    const absSlot = g_ordIdx[@intCast(vk)];
    if (absSlot < 0) return;
    const abs: usize = @intCast(absSlot);
    const rel = if (abs >= g_ordHead) abs - g_ordHead else abs + ORD_MAX - g_ordHead;
    ordRemoveAt(rel);
}
fn queueCallback(callbackId: i32, key1: *const [KN_LEN]u16, key2: [*:0]const u16, type_: i32) void {
    // Hold/tap/combo resolution reaches this function with the runtime's
    // semantic decision already made.  Use the same callback transport as
    // queueRuntimeCallback: a compiled Zig callback executes in Zig, while a
    // compiled AHK callback remains a pending IPC record.  This preserves the
    // type/key metadata needed by the AHK bridge without creating a second
    // decision path for compiled rows.
    if (invokeCompiledZigCallback(callbackId)) return;
    var cb = PendingCallback{ .callbackId = callbackId, .type_ = type_, .vk = 0, .modifierMask = 0 };
    @memcpy(cb.key1[0..KN_LEN], key1);
    wcpyS(&cb.key2, 8, key2);
    // O(1) flat keyed lookup replaces the old O(keyCount) linear scan.
    cb.vk = getVKFromName(@as([*:0]const u16, @ptrCast(key1)));
    cb.modifierMask = parseModifierMask(@ptrCast(&cb.key2));
    // type_ == 0 is a hold callback.  If the key was contaminated (another key
    // was pressed while it was buffered undecided) it was not a deliberate solo
    // hold — silently drop it here regardless of which code path called us.
    if (type_ == 0) {
        // Final O(1) guard: a hold callback can never escape after another
        // genuine physical key-down occurred later in this press lifetime.
        if (holdHadLaterPhysicalKeyDown(cb.vk)) return;
        if (kbGet(cb.vk)) |kd| {
            if (kd.isContaminated()) return;
        }
    }
    pcbAppend(cb);
}
inline fn queueDirectTapCallback(vk: i32, key1: *const [KN_LEN]u16) void {
    if (directTapAppend(vk)) return;
    var cb = PendingCallback{ .callbackId = -4, .type_ = 4, .vk = vk, .modifierMask = 0 };
    @memcpy(cb.key1[0..KN_LEN], key1);
    pcbAppend(cb);
}
fn queueCallbackEmpty(callbackId: i32, type_: i32) void {
    const empty: [KN_LEN]u16 = [_]u16{0} ** KN_LEN;
    const emptyZ: [1]u16 = [_]u16{0};
    queueCallback(callbackId, &empty, @ptrCast(&emptyZ), type_);
}

// ============================================================================
// Native paste payloads
//
// A pure-string hotstring carries its replacement text inside the DLL instead
// of round-tripping through an AHK callback that would only DllCall straight
// back into QMK_Paste. The AHK entry builder packs every payload into one
// null-terminated UTF-16 buffer and encodes the payload's offset in the
// record's callbackId field as NATIVE_PAYLOAD_ID_BASE - offset.
//
// The base sits far below every negative callbackId meaning that already
// exists (the IPC control codes in ipc_types.zig, the static shortcut and
// hotstring table indices decoded by pendingCallbackToIpcIndex, and the -4
// direct-tap sentinel), so the ranges cannot overlap.
// ============================================================================
const NATIVE_PAYLOAD_ID_BASE: i32 = -0x4000_0000;
const NATIVE_PAYLOAD_APPEND_FAILED: usize = std.math.maxInt(usize);

var g_nativeHotstringPayloads: []u16 = &[_]u16{};
var g_nativeHotkeyPayloads: []u16 = &[_]u16{};
var g_nativeHotstringPayloadsPublishedLen: usize = 0;

inline fn nativeHotstringPayloadOffset(callbackId: i32) ?[*:0]const u16 {
    if (callbackId > NATIVE_PAYLOAD_ID_BASE) return null;
    const off = @as(i64, NATIVE_PAYLOAD_ID_BASE) - @as(i64, callbackId);
    if (off < 0 or off >= @as(i64, @intCast(g_nativeHotstringPayloads.len))) return null;
    const rest = g_nativeHotstringPayloads[@intCast(off)..];
    return @ptrCast(rest.ptr);
}

inline fn nativeHotkeyPayloadOffset(callbackId: i32) ?[*:0]const u16 {
    if (callbackId > NATIVE_PAYLOAD_ID_BASE) return null;
    const off = @as(i64, NATIVE_PAYLOAD_ID_BASE) - @as(i64, callbackId);
    if (off < 0 or off >= @as(i64, @intCast(g_nativeHotkeyPayloads.len))) return null;
    const rest = g_nativeHotkeyPayloads[@intCast(off)..];
    return @ptrCast(rest.ptr);
}

fn appendNativePayloadBuffer(storage: *[]u16, chars: [*]const u16, charsLen: u32) usize {
    // Payload IDs are permanent registration data, so later setup calls must
    // append instead of replacing the backing buffer. Every payload needs its
    // own NUL because native dispatch reads the payload through a zero-terminated
    // pointer. Keep one additional trailing guard NUL and return the base offset
    // for this call.
    // Do not immediately free the previous buffer here: the async native paste
    // worker may already have resolved a pointer into it.
    const old_content_len: usize = if (storage.*.len == 0) 0 else storage.*.len - 1;
    if (charsLen == 0) return old_content_len;
    const chars_len: usize = @as(usize, @intCast(charsLen));
    const payload_len: usize = chars_len + 1;
    const new_len = old_content_len + payload_len + 1;
    const buf = gAlloc.alloc(u16, new_len) catch return NATIVE_PAYLOAD_APPEND_FAILED;
    const old_storage = storage.*;
    if (old_content_len != 0) @memcpy(buf[0..old_content_len], storage.*[0..old_content_len]);
    @memcpy(buf[old_content_len .. old_content_len + chars_len], chars[0..chars_len]);
    buf[old_content_len + chars_len] = 0;
    buf[old_content_len + payload_len] = 0;
    storage.* = buf;
    retireSlice(u16, old_storage);
    return old_content_len;
}

inline fn appendNativeHotstringPayloads(chars: [*]const u16, charsLen: u32) usize {
    return appendNativePayloadBuffer(&g_nativeHotstringPayloads, chars, charsLen);
}

inline fn appendNativeHotkeyPayloads(chars: [*]const u16, charsLen: u32) usize {
    return appendNativePayloadBuffer(&g_nativeHotkeyPayloads, chars, charsLen);
}

inline fn rebaseNativePayloadId(callback_id: i32, payload_base: usize) i32 {
    if (callback_id > NATIVE_PAYLOAD_ID_BASE) return callback_id;
    const local_off = @as(i64, NATIVE_PAYLOAD_ID_BASE) - @as(i64, callback_id);
    if (local_off < 0) return callback_id;
    const global_off = @as(i64, @intCast(payload_base)) + local_off;
    if (global_off > std.math.maxInt(i32)) return callback_id;
    return NATIVE_PAYLOAD_ID_BASE - @as(i32, @intCast(global_off));
}

// Paste requests run on their own thread. QMK_Paste opens the clipboard and
// copies every existing format before injecting Ctrl+V, which is far too much
// work to do on the key-event thread.
const NATIVE_PASTE_Q_MAX: u32 = 16;
const NATIVE_PASTE_Q_MASK: u32 = NATIVE_PASTE_Q_MAX - 1;
const NativePasteRequest = extern struct {
    kind: u8,
    _pad: [3]u8 = .{ 0, 0, 0 },
    callbackId: i32,
};
var g_nativePasteQ: [NATIVE_PASTE_Q_MAX]NativePasteRequest = [_]NativePasteRequest{.{ .kind = 0, .callbackId = 0 }} ** NATIVE_PASTE_Q_MAX;
var g_nativePasteHead: u32 = 0;
var g_nativePasteTail: u32 = 0;
var g_nativePasteEvent: ?HANDLE = null;
var g_nativePasteThread: ?HANDLE = null;
var g_nativePasteActive: i32 = 0;
var g_nativePasteInFlight: i32 = 0;
var g_nativePasteFired: u32 = 0;
var g_nativePasteDropped: u32 = 0;
var g_nativePasteFailed: u32 = 0;
var g_testDirectKeySendCount: u32 = 0;
var g_testLastDirectKeyVK: i32 = 0;
var g_testLastDirectModifierMask: u16 = 0;

fn nativePasteThreadProc(_: ?*anyopaque) callconv(.winapi) u32 {
    _ = SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);

    while (@atomicLoad(i32, &g_nativePasteActive, .acquire) != 0) {
        const head = @atomicLoad(u32, &g_nativePasteHead, .acquire);
        const tail = g_nativePasteTail;

        if (head == tail) {
            if (g_nativePasteEvent) |ev| {
                _ = WaitForSingleObject(ev, INFINITE);
                _ = ResetEvent(ev);
            } else {
                Sleep(1);
            }
            continue;
        }

        const request = g_nativePasteQ[tail & NATIVE_PASTE_Q_MASK];
        @atomicStore(u32, &g_nativePasteTail, tail + 1, .release);
        @atomicStore(i32, &g_nativePasteInFlight, 1, .release);

        const text: ?[*:0]const u16 = switch (request.kind) {
            7 => nativeHotstringPayloadOffset(request.callbackId),
            9 => nativeHotkeyPayloadOffset(request.callbackId),
            else => null,
        };
        if (text == null) {
            @atomicStore(i32, &g_nativePasteInFlight, 0, .release);
            _ = @atomicRmw(u32, &g_nativePasteFailed, .Add, 1, .monotonic);
            continue;
        }
        // Replay/test mode suppresses every output route, including the
        // native-payload worker.  The ring sender already observes this flag,
        // but calling QMK_Paste here would bypass it and could inject text
        // during an otherwise non-interactive Zig verification run.
        if (g_suppressOutputForReplay) {
            @atomicStore(i32, &g_nativePasteInFlight, 0, .release);
            reclaimRetiredAllocationsIfSafe();
            continue;
        }
        if (QMK_Paste(text.?) == 0) {
            _ = @atomicRmw(u32, &g_nativePasteFailed, .Add, 1, .monotonic);
        }
        @atomicStore(i32, &g_nativePasteInFlight, 0, .release);
        reclaimRetiredAllocationsIfSafe();
    }
    return 0;
}

fn initNativePasteThread() void {
    if (g_nativePasteEvent == null) g_nativePasteEvent = CreateEventW(null, TRUE, FALSE, null);
    if (g_nativePasteThread) |th| {
        const wait_result = WaitForSingleObject(th, 0);
        if (wait_result == WAIT_OBJECT_0) {
            _ = CloseHandle(th);
            g_nativePasteThread = null;
            if (g_nativePasteEvent) |ev| {
                _ = CloseHandle(ev);
                g_nativePasteEvent = null;
            }
            @atomicStore(u32, &g_nativePasteHead, 0, .release);
            @atomicStore(u32, &g_nativePasteTail, 0, .release);
            @atomicStore(i32, &g_nativePasteInFlight, 0, .release);
        } else {
            return;
        }
    }
    if (@atomicRmw(i32, &g_nativePasteActive, .Xchg, 1, .acq_rel) == 0) {
        g_nativePasteThread = CreateThread(null, 0, nativePasteThreadProc, null, 0, null);
        if (g_nativePasteThread == null) @atomicStore(i32, &g_nativePasteActive, 0, .release);
    }
}

fn stopNativePasteThread() bool {
    @atomicStore(i32, &g_nativePasteActive, 0, .release);
    if (g_nativePasteEvent) |ev| _ = SetEvent(ev);
    if (g_nativePasteThread) |th| {
        const wait_result = WaitForSingleObject(th, 2000);
        if (wait_result != WAIT_OBJECT_0) return false;
        _ = CloseHandle(th);
        g_nativePasteThread = null;
    }
    if (g_nativePasteEvent) |ev| {
        _ = CloseHandle(ev);
        g_nativePasteEvent = null;
    }
    @atomicStore(u32, &g_nativePasteHead, 0, .release);
    @atomicStore(u32, &g_nativePasteTail, 0, .release);
    @atomicStore(i32, &g_nativePasteInFlight, 0, .release);
    reclaimRetiredAllocationsIfSafe();
    return true;
}

/// Bounded, non-blocking hand-off from the key-event thread to the worker.
/// Store payload identity, not a raw pointer: setup can append/realloc payload
/// buffers before the worker wakes up.
inline fn enqueueNativePaste(kind: u8, callbackId: i32) void {
    const head = g_nativePasteHead;
    const tail = @atomicLoad(u32, &g_nativePasteTail, .acquire);
    if (head - tail >= NATIVE_PASTE_Q_MAX) {
        _ = @atomicRmw(u32, &g_nativePasteDropped, .Add, 1, .monotonic);
        return;
    }
    g_nativePasteQ[head & NATIVE_PASTE_Q_MASK] = .{ .kind = kind, .callbackId = callbackId };
    @atomicStore(u32, &g_nativePasteHead, head + 1, .release);
    _ = @atomicRmw(u32, &g_nativePasteFired, .Add, 1, .monotonic);
    if (g_nativePasteEvent) |ev| _ = SetEvent(ev);
}

fn invokeCompiledZigCallback(callbackId: i32) bool {
    if (callbackId > COMPILED_ZIG_CALLBACK_ID_BASE or
        callbackId <= COMPILED_ZIG_CALLBACK_ID_BASE - @as(i32, @intCast(COMPILED_CALLBACK_SLOT_MAX))) return false;
    if (comptime has_compiled_user_shortcuts_build and @hasDecl(compiled_user_shortcuts, "Compiled_Callbacks")) {
        const slot: u32 = @intCast(COMPILED_ZIG_CALLBACK_ID_BASE - callbackId);
        inline for (compiled_user_shortcuts.Compiled_Callbacks.zig) |descriptor| {
            if (descriptor.slot == slot) {
                if (descriptor.zig_fn) |callback| {
                    callback();
                    return true;
                }
            }
        }
    }
    return false;
}

// Test-only entry points exercise the same direct dispatch routine used by
// queued runtime callbacks. They are intentionally observational and are not
// part of the production callback ABI.
export fn QMK_TestInvokeCompiledZigCallback(slot: i32) callconv(.c) i32 {
    if (slot < 0 or slot >= @as(i32, @intCast(COMPILED_CALLBACK_SLOT_MAX))) return 0;
    return if (invokeCompiledZigCallback(COMPILED_ZIG_CALLBACK_ID_BASE - slot)) 1 else 0;
}

export fn QMK_TestGetCompiledZigSentinel() callconv(.c) u32 {
    if (comptime has_compiled_user_shortcuts_build and @hasDecl(compiled_user_shortcuts, "Compiled_Callbacks") and
        @hasDecl(compiled_user_shortcuts.Compiled_Callbacks, "zig_sentinel"))
        return compiled_user_shortcuts.Compiled_Callbacks.zig_sentinel;
    return 0;
}

fn queueRuntimeCallback(callbackId: i32, type_: i32) void {
    if (invokeCompiledZigCallback(callbackId)) return;
    if (@atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire) != 0 and callbackId >= 0) {
        const id: usize = @intCast(callbackId);
        if (id >= g_runtimeCallbackSuspendExempt.len or !g_runtimeCallbackSuspendExempt[id]) return;
    }
    // A pure-string hotstring/hotkey stays in Zig, so AHK is never notified.
    // Hotkey payloads first get AHK Send-style direct-key parsing; only text
    // that is not a direct key spec falls through to the paste worker.
    if (type_ == 7) {
        if (nativeHotstringPayloadOffset(callbackId)) |ptr| {
            _ = ptr;
            enqueueNativePaste(7, callbackId);
            return;
        }
        if (callbackId <= NATIVE_PAYLOAD_ID_BASE) {
            _ = @atomicRmw(u32, &g_nativePasteFailed, .Add, 1, .monotonic);
            return;
        }
    } else if (type_ == 9) {
        if (nativeHotkeyPayloadOffset(callbackId)) |ptr| {
            if (parseSendDirectSpecText16(wideZSpan(ptr))) |parsed| {
                sendDirectSpec(parsed);
            } else {
                enqueueNativePaste(9, callbackId);
            }
            return;
        }
        if (callbackId <= NATIVE_PAYLOAD_ID_BASE) {
            _ = @atomicRmw(u32, &g_nativePasteFailed, .Add, 1, .monotonic);
            return;
        }
    }
    if (g_pendingCBsLen >= PCB_MAX) return;
    var cb = PendingCallback{ .callbackId = callbackId, .type_ = type_, .vk = 0, .modifierMask = 0 };
    @memset(&cb.key1, 0);
    @memset(&cb.key2, 0);
    pcbAppend(cb);
}

inline fn wakeIpcHead(addr: *const anyopaque) void {
    if (g_wakeByAddressSingle == null) {
        const kernel32_name: [*:0]const u8 = "kernel32.dll";
        const kernelbase_name: [*:0]const u8 = "KernelBase.dll";
        const proc_name: [*:0]const u8 = "WakeByAddressSingle";
        if (GetModuleHandleA(kernel32_name)) |mod| {
            if (GetProcAddress(mod, proc_name)) |proc| {
                g_wakeByAddressSingle = @ptrCast(proc);
            }
        }
        if (g_wakeByAddressSingle == null) {
            if (GetModuleHandleA(kernelbase_name)) |mod| {
                if (GetProcAddress(mod, proc_name)) |proc| {
                    g_wakeByAddressSingle = @ptrCast(proc);
                }
            }
        }
    }
    if (g_wakeByAddressSingle) |wake| wake(addr);
}

inline fn pushIpcEvent(callback_idx: i64, scan_code: u16, flags: u16, state_mask: u32) bool {
    const ring = g_ipcRing orelse return false;
    const head = ring.head;
    const tail = @atomicLoad(u64, &ring.tail, .acquire);
    if (head - tail >= ipc.RING_CAPACITY) return false;

    ring.slots[head & ipc.RING_MASK] = .{
        .scan_code = scan_code,
        .flags = flags,
        .state_mask = state_mask,
        .timestamp = 0,
        .callback_idx = callback_idx,
    };
    @atomicStore(u64, &ring.head, head + 1, .release);
    wakeIpcHead(@ptrCast(&ring.head));
    return true;
}

fn pushIpcControl(callback_idx: i64) bool {
    var attempts: u32 = 0;
    while (attempts < 16) : (attempts += 1) {
        if (pushIpcEvent(callback_idx, 0, 0, 0)) return true;
        _ = Sleep(1);
    }
    g_ipcControlDropCount +%= 1;
    return false;
}

fn pendingCallbackToIpcIndex(cb: PendingCallback) i64 {
    // Runtime callbacks use the ordinary positive callback table.  Compiled
    // AHK callbacks use the reserved negative compiled-ID range and must be
    // forwarded unchanged so QMKInterception.ahk can resolve them in
    // QMKCompiledCallbackMap.
    return switch (cb.type_) {
        0, 1, 2, 5, 6 => if (isCompiledZigCallbackId(cb.callbackId))
            // Holds, taps, modifiers, and chord callbacks use the legacy
            // type-specific conversion below for ordinary runtime IDs.  A
            // generated AHK callback is different: preserve its reserved
            // compiled ID so the AHK callback map can receive it.
            cb.callbackId
        else
            shortcutCallbackIndex(cb.type_, cb.callbackId),
        7 => if (isCompiledZigCallbackId(cb.callbackId))
            // Generated AHK callbacks already carry the reserved compiled
            // ID. Preserve it for QMKInterception.ahk; treating it as the
            // legacy negative hotstring-table index would turn it into
            // IPC_NOOP and the callback would never cross the bridge.
            cb.callbackId
        else if (cb.callbackId < 0)
            hotstringCallbackIndex(@intCast(-cb.callbackId - 1))
        else
            cb.callbackId,
        8 => if (cb.callbackId >= 0)
            hotkeyCallbackIndex(@intCast(cb.callbackId))
        else if (isCompiledZigCallbackId(cb.callbackId))
            cb.callbackId
        else
            ipc.IPC_NOOP,
        9 => cb.callbackId,
        99 => ipc.IPC_EMERGENCY_RESET,
        else => ipc.IPC_NOOP,
    };
}

fn flushPendingCallbacksToIpc() void {
    acquirePendingCBLock();
    defer releasePendingCBLock();
    const cbLen = g_pendingCBsLen;
    if (cbLen == 0) return;
    var i: usize = 0;
    var slow: usize = 0;
    while (i < cbLen) : (i += 1) {
        const idx = pendingCallbackToIpcIndex(g_pendingCBs[i]);
        if (idx == ipc.IPC_NOOP) continue;
        if (!pushIpcEvent(idx, 0, 0, 0)) {
            g_pendingCBs[slow] = g_pendingCBs[i];
            slow += 1;
        }
    }
    g_pendingCBsLen = slow;
}

fn queueTimer(tidBuf: *const [TID_LEN]u16, tidHash: u64, delay: i32, timerType: i32, pk: *const [KN_LEN]u16, sk: *const [KN_LEN]u16, captureTime: i64) void {
    const pkVK = getVKFromKN(pk);
    const skVK = getVKFromKN(sk);
    cancelTimer(tidHash);
    if (pkVK != 0) clearKeyTimerHash(pkVK, tidHash);
    if (skVK != 0 and skVK != pkVK) clearKeyTimerHash(skVK, tidHash);

    timerAdd(tidHash);
    if (pkVK != 0) {
        if (kbGet(pkVK)) |kd| kd.addTidHash(tidHash);
    }
    if (skVK != 0 and skVK != pkVK) {
        if (kbGet(skVK)) |kd| kd.addTidHash(tidHash);
    }

    var now: i64 = 0;
    now = @as(i64, @bitCast(rdtsc()));
    const delay_ticks = @divTrunc(@as(i64, delay) * g_qpcFreq, 1000);
    var entry = SchedEntry{
        .tidHash = tidHash,
        .deadline = now + delay_ticks,
        .timerType = timerType,
        .captureTime = captureTime,
    };
    @memcpy(&entry.primaryKey, pk);
    @memcpy(&entry.secondaryKey, sk);

    _ = tidBuf;
    schedInsert(entry);
}
// ============================================================================
// Section 13 — Scan-code cache & SendInput ring
// Packed scan-code helpers.
// g_scPacked[vk]: bit 15 = E0, bits [7:0] = scan code. Zero = not cached.
inline fn scPackedIsE0(vk: u16) bool {
    return (g_scPacked[vk] & 0x8000) != 0;
}
inline fn scPackedSet(vk: u16, sc: u16, e0: bool) void {
    g_scPacked[vk] = sc | (if (e0) @as(u16, 0x8000) else 0);
}
inline fn scPackedGetSC(vk: u16) u16 {
    return g_scPacked[vk] & 0x7FFF;
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
    // Generic modifiers used by sendKeyDirect wrapper construction.
    t[0x11] = .{ .sc = 0x1D, .e0 = false }; // Ctrl -> LCtrl
    t[0x10] = .{ .sc = 0x2A, .e0 = false }; // Shift -> LShift
    t[0x12] = .{ .sc = 0x38, .e0 = false }; // Alt -> LAlt
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

    // Fast path: already cached in packed form — one load covers both SC and E0.
    if (g_scPacked[vk] != 0) return scPackedGetSC(vk);

    // Comptime QWERTY table — no MapVirtualKeyW call, no cache miss for standard keys.
    const ct = QWERTY_SC[vk];
    if (ct.sc != 0) {
        scPackedSet(vk, ct.sc, ct.e0);
        return ct.sc;
    }

    // Slow path: call MapVirtualKeyW once and cache the result.
    var nvk = vk;
    if (vk == VK_CONTROL) nvk = VK_LCONTROL;
    if (vk == VK_SHIFT) nvk = VK_LSHIFT;
    if (vk == VK_MENU) nvk = VK_LMENU;
    const sc: u32 = MapVirtualKeyW(nvk, MAPVK_VK_TO_VSC);
    if (sc == 0) return 0;
    const sc16: u16 = @intCast(sc & 0x7FFF);
    const isE0 = (nvk == 0xA5 or nvk == 0xA3 or nvk == 0x5B or nvk == 0x5C or nvk == 0x5D or
        (nvk >= 0x21 and nvk <= 0x28) or nvk == 0x2D or nvk == 0x2E or nvk == 0x6F);
    scPackedSet(vk, sc16, isE0);
    return sc16;
}

inline fn acquireSendRingLock() void {
    while (@atomicRmw(i32, &g_sendRingLock, .Xchg, 1, .acq_rel) != 0) {
        Sleep(0);
    }
}

inline fn releaseSendRingLock() void {
    @atomicStore(i32, &g_sendRingLock, 0, .release);
}

inline fn acquireSetupPublishLock() void {
    const tid = GetCurrentThreadId();
    if (@atomicRmw(i32, &g_setupPublishLock, .Xchg, 1, .acq_rel) == 0) {
        @atomicStore(u32, &g_setupPublishLockOwnerThreadId, tid, .release);
        g_setupPublishLockRecursion = 1;
        return;
    }
    if (@atomicLoad(u32, &g_setupPublishLockOwnerThreadId, .acquire) == tid) {
        g_setupPublishLockRecursion += 1;
        return;
    }
    while (@atomicRmw(i32, &g_setupPublishLock, .Xchg, 1, .acq_rel) != 0) {
        Sleep(0);
    }
    @atomicStore(u32, &g_setupPublishLockOwnerThreadId, tid, .release);
    g_setupPublishLockRecursion = 1;
}

inline fn tryAcquireSetupPublishLock() bool {
    const tid = GetCurrentThreadId();
    if (@atomicRmw(i32, &g_setupPublishLock, .Xchg, 1, .acq_rel) == 0) {
        @atomicStore(u32, &g_setupPublishLockOwnerThreadId, tid, .release);
        g_setupPublishLockRecursion = 1;
        return true;
    }
    if (@atomicLoad(u32, &g_setupPublishLockOwnerThreadId, .acquire) == tid) {
        g_setupPublishLockRecursion += 1;
        return true;
    }
    return false;
}

inline fn releaseSetupPublishLock() void {
    if (g_setupPublishLockRecursion > 1) {
        g_setupPublishLockRecursion -= 1;
        return;
    }
    g_setupPublishLockRecursion = 0;
    @atomicStore(u32, &g_setupPublishLockOwnerThreadId, 0, .release);
    @atomicStore(i32, &g_setupPublishLock, 0, .release);
}

const RUNTIME_PUBLISH_SETUP: u32 = 1 << 0;
const RUNTIME_PUBLISH_KEYGATE: u32 = 1 << 1;
const RUNTIME_PUBLISH_CONTEXTS: u32 = 1 << 2;
const RUNTIME_PUBLISH_HOTSTRING_CONTEXT_MASK: u32 = 1 << 3;

fn reconcileTrackedPhysicalKeysDown() u32 {
    var count: u32 = 0;
    inline for (0..4) |i| count += @popCount(@atomicLoad(u64, &g_is_vk_held[i], .acquire));
    g_trackedPhysicalKeysDown = count;
    return count;
}

fn rebuildTrackedPhysicalModifierDerivedState() void {
    var physical_mask: u16 = 0;
    var hotkey_mask: u16 = 0;
    var lr_mask: u8 = 0;
    @memset(&g_active_physical_modifier_key_counts_by_category, 0);
    for (ALL_MOD_VKS, ALL_MOD_MASKS) |vk, bit| {
        const vki: usize = @intCast(vk);
        if (!physicalKeyDownAt(vki)) continue;
        physical_mask |= bit;
        lr_mask |= physicalModifierLRBitForVK(vk);
        const slot_i = hotkeyModSlotForVK(vk);
        if (slot_i >= 0) {
            const slot: usize = @intCast(slot_i);
            if (g_active_physical_modifier_key_counts_by_category[slot] != std.math.maxInt(u8)) {
                g_active_physical_modifier_key_counts_by_category[slot] += 1;
            }
            hotkey_mask |= hotkeyModBitForSlot(slot);
        }
    }
    g_which_physical_modifiers_to_send = hotkey_mask;
    g_lr_active_physical_modifiers = lr_mask;
    g_active_physical_modifiers = physical_mask;
    g_any_physical_modifiers_active = physical_mask != 0;
    g_active_physical_and_windows_facing_modifiers = physical_mask;
    rfSetIf(RF_PHYSICAL_MODS, g_any_physical_modifiers_active);
    rfSetIf(RF_SYS_MODS, g_active_physical_and_windows_facing_modifiers != 0);
}

inline fn restoreSystemModBitmaskFromPhysicalState() void {
    g_active_physical_and_windows_facing_modifiers = @intCast(g_active_physical_modifiers);
    rfSetIf(RF_SYS_MODS, g_active_physical_and_windows_facing_modifiers != 0);
}

fn syncPhysicalModifierStateFromSystem() void {
    const hidden_before = hiddenPhysicalModsFromOs();
    var physical_lr_mask: u8 = 0;
    inline for (ALL_MOD_VKS) |vk| {
        const vki: usize = @intCast(vk);
        const was_down = physicalKeyDownAt(vki);
        const bit = physicalModifierLRBitForVK(vk);
        const os_down = (GetAsyncKeyState(vk) & @as(i16, -0x8000)) != 0;
        const qmk_hidden_down = was_down and bit != 0 and (hidden_before & bit) != 0;
        const is_down = os_down or qmk_hidden_down;
        setPhysicalKeyDownAt(vki, is_down);
        if (is_down and !was_down) {
            g_lastPhysicalDownVK = vk;
            physical_lr_mask |= bit;
        } else if (is_down) {
            physical_lr_mask |= bit;
        }
    }
    const hidden = hiddenPhysicalModsFromOs();
    const stale_hidden = hidden & ~physical_lr_mask;
    if (stale_hidden != 0) clearPhysicalModsHiddenFromOs(stale_hidden);
    _ = reconcileTrackedPhysicalKeysDown();
    rebuildTrackedPhysicalModifierDerivedState();
}

fn seedHiddenPhysicalModifiersBeforeColdSync() void {
    const hidden = hiddenPhysicalModsFromOs();
    if (hidden == 0) return;
    for (ALL_MOD_VKS) |vk| {
        const bit = physicalModifierLRBitForVK(vk);
        if ((hidden & bit) == 0) continue;
        setPhysicalKeyDownAt(@intCast(vk), true);
    }
}

fn syncForeignPhysicalKeysFromSystem() void {
    @memset(&g_foreignPhysicalKeyDown, false);
}

fn foreignPhysicalKeysStillHeld() bool {
    return false;
}

fn armForeignPhysicalKeyQuarantine() void {
    syncForeignPhysicalKeysFromSystem();
    g_foreignPhysicalQuarantineArmed = false;
}

fn syncColdPhysicalStateFromSystem() void {
    seedHiddenPhysicalModifiersBeforeColdSync();
    syncPhysicalModifierStateFromSystem();
}

fn clearRuntimePublishStateForReset() void {
    g_precompiledShortcutsApplied = false;
    g_precompiledShortcutsLoadStarted = false;
    @atomicStore(u32, &g_runtimePublishPendingMask, 0, .release);
    g_pendingContextChangedMask = 0;
    g_pendingHotstringContextMask = 0;
    g_pendingHotstringContextMaskValid = false;
    @atomicStore(i32, &g_runtimePublishInProgress, 0, .release);
    @atomicStore(i32, &g_hotPathActiveCount, 0, .release);
    @atomicStore(i32, &g_runtimePublishWorkerActive, 0, .release);
    @atomicStore(i32, &g_nativePasteInFlight, 0, .release);
    g_bulkRuntimeHotkeysDirty = false;
    g_bulkRuntimeModifiersDirty = false;
    g_bulkRuntimeContextActionsDirty = false;
    g_bulkRuntimeCombosDirty = false;
    g_bulkRuntimeChordsDirty = false;
    g_bulkRuntimeHotstringsDirty = false;
    g_bulkRuntimeKeyGateDirty = false;
    g_runtimeHotkeyContextsDirty = false;
    g_hsContextIndexDirty = false;
    g_runtimeHotkeysPublishedLen = 0;
    g_compiledHotkeysLen = 0;
    g_runtimeContextActionsPublishedLen = 0;
    g_compiledContextActionsLen = 0;
    g_runtimeModifiersPublishedLen = 0;
    g_compiledModifiersLen = 0;
    g_runtimePassthroughsPublishedLen = 0;
    g_compiledPassthroughsLen = 0;
    g_runtimeCombosPublishedLen = 0;
    g_compiledCombosLen = 0;
    g_runtimeInstantCombosPublishedLen = 0;
    g_compiledInstantCombosLen = 0;
    g_runtimeComboPublishedRegistrationSeq = 0;
    g_runtimeChordsPublishedLen = 0;
    g_compiledChordsLen = 0;
    g_runtimeHotstringPublishedLen = 0;
    g_compiledHotstringsLen = 0;
    g_hsCtxRowsPublishedLen = 0;
    g_nativeHotstringPayloadsPublishedLen = 0;
    g_bulkSetupSerial = 0;
    g_hotkeysPreparedSerial = 0;
    g_modifiersPreparedSerial = 0;
    g_contextActionsPreparedSerial = 0;
    g_combosPreparedSerial = 0;
    g_chordsPreparedSerial = 0;
    g_hotstringsPreparedSerial = 0;
}

fn flushRuntimePublishIfIdleLocked() void {
    while (true) {
        if (@atomicLoad(i32, &g_hotPathActiveCount, .acquire) != 0 or
            @atomicLoad(u32, &g_runtimePublishPendingMask, .acquire) == 0 or
            @atomicLoad(i32, &g_runtimePublishInProgress, .acquire) != 0) return;
        @atomicStore(i32, &g_runtimePublishInProgress, 1, .release);
        if (reconcileTrackedPhysicalKeysDown() != 0 or
            @atomicLoad(i32, &g_hotPathActiveCount, .acquire) != 0)
        {
            @atomicStore(i32, &g_runtimePublishInProgress, 0, .release);
            return;
        }

        const mask = @atomicRmw(u32, &g_runtimePublishPendingMask, .Xchg, 0, .acq_rel);
        var publish_failed_mask: u32 = 0;

        if ((mask & RUNTIME_PUBLISH_HOTSTRING_CONTEXT_MASK) != 0 and g_pendingHotstringContextMaskValid) {
            const previous = @atomicLoad(u64, &g_hotstringContextState.active_mask, .acquire);
            @atomicStore(u64, &g_hotstringContextState.previous_mask, previous, .release);
            @atomicStore(u64, &g_hotstringContextState.active_mask, g_pendingHotstringContextMask, .release);
            _ = @atomicRmw(u32, &g_hotstringContextState.generation, .Add, 1, .acq_rel);
            g_hotstringMatcher.reset();
            g_pendingHotstringContextMaskValid = false;
        }

        if ((mask & RUNTIME_PUBLISH_SETUP) != 0) {
            if (!publishDeferredRuntimeSetup()) {
                publish_failed_mask |= RUNTIME_PUBLISH_SETUP;
            } else if (g_precompiledShortcutsLoadStarted) {
                // The compiled preload is complete only after the combined
                // runtime rows and their active indexes publish successfully.
                g_precompiledShortcutsApplied = true;
            }
        }
        if ((mask & RUNTIME_PUBLISH_CONTEXTS) != 0 and g_pendingContextChangedMask != 0) {
            const changed = g_pendingContextChangedMask;
            g_pendingContextChangedMask = 0;
            if (!recalculateHotkeyContexts(changed)) {
                g_pendingContextChangedMask |= changed;
                publish_failed_mask |= RUNTIME_PUBLISH_CONTEXTS;
            }
        }
        if ((mask & RUNTIME_PUBLISH_KEYGATE) != 0 and publish_failed_mask == 0) {
            rebuild_runtime_vk_plan();
            g_keyGateDirty = false;
            warmHotTables();
        } else if ((mask & RUNTIME_PUBLISH_KEYGATE) != 0) {
            publish_failed_mask |= RUNTIME_PUBLISH_KEYGATE;
        }

        @atomicStore(i32, &g_runtimePublishInProgress, 0, .release);
        reclaimRetiredAllocationsIfSafe();
        if (publish_failed_mask != 0) {
            _ = @atomicRmw(u32, &g_runtimePublishPendingMask, .Or, publish_failed_mask, .acq_rel);
            startRuntimePublishWorkerIfNeeded();
            return;
        }
    }
}

inline fn requestRuntimePublish(mask: u32) void {
    _ = @atomicRmw(u32, &g_runtimePublishPendingMask, .Or, mask, .acq_rel);
    flushRuntimePublishIfIdleLocked();
    if (@atomicLoad(u32, &g_runtimePublishPendingMask, .acquire) != 0) startRuntimePublishWorkerIfNeeded();
}

fn runtimePublishWorkerProc(_: ?*anyopaque) callconv(.winapi) u32 {
    while (@atomicLoad(u32, &g_runtimePublishPendingMask, .acquire) != 0) {
        // Let the input callback or setup call that requested the publish unwind.
        Sleep(0);
        if (tryAcquireSetupPublishLock()) {
            flushRuntimePublishIfIdleLocked();
            releaseSetupPublishLock();
        }
        if (@atomicLoad(u32, &g_runtimePublishPendingMask, .acquire) == 0) break;
        Sleep(1);
    }
    @atomicStore(i32, &g_runtimePublishWorkerActive, 0, .release);
    if (@atomicLoad(u32, &g_runtimePublishPendingMask, .acquire) != 0) startRuntimePublishWorkerIfNeeded();
    return 0;
}

fn startRuntimePublishWorkerIfNeeded() void {
    if (@atomicLoad(u32, &g_runtimePublishPendingMask, .acquire) == 0) return;
    if (@atomicLoad(i32, &g_hotPathActiveCount, .acquire) != 0) return;
    reclaimRetiredAllocationsIfSafe();
    if (@atomicRmw(i32, &g_runtimePublishWorkerActive, .Xchg, 1, .acq_rel) != 0) return;
    if (CreateThread(null, 0, runtimePublishWorkerProc, null, 0, null)) |hThread| {
        _ = CloseHandle(hThread);
    } else {
        @atomicStore(i32, &g_runtimePublishWorkerActive, 0, .release);
    }
}

inline fn beginHotPathActivity() void {
    _ = @atomicRmw(i32, &g_hotPathActiveCount, .Add, 1, .acq_rel);
    while (@atomicLoad(i32, &g_runtimePublishInProgress, .acquire) != 0) {
        Sleep(0);
    }
}

inline fn endHotPathActivity(is_down: bool) void {
    const previous = @atomicRmw(i32, &g_hotPathActiveCount, .Sub, 1, .acq_rel);
    if (previous <= 1) @atomicStore(i32, &g_hotPathActiveCount, 0, .release);
    if (!is_down) flushRuntimePublishAfterKeyEvent(is_down);
}

inline fn ringReset() void {
    acquireSendRingLock();
    g_ringCount = 0;
}
// Precompute everything ringSend needs at add-time so the send loop is
// just a memcpy + one indirect call, with no per-stroke conditionals.
// wScan and the e0 flag are baked into the slot here; the send loop reads
// them with a single indexed load instead of a separate scCacheIsE0 call.
// wScan==0 keys are silently dropped here — no branch needed in ringSend.
fn ringAddKeyWithInfoTagged(vk: u16, flags: u32, extraInfo: u64, internalFlags: u32) void {
    if (g_ringCount >= RING_SIZE) return;
    const sc = scLookup(vk);
    if (sc == 0) return; // guard here — eliminates the wScan==0 branch from ringSend
    // E0 flag already in g_scPacked from scLookup — no second memory access needed.
    const e0Flag: u32 = if (scPackedIsE0(vk)) 0x8000_0000 else 0;
    g_ring[g_ringCount] = .{
        .wVk = vk,
        .wScan = sc,
        .dwFlags = flags | e0Flag | internalFlags,
        .dwExtraInfo = extraInfo,
    };
    g_ringCount += 1;
}
fn ringAddTapWithInfoTagged(vk: u16, extraInfo: u64, internalFlags: u32) void {
    if (g_ringCount + 1 >= RING_SIZE) return;
    const sc = scLookup(vk);
    if (sc == 0) return;
    const e0Flag: u32 = if (scPackedIsE0(vk)) 0x8000_0000 else 0;
    const base = g_ringCount;
    const commonFlags = e0Flag | internalFlags;
    g_ring[base] = .{
        .wVk = vk,
        .wScan = sc,
        .dwFlags = commonFlags,
        .dwExtraInfo = extraInfo,
    };
    g_ring[base + 1] = .{
        .wVk = vk,
        .wScan = sc,
        .dwFlags = commonFlags | KEYEVENTF_KEYUP,
        .dwExtraInfo = extraInfo,
    };
    g_ringCount = base + 2;
}
fn ringAddKeyWithInfo(vk: u16, flags: u32, extraInfo: u64) void {
    ringAddKeyWithInfoTagged(vk, flags, extraInfo, 0);
}
fn ringAddKey(vk: u16, flags: u32) void {
    ringAddKeyWithInfo(vk, flags, AHK_SENDLEVEL_2);
}
inline fn ringAddTapFlushing(vk: u16) void {
    if (g_ringCount + 2 >= RING_SIZE) ringSendImpl(false);
    ringAddTapWithInfoTagged(vk, AHK_SENDLEVEL_2, 0);
}
fn ringSend() void {
    ringSendImpl(true);
}
fn ringSendImpl(unlock_after: bool) void {
    defer {
        if (unlock_after) releaseSendRingLock();
    }
    if (g_ringCount == 0) return;
    if (g_suppressOutputForReplay) {
        g_ringCount = 0;
        return;
    }
    if (g_interceptionSendReady) {
        @branchHint(.likely);
        // Hoist globals to locals — compiler can register-allocate these
        // instead of re-loading mutable globals on every loop iteration.
        const ictx = g_sendCtx;
        const idev = g_sendDev;
        const sendFn = fp_send orelse {
            g_ringCount = 0;
            return;
        };
        var batchLen: u32 = 0;
        // Tight encode loop: all per-stroke data is already in the InputSlot.
        // No function calls, no cache-miss loads — just indexed reads and
        // a single write per stroke. wScan==0 slots are pre-filtered at
        // ringAddKey time so no branch is needed here.
        for (0..g_ringCount) |i| {
            const slot = g_ring[i];
            const isUp = (slot.dwFlags & KEYEVENTF_KEYUP) != 0;
            const isE0 = (slot.dwFlags & 0x8000_0000) != 0;
            var state: u16 = if (isUp) IKEY_UP else IKEY_DOWN;
            if (isE0) state |= IKEY_E0;
            g_strokeBatch[batchLen] = .{
                .code = slot.wScan,
                .state = state,
                .information = @intCast(slot.dwExtraInfo & 0xFFFF_FFFF),
            };
            batchLen += 1;
        }
        if (batchLen > 0) {
            _ = sendFn(ictx, idev, g_strokeBatch[0..batchLen].ptr, batchLen);
        }
    } else {
        // --- ASYNC SENDINPUT PATH ---
        // Load head once; increment locally so we only write the atomic once
        // per batch instead of once per stroke.  This halves the number of
        // fence instructions on the hot path.
        var head = @atomicLoad(u32, &g_async_head, .acquire);
        const tail = @atomicLoad(u32, &g_async_tail, .acquire);
        if (head - tail + @as(u32, @intCast(g_ringCount)) > ASYNC_RING_SIZE) {
            g_asyncSendDropCount +%= 1;
            g_ringCount = 0;
            return;
        }
        for (0..g_ringCount) |i| {
            var slot = g_ring[i];
            // Strip our internal e0 tag from dwFlags before sending to Win32.
            slot.dwFlags &= ~@as(u32, 0x8000_0000);
            if ((slot.dwFlags & 0x0008) == 0) {
                slot.dwFlags |= 0x0008; // KEYEVENTF_SCANCODE
                if (scPackedIsE0(slot.wVk)) slot.dwFlags |= 0x0001; // KEYEVENTF_EXTENDEDKEY
            }
            g_async_ring[head % ASYNC_RING_SIZE] = slot;
            head +%= 1;
        }
        @atomicStore(u32, &g_async_head, head, .release);
        // Wake the background thread instantly
        if (g_async_event) |ev| {
            _ = SetEvent(ev);
        }
    }
    g_ringCount = 0;
}
/// Flushes the pending ring through one synchronous SendInput call.
///
/// AutoHotkey's SendKeys depends on SendInput being uninterruptible: Windows
/// will not let another thread's keyboard events intermix with a single batch.
/// `keyboard_mouse.cpp` calls this out directly, noting that the only case
/// where the assumption breaks is when some other process owns a low-level
/// hook. The Interception path in ringSend has no equivalent guarantee, so a
/// physically held key can land between the injected Ctrl down and the V and
/// turn the paste into Ctrl+Space or Ctrl+F instead.
///
/// Use this only for sequences that must not be split. Everything else should
/// keep going through ringSend so ordering with the driver stays consistent.
fn ringSendAtomic() void {
    defer releaseSendRingLock();
    if (g_ringCount == 0) return;
    if (g_suppressOutputForReplay) {
        g_ringCount = 0;
        return;
    }
    for (0..g_ringCount) |i| {
        g_ring[i].dwFlags &= ~@as(u32, 0x8000_0000);
        if ((g_ring[i].dwFlags & 0x0008) == 0) {
            g_ring[i].dwFlags |= 0x0008; // KEYEVENTF_SCANCODE
            if (scPackedIsE0(g_ring[i].wVk)) g_ring[i].dwFlags |= 0x0001; // KEYEVENTF_EXTENDEDKEY
        }
    }
    _ = SendInput(@intCast(g_ringCount), @ptrCast(&g_ring[0]), INPUT_STRUCT_SIZE);
    g_ringCount = 0;
}

/// The modifiers AHK's SendKeys tracks as `mods_down_physically_orig`.
const NEUTRALIZABLE_MODS = [_]u16{
    VK_LSHIFT, VK_RSHIFT,
    VK_LCONTROL, VK_RCONTROL,
    VK_LMENU,  VK_RMENU,
    VK_LWIN,   VK_RWIN,
};

/// Snapshot the left/right physical modifier bitboard. This is physical truth.
fn snapshotPhysicalMods() u8 {
    var mask: u8 = 0;
    if (physicalKeyDownVK(VK_LSHIFT)) mask |= physicalModifierLRBitForVK(VK_LSHIFT);
    if (physicalKeyDownVK(VK_RSHIFT)) mask |= physicalModifierLRBitForVK(VK_RSHIFT);
    if (physicalKeyDownVK(VK_LCONTROL)) mask |= physicalModifierLRBitForVK(VK_LCONTROL);
    if (physicalKeyDownVK(VK_RCONTROL)) mask |= physicalModifierLRBitForVK(VK_RCONTROL);
    if (physicalKeyDownVK(VK_LMENU)) mask |= physicalModifierLRBitForVK(VK_LMENU);
    if (physicalKeyDownVK(VK_RMENU)) mask |= physicalModifierLRBitForVK(VK_RMENU);
    if (physicalKeyDownVK(VK_LWIN)) mask |= physicalModifierLRBitForVK(VK_LWIN);
    if (physicalKeyDownVK(VK_RWIN)) mask |= physicalModifierLRBitForVK(VK_RWIN);
    return mask;
}

inline fn hiddenPhysicalModsFromOs() u8 {
    return @atomicLoad(u8, &g_physical_modifier_hidden_from_os_lr_mask, .acquire);
}

inline fn markPhysicalModsHiddenFromOs(mask: u8) void {
    if (mask == 0) return;
    _ = @atomicRmw(u8, &g_physical_modifier_hidden_from_os_lr_mask, .Or, mask, .acq_rel);
}

inline fn clearPhysicalModsHiddenFromOs(mask: u8) void {
    if (mask == 0) return;
    _ = @atomicRmw(u8, &g_physical_modifier_hidden_from_os_lr_mask, .And, ~mask, .acq_rel);
}

/// Snapshot physical modifiers whose DOWN Windows currently owns. Synthetic
/// send/paste neutralization releases and restores only this set, so already
/// hidden modifiers stay hidden after the temporary send finishes.
fn snapshotVisiblePhysicalMods() u8 {
    return snapshotPhysicalMods() & ~hiddenPhysicalModsFromOs();
}

/// Queues key-ups for every modifier the user is holding, so an injected
/// Ctrl+V is not silently promoted to Ctrl+Shift+V (paste-as-plain-text in
/// browsers) or Ctrl+Alt+V. This mirrors the release half of AHK's
/// SetModifierLRState(mods_to_set, ...) before a Send.
fn ringAddModifierRelease(held_mask: u8, extraInfo: u64) void {
    var released: u8 = 0;
    for (NEUTRALIZABLE_MODS) |vk| {
        const bit = physicalModifierLRBitForVK(vk);
        if ((held_mask & bit) == 0) continue;
        ringAddKeyWithInfoTagged(vk, KEYEVENTF_KEYUP, extraInfo, 0);
        released |= bit;
    }
    if (released != 0) markPhysicalModsHiddenFromOs(released);
}

/// Puts the neutralized modifiers back down, but only those the user is still
/// physically holding. Visibility changes here do not alter physical truth.
fn ringAddModifierRestore(held_mask: u8, extraInfo: u64) void {
    var restored: u8 = 0;
    for (NEUTRALIZABLE_MODS) |vk| {
        const bit = physicalModifierLRBitForVK(vk);
        if ((held_mask & bit) == 0) continue;
        if (!physicalKeyDownVK(vk)) continue;
        ringAddKeyWithInfoTagged(vk, 0, extraInfo, 0);
        restored |= bit;
    }
    if (restored != 0) clearPhysicalModsHiddenFromOs(restored);
}

fn sendPhysicalModsBeforeNativeForward(extraInfo: u64, atomic_send: bool) void {
    // Native passthrough is made self-contained from QMK physical truth. Windows
    // visibility can lag a real event, so send all currently-held LR physical
    // modifiers before the native key and only use hiddenFromOs as bookkeeping.
    const held = snapshotPhysicalMods();
    if (held == 0) return;
    ringReset();
    ringAddModifierRestore(held, extraInfo);
    if (atomic_send) {
        ringSendAtomic();
    } else {
        ringSend();
    }
    clearPhysicalModsHiddenFromOs(held);
}

fn sendInterceptionNativeForwardBatch(ctx: InterceptionContext, device: InterceptionDevice, stroke: *const InterceptionKeyStroke) void {
    const sendFn = fp_send orelse return;
    // Batch held LR physical modifiers with the captured native key. This uses
    // QMK's event-driven bitboard, not a Windows query, so fast LShift+F does
    // not depend on whether Windows has caught up to the modifier DOWN yet.
    const held = snapshotPhysicalMods();
    var batch: [9]InterceptionKeyStroke = undefined;
    var batch_len: u32 = 0;
    for (NEUTRALIZABLE_MODS) |vk| {
        const bit = physicalModifierLRBitForVK(vk);
        if ((held & bit) == 0) continue;
        const sc = scLookup(vk);
        if (sc == 0) continue;
        var state: u16 = IKEY_DOWN;
        if (scPackedIsE0(vk)) state |= IKEY_E0;
        batch[batch_len] = .{
            .code = sc,
            .state = state,
            .information = @intCast(AHK_SENDLEVEL_2 & 0xFFFF_FFFF),
        };
        batch_len += 1;
    }
    batch[batch_len] = stroke.*;
    batch_len += 1;
    _ = sendFn(ctx, device, batch[0..batch_len].ptr, batch_len);
    clearPhysicalModsHiddenFromOs(held);
}

// ============================================================================
// Section 14 — Key send helpers
// ============================================================================
fn sendKeyDirect(vk: i32, modifierMask: u16) void {
    sendKeyDirectWithInfo(vk, modifierMask, AHK_SENDLEVEL_2);
}

inline fn contextMenuDigitIndex(vk: i32) ?usize {
    if (vk >= 0x30 and vk <= 0x39) return @intCast(vk - 0x30);
    return null;
}

inline fn tryHandleContextMenuDigit(vk: i32, is_down: bool) bool {
    if (g_hotkeyContextState.has_context_menu == 0) return false;
    const index = contextMenuDigitIndex(vk) orelse return false;
    const mappedVK = g_contextMenuDigitAccessVK[index];
    // Only consume the digit when a mapping actually exists. Without a mapping
    // the key must reach the OS so AutoHotkey's menu-scoped digit hotkeys can
    // see it; consuming unconditionally made the digit disappear at the
    // Interception layer.
    if (mappedVK == 0) return false;
    if (is_down) sendKeyDirect(mappedVK, 0);
    return true;
}

fn sendKeyDirectSingleModProfiled(vk: i32, modifierMask: u16) void {
    if (vk == 0) return;

    const ku231_start = profStartSect();
    hotstringObserveSyntheticEdit(vk, modifierMask);
    profSpan(KU_BASE + 231, ku231_start); // ku231 span: single-mod send hotstring observe

    const profT = profStart();

    if (modifierMask == 0) {
        const ku232_start = profStartSect();
        ringReset();
        ringAddTapWithInfoTagged(@intCast(vk), AHK_SENDLEVEL_2, 0);
        profSpan(KU_BASE + 232, ku232_start); // ku232 span: single-mod send ring build

        profRecord(&g_profiling.directSendProcessing, profT);
        const ku233_start = profStartSect();
        ringSend();
        profSpan(KU_BASE + 233, ku233_start); // ku233 span: single-mod ringSend
        return;
    }

    const ku232_start = profStartSect();
    const held_mod_mask = snapshotVisiblePhysicalMods();
    ringReset();
    if (held_mod_mask != 0) ringAddModifierRelease(held_mod_mask, AHK_SENDLEVEL_2);
    if (modifierMask & 0x01 != 0) ringAddKeyWithInfo(VK_CONTROL, 0, AHK_SENDLEVEL_2);
    if (modifierMask & 0x02 != 0) ringAddKeyWithInfo(VK_MENU, 0, AHK_SENDLEVEL_2);
    if (modifierMask & 0x04 != 0) ringAddKeyWithInfo(VK_SHIFT, 0, AHK_SENDLEVEL_2);
    if (modifierMask & 0x08 != 0) ringAddKeyWithInfo(VK_LWIN, 0, AHK_SENDLEVEL_2);
    ringAddKeyWithInfo(@intCast(vk), 0, AHK_SENDLEVEL_2);
    ringAddKeyWithInfo(@intCast(vk), KEYEVENTF_KEYUP, AHK_SENDLEVEL_2);
    if (modifierMask & 0x08 != 0) ringAddKeyWithInfo(VK_LWIN, KEYEVENTF_KEYUP, AHK_SENDLEVEL_2);
    if (modifierMask & 0x04 != 0) ringAddKeyWithInfo(VK_SHIFT, KEYEVENTF_KEYUP, AHK_SENDLEVEL_2);
    if (modifierMask & 0x02 != 0) ringAddKeyWithInfo(VK_MENU, KEYEVENTF_KEYUP, AHK_SENDLEVEL_2);
    if (modifierMask & 0x01 != 0) ringAddKeyWithInfo(VK_CONTROL, KEYEVENTF_KEYUP, AHK_SENDLEVEL_2);
    if (held_mod_mask != 0) ringAddModifierRestore(held_mod_mask, AHK_SENDLEVEL_2);
    profSpan(KU_BASE + 232, ku232_start); // ku232 span: single-mod send ring build

    profRecord(&g_profiling.directSendProcessing, profT);
    const ku233_start = profStartSect();
    ringSend();
    profSpan(KU_BASE + 233, ku233_start); // ku233 span: single-mod ringSend
}

inline fn hotstringObserveSyntheticEdit(vk: i32, modifierMask: u16) void {
    _ = modifierMask;

    if (hotstringIsNavigationVK(vk)) {
        g_hotstringMatcher.reset();
    }
}

fn sendKeyDirectWithInfo(vk: i32, modifierMask: u16, extraInfo: u64) void {
    g_testLastDirectKeyVK = vk;
    g_testLastDirectModifierMask = modifierMask;
    if (compiled_shortcuts_test_observability)
        _ = @atomicRmw(u32, &g_testDirectKeySendCount, .Add, 1, .monotonic);
    if (vk == 0) return;
    hotstringObserveSyntheticEdit(vk, modifierMask);
    const profT = profStart();

    if (modifierMask == 0) {
        // Fast path: single key, no modifiers
        ringReset();
        ringAddTapWithInfoTagged(@intCast(vk), extraInfo, 0);
        // Processing-only metric: stop before ringSend (actual injection path).
        profRecord(&g_profiling.directSendProcessing, profT);
        ringSend();
        return;
    }
    ringReset();
    const held_mod_mask = snapshotVisiblePhysicalMods();
    if (held_mod_mask != 0) ringAddModifierRelease(held_mod_mask, extraInfo);
    if (modifierMask & 0x01 != 0) ringAddKeyWithInfo(VK_CONTROL, 0, extraInfo);
    if (modifierMask & 0x02 != 0) ringAddKeyWithInfo(VK_MENU, 0, extraInfo);
    if (modifierMask & 0x04 != 0) ringAddKeyWithInfo(VK_SHIFT, 0, extraInfo);
    if (modifierMask & 0x08 != 0) ringAddKeyWithInfo(VK_LWIN, 0, extraInfo);
    ringAddKeyWithInfo(@intCast(vk), 0, extraInfo);
    ringAddKeyWithInfo(@intCast(vk), KEYEVENTF_KEYUP, extraInfo);
    if (modifierMask & 0x08 != 0) ringAddKeyWithInfo(VK_LWIN, KEYEVENTF_KEYUP, extraInfo);
    if (modifierMask & 0x04 != 0) ringAddKeyWithInfo(VK_SHIFT, KEYEVENTF_KEYUP, extraInfo);
    if (modifierMask & 0x02 != 0) ringAddKeyWithInfo(VK_MENU, KEYEVENTF_KEYUP, extraInfo);
    if (modifierMask & 0x01 != 0) ringAddKeyWithInfo(VK_CONTROL, KEYEVENTF_KEYUP, extraInfo);
    if (held_mod_mask != 0) ringAddModifierRestore(held_mod_mask, extraInfo);
    // Processing-only metric: stop before ringSend (actual injection path).
    profRecord(&g_profiling.directSendProcessing, profT);
    ringSend();
}
fn sendRepeatKeyDirect(vk: i32) void {
    if (vk == 0) return;
    _ = @atomicRmw(u64, &g_repeatEmitCount, .Add, 1, .monotonic);
    ringReset();
    ringAddTapWithInfoTagged(@intCast(vk), AHK_SENDLEVEL_2, INTERNAL_FLAG_REPEAT);
    ringSend();
}

fn sendFirstRepeatKeyDirect(vk: i32) void {
    if (vk == 0) return;
    ringReset();
    ringAddKeyWithInfoTagged(@intCast(vk), 0, AHK_SENDLEVEL_2, 0); // KeyDown only
    ringSend();

    var spin_now: i64 = 0;
    spin_now = @as(i64, @bitCast(rdtsc()));
    const spin_end = spin_now + @divTrunc(g_qpcFreq, 1000); // 1ms delay
    while (spin_now < spin_end) {
        asm volatile ("pause" ::: .{});
        spin_now = @as(i64, @bitCast(rdtsc()));
    }

    ringReset();
    ringAddKeyWithInfoTagged(@intCast(vk), KEYEVENTF_KEYUP, AHK_SENDLEVEL_2, 0); // KeyUp
    ringSend();
}
inline fn repeatGestureStillDown(triggerVK: i32) bool {
    if (!physicalKeyDownVK(triggerVK)) return false;
    const required_len: usize = @intCast(@atomicLoad(u32, &g_repeat.required_len, .acquire));
    if (required_len == 0) return true;
    const required_key = @atomicLoad(u64, &g_repeat.required_key, .acquire);
    if (!repeatPackedKeysStillDown(required_key, required_len)) return false;

    // Generalize current QMKCore's strict single-key popcount check: the
    // complete physical-down bitboard must equal the gesture size. Thus a
    // single repeat permits exactly one held key; a 2-key combo repeat permits
    // exactly its two held trigger keys and no third physical key.
    var physical_down_count: u32 = 0;
    inline for (0..4) |i| {
        physical_down_count += @popCount(@atomicLoad(u64, &g_is_vk_held[i], .acquire));
    }
    return physical_down_count == @as(u32, @intCast(required_len));
}

inline fn repeatPackedKeysStillDown(required_key: u64, required_len: usize) bool {
    var i: usize = 0;
    while (i < required_len and i < 4) : (i += 1) {
        const vk = chordKeyVKAt(required_key, i);
        if (!physicalKeyDownVK(vk)) return false;
    }
    return true;
}

inline fn repeatRequiredContains(vk: i32) bool {
    const required_len: usize = @intCast(@atomicLoad(u32, &g_repeat.required_len, .acquire));
    if (required_len == 0) return false;
    const required_key = @atomicLoad(u64, &g_repeat.required_key, .acquire);
    var i: usize = 0;
    while (i < required_len and i < 4) : (i += 1) {
        if (chordKeyVKAt(required_key, i) == vk) return true;
    }
    return false;
}

fn sendRepeatResolvedAction(triggerVK: i32) bool {
    if (!repeatGestureStillDown(triggerVK)) return false;
    const kind = @atomicLoad(i32, &g_repeat.action_kind, .acquire);
    if (kind == REPEAT_ACTION_DIRECT) {
        const target_vk = @atomicLoad(i32, &g_repeat.action_target_vk, .acquire);
        const mod_mask: u16 = @intCast(@atomicLoad(u32, &g_repeat.action_mod_mask, .acquire) & 0xFFFF);
        if (target_vk == 0) return false;
        _ = @atomicRmw(u64, &g_repeatEmitCount, .Add, 1, .monotonic);
        sendKeyDirect(target_vk, mod_mask);
        return true;
    }
    if (kind == REPEAT_ACTION_CALLBACK) {
        const callback_id = @atomicLoad(i32, &g_repeat.action_callback_id, .acquire);
        if (callback_id < 0 and !isCompiledZigCallbackId(callback_id)) return false;
        const name_vk = @atomicLoad(i32, &g_repeat.action_name_vk, .acquire);
        const name_ref = cachedNameFromVK(name_vk) orelse return false;
        const callback_type = @atomicLoad(i32, &g_repeat.action_callback_type, .acquire);
        _ = @atomicRmw(u64, &g_repeatEmitCount, .Add, 1, .monotonic);
        queueCallback(callback_id, name_ref, @ptrCast(&[_:0]u16{0}), callback_type);
        notifyAHK(true, false);
        return true;
    }
    sendRepeatKeyDirect(triggerVK);
    return true;
}
inline fn repeatIsActive() bool {
    return @atomicLoad(i32, &g_repeat.active, .acquire) != 0;
}

inline fn repeatVK() i32 {
    return @atomicLoad(i32, &g_repeat.vk, .acquire);
}

inline fn repeatGeneration() usize {
    return @atomicLoad(usize, &g_repeat.generation, .acquire);
}

inline fn repeatStillMine(myGen: usize, vk: i32) bool {
    return @atomicLoad(i32, &g_repeat.active, .acquire) != 0 and
        @atomicLoad(usize, &g_repeat.generation, .acquire) == myGen and
        @atomicLoad(i32, &g_repeat.vk, .acquire) == vk;
}

inline fn onlyPhysicalKeyDown(vk: i32) bool {
    if (vk <= 0 or vk >= VK_COUNT or !physicalKeyDownVK(vk)) return false;
    var count: u32 = 0;
    inline for (0..4) |i| count += @popCount(@atomicLoad(u64, &g_is_vk_held[i], .acquire));
    return count == 1;
}

fn repeatVkIsOnlyPhysicalKeyDown(vk: i32) bool {
    return onlyPhysicalKeyDown(vk);
}

// E223: No double-tap repeat thread - these are stubs
inline fn dtRepeatIsActive() bool {
    return false;
}

inline fn dtRepeatVK() i32 {
    return 0;
}

fn stopDoubleTapRepeat() void {
    // No-op in E223
}

fn startDoubleTapRepeat(_: i32, _: i64) bool {
    // No-op in E223
    return false;
}

fn initDtRepeatWorker() void {
    // No-op in E223
}

fn stopDtRepeatWorker() void {
    // No-op in E223
}
// Send a single key down+up with NO modifier wrapping.
// Used for chord repeat (a+s held, l repeating): the physical keys are still
// in the driver so modifiers are already logically down. Re-wrapping them on
// every repeat causes a flicker/race that makes the chord drop under battery.
fn sendKeyOnly(vk: i32) void {
    if (vk == 0) return;
    ringReset();
    ringAddTapWithInfoTagged(@intCast(vk), AHK_SENDLEVEL_2, 0);
    ringSend();
}

inline fn hotstringVKToCommittedByte(vk: i32) ?u8 {
    return switch (vk) {
        0x30...0x39 => @as(u8, @intCast(vk)),
        0x60...0x69 => @as(u8, @intCast('0' + (vk - 0x60))),
        0x41...0x5A => @as(u8, @intCast(vk + 32)),
        0x6D => '-',
        0xBD => '-',
        VK_OEM_PLUS => '=',
        VK_OEM_COMMA => ',',
        VK_OEM_PERIOD => '.',
        0x6E => '.',
        VK_OEM_SLASH => if (hotstringShiftDown()) '?' else '/',
        0x6F => '/',
        VK_SPACE => ' ',
        VK_RETURN => '\n',
        else => null,
    };
}

inline fn hotstringIsEndVK(vk: i32) bool {
    return switch (vk) {
        VK_SPACE, VK_RETURN, VK_OEM_COMMA, VK_OEM_PERIOD, VK_OEM_SLASH, 0x6E, 0x6F => true,
        else => false,
    };
}

inline fn hotstringIsNavigationVK(vk: i32) bool {
    return switch (vk) {
        VK_LEFT, VK_RIGHT, VK_DOWN, VK_UP, VK_NEXT, VK_PRIOR, VK_HOME, VK_END => true,
        else => false,
    };
}

inline fn hotstringShouldInspectVK(vk: i32) bool {
    return switch (vk) {
        0x30...0x39,
        0x41...0x5A,
        0x60...0x69,
        0x6D,
        0x6E,
        0x6F,
        0xBD,
        VK_OEM_PLUS,
        VK_BACK,
        VK_RETURN,
        VK_SPACE,
        VK_LEFT,
        VK_RIGHT,
        VK_DOWN,
        VK_UP,
        VK_NEXT,
        VK_PRIOR,
        VK_HOME,
        VK_END,
        VK_OEM_COMMA,
        VK_OEM_PERIOD,
        VK_OEM_SLASH,
        => true,
        else => false,
    };
}

inline fn hotstringAnyModifierDown() bool {
    return g_which_physical_modifiers_to_send != 0;
}

inline fn hotstringShiftDown() bool {
    return (g_which_physical_modifiers_to_send & hotkeys.HOTKEY_MOD_SHIFT) != 0;
}

fn hotstringAddAsciiTap(byte: u8) void {
    switch (byte) {
        'a'...'z' => ringAddTapFlushing(@intCast(byte - 'a' + 0x41)),
        'A'...'Z' => {
            ringAddKeyWithInfo(VK_SHIFT, 0, AHK_SENDLEVEL_2);
            ringAddTapFlushing(@intCast(byte - 'A' + 0x41));
            ringAddKeyWithInfo(VK_SHIFT, KEYEVENTF_KEYUP, AHK_SENDLEVEL_2);
        },
        '0'...'9' => ringAddTapFlushing(@intCast(byte)),
        ' ' => ringAddTapFlushing(VK_SPACE),
        '\n', '\r' => ringAddTapFlushing(VK_RETURN),
        ',' => ringAddTapFlushing(VK_OEM_COMMA),
        '.' => ringAddTapFlushing(VK_OEM_PERIOD),
        '/' => ringAddTapFlushing(VK_OEM_SLASH),
        '?' => {
            ringAddKeyWithInfo(VK_SHIFT, 0, AHK_SENDLEVEL_2);
            ringAddTapFlushing(VK_OEM_SLASH);
            ringAddKeyWithInfo(VK_SHIFT, KEYEVENTF_KEYUP, AHK_SENDLEVEL_2);
        },
        '-' => ringAddTapFlushing(0xBD),
        else => {},
    }
}

fn sendHotstringInterceptionText(match: hotstrings.HotstringMatch, entry: hotstrings.HotstringEntry) void {
    ringReset();
    var i: usize = 0;
    while (i < match.backspace_count) : (i += 1) {
        ringAddTapFlushing(VK_BACK);
    }
    for (entry.replacement) |byte| {
        hotstringAddAsciiTap(byte);
    }
    if (!match.omit_end_char and match.end_char != 0) {
        hotstringAddAsciiTap(match.end_char);
    }
    ringSendAtomic();
}

fn putUtf8OnClipboard(text: []const u8, decode_escapes: bool) bool {
    if (!openClipboardWithRetry()) return false;
    defer _ = CloseClipboard();

    _ = EmptyClipboard();
    const bytes = ((text.len * 2) + 1) * @sizeOf(u16);
    const hmem = GlobalAlloc(GMEM_MOVEABLE, bytes) orelse return false;
    errdefer _ = GlobalFree(hmem);
    const raw = GlobalLock(hmem) orelse return false;
    const wide: [*]u16 = @ptrCast(@alignCast(raw));

    const out = if (decode_escapes)
        writeDecodedPasteUtf8(wide, text)
    else
        writeVerbatimPasteUtf8(wide, text);
    wide[out] = 0;
    _ = GlobalUnlock(hmem);
    if (SetClipboardData(CF_UNICODETEXT, hmem) == null) return false;
    return true;
}

/// Copies the text through unchanged apart from CRLF normalization, which the
/// clipboard expects.
///
/// Runtime payloads arrive already resolved: AutoHotkey turns `n and friends
/// into real characters while parsing, so every byte that reaches us is
/// literal content. Running the escape decoder over them would silently eat
/// any backtick or backslash the text legitimately contains. Only the compiled
/// HOTSTRINGS table needs decoding, because its replacements are Zig source
/// strings that still hold two-character \n sequences.
fn writeVerbatimPasteUtf8(wide: [*]u16, text: []const u8) usize {
    var out: usize = 0;
    var i: usize = 0;
    var pending_cr = false;
    while (i < text.len) {
        const cp = decodeHotstringUtf8(text, &i);
        appendNormalizedUtf16Codepoint(wide, &out, cp, &pending_cr);
    }
    flushPendingCr(wide, &out, &pending_cr);
    return out;
}

fn writeDecodedPasteUtf8(wide: [*]u16, text: []const u8) usize {
    var out: usize = 0;
    var i: usize = 0;
    var pending_cr = false;
    while (i < text.len) {
        if (decodeHotstringUtf8Escape(text, &i)) |escaped| {
            appendNormalizedUtf16Unit(wide, &out, escaped, &pending_cr);
            continue;
        }
        const cp = decodeHotstringUtf8(text, &i);
        appendNormalizedUtf16Codepoint(wide, &out, cp, &pending_cr);
    }
    flushPendingCr(wide, &out, &pending_cr);
    return out;
}

fn decodeHotstringUtf8Escape(text: []const u8, index: *usize) ?u16 {
    if (index.* + 1 >= text.len) return null;
    const prefix = text[index.*];
    const escaped = text[index.* + 1];
    if (prefix == '`') {
        index.* += 2;
        return switch (escaped) {
            'a' => 0x0007,
            'b' => 0x0008,
            'f' => 0x000C,
            'n' => '\n',
            'r' => '\r',
            't' => '\t',
            'v' => 0x000B,
            's' => ' ',
            else => escaped,
        };
    }
    if (prefix == '\\' and (escaped == 'n' or escaped == 'r')) {
        index.* += 2;
        return if (escaped == 'n') '\n' else '\r';
    }
    return null;
}

fn decodeHotstringUtf8(text: []const u8, index: *usize) u21 {
    const b0 = text[index.*];
    if (b0 < 0x80) {
        index.* += 1;
        return @intCast(b0);
    }

    if (b0 >= 0xC2 and b0 <= 0xDF and index.* + 1 < text.len) {
        const b1 = text[index.* + 1];
        if ((b1 & 0xC0) == 0x80) {
            index.* += 2;
            return (@as(u21, b0 & 0x1F) << 6) | @as(u21, b1 & 0x3F);
        }
    } else if (b0 >= 0xE0 and b0 <= 0xEF and index.* + 2 < text.len) {
        const b1 = text[index.* + 1];
        const b2 = text[index.* + 2];
        const valid_prefix = (b0 != 0xE0 or b1 >= 0xA0) and (b0 != 0xED or b1 < 0xA0);
        if (valid_prefix and (b1 & 0xC0) == 0x80 and (b2 & 0xC0) == 0x80) {
            index.* += 3;
            return (@as(u21, b0 & 0x0F) << 12) | (@as(u21, b1 & 0x3F) << 6) | @as(u21, b2 & 0x3F);
        }
    } else if (b0 >= 0xF0 and b0 <= 0xF4 and index.* + 3 < text.len) {
        const b1 = text[index.* + 1];
        const b2 = text[index.* + 2];
        const b3 = text[index.* + 3];
        const valid_prefix = (b0 != 0xF0 or b1 >= 0x90) and (b0 != 0xF4 or b1 < 0x90);
        if (valid_prefix and (b1 & 0xC0) == 0x80 and (b2 & 0xC0) == 0x80 and (b3 & 0xC0) == 0x80) {
            index.* += 4;
            return (@as(u21, b0 & 0x07) << 18) | (@as(u21, b1 & 0x3F) << 12) | (@as(u21, b2 & 0x3F) << 6) | @as(u21, b3 & 0x3F);
        }
    }

    // Invalid UTF-8 fallback: preserve the byte as a Latin-1-ish codepoint.
    index.* += 1;
    return @intCast(b0);
}

fn appendNormalizedUtf16Codepoint(wide: [*]u16, out: *usize, cp: u21, pending_cr: *bool) void {
    if (cp <= 0xFFFF) {
        appendNormalizedUtf16Unit(wide, out, @intCast(cp), pending_cr);
        return;
    }
    flushPendingCr(wide, out, pending_cr);
    appendUtf16Codepoint(wide, out, cp);
}

fn appendNormalizedUtf16Unit(wide: [*]u16, out: *usize, unit: u16, pending_cr: *bool) void {
    if (unit == '\r') {
        flushPendingCr(wide, out, pending_cr);
        wide[out.*] = '\r';
        out.* += 1;
        pending_cr.* = true;
        return;
    }
    if (unit == '\n') {
        if (!pending_cr.*) {
            wide[out.*] = '\r';
            out.* += 1;
        }
        wide[out.*] = '\n';
        out.* += 1;
        pending_cr.* = false;
        return;
    }
    flushPendingCr(wide, out, pending_cr);
    wide[out.*] = unit;
    out.* += 1;
}

fn flushPendingCr(wide: [*]u16, out: *usize, pending_cr: *bool) void {
    if (!pending_cr.*) return;
    wide[out.*] = '\n';
    out.* += 1;
    pending_cr.* = false;
}

fn appendUtf16Codepoint(wide: [*]u16, out: *usize, cp: u21) void {
    if (cp <= 0xFFFF) {
        wide[out.*] = @intCast(cp);
        out.* += 1;
        return;
    }

    const scalar = cp - 0x10000;
    wide[out.*] = @intCast(0xD800 + (scalar >> 10));
    out.* += 1;
    wide[out.*] = @intCast(0xDC00 + (scalar & 0x3FF));
    out.* += 1;
}

fn clearClipboardBackup() void {
    const heap = GetProcessHeap();
    var i: usize = 0;
    while (i < g_hotstringClipboardBackupLen) : (i += 1) {
        if (g_hotstringClipboardBackup[i].data) |data| {
            _ = HeapFree(heap, 0, data);
        }
        g_hotstringClipboardBackup[i] = .{};
    }
    g_hotstringClipboardBackupLen = 0;
}

fn backupClipboardAllOpen() void {
    clearClipboardBackup();
    const heap = GetProcessHeap();
    var format: u32 = 0;
    while (g_hotstringClipboardBackupLen < g_hotstringClipboardBackup.len) {
        format = EnumClipboardFormats(format);
        if (format == 0) break;

        const hmem = GetClipboardData(format) orelse continue;
        const size = GlobalSize(hmem);
        if (size == 0) continue;
        const src = GlobalLock(hmem) orelse continue;

        const copy = HeapAlloc(heap, 0, size) orelse {
            _ = GlobalUnlock(hmem);
            continue;
        };
        const src_bytes: [*]const u8 = @ptrCast(src);
        const dst_bytes: [*]u8 = @ptrCast(copy);
        @memcpy(dst_bytes[0..size], src_bytes[0..size]);
        _ = GlobalUnlock(hmem);

        g_hotstringClipboardBackup[g_hotstringClipboardBackupLen] = .{
            .format = format,
            .size = size,
            .data = copy,
        };
        g_hotstringClipboardBackupLen += 1;
    }
}

/// Every caller reaches here with a string AutoHotkey has already parsed, so
/// the text is literal content and only CRLF normalization is wanted. An
/// escape pass here would be a second decode and would eat backticks the
/// payload is supposed to keep.
fn putWideOnClipboard(text: []const u16) bool {
    if (!openClipboardWithRetry()) return false;
    defer _ = CloseClipboard();

    _ = EmptyClipboard();
    const bytes = ((text.len * 2) + 1) * @sizeOf(u16);
    const hmem = GlobalAlloc(GMEM_MOVEABLE, bytes) orelse return false;
    errdefer _ = GlobalFree(hmem);
    const raw = GlobalLock(hmem) orelse return false;
    const wide: [*]u16 = @ptrCast(@alignCast(raw));
    const out = writeVerbatimPasteWide(wide, text);
    wide[out] = 0;
    _ = GlobalUnlock(hmem);
    if (SetClipboardData(CF_UNICODETEXT, hmem) == null) return false;
    return true;
}

fn writeVerbatimPasteWide(wide: [*]u16, text: []const u16) usize {
    var out: usize = 0;
    var pending_cr = false;
    for (text) |unit| {
        appendNormalizedUtf16Unit(wide, &out, unit, &pending_cr);
    }
    flushPendingCr(wide, &out, &pending_cr);
    return out;
}

fn restoreClipboardThreadProc(param: ?*anyopaque) callconv(.winapi) u32 {
    const generation: u32 = @truncate(@intFromPtr(param));
    Sleep(1000);
    var attempt: u32 = 0;
    while (attempt < 200) : (attempt += 1) {
        if (generation != @atomicLoad(u32, &g_hotstringClipboardRestoreGeneration, .acquire)) return 0;
        if (restoreClipboardAll(generation)) return 0;
        Sleep(25);
    }
    return 0;
}

/// AutoHotkey never makes a single OpenClipboard attempt. `Clipboard::Open()`
/// loops until g_ClipboardTimeout (1000 ms by default) because another process
/// holding the clipboard open is routine, not exceptional. We retry the same
/// way but on a much smaller budget, since this runs on the key-event thread
/// and AHK's full second of stalling would be felt as dropped typing.
const CLIPBOARD_OPEN_ATTEMPTS: u32 = 250;
const CLIPBOARD_OPEN_RETRY_MS: u32 = 4;

fn openClipboardWithRetry() bool {
    // A registered owner is useful when available, but it is optional.
    // OpenClipboard(null) is the longstanding fallback used by the 8.4
    // implementation and must remain valid when AHK has not registered one.
    const owner = g_clipboardOwnerHwnd;
    var attempt: u32 = 0;
    while (attempt < CLIPBOARD_OPEN_ATTEMPTS) : (attempt += 1) {
        if (OpenClipboard(owner) != FALSE) return true;
        Sleep(CLIPBOARD_OPEN_RETRY_MS);
    }
    return false;
}

fn ensureClipboardMutex() bool {
    if (g_clipboardMutex == null) {
        g_clipboardMutex = CreateMutexW(null, FALSE, null);
    }
    return g_clipboardMutex != null;
}

fn lockClipboardState() bool {
    if (!ensureClipboardMutex()) return false;
    return WaitForSingleObject(g_clipboardMutex.?, INFINITE) == WAIT_OBJECT_0;
}

fn unlockClipboardState() void {
    if (g_clipboardMutex) |mutex| _ = ReleaseMutex(mutex);
}

fn backupClipboardThenPutUtf8(text: []const u8, decode_escapes: bool) bool {
    if (!openClipboardWithRetry()) return false;
    backupClipboardAllOpen();
    _ = CloseClipboard();
    if (!putUtf8OnClipboard(text, decode_escapes)) {
        // Leaving the backup populated would strand its heap blocks until the
        // next paste and arm nothing to free them.
        clearClipboardBackup();
        return false;
    }
    const generation = @atomicRmw(u32, &g_hotstringClipboardRestoreGeneration, .Add, 1, .acq_rel) + 1;
    if (CreateThread(null, 0, restoreClipboardThreadProc, @ptrFromInt(@as(usize, generation)), 0, null)) |h| {
        _ = CloseHandle(h);
    }
    return true;
}

fn restoreClipboardAll(expected_generation: u32) bool {
    if (!lockClipboardState()) return false;
    defer unlockClipboardState();
    if (expected_generation != @atomicLoad(u32, &g_hotstringClipboardRestoreGeneration, .acquire)) return true;
    if (!openClipboardWithRetry()) return false;
    defer _ = CloseClipboard();

    _ = EmptyClipboard();
    var success = true;
    var i: usize = 0;
    while (i < g_hotstringClipboardBackupLen) : (i += 1) {
        const backup = g_hotstringClipboardBackup[i];
        const src = backup.data orelse continue;
        const hmem = GlobalAlloc(GMEM_MOVEABLE, backup.size) orelse continue;
        const dst = GlobalLock(hmem) orelse {
            _ = GlobalFree(hmem);
            continue;
        };
        const src_bytes: [*]const u8 = @ptrCast(src);
        const dst_bytes: [*]u8 = @ptrCast(dst);
        @memcpy(dst_bytes[0..backup.size], src_bytes[0..backup.size]);
        _ = GlobalUnlock(hmem);
        if (SetClipboardData(backup.format, hmem) == null) {
            _ = GlobalFree(hmem);
            success = false;
        }
    }
    if (success) clearClipboardBackup();
    return success;
}

/// Puts the replacement on the clipboard, backspaces the trigger away and
/// injects Ctrl+V. The clipboard restore is already deferred by
/// `backupClipboardThenPutUtf8`, which arms a generation-guarded thread that
/// sleeps a second first, so the target window has time to service the paste
/// before the old contents come back.
/// `decode_escapes` must be true only for the compiled HOTSTRINGS table. See
/// writeVerbatimPasteUtf8 for why runtime payloads must go through untouched.
fn sendHotstringPaste(match: hotstrings.HotstringMatch, entry: hotstrings.HotstringEntry, decode_escapes: bool) void {
    if (!lockClipboardState()) {
        _ = @atomicRmw(u32, &g_nativePasteFailed, .Add, 1, .monotonic);
        return;
    }
    defer unlockClipboardState();
    if (!backupClipboardThenPutUtf8(entry.replacement, decode_escapes)) {
        _ = @atomicRmw(u32, &g_nativePasteFailed, .Add, 1, .monotonic);
        return;
    }
    _ = @atomicRmw(u32, &g_nativePasteFired, .Add, 1, .monotonic);

    // This sequence must not interleave with physical keys: release held mods,
    // backspace the trigger, paste, then restore still-held mods.
    const held_mod_mask = snapshotVisiblePhysicalMods();

    ringReset();
    var i: usize = 0;
    while (i < match.backspace_count) : (i += 1) {
        ringAddTapWithInfoTagged(VK_BACK, AHK_SENDLEVEL_2, 0);
    }
    if (held_mod_mask != 0) ringAddModifierRelease(held_mod_mask, AHK_SENDLEVEL_2);
    ringAddKeyWithInfoTagged(VK_CONTROL, 0, AHK_SENDLEVEL_2, 0);
    ringAddTapWithInfoTagged(0x56, AHK_SENDLEVEL_2, 0);
    ringAddKeyWithInfoTagged(VK_CONTROL, KEYEVENTF_KEYUP, AHK_SENDLEVEL_2, 0);
    // End char before the restore, so a physically held Shift cannot capitalize
    // it on the way back down.
    if (!match.omit_end_char and match.end_char != 0) {
        hotstringAddAsciiTap(match.end_char);
    }
    if (held_mod_mask != 0) ringAddModifierRestore(held_mod_mask, AHK_SENDLEVEL_2);
    ringSendAtomic();
}

fn sendHotstringNativePayload(match: hotstrings.HotstringMatch, text: [*:0]const u16) void {
    if (!lockClipboardState()) {
        _ = @atomicRmw(u32, &g_nativePasteFailed, .Add, 1, .monotonic);
        return;
    }
    defer unlockClipboardState();
    const text_len = std.mem.len(text);
    if (!openClipboardWithRetry()) {
        _ = @atomicRmw(u32, &g_nativePasteFailed, .Add, 1, .monotonic);
        return;
    }

    backupClipboardAllOpen();
    _ = CloseClipboard();

    if (!putWideOnClipboard(text[0..text_len])) {
        _ = @atomicRmw(u32, &g_nativePasteFailed, .Add, 1, .monotonic);
        return;
    }

    const generation = @atomicRmw(u32, &g_hotstringClipboardRestoreGeneration, .Add, 1, .acq_rel) + 1;
    if (CreateThread(null, 0, restoreClipboardThreadProc, @ptrFromInt(@as(usize, generation)), 0, null)) |h| {
        _ = CloseHandle(h);
    }
    _ = @atomicRmw(u32, &g_nativePasteFired, .Add, 1, .monotonic);

    const held_mod_mask = snapshotVisiblePhysicalMods();

    ringReset();
    var i: usize = 0;
    while (i < match.backspace_count) : (i += 1) {
        ringAddTapWithInfoTagged(VK_BACK, AHK_SENDLEVEL_2, 0);
    }
    if (held_mod_mask != 0) ringAddModifierRelease(held_mod_mask, AHK_SENDLEVEL_2);
    ringAddKeyWithInfoTagged(VK_CONTROL, 0, AHK_SENDLEVEL_2, 0);
    ringAddTapWithInfoTagged(0x56, AHK_SENDLEVEL_2, 0);
    ringAddKeyWithInfoTagged(VK_CONTROL, KEYEVENTF_KEYUP, AHK_SENDLEVEL_2, 0);
    if (!match.omit_end_char and match.end_char != 0) {
        hotstringAddAsciiTap(match.end_char);
    }
    if (held_mod_mask != 0) ringAddModifierRestore(held_mod_mask, AHK_SENDLEVEL_2);
    ringSendAtomic();
}

fn sendHotstringCallback(match: hotstrings.HotstringMatch) void {
    // Static table callbacks share the same callback queue type as runtime
    // AHK-registered hotstrings, so encode table indices as negative IDs.
    const table_index: i32 = @intCast(match.entry_index);
    sendHotstringCallbackId(match, -1 - table_index);
}

fn sendRuntimeHotstringCallback(match: hotstrings.HotstringMatch) void {
    if (match.entry_index >= g_runtimeHotstringLen) return;
    const callback_id = g_runtimeHotstringCallbackIds[match.entry_index];
    if (nativeHotstringPayloadOffset(callback_id)) |ptr| {
        sendHotstringNativePayload(match, ptr);
        return;
    }
    if (callback_id <= NATIVE_PAYLOAD_ID_BASE) {
        _ = @atomicRmw(u32, &g_nativePasteFailed, .Add, 1, .monotonic);
        return;
    }
    sendHotstringCallbackId(match, callback_id);
}

fn sendHotstringCallbackId(match: hotstrings.HotstringMatch, callbackId: i32) void {
    var i: usize = 0;
    ringReset();
    while (i < match.backspace_count) : (i += 1) {
        ringAddTapFlushing(VK_BACK);
    }
    if (!match.omit_end_char and match.end_char != 0) {
        hotstringAddAsciiTap(match.end_char);
    }
    ringSendAtomic();

    queueRuntimeCallback(callbackId, 7);
    notifyAHK(true, false);
}

/// Records a keystroke that `bufferKeyDown` consumes without ever buffering it.
///
/// The matcher is normally fed on key-up, and only when that key-up emitted a
/// direct tap. The repeat-arming branch returns before the key reaches
/// `pendingSolo` or the key buffer, so its key-up finds nothing to tap and the
/// character never reaches the matcher even though it still reaches the
/// screen. Since repeat arms on a second press of the same key, that silently
/// breaks every trigger containing a doubled letter, such as `.loop`.
///
/// This appends without attempting a match: firing a replacement here would
/// fight the repeat that was just armed, and triggers requiring an end
/// character still match when that end character arrives on a later key.
inline fn hotstringRecordConsumedKeyDown(vk: i32) void {
    if (!hotstringShouldInspectVK(vk)) return;
    const committed = hotstringVKToCommittedByte(vk) orelse return;
    g_hotstringMatcher.appendCommittedByte(committed);
}

fn hotstringAfterKeyDown(vk: i32) bool {
    if (hotstringIsNavigationVK(vk)) {
        g_hotstringMatcher.reset();
        return false;
    }

    if (vk == VK_BACK) {
        if (hotstringAnyModifierDown()) {
            g_hotstringMatcher.reset();
        } else {
            g_hotstringMatcher.backspaceCommittedChar();
        }
        return false;
    }

    const committed = hotstringVKToCommittedByte(vk) orelse return false;
    g_hotstringMatcher.appendCommittedByte(committed);
    // Only a structural trigger suffix permits context work. A stale active
    // hotstring bank must not be allowed to hide a valid contextual trigger.
    prepareStructuralHotstringContext();
    const context_mask = @atomicLoad(u64, &g_hotstringContextState.active_mask, .acquire);
    const runtime_view = activeRuntimeHotstrings();
    if (runtime_view.len != 0) {
        const runtime_entries = runtime_view.entries;
        if (g_hotstringMatcher.findMatchWithEndChars(runtime_entries[0..runtime_view.len], context_mask, g_runtimeHotstringEndChars[0..g_runtimeHotstringEndCharsLen])) |runtime_matched| {
            const runtime_entry = runtime_entries[runtime_matched.entry_index];
            if (@atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire) != 0 and !g_runtimeHotstringSuspendExempt[runtime_matched.entry_index]) {
                g_hotstringMatcher.reset();
                return false;
            }
            // Runtime entries carry the same action kinds as the compiled table.
            // A row registered with a native payload owns its replacement text
            // here and must paste from Zig; only .ahk_callback rows notify AHK.
            switch (runtime_entry.action) {
                .interception_text => sendHotstringInterceptionText(runtime_matched, runtime_entry),
                .paste_withbackup => sendHotstringPaste(runtime_matched, runtime_entry, false),
                .ahk_callback => sendRuntimeHotstringCallback(runtime_matched),
            }
            g_hotstringMatcher.finishAfterFire(runtime_matched, runtime_entry);
            return true;
        }
    }

    return false;
}

// Passthrough keys are delivered by the OS instead of processKeyEventHot.
// They still need to reach the native hotstring matcher when an earlier
// one-letter hotkey was intentionally deferred for a chord/sequence.
inline fn observePassthroughHotstring(vk: i32, is_down: bool) void {
    if (!is_down and hotstringShouldInspectVK(vk)) _ = hotstringAfterKeyDown(vk);
}

// Send keyVK with whatever modifiers are currently active.
// Checks g_internalCombos before sending so internal remaps take effect here too.
fn sendModifiedKey(keyVK: i32) void {
    const mask = get_active_virtual_modifier_mask();
    if (g_hasInternalCombos) {
        if (icGet(makeComboKey(keyVK, 0))) |remap| {
            if (queueCompiledHotkeyIfMatched(remap.targetVK, remap.modMask | mask, true)) return;
            sendKeyDirect(remap.targetVK, remap.modMask | mask);
            return;
        }
    }
    if (queueCompiledHotkeyIfMatched(keyVK, mask, true)) return;
    sendKeyDirect(keyVK, mask);
    queueCallbackEmpty(-4, 4);
}
// ============================================================================
// Section 15 — Repeat thread
// ============================================================================
inline fn repeatMsToTicks(ms: i32) i64 {
    return @divTrunc(@as(i64, ms) * g_qpcFreq, 1000);
}

inline fn repeatBumpGeneration() usize {
    return @atomicRmw(usize, &g_repeat.generation, .Add, 1, .acq_rel) + 1;
}

inline fn repeatWakeWorker() void {
    if (g_repeat.wake_event) |ev| {
        _ = SetEvent(ev);
    }
}

inline fn qpcDeltaToRelative100ns(delta_ticks: i64) i64 {
    if (delta_ticks <= 0) return -1;

    var due_100ns = -@divTrunc(delta_ticks * 10_000_000, g_qpcFreq);
    if (due_100ns == 0) due_100ns = -1;
    return due_100ns;
}

fn repeatThreadProc(_: ?*anyopaque) callconv(.winapi) u32 {
    _ = SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);

    const wake_event = g_repeat.wake_event orelse return 0;
    const timer = g_repeat.timer orelse return 0;
    const handles = [_]HANDLE{ timer, wake_event };

    while (@atomicLoad(i32, &g_repeat.worker_active, .acquire) != 0) {
        const active = @atomicLoad(i32, &g_repeat.active, .acquire);
        const vk = repeatVK();

        if (active == 0 or vk == 0) {
            @atomicStore(i32, &g_repeat.worker_phase, RP_SLEEPING, .release);
            @atomicStore(i64, &g_repeat.armed_due, 0, .release);

            // Do NOT poll every 1 ms.
            // Do NOT cancel the timer here.
            // The worker wakes only when start/stop/shutdown SetEvent()s it.
            _ = WaitForSingleObject(wake_event, INFINITE);
            continue;
        }

        const myGen = repeatGeneration();

        const due = @atomicLoad(i64, &g_repeat.next_due, .acquire);
        const now = getTime();

        if (due > now) {
            const due_100ns = qpcDeltaToRelative100ns(due - now);

            @atomicStore(i64, &g_repeat.armed_due, due, .release);
            @atomicStore(i32, &g_repeat.worker_phase, RP_ARMED, .release);

            _ = SetWaitableTimer(timer, &due_100ns, 0, null, null, FALSE);

            // Wait indefinitely for either:
            //   index 0: timer fired
            //   index 1: state changed / stop / shutdown
            const wait_result = WaitForMultipleObjects(2, &handles, FALSE, INFINITE);

            @atomicStore(i64, &g_repeat.armed_due, 0, .release);
            @atomicStore(i32, &g_repeat.worker_phase, RP_EMITTING, .release);

            // Wake event means generation/state changed. Loop and re-read.
            // Do NOT CancelWaitableTimer here; stale timer work is rejected
            // by generation checks.
            if (wait_result != 0) continue;
        } else {
            @atomicStore(i64, &g_repeat.armed_due, 0, .release);
            @atomicStore(i32, &g_repeat.worker_phase, RP_EMITTING, .release);
        }

        const emitGen = repeatGeneration();
        const emitVk = repeatVK();

        if (emitGen != myGen or
            emitVk == 0 or
            emitVk < 0 or
            emitVk >= VK_COUNT or
            !repeatGestureStillDown(emitVk) or
            @atomicLoad(i32, &g_repeat.active, .acquire) == 0)
        {
            stopRepeatThread();
            continue;
        }

        _ = @atomicRmw(i32, &g_repeat.first_emit_pending, .Xchg, 0, .acq_rel);
        if (!sendRepeatResolvedAction(emitVk)) {
            stopRepeatThread();
            continue;
        }

        const interval = @atomicLoad(i64, &g_repeat.interval, .acquire);
        var next_due = @atomicLoad(i64, &g_repeat.next_due, .acquire) + interval;
        const after_emit = getTime();

        if (next_due <= after_emit) {
            next_due = after_emit + interval;
        }

        @atomicStore(i64, &g_repeat.next_due, next_due, .release);
    }

    @atomicStore(i32, &g_repeat.worker_phase, RP_STOPPING, .release);
    @atomicStore(i64, &g_repeat.armed_due, 0, .release);

    // Final cleanup only.
    _ = CancelWaitableTimer(timer);
    return 0;
}
fn initRepeatWorker() void {
    if (g_repeat.worker_handle) |th| {
        const wait_result = WaitForSingleObject(th, 0);
        if (wait_result == WAIT_OBJECT_0) {
            _ = CloseHandle(th);
            g_repeat.worker_handle = null;
        } else {
            return;
        }
    }
    if (g_repeat.wake_event == null) {
        g_repeat.wake_event = CreateEventW(null, FALSE, FALSE, null);
    }
    if (g_repeat.timer == null) {
        g_repeat.timer = CreateWaitableTimerExW(null, null, CREATE_WAITABLE_TIMER_HIGH_RESOLUTION, TIMER_ALL_ACCESS);
        if (g_repeat.timer == null) {
            g_repeat.timer = CreateWaitableTimerExW(null, null, 0, TIMER_ALL_ACCESS);
        }
    }
    if (g_repeat.worker_handle == null and g_repeat.wake_event != null and g_repeat.timer != null) {
        @atomicStore(i32, &g_repeat.worker_active, 1, .release);
        @atomicStore(i32, &g_repeat.worker_phase, RP_BOOT, .release);
        g_repeat.worker_handle = CreateThread(null, 0, repeatThreadProc, null, 0, null);
        if (g_repeat.worker_handle == null) {
            @atomicStore(i32, &g_repeat.worker_active, 0, .release);
            @atomicStore(i32, &g_repeat.worker_phase, RP_STOPPING, .release);
        }
    }
}

fn stopRepeatWorker() void {
    stopRepeatThread();
    @atomicStore(i32, &g_repeat.worker_active, 0, .release);
    @atomicStore(i32, &g_repeat.worker_phase, RP_STOPPING, .release);
    if (g_repeat.wake_event) |ev| _ = SetEvent(ev);
    if (g_repeat.worker_handle) |th| {
        const wait_result = WaitForSingleObject(th, 2000);
        if (wait_result != WAIT_OBJECT_0) return;
        _ = CloseHandle(th);
        g_repeat.worker_handle = null;
    }
    if (g_repeat.timer) |timer| {
        _ = CancelWaitableTimer(timer);
        _ = CloseHandle(timer);
        g_repeat.timer = null;
    }
    if (g_repeat.wake_event) |ev| {
        _ = CloseHandle(ev);
        g_repeat.wake_event = null;
    }
}

fn startRepeatResolved(
    triggerVK: i32,
    now: i64,
    action_kind: i32,
    target_vk: i32,
    mod_mask: u16,
    callback_id: i32,
    callback_type: i32,
    callback_name_vk: i32,
    required_key: u64,
    required_len: u32,
) bool {
    if (g_repeat.worker_handle == null or g_repeat.wake_event == null or g_repeat.timer == null) {
        return false;
    }
    if (!physicalKeyDownVK(triggerVK)) return false;
    if (required_len != 0 and !repeatPackedKeysStillDown(required_key, @intCast(required_len))) return false;

    // Invalidate any old armed timer / old repeat state.
    @atomicStore(i32, &g_repeat.active, 0, .release);
    @atomicStore(i32, &g_repeat.vk, 0, .release);
    _ = repeatBumpGeneration();

    const interval = repeatMsToTicks(g_RepeatInterval);
    const initial = repeatMsToTicks(g_RepeatInitialDelay);

    // Publish the already-resolved output and the physical keys that must stay held.
    @atomicStore(i32, &g_repeat.action_kind, action_kind, .release);
    @atomicStore(i32, &g_repeat.action_target_vk, target_vk, .release);
    @atomicStore(u32, &g_repeat.action_mod_mask, mod_mask, .release);
    @atomicStore(i32, &g_repeat.action_callback_id, callback_id, .release);
    @atomicStore(i32, &g_repeat.action_callback_type, callback_type, .release);
    @atomicStore(i32, &g_repeat.action_name_vk, callback_name_vk, .release);
    @atomicStore(u64, &g_repeat.required_key, required_key, .release);
    @atomicStore(u32, &g_repeat.required_len, required_len, .release);
    @atomicStore(i64, &g_repeat.interval, interval, .release);
    @atomicStore(i64, &g_repeat.next_due, now + initial, .release);
    // Current QMKCore emits the initiating tap/combo on the input thread; the
    // worker begins at the first repeat deadline rather than duplicating it now.
    @atomicStore(i32, &g_repeat.first_emit_pending, 1, .release);
    @atomicStore(i32, &g_repeat.vk, triggerVK, .release);
    @atomicStore(i32, &g_repeat.active, 1, .release);

    // Commit marker. Worker rejects stale work by generation.
    _ = repeatBumpGeneration();
    repeatWakeWorker();
    return true;
}

fn startRepeatFast(keyVK: i32, now: i64) bool {
    // Preserve the current single-key repeat rule. Combo repeat deliberately
    // bypasses this through startRepeatResolved() with a two-key required set.
    if (!repeatVkIsOnlyPhysicalKeyDown(keyVK)) return false;
    const required_key = @as(u64, @intCast(keyVK));
    return startRepeatResolved(keyVK, now, REPEAT_ACTION_TAP, keyVK, 0, -1, 0, keyVK, required_key, 1);
}

inline fn packedRepeatKey2(a: i32, b: i32) u64 {
    const lo: u64 = @intCast(@min(a, b));
    const hi: u64 = @intCast(@max(a, b));
    return lo | (hi << 16);
}

inline fn comboTriggerHasRecentUp(triggerVK: i32, now: i64) bool {
    if (kutGet(triggerVK)) |up_time| {
        if (now - up_time < g_DoubleTapThreshold) {
            kutRemove(triggerVK);
            return true;
        }
        kutRemove(triggerVK);
    }
    return false;
}

inline fn markConsumedTriggerDownForRepeat(triggerVK: i32, now: i64) void {
    if (triggerVK <= 0 or triggerVK >= VK_COUNT) return;
    const gate = &activeContextDerived().gate[@intCast(triggerVK)];
    if ((gate.kuMask & KU_DOUBLE_TAP) != 0) kdtPut(triggerVK, now);
}

fn armDirectComboRepeatIfRequested(pkVK: i32, skVK: i32, now: i64, targetVK: i32, modMask: u16) void {
    markConsumedTriggerDownForRepeat(skVK, now);
    if (!comboTriggerHasRecentUp(skVK, now)) return;
    _ = startRepeatResolved(skVK, now, REPEAT_ACTION_DIRECT, targetVK, modMask, -1, 0, skVK, packedRepeatKey2(pkVK, skVK), 2);
}

fn armCallbackComboRepeatIfRequested(pkVK: i32, skVK: i32, now: i64, callbackId: i32, callbackType: i32) void {
    markConsumedTriggerDownForRepeat(skVK, now);
    if (!comboTriggerHasRecentUp(skVK, now)) return;
    _ = startRepeatResolved(skVK, now, REPEAT_ACTION_CALLBACK, 0, 0, callbackId, callbackType, pkVK, packedRepeatKey2(pkVK, skVK), 2);
}
fn resetRepeatLocalState() void {
    // Repeat is about to wipe local key state. Release only logically-active
    // homerow modifiers before clearing, then kill pending timers.
    var releasedModMask: u16 = 0;
    for (0..g_kbLen) |i| {
        const kd = &g_kbData[i];
        if (!kd.modifierActivated()) continue;

        const vk = g_kbVK[i];
        const modVK = g_virtual_modifier_output_vk[@intCast(vk)];
        if (modVK != 0) {
            ringReset();
            ringAddKey(modVK, KEYEVENTF_KEYUP);
            ringSend();
            releasedModMask |= @intCast(g_key_virtual_modifier_mask[@intCast(vk)]);
        }

        kd.cf(FLAG_MOD_ACT | FLAG_MOD_TRIG);
    }
    for (0..@as(usize, @intCast(g_active_virtual_modifier_count))) |i| {
        const vk = g_active_virtual_modifiers_by_vk[i];
        if (vk < 0 or vk >= VK_COUNT) continue;
        const modMask: u16 = @intCast(g_key_virtual_modifier_mask[@intCast(vk)]);
        if (modMask == 0 or (releasedModMask & modMask) != 0) continue;
        const modVK = g_virtual_modifier_output_vk[@intCast(vk)];
        if (modVK != 0) {
            ringReset();
            ringAddKey(modVK, KEYEVENTF_KEYUP);
            ringSend();
            releasedModMask |= modMask;
        }
    }

    timerClear();
    ptmClear();

    kbClear();
    ordClear();
    kdtClear();
    kutClear();
    clear_active_virtual_modifiers();
    restoreSystemModBitmaskFromPhysicalState();
    g_unrelModCount = 0;
    g_cleanUnrelModCount = 0;
    g_activeModKeyCnt = 0;
    g_modStackDirty = false;
    // FSM-lite: clear local virtual-mod state; physical sys-mod state is restored above.
    rfClear(RF_UNREL_MODS | RF_CLEAN_UNREL_MODS);
}

fn stopRepeatThread() void {
    @atomicStore(i32, &g_repeat.active, 0, .release);
    @atomicStore(i32, &g_repeat.vk, 0, .release);
    @atomicStore(i32, &g_repeat.first_emit_pending, 0, .release);
    @atomicStore(i32, &g_repeat.action_kind, REPEAT_ACTION_TAP, .release);
    @atomicStore(i32, &g_repeat.action_target_vk, 0, .release);
    @atomicStore(u32, &g_repeat.action_mod_mask, 0, .release);
    @atomicStore(i32, &g_repeat.action_callback_id, -1, .release);
    @atomicStore(i32, &g_repeat.action_callback_type, 0, .release);
    @atomicStore(i32, &g_repeat.action_name_vk, 0, .release);
    @atomicStore(u64, &g_repeat.required_key, 0, .release);
    @atomicStore(u32, &g_repeat.required_len, 0, .release);

    // Invalidate any armed timer or in-flight emit.
    _ = repeatBumpGeneration();

    // Wake the repeat worker if it is sleeping or armed.
    repeatWakeWorker();
}

fn cancelRepeatForDifferentKeyDown(keyVK: i32) void {
    if (repeatIsActive() and repeatVK() != keyVK and !repeatRequiredContains(keyVK)) {
        stopRepeatThread();
    }
}

inline fn cancelRepeatForRequiredKeyUp(keyVK: i32) void {
    if (repeatIsActive() and repeatRequiredContains(keyVK)) {
        stopRepeatThread();
    }
}

fn stopSchedThread() void {
    @atomicStore(i32, &g_schedActive, 0, .release);
    if (g_schedEvent) |ev| _ = SetEvent(ev);

    if (g_schedThread) |th| {
        const wait_result = WaitForSingleObject(th, 2000);
        if (wait_result != WAIT_OBJECT_0) return;
        _ = CloseHandle(th);
        g_schedThread = null;
    }

    if (g_schedTimer) |timer| {
        _ = CancelWaitableTimer(timer);
        _ = CloseHandle(timer);
        g_schedTimer = null;
    }
    if (g_schedEvent) |ev| {
        _ = CloseHandle(ev);
        g_schedEvent = null;
    }

    @memset(&g_sched, SchedEntry{});
    g_schedLen = 0;
}

fn stopAsyncThread() void {
    @atomicStore(i32, &g_async_active, 0, .release);
    if (g_async_event) |ev| _ = SetEvent(ev);

    if (g_async_thread) |th| {
        const wait_result = WaitForSingleObject(th, 2000);
        if (wait_result != WAIT_OBJECT_0) return;
        _ = CloseHandle(th);
        g_async_thread = null;
    }

    if (g_async_event) |ev| {
        _ = CloseHandle(ev);
        g_async_event = null;
    }

    @atomicStore(u32, &g_async_head, 0, .release);
    @atomicStore(u32, &g_async_tail, 0, .release);
}
// ============================================================================
// Section 15B — Async SendInput Thread
// ============================================================================
fn asyncSendThreadProc(_: ?*anyopaque) callconv(.winapi) u32 {
    // Raise this thread to TIME_CRITICAL so injected keystrokes are never
    // pre-empted by lower-priority work on the same core.  The async send
    // thread is the last hop before the kernel; any scheduling jitter here
    // shows up directly as injection latency.
    _ = SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);
    _ = SetThreadAffinityMask(GetCurrentThread(), ASYNC_AFFINITY_MASK);
    var local_batch: [128]InputSlot = undefined;

    while (@atomicLoad(i32, &g_async_active, .acquire) != 0) {
        // INFINITE: no polling overhead — wake only on SetEvent from ringSend.
        // The event is auto-reset; a spurious wake drains an empty ring safely.
        _ = WaitForSingleObject(g_async_event.?, INFINITE);
        if (@atomicLoad(i32, &g_async_active, .acquire) == 0) break;

        var head = @atomicLoad(u32, &g_async_head, .acquire);
        var tail = @atomicLoad(u32, &g_async_tail, .acquire);
        while (tail != head) {
            var batch_count: u32 = 0;
            while (tail != head and batch_count < 128) {
                var slot = g_async_ring[tail % ASYNC_RING_SIZE];
                tail +%= 1;
                if ((slot.dwFlags & INTERNAL_FLAG_REPEAT) != 0) {
                    // Repeat taps are enqueued as key-down/key-up pairs. A
                    // different key can cancel repeat between the two slots, so
                    // only stale repeat key-downs are droppable. Repeat key-ups
                    // must still drain to avoid wedging a repeated home-row key
                    // or its modifier role down.
                    const is_repeat_up = (slot.dwFlags & KEYEVENTF_KEYUP) != 0;
                    const slot_vk: i32 = @intCast(slot.wVk);
                    const valid_repeat = repeatIsActive() and slot_vk == repeatVK();
                    if (!is_repeat_up and !valid_repeat) {
                        continue;
                    }
                    slot.dwFlags &= ~INTERNAL_FLAG_REPEAT;
                }
                local_batch[batch_count] = slot;
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
// Section 15C — Double-Tap Repeat Thread (UMWAIT Architecture 27)
// ============================================================================

inline fn cpuHasWaitPkg() bool {
    var eax: u32 = 7;
    var ecx: u32 = 0;
    var ebx: u32 = 0;
    var edx: u32 = 0;
    asm volatile ("cpuid"
        : [eax] "={eax}" (eax),
          [ebx] "={ebx}" (ebx),
          [ecx] "={ecx}" (ecx),
          [edx] "={edx}" (edx),
        : [leaf] "{eax}" (eax),
          [subleaf] "{ecx}" (ecx),
        : .{});
    return (ecx & (@as(u32, 1) << 5)) != 0;
}

inline fn umonitorPtr(ptr: *u64) void {
    asm volatile ("umonitor %[addr]"
        :
        : [addr] "r" (ptr),
        : .{});
}

inline fn umwaitUntil(control: u32, deadline_tsc: u64) void {
    const lo: u32 = @truncate(deadline_tsc);
    const hi: u32 = @truncate(deadline_tsc >> 32);
    asm volatile ("umwait %%ecx"
        :
        : [lo] "{eax}" (lo),
          [hi] "{edx}" (hi),
          [control] "{ecx}" (control),
        : .{});
}

inline fn rdtsc() u64 {
    var lo: u32 = undefined;
    var hi: u32 = undefined;
    asm volatile ("rdtsc"
        : [lo] "={eax}" (lo),
          [hi] "={edx}" (hi),
    );
    return (@as(u64, hi) << 32) | @as(u64, lo);
}

// ============================================================================
// Section 16 — Combo helpers
// ============================================================================
inline fn hasCombo(primary: i32, secondary: i32) bool {
    if (primary < 0 or primary >= VK_COUNT or secondary < 0 or secondary >= VK_COUNT) return false;
    prepareStructuralComboContext(primary, secondary);
    const runtime_combos = activeRuntimeCombos();
    return g_comboMatrix[@intCast(primary)][@intCast(secondary)] or
        runtime_combos.comboMatrix[@intCast(primary)][@intCast(secondary)];
}
inline fn hasInstantCombo(primary: i32, secondary: i32) bool {
    if (primary < 0 or primary >= VK_COUNT or secondary < 0 or secondary >= VK_COUNT) return false;
    prepareStructuralComboContext(primary, secondary);
    const runtime_combos = activeRuntimeCombos();
    return g_instantComboMatrix[@intCast(primary)][@intCast(secondary)] or
        runtime_combos.instantMatrix[@intCast(primary)][@intCast(secondary)];
}
// Fire a combo immediately. Checks g_internalCombos first; only calls AHK if
// no internal remap exists.
// Fire a combo immediately.
fn triggerComboImmediate(pkVK: i32, skVK: i32, pk: *const [KN_LEN]u16, sk: *const [KN_LEN]u16, skName: *const [KN_LEN]u16) void {
    _ = skName; // silence unused parameter warning
    const currentTime = getTime();
    const pkIt = kbGet(pkVK) orelse return;
    if (pkIt.isReleased()) return;
    // Only pay the buildTid / timerRemove cost when timers are actually live.
    if (g_timerLen > 0 or g_schedLen > 0) {
        var tidBuf: [TID_LEN]u16 = [_]u16{0} ** TID_LEN;
        cancelTimer(buildTid(&tidBuf, pk, "*", sk));
        cancelKeyTimers(pkVK);
        cancelKeyTimers(skVK);
    }
    pkIt.sf(FLAG_COMBO_TRIG);
    kbMarkComboRepeat(pkVK, pkIt);
    var removed_modifier = false;
    if (kbGet(skVK)) |skIt| {
        skIt.sf(FLAG_COMBO_TRIG);
        removed_modifier = skIt.isRuntimeModifier() and !skIt.isReleased();
        _ = kbRemove(skVK);
        removeFromKeyOrder(skVK);
    }
    if (removed_modifier) rebuildUnreleasedModifierCounters();
    const ck = makeComboKey(pkVK, skVK);
    const pkIndex: usize = @intCast(pkVK);
    const skIndex: usize = @intCast(skVK);
    const runtime_combos = activeRuntimeCombos();
    const runtimeTarget = runtime_combos.comboRemapTarget[pkIndex][skIndex];
    if (runtimeTarget != 0) {
        armDirectComboRepeatIfRequested(pkVK, skVK, currentTime, runtimeTarget, runtime_combos.comboRemapMask[pkIndex][skIndex]);
        sendKeyDirect(runtimeTarget, runtime_combos.comboRemapMask[pkIndex][skIndex]);
        return;
    }
    if (icGet(ck)) |remap| {
        armDirectComboRepeatIfRequested(pkVK, skVK, currentTime, remap.targetVK, remap.modMask);
        sendKeyDirect(remap.targetVK, remap.modMask);
        return;
    }
    const runtimeCb = runtime_combos.comboCallback[pkIndex][skIndex];
    if (runtimeCb >= 0 or isCompiledZigCallbackId(runtimeCb)) {
        armCallbackComboRepeatIfRequested(pkVK, skVK, currentTime, runtimeCb, 1);
        queueCallback(runtimeCb, pk, @as([*:0]const u16, &[_:0]u16{0}), 1);
        return;
    }
    if (ccGet(ck)) |cbId| {
        armCallbackComboRepeatIfRequested(pkVK, skVK, currentTime, cbId, 1);
        queueCallback(cbId, pk, @as([*:0]const u16, &[_:0]u16{0}), 1);
    } else if (iccGet(ck)) |cbId| {
        armCallbackComboRepeatIfRequested(pkVK, skVK, currentTime, cbId, 2);
        queueCallback(cbId, pk, @as([*:0]const u16, &[_:0]u16{0}), 2);
    }
}

inline fn markInstantComboSecondaryConsumed(skVK: i32, currentTime: i64) void {
    if (skVK <= 0 or skVK >= VK_COUNT) return;
    cancelKeyTimers(skVK);
    if (kbGet(skVK)) |skIt| {
        remove_active_virtual_modifier(skVK);
        skIt.sf(FLAG_COMBO_TRIG);
        skIt.cf(FLAG_MOD_ACT | FLAG_CHORD_PENDING);
        skIt.actionType = .modifier_used;
        rebuildUnreleasedModifierCounters();
        return;
    }
    var skData = KeyData{};
    skData.downTime = currentTime;
    skData.sf(FLAG_COMBO_TRIG);
    skData.actionType = .modifier_used;
    kbPut(skVK, skData);
    ordAppend(skVK);
    if (g_ordLen > @as(usize, @intCast(g_MaxBufferSize))) {
        const f = ordAt(0);
        ordRemoveFirst();
        _ = kbRemove(f);
    }
}

// Instant combos fire as soon as the secondary key is pressed (no hold wait).
// Instant combos fire as soon as the secondary key is pressed
fn triggerInstantComboVK(pkVK: i32, skVK: i32, pk: *const [KN_LEN]u16, currentTime: i64) void {
    const pkIt = kbGet(pkVK) orelse return;
    if (pkIt.isReleased()) return;
    if (g_timerLen > 0 or g_schedLen > 0) {
        cancelKeyTimers(pkVK);
        cancelKeyTimers(skVK);
    }
    pkIt.sf(FLAG_COMBO_TRIG);
    kbMarkComboRepeat(pkVK, pkIt);
    markInstantComboSecondaryConsumed(skVK, currentTime);
    const primaryWasModifier = pkIt.isRuntimeModifier();
    if (primaryWasModifier) {
        pkIt.sf(FLAG_MOD_ACT | FLAG_MOD_TRIG);
        add_active_virtual_modifier(pkVK);
    }
    defer {
        if (primaryWasModifier) {
            pkIt.cf(FLAG_MOD_ACT);
            remove_active_virtual_modifier(pkVK);
        }
    }
    const ck = makeComboKey(pkVK, skVK);
    const pkIndex: usize = @intCast(pkVK);
    const skIndex: usize = @intCast(skVK);
    const runtime_combos = activeRuntimeCombos();
    const runtimeTarget = runtime_combos.instantRemapTarget[pkIndex][skIndex];
    if (runtimeTarget != 0) {
        armDirectComboRepeatIfRequested(pkVK, skVK, currentTime, runtimeTarget, runtime_combos.instantRemapMask[pkIndex][skIndex]);
        sendKeyDirect(runtimeTarget, runtime_combos.instantRemapMask[pkIndex][skIndex]);
        return;
    }
    if (icGet(ck)) |remap| {
        armDirectComboRepeatIfRequested(pkVK, skVK, currentTime, remap.targetVK, remap.modMask);
        sendKeyDirect(remap.targetVK, remap.modMask);
        return;
    }
    const runtimeCb = runtime_combos.instantCallback[pkIndex][skIndex];
    if (runtimeCb >= 0 or isCompiledZigCallbackId(runtimeCb)) {
        armCallbackComboRepeatIfRequested(pkVK, skVK, currentTime, runtimeCb, 2);
        queueCallback(runtimeCb, pk, @as([*:0]const u16, &[_:0]u16{0}), 2);
        return;
    }
    if (iccGet(ck)) |cbId| {
        armCallbackComboRepeatIfRequested(pkVK, skVK, currentTime, cbId, 2);
        queueCallback(cbId, pk, @as([*:0]const u16, &[_:0]u16{0}), 2);
    }
}
fn triggerInstantCombo(pkVK: i32, pk: *const [KN_LEN]u16, sk: *const [KN_LEN]u16, skName: *const [KN_LEN]u16) void {
    _ = skName;
    const skVK = getVKFromKN(sk);
    if (skVK == 0) return;
    triggerInstantComboVK(pkVK, skVK, pk, getTime());
}
// Timer-type 0: fire combo after quiet-period check.
fn triggerComboWithQuietCheck(pk: *const [KN_LEN]u16, sk: *const [KN_LEN]u16, captureTime: i64) void {
    const profT = profStart();
    defer profRecord(&g_profiling.kernelInjection, profT);
    const currentTime = timeFromProfStart(profT);
    if ((currentTime - g_lastKeyTime) >= g_QuietPeriodDuration) {
        var allReleased = true;
        for (0..g_kbLen) |i| {
            if (!g_kbData[i].isReleased()) {
                allReleased = false;
                break;
            }
        }
        if (allReleased and kbCount() > 0) {
            processQueueAfterKeyUp();
            if (kbCount() > 0) {
                kbClear();
                ordClear();
                clear_active_virtual_modifiers();
                timerClear();
            }
            return;
        }
    }
    const pkVK = getVKFromKN(pk);
    if (pkVK == 0) return;
    const pkIt = kbGet(pkVK) orelse return;
    if (pkIt.isReleased()) return;
    if (g_lastKeyTime > captureTime and g_lastKeyTime - captureTime > @divTrunc(50 * g_qpcFreq, 1000)) return;
    const skVK = getVKFromKN(sk);
    if (skVK == 0) return;
    const skNameRef = cachedNameFromVK(skVK) orelse sk;
    triggerComboImmediate(pkVK, skVK, pk, sk, skNameRef);
}
// Timer-type 1: same-modifier gesture-window timer fired.
fn sameModifierGestureWindowTimer(pk: *const [KN_LEN]u16, sk: *const [KN_LEN]u16) void {
    const profT = profStart();
    defer profRecord(&g_profiling.sendInputProcessing, profT);
    var tidBuf: [TID_LEN]u16 = [_]u16{0} ** TID_LEN;
    const tidHash = buildTid(&tidBuf, pk, "_sameMod_", sk);
    cancelTimer(tidHash);
    const pkVK = getVKFromKN(pk);
    if (pkVK == 0) return;
    const skVK = getVKFromKN(sk);
    if (skVK == 0) return;
    clearKeyTimerHash(pkVK, tidHash);
    clearKeyTimerHash(skVK, tidHash);
    const skIt = kbGet(skVK) orelse return;
    if (skIt.sameModPartnerVK == pkVK) skIt.sameModPartnerVK = 0;
    const pkIt = kbGet(pkVK) orelse return;
    if (pkIt.isReleased() or pkIt.modifierActivated() or pkIt.modifierTriggered()) return;
    if (skIt.isReleased()) return;
    add_active_virtual_modifier(pkVK);
    pkIt.sf(FLAG_MOD_ACT | FLAG_MOD_TRIG);
    sendModifiedKey(skVK);
    // sendKeyDirect sent modifier down+up as a complete pair — clear MOD_ACT so
    // the next keypress doesn't re-enter the active-mod path and so key-up
    // doesn't emit a spurious extra modifier-up stroke.
    pkIt.cf(FLAG_MOD_ACT);
    pkIt.actionType = .modifier_used;
    remove_active_virtual_modifier(pkVK);
    _ = kbRemove(skVK);
    removeFromKeyOrder(skVK);
    processQueue();
}
// Timer-type 2: retroactive combo trigger.
fn retroTriggerCombo(pk: *const [KN_LEN]u16, sk: *const [KN_LEN]u16) void {
    const profT = profStart();
    defer profRecord(&g_profiling.sendInputProcessing, profT);
    var tidBuf: [TID_LEN]u16 = [_]u16{0} ** TID_LEN;
    const tidHash = buildTid(&tidBuf, pk, "_retroCombo_", sk);
    cancelTimer(tidHash);
    const pkVK = getVKFromKN(pk);
    if (pkVK == 0) return;
    const skVK = getVKFromKN(sk);
    if (skVK == 0) return;
    clearKeyTimerHash(pkVK, tidHash);
    clearKeyTimerHash(skVK, tidHash);
    const pkIt = kbGet(pkVK) orelse return;
    if (pkIt.isReleased() or pkIt.comboTriggered() or pkIt.modifierActivated()) return;
    const skIt = kbGet(skVK) orelse return;
    if (!skIt.isReleased()) return;
    pkIt.sf(FLAG_COMBO_TRIG); // Add the receipt flag here too!
    kbMarkComboRepeat(pkVK, pkIt);
    const ck = makeComboKey(pkVK, skVK);
    if (icGet(ck)) |remap| {
        sendKeyDirect(remap.targetVK, remap.modMask);
        _ = kbRemove(skVK);
        removeFromKeyOrder(skVK);
        processQueueAfterKeyUp();
        return;
    }
    if (ccGet(ck)) |cbId|
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
    const tidHash = buildTid(&tidBuf, pk, "_retroMod_", sk);
    cancelTimer(tidHash);
    const pkVK = getVKFromKN(pk);
    if (pkVK == 0) return;
    const skVK = getVKFromKN(sk);
    if (skVK == 0) return;
    clearKeyTimerHash(pkVK, tidHash);
    clearKeyTimerHash(skVK, tidHash);
    const pkIt = kbGet(pkVK) orelse return;
    if (pkIt.isReleased() or pkIt.modifierActivated() or pkIt.modifierTriggered()) return;
    const skIt = kbGet(skVK) orelse return;
    if (!skIt.isReleased()) return;
    add_active_virtual_modifier(pkVK);
    pkIt.sf(FLAG_MOD_ACT | FLAG_MOD_TRIG);
    sendModifiedKey(skVK);
    // sendKeyDirect sent modifier down+up as a complete pair — clear MOD_ACT so
    // the next keypress doesn't re-enter the active-mod path and so key-up
    // doesn't emit a spurious extra modifier-up stroke.
    pkIt.cf(FLAG_MOD_ACT);
    pkIt.actionType = .modifier_used;
    remove_active_virtual_modifier(pkVK);
    _ = kbRemove(skVK);
    removeFromKeyOrder(skVK);
    processQueue();
}
// ============================================================================
// Section 17 — processQueue
// ============================================================================
inline fn holdHadLaterPhysicalKeyDown(vk: i32) bool {
    return g_lastPhysicalDownVK != vk;
}

inline fn callbackIdUsable(callback_id: i32) bool {
    return callback_id >= 0 or isCompiledZigCallbackId(callback_id);
}

inline fn queueHoldCallbackOnce(vk: i32, key1: *const [KN_LEN]u16) bool {
    if (vk <= 0 or vk >= VK_COUNT) return false;
    const vki: usize = @intCast(vk);
    const callback_id = effectiveHoldCallbackId(vki);
    if (!callbackIdUsable(callback_id)) return false;
    if (g_holdCallbackQueued[vki]) return true;
    g_holdCallbackQueued[vki] = true;
    queueCallback(callback_id, key1, @ptrCast(&[_:0]u16{0}), 0);
    return true;
}

inline fn classifyReleasedNonModAction(vk: i32, hasHold: bool, duration: i64, hasInterfering: bool, modifierPressed: bool) ActionType {
    if (modifierPressed) return .none;
    if (releaseOverMaxSuppressed(duration)) return .none;

    // Preserve the original interference policy: an overlapped hold becomes a
    // normal tap, rather than disappearing.  The last-physical-down check is an
    // O(1) backstop for optimized pending/fast paths that may never stamp
    // FLAG_INTERFERING into KeyData.  Only hold-enabled keys consult it.
    const holdInterfered = hasHold and holdHadLaterPhysicalKeyDown(vk);
    const effectiveInterfering = hasInterfering or holdInterfered;

    if (!hasHold and !effectiveInterfering) return .tap;
    if (effectiveInterfering or duration < g_SingleKeyHoldThreshold or !hasHold) return .tap;
    return .hold;
}
inline fn releaseOverMaxSuppressed(duration: i64) bool {
    return g_MaxThresholdSupress and duration > g_MaxHoldThreshold;
}

fn processQueue() void {
    // SECTION 1: Remove stale active modifiers
    // Remove stale active modifiers (keys that left the buffer without cleanup).
    // g_modStackDirty is set by kbRemove when g_active_virtual_modifier_count > 0, so this
    // block is skipped on the vast majority of calls where nothing was removed.
    if (g_active_virtual_modifier_count > 0 and g_modStackDirty) {
        g_modStackDirty = false;
        var toDelete: [ACTIVE_MOD_MAX]i32 = undefined;
        var tdCount: usize = 0;
        for (0..@intCast(g_active_virtual_modifier_count)) |i|
            if (!kbContains(g_active_virtual_modifiers_by_vk[i])) {
                toDelete[tdCount] = g_active_virtual_modifiers_by_vk[i];
                tdCount += 1;
            };
        for (toDelete[0..tdCount]) |vk| remove_active_virtual_modifier(vk);
    }

    while (g_ordLen > 0) {
        // SECTION 2: Load first key and metadata
        const firstVK = ordAt(0);
        const keyData = kbGet(firstVK) orelse {
            ordRemoveFirst();
            continue;
        };
        // One array load replaces: g_keyGate[..].props + 3 bit-extract locals.
        const pqPlan: u32 = activeContextDerived().queuePlan[@intCast(firstVK)];
        const keyScanFlags: u16 = activeContextDerived().scanFlags[@intCast(firstVK)];
        const firstCanComboSecondary = (pqPlan & PQP_CAN_COMBO_SECONDARY) != 0;
        const firstCanInstantSecondary = (pqPlan & PQP_CAN_INSTANT_SECONDARY) != 0;

        if (!keyData.isReleased()) break;

        // SECTION 3: FAST PATH — PQP_FAST_EMIT_TAP
        if ((pqPlan & PQP_FAST_EMIT_TAP) != 0 and
            keyData.actionType == .undecided and
            !keyData.modifierPressed() and
            (g_runtimeFlags & (RF_UNREL_KEYS | RF_ACTIVE_MODS)) == 0 and
            !releaseOverMaxSuppressed(keyData.releaseTime - keyData.downTime))
        {
            const firstName = g_keyNamePtr[@intCast(firstVK)] orelse {
                ordRemoveFirst();
                _ = kbRemove(firstVK);
                continue;
            };
            ordRemoveFirst();
            _ = kbRemove(firstVK);
            queueDirectTapCallback(firstVK, firstName);
            continue;
        }
        // We didn't take fast path, so clear the timer for that section

        // SECTION 3.5: FAST RESOLVE — released non-modifier with no live blockers.
        // With no unreleased keys and no active mods, the wait scan cannot change
        // the answer. Classify here, then reuse the normal removal/emission block.
        if (keyData.actionType == .undecided and
            (pqPlan & PQP_HAS_VIRTUAL_MODIFIER_ROLE) == 0 and
            (g_runtimeFlags & (RF_UNREL_KEYS | RF_ACTIVE_MODS)) == 0 and
            !keyData.modifierPressed() and
            !keyData.comboTriggered())
        {
            const dur = keyData.releaseTime - keyData.downTime;
            const hasHold = (pqPlan & PQP_HAS_HOLD) != 0;
            keyData.actionType = classifyReleasedNonModAction(firstVK, hasHold, dur, keyData.hasInterferingKeys(), false);
        }

        // SECTION 3.6: FAST RESOLVE — queue head is known oldest.
        // When every buffered key is represented in ord, ordAt(0) cannot have
        // an older unreleased blocker. This skips the wait scan in rolling cases
        // where younger keys are still held.
        if (keyData.actionType == .undecided and
            (pqPlan & PQP_HAS_VIRTUAL_MODIFIER_ROLE) == 0 and
            g_kbLen == g_ordLen and
            !keyData.modifierPressed() and
            !keyData.comboTriggered())
        {
            const dur = keyData.releaseTime - keyData.downTime;
            const hasHold = (pqPlan & PQP_HAS_HOLD) != 0;
            keyData.actionType = classifyReleasedNonModAction(firstVK, hasHold, dur, keyData.hasInterferingKeys(), false);
        }

        // SECTION 4: Resolve undecided action
        // Sub-timer: measure the gate check itself (pure overhead before undecided block)
        const pq_actionIsUndecided = keyData.actionType == .undecided and (pqPlan & PQP_NEEDS_SLOW_RESOLVE) != 0;
        if (pq_actionIsUndecided) {
            // SECTION 4a: MODIFIER RESOLUTION
            if ((pqPlan & PQP_NEEDS_MODIFIER_RESOLVE) != 0 and
                (keyScanFlags & KFS_PQ_MODIFIER_RESOLVE) != 0 and
                keyData.modifierActivated() and !keyData.modifierTriggered())
            {
                var hasOtherUnrel = false;
                var anyUsed = false;
                var wasQuickStack = false;
                const hasUnreleased = g_unreleasedKeyCount != 0;
                const pq24_start = profStartSect();
                for (0..g_kbLen) |i| {
                    const pvk = g_kbVK[i];
                    const pd = &g_kbData[i];
                    if (pvk != firstVK) {
                        if (pd.isRuntimeModifier() and !pd.isReleased() and pd.modifierActivated()) hasOtherUnrel = true;
                    }
                    if ((pd.isRuntimeModifier() and pd.modifierActivated() and pd.modifierTriggered()) or pd.comboTriggered())
                        anyUsed = true;
                    if (!wasQuickStack and pvk != firstVK and
                        (keyData.releaseTime - keyData.downTime) < g_SingleKeyHoldThreshold and
                        pd.isRuntimeModifier() and pd.isReleased() and
                        @abs(pd.downTime - keyData.downTime) < g_ModifierGestureWindow and
                        @abs(pd.releaseTime - keyData.releaseTime) < g_SingleKeyHoldThreshold and
                        (pd.releaseTime - pd.downTime) < g_SingleKeyHoldThreshold)
                        wasQuickStack = true;
                }
                profSpan(PQ_BASE + 24, pq24_start); // pq24 span: modifier resolution buffer scan
                if (hasOtherUnrel) {
                    break;
                }
                if (!anyUsed and !hasUnreleased) {
                    var hadSimultaneousMod = false;
                    const pq27_start = profStartSect();
                    for (0..g_kbLen) |i| {
                        const pd = &g_kbData[i];
                        if (g_kbVK[i] != firstVK and pd.isRuntimeModifier() and pd.isReleased() and
                            @abs(pd.downTime - keyData.downTime) < g_SingleKeyHoldThreshold and
                            @abs(pd.releaseTime - keyData.releaseTime) < g_SingleKeyHoldThreshold)
                        {
                            hadSimultaneousMod = true;
                            break;
                        }
                    }
                    profSpan(PQ_BASE + 27, pq27_start); // pq27 span: simultaneous modifier scan
                    if (hadSimultaneousMod) {
                        keyData.actionType = .modifier_used;
                        const pq29_start = profStartSect();
                        for (0..g_kbLen) |i| {
                            const pd = &g_kbData[i];
                            if (g_kbVK[i] != firstVK and pd.isRuntimeModifier() and pd.isReleased() and
                                @abs(pd.downTime - keyData.downTime) < g_SingleKeyHoldThreshold)
                                pd.actionType = .modifier_used;
                        }
                        profSpan(PQ_BASE + 29, pq29_start); // pq29 span: simultaneous modifier action stamp
                        continue;
                    }
                }
                keyData.actionType = if (wasQuickStack and !anyUsed and !hasUnreleased) .tap else if (!anyUsed and !keyData.modifierActivated()) blk2: {
                    var hadSiblingMod = false;
                    const pq31_start = profStartSect();
                    for (0..g_kbLen) |si| {
                        const spd = &g_kbData[si];
                        if (g_kbVK[si] != firstVK and spd.isRuntimeModifier() and spd.isReleased() and
                            @abs(spd.downTime - keyData.downTime) < g_SingleKeyHoldThreshold and
                            @abs(spd.releaseTime - keyData.releaseTime) < g_SingleKeyHoldThreshold)
                        {
                            hadSiblingMod = true;
                            break;
                        }
                    }
                    profSpan(PQ_BASE + 31, pq31_start); // pq31 span: sibling modifier scan
                    break :blk2 if (hadSiblingMod) .modifier_used else .tap;
                } else .modifier_used;
            }

            // SECTION 4b: WAIT SCAN
            if (keyData.actionType == .undecided and
                (pqPlan & PQP_NEEDS_WAIT_SCAN) != 0 and
                (keyScanFlags & KFS_PQ_WAIT_SCAN) != 0)
            {
                const waitCanMatter =
                    (g_runtimeFlags & RF_UNREL_KEYS) != 0 and ((g_runtimeFlags & RF_UNREL_MODS) != 0 or
                        (firstCanComboSecondary and (g_runtimeFlags & RF_ACTIVE_COMBO_PRIMARY) != 0) or
                        (firstCanInstantSecondary and (g_runtimeFlags & RF_ACTIVE_INSTANT_PRIMARY) != 0));
                if (waitCanMatter) {
                    var needWait = false;
                    const pq35_start = profStartSect();
                    for (0..g_kbLen) |i| {
                        const evk = g_kbVK[i];
                        const ekd = &g_kbData[i];
                        if (!ekd.isReleased() and ekd.downTime < keyData.downTime) {
                            if (ekd.modifierTriggered() or ekd.comboTriggered()) continue;
                            if ((ekd.isRuntimeModifier() and !ekd.modifierActivated()) or
                                secondaryAllowsPrimaryFast(
                                    evk,
                                    firstVK,
                                    firstCanComboSecondary and !ekd.modifierActivated(),
                                    firstCanInstantSecondary,
                                ))
                            {
                                needWait = true;
                                break;
                            }
                        }
                    }
                    profSpan(PQ_BASE + 35, pq35_start); // pq35 span: wait blocker scan
                    if (needWait) {
                        break;
                    }
                }
                const dur = keyData.releaseTime - keyData.downTime;
                const hasHold = (pqPlan & PQP_HAS_HOLD) != 0;
                keyData.actionType = classifyReleasedNonModAction(firstVK, hasHold, dur, keyData.hasInterferingKeys(), keyData.modifierPressed());
            }
        } else {
            // Key already had a resolved action — record how long the decided path took
        }

        const actionCopy = keyData.actionType;
        const comboTrigCpy = keyData.comboTriggered();
        const keyDownTime = keyData.downTime;

        // SECTION 5: Key removal
        const pq39_start = profStartSect();
        ordRemoveFirst();
        _ = kbRemove(firstVK);
        profSpan(PQ_BASE + 39, pq39_start); // pq39 span: ordRemoveFirst + kbRemove

        if (comboTrigCpy or actionCopy == .modifier_used or actionCopy == .none) continue;
        const firstName = g_keyNamePtr[@intCast(firstVK)] orelse continue;

        // SECTION 6: Emit tap or hold
        if (actionCopy == .tap) {
            // SECTION 6a: Prefix scan for modifiers
            if ((pqPlan & PQP_CAN_PREFIX_SCAN) != 0 and
                (keyScanFlags & KFS_PQ_PREFIX_SCAN) != 0 and
                (g_runtimeFlags & RF_KB_NONEMPTY) != 0)
            {
                var pfx: [8]u16 = [_]u16{0} ** 8;
                var seen: u8 = 0;
                var pi: usize = 0;
                const pq45_start = profStartSect();
                for (0..g_kbLen) |i| {
                    const evk = g_kbVK[i];
                    const ekd = &g_kbData[i];
                    if (ekd.downTime >= keyDownTime) continue;
                    if (ekd.downTime + g_ModifierGestureWindow > keyDownTime) continue;
                    const mv: usize = @intCast(evk);
                    const mm = g_key_virtual_modifier_mask[mv];
                    if (mm != 0 and seen & mm == 0 and pi < 7) {
                        seen |= mm;
                        pfx[pi] = g_keyModPrefix[mv];
                        pi += 1;
                    }
                }
                profSpan(PQ_BASE + 45, pq45_start); // pq45 span: tap prefix scan
                queueCallback(-4, firstName, @ptrCast(&pfx), 4);
            } else {
                queueDirectTapCallback(firstVK, firstName);
            }
        } else if (actionCopy == .hold) {
            if (keyData.isContaminated()) {
                continue;
            }
            if (!queueHoldCallbackOnce(firstVK, firstName)) {
                queueDirectTapCallback(firstVK, firstName);
            }
        }
    }
}

fn drainHeadOldestKeyupTap() bool {
    if (g_ordLen == 0 or g_kbLen != g_ordLen) return false;
    if (g_active_virtual_modifier_count != 0 or g_active_physical_and_windows_facing_modifiers != 0) return false;

    const firstVK = ordAt(0);
    const firstIdx = g_kbIdx[@intCast(firstVK)];
    if (firstIdx < 0) return false;
    const keyData = &g_kbData[@intCast(firstIdx)];
    if (!keyData.isReleased() or keyData.actionType != .undecided) return false;
    if (keyData.modifierPressed() or keyData.modifierActivated() or keyData.modifierTriggered()) return false;
    if (keyData.comboTriggered()) return false;
    if (keyData.tidCount != 0 or keyData.sameModTidHash != 0) return false;

    const pqPlan = activeContextDerived().queuePlan[@intCast(firstVK)];
    if ((pqPlan & PQP_HAS_VIRTUAL_MODIFIER_ROLE) != 0) return false;
    const dur = keyData.releaseTime - keyData.downTime;
    const hasHold = (pqPlan & PQP_HAS_HOLD) != 0;
    const actionHead = classifyReleasedNonModAction(firstVK, hasHold, dur, keyData.hasInterferingKeys(), false);
    if (actionHead != .tap) return false;

    const firstName = g_keyNamePtr[@intCast(firstVK)] orelse return false;
    ordRemoveFirst();
    _ = kbRemove(firstVK);
    queueDirectTapCallback(firstVK, firstName);
    return true;
}

inline fn processQueueAfterKeyUpNoWork() bool {
    if (g_ordLen == 0) return false;
    if (g_active_virtual_modifier_count > 0 and g_modStackDirty) return false;
    const firstVK = ordAt(0);
    if (firstVK < 0 or firstVK >= VK_COUNT) return false;
    const firstIdx = g_kbIdx[@intCast(firstVK)];
    if (firstIdx < 0) return false;
    return !g_kbData[@intCast(firstIdx)].isReleased();
}

inline fn processQueueAfterKeyUp() void {
    if (g_ordLen == 0) {
        if (!(g_active_virtual_modifier_count > 0 and g_modStackDirty)) return;
        const ku234_start = profStartSect();
        processQueue();
        profSpan(KU_BASE + 234, ku234_start); // ku234 span: pqAfter empty-order dirty processQueue
        return;
    }
    const ku237_start = profStartSect();
    if (processQueueAfterKeyUpNoWork()) {
        profSpan(KU_BASE + 237, ku237_start); // ku237 span: pqAfter unreleased-head no-work skip
        return;
    }
    profSpan(KU_BASE + 237, ku237_start); // ku237 span: pqAfter unreleased-head no-work check
    const ku235_start = profStartSect();
    const drained_head =
        g_kbLen == g_ordLen and
        g_active_virtual_modifier_count == 0 and
        g_active_physical_and_windows_facing_modifiers == 0 and
        drainHeadOldestKeyupTap();
    profSpan(KU_BASE + 235, ku235_start); // ku235 span: pqAfter head-oldest drain attempt
    if (g_kbLen == g_ordLen and
        g_active_virtual_modifier_count == 0 and
        g_active_physical_and_windows_facing_modifiers == 0 and
        drained_head and
        g_ordLen == 0)
    {
        return;
    }
    const ku236_start = profStartSect();
    processQueue();
    profSpan(KU_BASE + 236, ku236_start); // ku236 span: pqAfter final processQueue
}

// ============================================================================
// Section 18 — bufferKeyDown
// ============================================================================
// Branchless sorting network for =5 elements — replaces the O(n²) bubble-sort
// used in both chord repeat and first-press paths.  A sorting network has a
// fixed, data-independent instruction count and no branches, making it faster
// and more predictable than bubble sort for the small sizes we need (2–5).
// Generated from the optimal sorting network for each size.
inline fn smin(a: *i32, b: *i32) void {
    const t = a.*;
    // Cast u1 to i32, then negate to get 0x00000000 or 0xFFFFFFFF
    const mask = -@as(i32, @intFromBool(t > b.*));
    a.* = t + ((b.* - t) & mask);
    b.* = b.* - ((b.* - t) & mask);
}
inline fn sortSmall5(arr: []i32, n: usize) void {
    // Optimal sorting networks (Knuth TAOCP vol 3):
    //  n=2: 1 comparator
    //  n=3: 3 comparators
    //  n=4: 5 comparators
    //  n=5: 9 comparators
    switch (n) {
        2 => smin(&arr[0], &arr[1]),
        3 => {
            smin(&arr[0], &arr[1]);
            smin(&arr[0], &arr[2]);
            smin(&arr[1], &arr[2]);
        },
        4 => {
            smin(&arr[0], &arr[1]);
            smin(&arr[2], &arr[3]);
            smin(&arr[0], &arr[2]);
            smin(&arr[1], &arr[3]);
            smin(&arr[1], &arr[2]);
        },
        5 => {
            smin(&arr[0], &arr[1]);
            smin(&arr[2], &arr[3]);
            smin(&arr[0], &arr[2]);
            smin(&arr[1], &arr[4]);
            smin(&arr[0], &arr[1]);
            smin(&arr[2], &arr[3]);
            smin(&arr[1], &arr[2]);
            smin(&arr[3], &arr[4]);
            smin(&arr[2], &arr[3]);
        },
        else => {}, // n<2 or n>5: nothing to sort
    }
}

inline fn chordKeyFromSorted(vks: []const i32) u64 {
    if (vks.len < 2 or vks.len > 5) return 0;
    var ck: u64 = @as(u64, @intCast(vks[0])) | (@as(u64, @intCast(vks[1])) << 16);
    if (vks.len >= 3) ck |= (@as(u64, @intCast(vks[2])) << 32);
    if (vks.len >= 4) ck |= (@as(u64, @intCast(vks[3])) << 48);
    if (vks.len >= 5) ck ^= @as(u64, @intCast(vks[4]));
    return ck;
}

inline fn chordRuntimePossibleForIncoming(keyVK: i32) bool {
    if (g_kbLen == 1) {
        const heldVK = g_kbVK[0];
        if (heldVK >= 0 and heldVK < VK_COUNT) {
            return (activeContextDerived().pairRelation[@intCast(heldVK)][@intCast(keyVK)] & REL_CHORD2) != 0;
        }
    }
    var chordVKs: [5]i32 = [_]i32{0} ** 5;
    var chordLen: usize = 0;
    for (0..g_kbLen) |i| {
        const ekd = &g_kbData[i];
        if (!ekd.isReleased() and chordLen < 4) {
            chordVKs[chordLen] = g_kbVK[i];
            chordLen += 1;
        }
    }
    if (chordLen < 1 or chordLen > 4) return false;
    chordVKs[chordLen] = keyVK;
    chordLen += 1;
    sortSmall5(&chordVKs, chordLen);
    const ck = chordKeyFromSorted(chordVKs[0..chordLen]);
    const chord = chordGetFast(ck) orelse return false;
    return chord.keyCount == @as(u8, @intCast(chordLen)) and
        (chord.kind == @intFromEnum(ChordHotKind.internal) or
            chord.kind == @intFromEnum(ChordHotKind.external));
}
inline fn chordRuntimePossibleForPair(aVK: i32, bVK: i32) bool {
    if ((!g_hasAnyChord and !activeRuntimeChords().hasAny) or aVK == bVK) return false;
    const a: u64 = @intCast(aVK);
    const b: u64 = @intCast(bVK);
    const lo = if (a < b) a else b;
    const hi = if (a < b) b else a;
    const chord = chordGetFast(lo | (hi << 16)) orelse return false;
    return chord.keyCount == 2 and
        (chord.kind == @intFromEnum(ChordHotKind.internal) or
            chord.kind == @intFromEnum(ChordHotKind.external));
}

inline fn chordPrefixPairPossibleForIncoming(keyVK: i32) bool {
    if (keyVK < 0 or keyVK >= VK_COUNT) return false;
    const relation = &activeContextDerived().pairRelation;
    const incoming: usize = @intCast(keyVK);
    for (0..g_kbLen) |i| {
        const ekd = &g_kbData[i];
        if (ekd.isReleased()) continue;
        const held = g_kbVK[i];
        if (held < 0 or held >= VK_COUNT or held == keyVK) continue;
        if ((relation[@intCast(held)][incoming] & REL_CHORD_PREFIX) != 0) return true;
    }
    return false;
}

inline fn chordCandidateContainsAll(candidate: []const i32, small: []const i32) bool {
    for (small) |svk| {
        var found = false;
        for (candidate) |cvk| {
            if (cvk == svk) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

fn chordEntryVKs(entry: ChordHotEntry, out: *[5]i32) []const i32 {
    const count: usize = @intCast(entry.keyCount);
    if (count == 0 or count > 4) return out[0..0];
    var i: usize = 0;
    while (i < count) : (i += 1) {
        out[i] = @intCast((entry.key >> @as(u6, @intCast(i * 16))) & 0xFFFF);
    }
    return out[0..count];
}

inline fn chordEntryIsAction(entry: ChordHotEntry) bool {
    return entry.kind == @intFromEnum(ChordHotKind.internal) or
        entry.kind == @intFromEnum(ChordHotKind.external);
}

fn markChordPrefixPairsForEntry(entry: ChordHotEntry, relation: *[VK_COUNT][VK_COUNT]u8) void {
    if (entry.keyCount < 3 or entry.keyCount > 4 or !chordEntryIsAction(entry)) return;
    var members_buf: [5]i32 = [_]i32{0} ** 5;
    const members = chordEntryVKs(entry, &members_buf);
    var i: usize = 0;
    while (i < members.len) : (i += 1) {
        const a = members[i];
        if (a < 0 or a >= VK_COUNT) continue;
        var j = i + 1;
        while (j < members.len) : (j += 1) {
            const b = members[j];
            if (b < 0 or b >= VK_COUNT or a == b) continue;
            relation[@intCast(a)][@intCast(b)] |= REL_CHORD_PREFIX;
            relation[@intCast(b)][@intCast(a)] |= REL_CHORD_PREFIX;
        }
    }
}

inline fn chordHotHas4Superset(entry: ChordHotEntry) bool {
    return (entry.flags & CHORD_HOT_HAS_4_SUPERSET) != 0;
}

fn recomputeChordHotSupersetFlags(table: []ChordHotEntry) void {
    var small_buf: [5]i32 = [_]i32{0} ** 5;
    var big_buf: [5]i32 = [_]i32{0} ** 5;

    for (table) |*entry| {
        entry.flags &= ~CHORD_HOT_HAS_4_SUPERSET;
    }

    for (0..table.len) |i| {
        if (table[i].key == 0 or table[i].keyCount != 3 or !chordEntryIsAction(table[i])) continue;
        const small = chordEntryVKs(table[i], &small_buf);
        for (table) |entry4| {
            if (entry4.key == 0 or entry4.keyCount != 4 or !chordEntryIsAction(entry4)) continue;
            if (chordCandidateContainsAll(chordEntryVKs(entry4, &big_buf), small)) {
                table[i].flags |= CHORD_HOT_HAS_4_SUPERSET;
                break;
            }
        }
    }
}

fn fireExactChordFromKeyUp(keyVK: i32, chordMods: []const i32, currentTime: i64) bool {
    if (chordMods.len < 2 or chordMods.len > 4) return false;
    var chordVKs: [5]i32 = [_]i32{0} ** 5;
    var chordLen: usize = 0;
    for (chordMods) |v| {
        const kd = kbGet(v) orelse return false;
        if (kd.isReleased()) return false;
        chordVKs[chordLen] = v;
        chordLen += 1;
    }
    chordVKs[chordLen] = keyVK;
    chordLen += 1;
    sortSmall5(&chordVKs, chordLen);
    const ck = chordKeyFromSorted(chordVKs[0..chordLen]);
    const chord = chordGetFast(ck) orelse return false;
    if (chord.keyCount != @as(u8, @intCast(chordLen))) return false;
    if (!chordFireAllowed(chord.keyCount, currentTime)) return false;
    const externalNameRef: ?*const [KN_LEN]u16 = if (chord.kind == @intFromEnum(ChordHotKind.external))
        cachedNameFromVK(keyVK) orelse return false
    else
        null;
    for (chordMods) |qvk| cancelKeyTimers(qvk);
    cancelKeyTimers(keyVK);
    for (chordMods) |qvk| {
        remove_active_virtual_modifier(qvk);
        if (kbGet(qvk)) |kd| {
            kd.sf(FLAG_COMBO_TRIG | FLAG_MOD_TRIG);
            kd.cf(FLAG_MOD_ACT | FLAG_CHORD_PENDING);
            kbMarkComboRepeat(qvk, kd);
            kd.actionType = .modifier_used;
        }
    }
    if (chord.kind == @intFromEnum(ChordHotKind.internal)) {
        sendKeyDirect(chord.targetVK, chord.modMask);
        queueCallbackEmpty(-4, 4);
        return true;
    }
    if (chord.kind == @intFromEnum(ChordHotKind.external)) {
        queueCallback(chord.callbackId, externalNameRef.?, @ptrCast(&[_:0]u16{0}), 5);
        return true;
    }
    return false;
}

fn fireExactHeldChordFromKeyUp(keyVK: i32, currentTime: i64) bool {
    var chordMods: [4]i32 = [_]i32{0} ** 4;
    var chordCount: usize = 0;
    for (0..g_kbLen) |i| {
        const evk = g_kbVK[i];
        if (evk == keyVK) continue;
        const ekd = &g_kbData[i];
        if (ekd.isReleased()) continue;
        if (chordCount >= chordMods.len) return false;
        chordMods[chordCount] = evk;
        chordCount += 1;
    }
    if (chordCount < 2) return false;
    return fireExactChordFromKeyUp(keyVK, chordMods[0..chordCount], currentTime);
}

inline fn pairRelationshipPossible(aVK: i32, bVK: i32) bool {
    return activeContextDerived().pairRelation[@intCast(aVK)][@intCast(bVK)] != 0;
}
inline fn durationFastEnough(now: i64, down: i64) bool {
    return (now - down) < g_SingleKeyHoldThreshold;
}
// True when at least one currently-held buffered key has been down past the
// tap/roll window.  A registered chord fires from an unordered VK set, so a fast
// typing roll whose letters happen to overlap can match one by accident: the
// "a-s-e" tail of "please" is exactly the a+s+e chord set.  A deliberate chord
// always holds its anchor keys, so requiring one held anchor separates the two
// without consulting the trigger key or its order.  Uses the same threshold as
// the clean-modifier roll check so both paths agree on what "held" means.
inline fn chordAnchorHeldPastRollWindow(currentTime: i64) bool {
    for (0..g_kbLen) |i| {
        const ekd = &g_kbData[i];
        if (ekd.isReleased()) continue;
        if (!durationFastEnough(currentTime, ekd.downTime)) return true;
    }
    return false;
}
// Three-or-more-key chords are intentional gestures when their anchors did not
// start inside typing quiet mode. A pending explicit chord key is different:
// it was buffered only because a smaller exact chord was waiting to see whether
// a larger registered chord would arrive, so its quiet bit must not veto that
// larger chord.
inline fn chordHeldAnchorsStartedOutsideTyping() bool {
    var sawHeldAnchor = false;
    for (0..g_kbLen) |i| {
        const ekd = &g_kbData[i];
        if (ekd.isReleased()) continue;
        sawHeldAnchor = true;
        if (ekd.inQuietPeriod() and !ekd.chordPending()) return false;
    }
    return sawHeldAnchor;
}

inline fn chordFireAllowed(chordKeyCount: u8, currentTime: i64) bool {
    if (chordKeyCount >= 3) return chordHeldAnchorsStartedOutsideTyping();
    return chordAnchorHeldPastRollWindow(currentTime);
}

fn clearPendingChordRecordOnly() void {
    g_pendingChord = .{};
}

fn chordKeyVKAt(key: u64, index: usize) i32 {
    if (index >= 4) return 0;
    return @intCast((key >> @as(u6, @intCast(index * 16))) & 0xFFFF);
}

fn pendingChordMembers(out: *[4]i32) []const i32 {
    if (!g_pendingChord.active or g_pendingChord.key == 0) return out[0..0];
    var len: usize = 0;
    while (len < 4) : (len += 1) {
        const vk = chordKeyVKAt(g_pendingChord.key, len);
        if (vk == 0) break;
        out[len] = vk;
    }
    return out[0..len];
}

fn pendingChordContains(keyVK: i32) bool {
    if (!g_pendingChord.active) return false;
    var members: [4]i32 = [_]i32{0} ** 4;
    const slice = pendingChordMembers(&members);
    var i: usize = 0;
    while (i < slice.len) : (i += 1) {
        if (slice[i] == keyVK) return true;
    }
    return false;
}

fn clearPendingChord() void {
    if (!g_pendingChord.active) return;
    var members: [4]i32 = [_]i32{0} ** 4;
    const slice = pendingChordMembers(&members);
    var i: usize = 0;
    while (i < slice.len) : (i += 1) {
        if (kbGet(slice[i])) |kd| kd.cf(FLAG_CHORD_PENDING);
    }
    clearPendingChordRecordOnly();
    rebuildUnreleasedModifierCounters();
}

fn storePendingChord(
    chordKey: u64,
    members: []const i32,
    triggerVK: i32,
    currentTime: i64,
    triggerIsVirtualMod: bool,
    inQuietPeriod: bool,
) void {
    clearPendingChord();
    if (members.len < 3 or members.len > 4) return;

    var i: usize = 0;
    while (i < members.len) : (i += 1) {
        const vk = members[i];
        cancelKeyTimers(vk);
        remove_active_virtual_modifier(vk);
        if (kbGet(vk)) |kd| {
            kd.sf(FLAG_CHORD_PENDING);
        } else if (vk == triggerVK) {
            var nd = KeyData{};
            nd.downTime = currentTime;
            nd.bf(RUNTIME_CURRENT_VK_IS_ACTIVE_MODIFIER, triggerIsVirtualMod);
            nd.bf(FLAG_QUIET, inQuietPeriod);
            nd.sf(FLAG_CHORD_PENDING);
            kbPut(vk, nd);
            ordAppend(vk);
            if (g_ordLen > @as(usize, @intCast(g_MaxBufferSize))) {
                const f = ordAt(0);
                ordRemoveFirst();
                _ = kbRemove(f);
            }
        }
    }
    g_pendingChord.active = true;
    g_pendingChord.key = chordKey;
    g_pendingChord.triggerVK = triggerVK;
    rebuildUnreleasedModifierCounters();
}

fn fireChordEntryFromMembers(chord: ChordHotEntry, members: []const i32, triggerVK: i32) bool {
    if (!chordEntryIsAction(chord)) return false;
    const externalNameRef: ?*const [KN_LEN]u16 = if (chord.kind == @intFromEnum(ChordHotKind.external))
        cachedNameFromVK(triggerVK) orelse return false
    else
        null;

    for (members) |vk| cancelKeyTimers(vk);
    for (members) |vk| {
        remove_active_virtual_modifier(vk);
        if (kbGet(vk)) |kd| {
            kd.sf(FLAG_COMBO_TRIG | FLAG_MOD_TRIG);
            kd.cf(FLAG_MOD_ACT | FLAG_CHORD_PENDING);
            kbMarkComboRepeat(vk, kd);
            kd.actionType = .modifier_used;
        }
    }

    if (chord.kind == @intFromEnum(ChordHotKind.internal)) {
        sendKeyDirect(chord.targetVK, chord.modMask);
        queueCallbackEmpty(-4, 4);
        return true;
    }
    if (chord.kind == @intFromEnum(ChordHotKind.external)) {
        queueCallback(chord.callbackId, externalNameRef.?, @ptrCast(&[_:0]u16{0}), 5);
        return true;
    }
    return false;
}

fn firePendingChord() bool {
    if (!g_pendingChord.active) return false;
    const chord = chordGetFast(g_pendingChord.key) orelse {
        clearPendingChord();
        return false;
    };
    const triggerVK = g_pendingChord.triggerVK;
    var members: [4]i32 = [_]i32{0} ** 4;
    const ok = fireChordEntryFromMembers(chord, pendingChordMembers(&members), triggerVK);
    if (ok) {
        clearPendingChordRecordOnly();
        rebuildUnreleasedModifierCounters();
    } else {
        clearPendingChord();
    }
    return ok;
}

fn resolvePendingChordOnKeyDown(keyVK: i32, currentTime: i64, isVirtualModKey: bool, inQuietPeriod: bool) bool {
    if (!g_pendingChord.active) return false;
    if (pendingChordContains(keyVK)) return true;

    var pending_members: [4]i32 = [_]i32{0} ** 4;
    const pending_slice = pendingChordMembers(&pending_members);
    if (pending_slice.len == 3) {
        var members: [4]i32 = pending_members;
        members[3] = keyVK;
        sortSmall5(&members, 4);
        const ck4 = chordKeyFromSorted(members[0..4]);
        if (chordGetFast(ck4)) |chord4| {
            if (chord4.keyCount == 4 and chordEntryIsAction(chord4) and chordFireAllowed(4, currentTime)) {
                if (!kbContains(keyVK)) {
                    var nd = KeyData{};
                    nd.downTime = currentTime;
                    nd.bf(RUNTIME_CURRENT_VK_IS_ACTIVE_MODIFIER, isVirtualModKey);
                    nd.bf(FLAG_QUIET, inQuietPeriod);
                    nd.sf(FLAG_CHORD_PENDING);
                    kbPut(keyVK, nd);
                    ordAppend(keyVK);
                    if (g_ordLen > @as(usize, @intCast(g_MaxBufferSize))) {
                        const f = ordAt(0);
                        ordRemoveFirst();
                        _ = kbRemove(f);
                    }
                }
                const ok = fireChordEntryFromMembers(chord4, members[0..4], keyVK);
                if (ok) {
                    clearPendingChordRecordOnly();
                    rebuildUnreleasedModifierCounters();
                } else {
                    clearPendingChord();
                }
                return ok;
            }
        }
    }

    _ = firePendingChord();
    return false;
}
// ============================================================================
fn bufferKeyDown(keyVK: i32) void {
    // SECTION 1: Input validation
    if (keyVK <= 0 or keyVK >= VK_COUNT) {
        return;
    }

    const prof_start = profStart();
    var prof_time = prof_start; // mutable copy
    defer profRecord(&g_profiling.keyDownProcessing, prof_time);

    // SECTION 2: Load per-key gate metadata
    const vki: usize = @intCast(keyVK);
    // A new physical press starts a new hold-delivery lifetime.  Do not reset
    // this for autorepeat/re-entrant key-downs while the key is still buffered.
    if (kbGet(keyVK) == null) g_holdCallbackQueued[vki] = false;
    const gate = &activeContextDerived().gate[vki];
    const kdPlan = gate.kdPlan;
    var hotFlags = g_hotFlags;

    // Only decode the bits needed before the early keydown fast paths.
    const kdDoubleTap = (kdPlan & KDP_DOUBLE_TAP) != 0;
    const hotRecentKeyUp = (hotFlags & HF_RECENT_KEYUP) != 0;

    const kdAction = gate.kdAction;
    if (pendingRollActive() and (pendingRollContains(keyVK) or kdAction == .phys_mod or g_any_physical_modifiers_active)) {
        pendingRollMaterialize();
    }
    if (pendingSoloActive() and (g_pendingSoloVK == keyVK or kdAction == .phys_mod or g_any_physical_modifiers_active)) {
        pendingSoloMaterialize();
    }

    if (kdAction == .phys_mod) {
        const bit: u16 = @intCast(g_vk_is_physical_modifier[vki]);
        if (bit != 0) {
            prof_time = 0; // stop timing
            _ = apply_physical_modifier_event(keyVK, true);
            return;
        }
    }

    if (g_any_physical_modifiers_active) {
        prof_time = 0; // stop timing
        sendKeyDirect(keyVK, compute_modifiers_to_send());
        return;
    }

    const currentTime = timeFromProfStart(prof_start);
    if ((hotFlags & HF_TYPING) != 0 and currentTime >= g_typingModeUntil) {
        g_hotFlags &= ~HF_TYPING;
        hotFlags &= ~HF_TYPING;
        rfClear(RF_TYPING); // FSM-lite
    }
    const inQuietPeriod = (hotFlags & HF_TYPING) != 0;
    if (resolvePendingChordOnKeyDown(keyVK, currentTime, (kdPlan & KDP_HAS_VIRTUAL_MODIFIER_ROLE) != 0, inQuietPeriod)) {
        return;
    }
    // The second press of a double-tap always lands inside the typing quiet
    // window opened by the first tap, and it always arrives on an empty buffer.
    // That is exactly the shape the quiet fast path claims, so without this the
    // fast path returns before the repeat-arming check below and double-tap
    // repeat can never fire.  The test is per-VK, so ordinary typing rolls keep
    // the fast path: only a key that already has a live recent-key-up entry
    // takes the longer route.
    const doubleTapArmed = kdDoubleTap and hotRecentKeyUp and g_kutTime[vki] != 0;
    if (!doubleTapArmed and (g_runtimeFlags & RB_KEYDOWN_QUIET_EMPTY_FAST) == 0) {
        switch (kdAction) {
            .strict_plain_fast => {
                if ((kdPlan & KDP_SKIP_ALL_BUFFER_DOWN) != 0) {
                    g_lastKeyTime = currentTime;
                    g_typingModeUntil = currentTime + g_QuietPeriodDuration;
                    g_hotFlags |= HF_TYPING;
                    rfSet(RF_TYPING); // FSM-lite
                    if (kdDoubleTap) kdtPut(keyVK, currentTime);
                    pendingSoloStore(keyVK, currentTime, MOD_NONE, inQuietPeriod, kdDoubleTap);
                    return;
                }
            },
            .taplike_primary_candidate => {
                if ((kdPlan & KDP_PRIMARY_TAPLIKE_DOWN) != 0) {
                    g_lastKeyTime = currentTime;
                    g_typingModeUntil = currentTime + g_QuietPeriodDuration;
                    g_hotFlags |= HF_TYPING;
                    rfSet(RF_TYPING); // FSM-lite
                    if (kdDoubleTap) kdtPut(keyVK, currentTime);
                    pendingSoloStore(keyVK, currentTime, MOD_NONE, inQuietPeriod, kdDoubleTap);
                    return;
                }
            },
            else => {},
        }
    }
    if (pendingRollActive()) {
        const incomingIsModRoll = (kdPlan & KDP_HAS_VIRTUAL_MODIFIER_ROLE) != 0;
        if (!incomingIsModRoll and
            (g_runtimeFlags & RB_PENDING_PAIR_CLEAN) == 0 and
            kdAction != .sys_mod and
            (kdPlan & (KDP_PHYS_MOD | KDP_SYS_MOD)) == 0 and
            pendingRollCanAppend(keyVK))
        {
            g_typingModeUntil = currentTime + g_QuietPeriodDuration;
            g_hotFlags |= HF_TYPING;
            rfSet(RF_TYPING);
            timerClear();

            var rollFlags: u16 = 0;
            if (inQuietPeriod) rollFlags |= PSF_QUIET;
            if (kdDoubleTap) rollFlags |= PSF_DOUBLE_TAP;
            pendingRollAppend(keyVK, currentTime, rollFlags);
            if (kdDoubleTap) kdtPut(keyVK, currentTime);
            g_lastKeyTime = currentTime;
            return;
        }
        pendingRollMaterialize();
    }
    if (pendingSoloActive()) {
        const pendingVK = g_pendingSoloVK;
        const pendingFlags = g_pendingSoloFlags;
        const incomingProps = gate.props;
        const pendingIsMod = (pendingFlags & PSF_IS_MOD) != 0;
        const incomingIsMod = (incomingProps & KP_HAS_VIRTUAL_MODIFIER_ROLE) != 0;
        if ((pendingFlags & PSF_IS_MOD) == 0 and
            !incomingIsMod and
            (g_runtimeFlags & RB_PENDING_PAIR_CLEAN) == 0 and
            kdAction != .sys_mod and
            (kdPlan & (KDP_PHYS_MOD | KDP_SYS_MOD)) == 0 and
            activeContextDerived().pairRelation[@intCast(pendingVK)][vki] == 0)
        {
            g_typingModeUntil = currentTime + g_QuietPeriodDuration;
            g_hotFlags |= HF_TYPING;
            rfSet(RF_TYPING);
            timerClear();

            const pendingDown = g_pendingSoloDownTime;
            pendingSoloDeactivate();
            var incomingFlags: u16 = 0;
            if (inQuietPeriod) incomingFlags |= PSF_QUIET;
            if (kdDoubleTap) incomingFlags |= PSF_DOUBLE_TAP;
            pendingRollStore(pendingVK, pendingDown, pendingFlags, keyVK, currentTime, incomingFlags);
            if (kdDoubleTap) kdtPut(keyVK, currentTime);
            g_lastKeyTime = currentTime;
            return;
        }
        if (pendingIsMod and
            (g_runtimeFlags & RB_PENDING_PAIR_CLEAN) == 0 and
            kdAction != .sys_mod and
            (kdPlan & (KDP_PHYS_MOD | KDP_SYS_MOD)) == 0 and
            durationFastEnough(currentTime, g_pendingSoloDownTime) and
            (!incomingIsMod or pendingFlagsModType(pendingFlags) != modTypeFromKdPlan(kdPlan)) and
            activeContextDerived().pairRelation[@intCast(pendingVK)][vki] == 0)
        {
            g_typingModeUntil = currentTime + g_QuietPeriodDuration;
            g_hotFlags |= HF_TYPING;
            rfSet(RF_TYPING);
            timerClear();

            var pendingModKd = KeyData{};
            pendingModKd.downTime = g_pendingSoloDownTime;
            pendingModKd.sf(FLAG_INTERFERING);
            pendingModKd.bf(FLAG_QUIET, (pendingFlags & PSF_QUIET) != 0);
            pendingModKd.sf(RUNTIME_CURRENT_VK_IS_ACTIVE_MODIFIER);
            pendingSoloDeactivate();
            kbPut(pendingVK, pendingModKd);
            ordAppend(pendingVK);
            g_unrelModCount += 1;
            g_cleanUnrelModCount = 0;
            rfSet(RF_UNREL_MODS);
            rfClear(RF_CLEAN_UNREL_MODS);

            var incomingModRollKd = KeyData{};
            incomingModRollKd.downTime = currentTime;
            incomingModRollKd.sf(FLAG_INTERFERING);
            incomingModRollKd.bf(FLAG_QUIET, inQuietPeriod);
            incomingModRollKd.bf(RUNTIME_CURRENT_VK_IS_ACTIVE_MODIFIER, incomingIsMod);
            kbPut(keyVK, incomingModRollKd);
            ordAppend(keyVK);
            if (g_ordLen > @as(usize, @intCast(g_MaxBufferSize))) {
                const f = ordAt(0);
                ordRemoveFirst();
                _ = kbRemove(f);
            }
            if (incomingIsMod) {
                g_unrelModCount += 1;
                rfSet(RF_UNREL_MODS);
            }
            if (kdDoubleTap) kdtPut(keyVK, currentTime);
            g_lastKeyTime = currentTime;
            return;
        }
        if ((activeContextDerived().pairRelation[@intCast(pendingVK)][vki] & REL_INSTANT) != 0 and
            instantPrimaryAllowedForSecondary(pendingVK, keyVK))
        {
            if (kdDoubleTap) kdtPut(keyVK, currentTime);
            g_lastKeyTime = currentTime;
            pendingSoloMaterialize();
            const pkName = g_keyNamePtr[@intCast(pendingVK)] orelse return;
            triggerInstantComboVK(pendingVK, keyVK, pkName, currentTime);
            return;
        }
        pendingSoloMaterialize();
    }

    const kutTimeSnap: i64 = g_kutTime[vki];
    if (doubleTapArmed) {
        if ((currentTime - kutTimeSnap) < g_DoubleTapThreshold) {
            if ((g_runtimeFlags & (RF_UNREL_MODS | RF_UNREL_KEYS)) == 0) {
                // This branch consumes the key-down and returns, so nothing
                // downstream will report the keystroke to the hotstring engine.
                hotstringRecordConsumedKeyDown(keyVK);
                kutRemove(keyVK);
                const kd185_start = profStartSect();
                stopRepeatThread();
                profSpan(185, kd185_start); // kd185 span: early repeat stopRepeatThread
                const kd186_start = profStartSect();
                resetRepeatLocalState();
                profSpan(186, kd186_start); // kd186 span: early resetRepeatLocalState
                const kd187_start = profStartSect();
                // Persistent repeat worker owns wake/timer handles; keydown only verifies readiness.
                profSpan(187, kd187_start); // kd187 span: early repeat event create/reset
                const kd188_start = profStartSect();
                const repeat_started = startRepeatFast(keyVK, currentTime);
                profSpan(188, kd188_start); // kd188 span: early repeat startRepeatFast
                if (!repeat_started) return;
                sendKeyDirect(keyVK, 0);
                return;
            }
        } else {
            kutRemove(keyVK);
        }
    }

    switch (kdAction) {
        .strict_plain_fast => {
            const kdSkipAllBufferDown = (kdPlan & KDP_SKIP_ALL_BUFFER_DOWN) != 0;
            if (kdSkipAllBufferDown and
                (g_runtimeFlags & RB_KEYDOWN_EMPTY_FAST) == 0)
            {
                g_lastKeyTime = currentTime;
                g_typingModeUntil = currentTime + g_QuietPeriodDuration;
                g_hotFlags |= HF_TYPING;
                rfSet(RF_TYPING); // FSM-lite
                if (kdDoubleTap) kdtPut(keyVK, currentTime);
                pendingSoloStore(keyVK, currentTime, MOD_NONE, false, kdDoubleTap);
                return;
            }

            if (kdSkipAllBufferDown and
                inQuietPeriod and
                (g_runtimeFlags & RF_KB_NONEMPTY) != 0 and
                g_kbIdx[vki] < 0 and
                (g_runtimeFlags & RB_KEYDOWN_ROLLING_FAST) == 0)
            {
                g_typingModeUntil = currentTime + g_QuietPeriodDuration;
                g_hotFlags |= HF_TYPING;
                rfSet(RF_TYPING); // FSM-lite
                g_lastKeyTime = currentTime;
                for (0..g_kbLen) |i| {
                    const ekd = &g_kbData[i];
                    ekd.sf(FLAG_INTERFERING);
                    ekd.sameModTidHash = 0;
                    ekd.tidCount = 0;
                }
                var ndPlainRoll = KeyData{};
                ndPlainRoll.downTime = currentTime;
                ndPlainRoll.sf(FLAG_INTERFERING | FLAG_QUIET);
                kbPut(keyVK, ndPlainRoll);
                ordAppend(keyVK);
                if (g_ordLen > @as(usize, @intCast(g_MaxBufferSize))) {
                    const f = ordAt(0);
                    ordRemoveFirst();
                    _ = kbRemove(f);
                }
                if (kdDoubleTap) kdtPut(keyVK, currentTime);

                return;
            }
        },
        .taplike_primary_candidate => {
            const kdPrimaryTaplikeDown = (kdPlan & KDP_PRIMARY_TAPLIKE_DOWN) != 0;
            if (kdPrimaryTaplikeDown and
                (g_runtimeFlags & RB_KEYDOWN_EMPTY_FAST) == 0)
            {
                g_lastKeyTime = currentTime;
                g_typingModeUntil = currentTime + g_QuietPeriodDuration;
                g_hotFlags |= HF_TYPING;
                rfSet(RF_TYPING); // FSM-lite
                if (kdDoubleTap) kdtPut(keyVK, currentTime);
                pendingSoloStore(keyVK, currentTime, MOD_NONE, false, kdDoubleTap);
                return;
            }

            if (kdPrimaryTaplikeDown and
                inQuietPeriod and
                (g_runtimeFlags & RF_KB_NONEMPTY) != 0 and
                g_kbIdx[vki] < 0 and
                (g_runtimeFlags & RB_KEYDOWN_ROLLING_FAST) == 0)
            {
                g_typingModeUntil = currentTime + g_QuietPeriodDuration;
                g_hotFlags |= HF_TYPING;
                rfSet(RF_TYPING); // FSM-lite
                g_lastKeyTime = currentTime;
                for (0..g_kbLen) |i| {
                    const ekd = &g_kbData[i];
                    ekd.sf(FLAG_INTERFERING);
                    ekd.sameModTidHash = 0;
                    ekd.tidCount = 0;
                }
                var ndPrimaryRoll = KeyData{};
                ndPrimaryRoll.downTime = currentTime;
                ndPrimaryRoll.sf(FLAG_INTERFERING | FLAG_QUIET);
                kbPut(keyVK, ndPrimaryRoll);
                ordAppend(keyVK);
                if (g_ordLen > @as(usize, @intCast(g_MaxBufferSize))) {
                    const f = ordAt(0);
                    ordRemoveFirst();
                    _ = kbRemove(f);
                }
                if (kdDoubleTap) kdtPut(keyVK, currentTime);

                return;
            }
        },
        else => {},
    }

    if ((g_runtimeFlags & RB_SOLO_UNRESOLVED) == 0 and
        (kdPlan & (KDP_PHYS_MOD | KDP_SYS_MOD)) == 0)
    {
        if (kdDoubleTap) kdtPut(keyVK, currentTime);
        g_lastKeyTime = currentTime;

        pendingSoloStore(keyVK, currentTime, modTypeFromKdPlan(kdPlan), inQuietPeriod, kdDoubleTap);
        return;
    }

    if (g_kbLen > 0) {
        if (kbGet(keyVK)) |ex| {
            if (ex.isReleased()) {
                _ = kbRemove(keyVK);
                removeFromKeyOrder(keyVK);
            }
        }
    }
    if (kdDoubleTap and
        hotRecentKeyUp and g_unrelModCount == 0 and
        kutTimeSnap != 0)
    {
        const upTime = kutTimeSnap;
        const otherHeld = g_unreleasedKeyCount != 0;
        if (currentTime - upTime < g_DoubleTapThreshold and !otherHeld) {
            kutRemove(keyVK);
            const kd190_start = profStartSect();
            stopRepeatThread();
            profSpan(190, kd190_start); // kd190 span: solo repeat stopRepeatThread
            const kd191_start = profStartSect();
            resetRepeatLocalState();
            profSpan(191, kd191_start); // kd191 span: solo repeat resetRepeatLocalState
            const kd192_start = profStartSect();
            // Persistent repeat worker owns wake/timer handles; keydown only verifies readiness.
            profSpan(192, kd192_start); // kd192 span: solo repeat event create/reset
            const kd193_start = profStartSect();
            const repeat_started = startRepeatFast(keyVK, currentTime);
            profSpan(193, kd193_start); // kd193 span: solo repeat startRepeatFast
            if (!repeat_started) {
                kutRemove(keyVK);
                return;
            }
            sendKeyDirect(keyVK, 0);
            if ((kdPlan & KDP_HAS_VIRTUAL_MODIFIER_ROLE) != 0 and g_unrelModCount > 0) {
                g_unrelModCount -= 1;
                rfSetIf(RF_UNREL_MODS, g_unrelModCount != 0);
            }
            _ = kbRemove(keyVK);
            removeFromKeyOrder(keyVK);
            return;
        }
        kutRemove(keyVK);
    }
    if (kdDoubleTap) kdtPut(keyVK, currentTime);
    g_lastKeyTime = currentTime;

    const hotIgnoredKeys = (hotFlags & HF_IGNORED_KEYS) != 0;
    const kdModContam = (kdPlan & KDP_MOD_CONTAM) != 0;
    const kdInstantSecondary = (kdPlan & KDP_INSTANT_SECONDARY) != 0;
    const kdComboSecondary = (kdPlan & KDP_COMBO_SECONDARY) != 0;
    const kdChord = (kdPlan & KDP_CHORD) != 0;
    const kdIntentionalChord = (kdPlan & KDP_INTENTIONAL_CHORD) != 0;
    const kdHeldMod = (kdPlan & KDP_HELD_MOD) != 0;
    const kdSameMod = (kdPlan & KDP_SAME_MOD) != 0;

    if (kdModContam and g_unrelModCount > 0) {
        for (0..g_kbLen) |_csi| {
            const _ekd = &g_kbData[_csi];
            if (_ekd.isRuntimeModifier() and !_ekd.isReleased() and
                _ekd.actionType == .undecided and
                g_kbVK[_csi] != keyVK)
            {
                _ekd.sf(FLAG_CONTAMINATED);
            }
        }
    }
    if (hotIgnoredKeys) {
        @branchHint(.unlikely);
        if (keyVK >= 0 and keyVK < 256 and g_keyVKIgnored[@intCast(keyVK)]) return;
    }
    if (kdAction == .sys_mod) {
        const keySysBit: i32 = @intCast(g_vk_windows_facing_modifiers[vki]);
        if (keySysBit != 0) {
            @branchHint(.unlikely);
            g_active_physical_and_windows_facing_modifiers |= keySysBit;
            rfSet(RF_SYS_MODS); // FSM-lite
            return;
        }
    }
    if (g_active_physical_and_windows_facing_modifiers > 0) {
        @branchHint(.unlikely);
        return;
    }
    if (kdSameMod or kdHeldMod) rebuildUnreleasedModifierCounters();
    const keyIndex = g_kbIdx[vki];
    const keyExists = keyIndex >= 0;
    if (keyExists) {
        const existingIdx: usize = @intCast(keyIndex);
        if (!g_kbData[existingIdx].inComboRepeatMode()) {
            return;
        }
    }

    const unrelMods = g_unrelModCount;
    const scanFlags = gate.scanFlags;
    const runInstantScan =
        (scanFlags & KFS_KD_RELATION_CHECK) != 0 and
        kdInstantSecondary and
        (g_runtimeFlags & RF_ACTIVE_INSTANT_PRIMARY) != 0 and
        hasActiveInstantPrimaryForSecondary(keyVK);
    const runComboScan =
        (scanFlags & KFS_KD_RELATION_CHECK) != 0 and
        kdComboSecondary and
        (g_runtimeFlags & RF_ACTIVE_COMBO_PRIMARY) != 0 and
        hasActiveComboPrimaryForSecondary(keyVK);
    const cleanUnrelMods: i32 = g_cleanUnrelModCount;
    const hasNonModKeys =
        g_unreleasedNonModCount != 0 and
        cleanUnrelMods >= 2 and
        kdIntentionalChord and
        (scanFlags & KFS_KD_INTENTIONAL_CHORD) != 0;
    prepareStructuralIncomingChordContext(keyVK);
    if (runInstantScan) {
        const pkVK = firstUnreleasedInstantPrimaryForSecondary(keyVK);
        if (pkVK != 0) {
            const pkName = cachedNameFromVK(pkVK) orelse return;
            triggerInstantComboVK(pkVK, keyVK, pkName, currentTime);
            return;
        }
    }
    const isModKey = (kdPlan & (KDP_PHYS_MOD | KDP_SYS_MOD)) != 0; // physical/system only: virtual mods must NOT block chord eligibility
    const isVirtualModKey = (kdPlan & KDP_HAS_VIRTUAL_MODIFIER_ROLE) != 0;
    const modType: i8 = modTypeFromKdPlan(kdPlan);
    const intentionalChordRuntimePossible =
        kdIntentionalChord and
        cleanUnrelMods >= 2 and
        !hasNonModKeys and
        !inQuietPeriod and
        !isVirtualModKey;
    const exactChordRuntimePossible =
        (scanFlags & KFS_KD_CHORD_CHECK) != 0 and
        kdChord and
        (g_hasAnyChord or activeRuntimeChords().hasAny) and
        !keyExists and
        chordRuntimePossibleForIncoming(keyVK);
    const chordPrefixPairPossible =
        (scanFlags & KFS_KD_CHORD_CHECK) != 0 and
        kdChord and
        (g_hasAnyChord or activeRuntimeChords().hasAny) and
        !keyExists and
        chordPrefixPairPossibleForIncoming(keyVK);
    const overlapBaseEligible =
        g_active_virtual_modifier_count == 0 and
        g_kbLen != 0 and
        unrelMods == 0 and
        !isModKey and
        !keyExists and
        !intentionalChordRuntimePossible and
        !runComboScan and
        !runInstantScan;
    const chordRuntimePossible =
        overlapBaseEligible and exactChordRuntimePossible;
    const shouldRunChordScan =
        (scanFlags & KFS_KD_CHORD_CHECK) != 0 and
        kdChord and
        (g_hasAnyChord or activeRuntimeChords().hasAny) and
        (keyExists or chordRuntimePossible or
            (!overlapBaseEligible and exactChordRuntimePossible));
    if (overlapBaseEligible and !chordRuntimePossible) {
        g_typingModeUntil = currentTime + g_QuietPeriodDuration;
        g_hotFlags |= HF_TYPING;
        rfSet(RF_TYPING); // FSM-lite
        timerClear();
        if (g_kbLen == 1) {
            const ekd = &g_kbData[0];
            ekd.sf(FLAG_INTERFERING);
            ekd.sameModTidHash = 0;
            ekd.tidCount = 0;
        } else {
            for (0..g_kbLen) |i| {
                const ekd = &g_kbData[i];
                ekd.sf(FLAG_INTERFERING);
                ekd.sameModTidHash = 0;
                ekd.tidCount = 0;
            }
        }
        var ndOverlapRoll = KeyData{};
        ndOverlapRoll.downTime = currentTime;
        ndOverlapRoll.sf(FLAG_INTERFERING);
        ndOverlapRoll.bf(FLAG_QUIET, inQuietPeriod);
        kbPut(keyVK, ndOverlapRoll);
        ordAppend(keyVK);
        if (g_ordLen > @as(usize, @intCast(g_MaxBufferSize))) {
            const f = ordAt(0);
            ordRemoveFirst();
            _ = kbRemove(f);
        }
        return;
    }

    if (g_cleanUnrelModCount > 0 and
        g_unrelModCount == g_cleanUnrelModCount and
        !keyExists and
        g_active_virtual_modifier_count == 0 and
        !intentionalChordRuntimePossible and
        !runComboScan and
        !runInstantScan and
        !exactChordRuntimePossible and
        !chordPrefixPairPossible)
    {
        var allCleanModsUnderThreshold = true;
        if (g_cleanUnrelModCount == 1) {
            var foundCleanMod = false;
            for (0..g_kbLen) |i| {
                const ekd = &g_kbData[i];
                if (ekd.isRuntimeModifier() and !ekd.isReleased() and !ekd.hasInterferingKeys()) {
                    foundCleanMod = true;
                    // A same-type virtual-mod partner is not ordinary rollover typing.
                    // Let it reach the dedicated SAME-MODIFIER section below, which
                    // owns prospective threshold resolution and release-order fallback.
                    if (isVirtualModKey and activeContextDerived().keyModType[@intCast(g_kbVK[i])] == modType) {
                        allCleanModsUnderThreshold = false;
                    } else if ((currentTime - ekd.downTime) >= g_SingleKeyHoldThreshold) {
                        allCleanModsUnderThreshold = false;
                    }
                    break;
                }
            }
            if (!foundCleanMod) allCleanModsUnderThreshold = false;
        } else {
            for (0..g_kbLen) |i| {
                const ekd = &g_kbData[i];
                if (ekd.isRuntimeModifier() and !ekd.isReleased() and !ekd.hasInterferingKeys()) {
                    if (isVirtualModKey and activeContextDerived().keyModType[@intCast(g_kbVK[i])] == modType) {
                        allCleanModsUnderThreshold = false;
                        break;
                    }
                    if ((currentTime - ekd.downTime) >= g_SingleKeyHoldThreshold) {
                        allCleanModsUnderThreshold = false;
                        break;
                    }
                }
            }
        }
        if (allCleanModsUnderThreshold) {
            g_typingModeUntil = currentTime + g_QuietPeriodDuration;
            g_hotFlags |= HF_TYPING;
            rfSet(RF_TYPING); // FSM-lite
            timerClear();
            if (g_kbLen == 1) {
                const ekd = &g_kbData[0];
                ekd.sf(FLAG_INTERFERING);
                ekd.sameModTidHash = 0;
                ekd.tidCount = 0;
            } else {
                for (0..g_kbLen) |i| {
                    const ekd = &g_kbData[i];
                    ekd.sf(FLAG_INTERFERING);
                    ekd.sameModTidHash = 0;
                    ekd.tidCount = 0;
                }
            }
            g_cleanUnrelModCount = 0;
            rfClear(RF_CLEAN_UNREL_MODS); // FSM-lite
            var ndCleanModRoll = KeyData{};
            ndCleanModRoll.downTime = currentTime;
            ndCleanModRoll.sf(FLAG_INTERFERING);
            ndCleanModRoll.bf(FLAG_QUIET, inQuietPeriod);
            ndCleanModRoll.bf(RUNTIME_CURRENT_VK_IS_ACTIVE_MODIFIER, isVirtualModKey);
            kbPut(keyVK, ndCleanModRoll);
            ordAppend(keyVK);
            if (g_ordLen > @as(usize, @intCast(g_MaxBufferSize))) {
                const f = ordAt(0);
                ordRemoveFirst();
                _ = kbRemove(f);
            }
            if (isVirtualModKey) {
                g_unrelModCount += 1;
                rfSet(RF_UNREL_MODS); // FSM-lite
            }
            return;
        }
    }

    const keyNameRef = g_keyNamePtr[vki];

    if (shouldRunChordScan) {
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
            if (kbContains(keyVK)) {
                var chordVKsRepeat: [5]i32 = [_]i32{0} ** 5;
                var rLen: usize = 0;
                for (heldVKs[0..heldCount]) |v| {
                    chordVKsRepeat[rLen] = v;
                    rLen += 1;
                }
                if (rLen >= 2) {
                    sortSmall5(&chordVKsRepeat, rLen);
                    const ckRepeat = chordKeyFromSorted(chordVKsRepeat[0..rLen]);
                    if (chordGetFast(ckRepeat)) |chord| {
                        if (chord.kind == @intFromEnum(ChordHotKind.internal) and
                            chord.keyCount == @as(u8, @intCast(rLen)))
                        {
                            sendKeyDirect(chord.targetVK, chord.modMask);
                            return;
                        }
                    } else {}
                }
            }
            var chordVKs: [5]i32 = [_]i32{0} ** 5;
            var chordLen: usize = 0;
            for (heldVKs[0..heldCount]) |v| {
                chordVKs[chordLen] = v;
                chordLen += 1;
            }
            chordVKs[chordLen] = keyVK;
            chordLen += 1;
            sortSmall5(&chordVKs, chordLen);
            const ck = chordKeyFromSorted(chordVKs[0..chordLen]);
            if (chordGetFast(ck)) |chord| {
                const chordExact = chord.keyCount == @as(u8, @intCast(chordLen));
                const chordAllowed = chordFireAllowed(chord.keyCount, currentTime);
                if (!keyExists and
                    chordExact and
                    chord.keyCount == 3 and
                    chordHotHas4Superset(chord))
                {
                    storePendingChord(ck, chordVKs[0..chordLen], keyVK, currentTime, isVirtualModKey, inQuietPeriod);
                    return;
                }
                const chordCanFire =
                    chordExact and chordAllowed;
                if (chordCanFire and
                    chord.kind == @intFromEnum(ChordHotKind.internal))
                {
                    for (heldVKs[0..heldCount]) |v| cancelKeyTimers(v);
                    for (heldVKs[0..heldCount]) |v| {
                        remove_active_virtual_modifier(v);
                        if (kbGet(v)) |kd| {
                            kd.sf(FLAG_COMBO_TRIG | FLAG_MOD_TRIG);
                            kd.cf(FLAG_MOD_ACT | FLAG_CHORD_PENDING);
                            kbMarkComboRepeat(v, kd);
                            kd.actionType = .modifier_used;
                        }
                    }
                    var ndTrig = KeyData{};
                    ndTrig.downTime = currentTime;
                    ndTrig.sf(FLAG_COMBO_TRIG | FLAG_COMBO_RPT);
                    kbPut(keyVK, ndTrig);
                    ordAppend(keyVK);
                    sendKeyDirect(chord.targetVK, chord.modMask);
                    queueCallbackEmpty(-4, 4);
                    return;
                }
                if (chordCanFire and
                    chord.kind == @intFromEnum(ChordHotKind.external))
                {
                    if (kbContains(keyVK)) return;
                    const nameRef = keyNameRef orelse return;
                    for (heldVKs[0..heldCount]) |v| cancelKeyTimers(v);
                    for (heldVKs[0..heldCount]) |v| {
                        remove_active_virtual_modifier(v);
                        if (kbGet(v)) |kd| {
                            kd.sf(FLAG_COMBO_TRIG | FLAG_MOD_TRIG);
                            kd.cf(FLAG_MOD_ACT | FLAG_CHORD_PENDING);
                            kbMarkComboRepeat(v, kd);
                            kd.actionType = .modifier_used;
                        }
                    }
                    var ndTrig = KeyData{};
                    ndTrig.downTime = currentTime;
                    ndTrig.sf(FLAG_COMBO_TRIG | FLAG_COMBO_RPT);
                    kbPut(keyVK, ndTrig);
                    ordAppend(keyVK);
                    queueCallback(chord.callbackId, nameRef, @ptrCast(&[_:0]u16{0}), 5);
                    return;
                }
            } else {}
        }
    }

    if (kdIntentionalChord) {
        const heldAnchorsOutsideTyping = chordHeldAnchorsStartedOutsideTyping();
        if (cleanUnrelMods >= 2 and !isVirtualModKey and heldAnchorsOutsideTyping) {
            g_typingModeUntil = 0;
            g_hotFlags &= ~HF_TYPING;
            rfClear(RF_TYPING); // FSM-lite
        }
        if (cleanUnrelMods >= 2 and !hasNonModKeys and heldAnchorsOutsideTyping and (g_hotFlags & HF_TYPING) == 0 and !isVirtualModKey) {
            var heldModVKs: [5]i32 = [_]i32{0} ** 5;
            var hmCount: usize = 0;
            var modMask: u16 = 0;
            for (0..g_kbLen) |i| {
                const evk = g_kbVK[i];
                const ekd = &g_kbData[i];
                if (!ekd.isRuntimeModifier() or ekd.isReleased() or ekd.hasInterferingKeys()) continue;
                if (hmCount < 5) {
                    heldModVKs[hmCount] = evk;
                    hmCount += 1;
                }
                modMask |= @intCast(g_key_virtual_modifier_mask[@intCast(evk)]);
            }
            var isExternalChordPrefix = false;
            const runtime_chords = activeRuntimeChords();
            if ((g_hasExternalChords and g_extChordCacheLen > 0) or (runtime_chords.hasExternal and runtime_chords.extCacheLen > 0)) {
                for (g_extChordCache[0..g_extChordCacheLen]) |entry| {
                    if (@as(usize, entry.keyCount) <= hmCount) continue;
                    if ((entry.modMask & modMask) == modMask) {
                        isExternalChordPrefix = true;
                        break;
                    }
                }
                if (!isExternalChordPrefix) {
                    for (runtime_chords.extCache[0..runtime_chords.extCacheLen]) |entry| {
                        if (@as(usize, entry.keyCount) <= hmCount) continue;
                        if ((entry.modMask & modMask) == modMask) {
                            isExternalChordPrefix = true;
                            break;
                        }
                    }
                }
            }
            if (!isExternalChordPrefix) {
                var isSameModPartner = false;
                if (isModKey) {
                    for (0..g_kbLen) |i| {
                        if (g_kbData[i].isRuntimeModifier() and !g_kbData[i].isReleased() and
                            activeContextDerived().keyModType[@intCast(g_kbVK[i])] == modType)
                        {
                            isSameModPartner = true;
                            break;
                        }
                    }
                }
                if (!isModKey or isSameModPartner) {
                    for (0..g_kbLen) |i| {
                        const ekd = &g_kbData[i];
                        if (ekd.isRuntimeModifier() and !ekd.isReleased() and
                            !ekd.modifierActivated() and !ekd.hasInterferingKeys())
                            cancelKeyTimers(g_kbVK[i]);
                    }
                    if (!queueCompiledHotkeyIfMatched(keyVK, modMask, true)) {
                        sendKeyDirect(keyVK, modMask);
                        queueCallbackEmpty(-4, 4);
                    }
                    for (0..g_kbLen) |i| {
                        const ekd = &g_kbData[i];
                        if (ekd.isRuntimeModifier() and !ekd.isReleased()) {
                            ekd.sf(FLAG_MOD_TRIG);
                            ekd.actionType = .modifier_used;
                        }
                    }
                    return;
                }
            }
        }
    }

    if (inQuietPeriod) {
        const hasBypass: bool = blk: {
            if (g_unrelModCount >= 1 and !isModKey) break :blk true;
            if (g_unrelModCount >= 2 and isModKey) break :blk true;
            if (isModKey and g_unrelModCount == 0) break :blk true;
            for (0..g_kbLen) |i| {
                const evk = g_kbVK[i];
                const ekd = &g_kbData[i];
                if (!ekd.isReleased()) {
                    if (secondaryAllowsPrimaryFast(evk, keyVK, runComboScan, runInstantScan)) break :blk true;
                    if (isModKey and ekd.isRuntimeModifier()) break :blk true;
                }
            }
            break :blk false;
        };
        if (!hasBypass) {
            if (!isModKey) {
                g_typingModeUntil = currentTime + g_QuietPeriodDuration;
                g_hotFlags |= HF_TYPING;
                rfSet(RF_TYPING); // FSM-lite
            }
            timerClear();
            for (0..g_kbLen) |i| {
                const ekd = &g_kbData[i];
                if (ekd.isRuntimeModifier() and !ekd.isReleased() and !ekd.hasInterferingKeys()) {
                    if (g_cleanUnrelModCount > 0) g_cleanUnrelModCount -= 1;
                }
                ekd.sf(FLAG_INTERFERING);
                ekd.sameModTidHash = 0;
                ekd.tidCount = 0;
            }
            rfSetIf(RF_CLEAN_UNREL_MODS, g_cleanUnrelModCount != 0); // FSM-lite
            var nd = KeyData{};
            nd.downTime = currentTime;
            nd.sf(FLAG_INTERFERING | FLAG_QUIET);
            nd.bf(RUNTIME_CURRENT_VK_IS_ACTIVE_MODIFIER, isVirtualModKey);
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

    if (runComboScan and unrelMods < 2) {
        var otherUnrel: i32 = 0;
        for (0..g_kbLen) |i| {
            const ekd = &g_kbData[i];
            if (ekd.isRuntimeModifier() and !ekd.isReleased() and !ekd.inComboRepeatMode()) otherUnrel += 1;
        }
        if (otherUnrel == 0) {
            const s: usize = @intCast(keyVK);
            const list = &activeContextDerived().comboPrimaryList[s];
            const len: usize = @intCast(activeContextDerived().comboPrimaryListLen[s]);
            for (list[0..len]) |ev16| {
                const evk: i32 = @intCast(ev16);
                const ekd = kbGet(evk) orelse continue;
                if (ekd.inComboRepeatMode() and !ekd.isReleased()) {
                    const pkN = cachedNameFromVK(evk) orelse continue;
                    const nameRef = keyNameRef orelse return;
                    triggerComboImmediate(evk, keyVK, pkN, nameRef, nameRef);
                    return;
                }
            }
        }
    }
    if (keyExists) {
        return;
    }

    if (runComboScan and unrelMods < 2) {
        const s: usize = @intCast(keyVK);
        const list = &activeContextDerived().comboPrimaryList[s];
        const len: usize = @intCast(activeContextDerived().comboPrimaryListLen[s]);
        for (list[0..len]) |ev16| {
            const evk: i32 = @intCast(ev16);
            const ekd = kbGet(evk) orelse continue;
            if (!ekd.isReleased() and !ekd.hasInterferingKeys()) {
                const pkN = cachedNameFromVK(evk) orelse continue;
                const nameRef = keyNameRef orelse return;
                const ck = makeComboKey(evk, keyVK);
                const primaryElapsed = currentTime - ekd.downTime;

                const isInternalInstant = if (icGet(ck)) |remap| remap.isInstant else false;

                if (isInternalInstant) {
                    triggerComboImmediate(evk, keyVK, pkN, nameRef, nameRef);
                    return;
                } else if (primaryElapsed >= g_SingleKeyHoldThreshold) {
                    triggerComboImmediate(evk, keyVK, pkN, nameRef, nameRef);
                    return;
                } else {
                    if (kbGet(evk)) |primaryKey| {
                        primaryKey.sf(FLAG_COMBO_TRIG);
                    }
                }
            }
        }
    }

    if (g_active_virtual_modifier_count > 0) {
        if (g_active_virtual_modifier_count == 1) {
            const modVK = g_active_virtual_modifiers_by_vk[0];
            if (kbGet(modVK)) |md| {
                if (!md.isReleased()) {
                    if (secondaryAllowsPrimaryFast(modVK, keyVK, runComboScan, runInstantScan)) {
                        if (runInstantScan and instantPrimaryAllowedForSecondary(modVK, keyVK)) {
                            const pkN = cachedNameFromVK(modVK) orelse return;
                            triggerInstantComboVK(modVK, keyVK, pkN, currentTime);
                            return;
                        }
                        if (runComboScan and comboPrimaryAllowedForSecondary(modVK, keyVK)) {
                            const pkN = cachedNameFromVK(modVK) orelse return;
                            const nameRef = keyNameRef orelse return;
                            triggerComboImmediate(modVK, keyVK, pkN, nameRef, nameRef);
                            return;
                        }
                    }
                }
            }
        }
        if (runComboScan) {
            const s: usize = @intCast(keyVK);
            const list = &activeContextDerived().comboPrimaryList[s];
            const len: usize = @intCast(activeContextDerived().comboPrimaryListLen[s]);
            for (list[0..len]) |ev16| {
                const evk: i32 = @intCast(ev16);
                const ekd = kbGet(evk) orelse continue;
                if (ekd.isReleased() or (currentTime - ekd.downTime) < g_SingleKeyHoldThreshold) continue;
                const pkN = cachedNameFromVK(evk) orelse continue;
                const nameRef = keyNameRef orelse return;
                triggerComboImmediate(evk, keyVK, pkN, nameRef, nameRef);
                return;
            }
        }
        if (isVirtualModKey) {
            for (0..@intCast(g_active_virtual_modifier_count)) |i| {
                const amod = g_active_virtual_modifiers_by_vk[i];
                if (kbGet(amod)) |amd| {
                    if (runComboScan and !amd.isReleased() and comboPrimaryAllowedForSecondary(amod, keyVK)) {
                        const pkN = cachedNameFromVK(amod) orelse continue;
                        const nameRef = keyNameRef orelse return;
                        triggerComboImmediate(amod, keyVK, pkN, nameRef, nameRef);
                        return;
                    }
                }
            }
            var modTypeActive = false;
            for (0..@intCast(g_active_virtual_modifier_count)) |i|
                if (activeContextDerived().keyModType[@intCast(g_active_virtual_modifiers_by_vk[i])] == modType) {
                    modTypeActive = true;
                    break;
                };
            if (modTypeActive) {
                sendModifiedKey(keyVK);
                for (0..@as(usize, @intCast(g_active_virtual_modifier_count))) |ai| {
                    if (kbGet(g_active_virtual_modifiers_by_vk[ai])) |amd| {
                        amd.sf(FLAG_MOD_TRIG);
                        amd.cf(FLAG_MOD_ACT);
                        amd.actionType = .modifier_used;
                    }
                }
                clear_active_virtual_modifiers();
                return;
            }
            add_active_virtual_modifier(keyVK);
            if (kbGet(keyVK)) |ex| {
                ex.sf(RUNTIME_CURRENT_VK_IS_ACTIVE_MODIFIER | FLAG_MOD_ACT);
            } else {
                var nd4 = KeyData{};
                nd4.downTime = currentTime;
                nd4.sf(RUNTIME_CURRENT_VK_IS_ACTIVE_MODIFIER | FLAG_MOD_ACT);
                nd4.bf(FLAG_QUIET, inQuietPeriod);
                kbPut(keyVK, nd4);
                ordAppend(keyVK);
            }
            return;
        }
        sendModifiedKey(keyVK);
        for (0..@as(usize, @intCast(g_active_virtual_modifier_count))) |ai| {
            if (kbGet(g_active_virtual_modifiers_by_vk[ai])) |amd| {
                amd.sf(FLAG_MOD_TRIG);
                amd.cf(FLAG_MOD_ACT);
                amd.actionType = .modifier_used;
            }
        }
        clear_active_virtual_modifiers();
        return;
    }

    // Established held-mod fallback for ordinary secondaries.
    //
    // The older held-mod branch below is gated by the incoming key's static
    // roles, so plain partner keys can otherwise sit in the buffer until key-up.
    // If a modifier-role anchor is clean, still physically held, outside typing
    // quiet mode, and already past the hold threshold, resolve the later key
    // immediately through the DLL send path.
    if (!isVirtualModKey and
        g_unrelModCount > 0 and
        g_active_virtual_modifier_count == 0 and
        g_active_physical_and_windows_facing_modifiers == 0 and
        !keyExists and
        !runComboScan and
        !runInstantScan)
    {
        var heldMods: [8]i32 = undefined;
        var heldCount: usize = 0;
        for (0..g_kbLen) |i| {
            const evk = g_kbVK[i];
            const ekd = &g_kbData[i];
            if (!ekd.isRuntimeModifier() or ekd.isReleased() or ekd.chordPending()) continue;
            if (ekd.hasInterferingKeys() or ekd.comboTriggered() or ekd.inQuietPeriod()) continue;
            if (ekd.modifierActivated() or ekd.modifierTriggered()) continue;
            if ((currentTime - ekd.downTime) < g_SingleKeyHoldThreshold) continue;
            if (secondaryAllowsPrimaryFast(evk, keyVK, runComboScan, runInstantScan)) continue;
            if (heldCount < 8) {
                heldMods[heldCount] = evk;
                heldCount += 1;
            }
        }
        if (heldCount > 0) {
            for (heldMods[0..heldCount]) |mv| {
                cancelKeyTimers(mv);
                add_active_virtual_modifier(mv);
                if (kbGet(mv)) |md| md.sf(FLAG_MOD_ACT);
            }
            sendModifiedKey(keyVK);
            for (heldMods[0..heldCount]) |mv| {
                if (kbGet(mv)) |md| {
                    md.cf(FLAG_MOD_ACT);
                    md.sf(FLAG_MOD_TRIG);
                    md.actionType = .modifier_used;
                }
                remove_active_virtual_modifier(mv);
            }
            return;
        }
    }

    if (kdHeldMod and unrelMods < 2 and (isVirtualModKey or runComboScan or runInstantScan)) {
        for (0..g_kbLen) |i| {
            const evk = g_kbVK[i];
            const ekd = &g_kbData[i];
            if (ekd.isReleased() or (currentTime - ekd.downTime) < g_SingleKeyHoldThreshold) continue;
            if (runInstantScan and instantPrimaryAllowedForSecondary(evk, keyVK)) {
                const pkN = cachedNameFromVK(evk) orelse return;
                triggerInstantComboVK(evk, keyVK, pkN, currentTime);
                return;
            }
            if (ekd.isRuntimeModifier() and !ekd.chordPending()) {
                if (runComboScan and comboPrimaryAllowedForSecondary(evk, keyVK)) {
                    const pkN = cachedNameFromVK(evk) orelse return;
                    const nameRef = keyNameRef orelse return;
                    triggerComboImmediate(evk, keyVK, pkN, nameRef, nameRef);
                    return;
                }
                if (!isVirtualModKey) {
                    add_active_virtual_modifier(evk);
                    ekd.sf(FLAG_MOD_ACT);
                    sendModifiedKey(keyVK);
                    ekd.cf(FLAG_MOD_ACT);
                    ekd.sf(FLAG_MOD_TRIG);
                    ekd.actionType = .modifier_used;
                    remove_active_virtual_modifier(evk);
                    return;
                }
            }
        }
    }

    if (kdSameMod) {
        if (unrelMods >= 2) {
            for (0..g_kbLen) |i| {
                const evk = g_kbVK[i];
                const ekd = &g_kbData[i];
                if (!ekd.isRuntimeModifier() or ekd.isReleased() or ekd.chordPending()) continue;
                if (activeContextDerived().keyModType[@intCast(evk)] == modType) {
                    for (0..g_kbLen) |j| {
                        const e2 = &g_kbData[j];
                        if (e2.isRuntimeModifier() and !e2.isReleased()) {
                            cancelKeyTimers(g_kbVK[j]);
                            add_active_virtual_modifier(g_kbVK[j]);
                            e2.sf(FLAG_MOD_ACT | FLAG_MOD_TRIG);
                        }
                    }
                    sendModifiedKey(keyVK);
                    for (0..g_kbLen) |jj| {
                        const e3 = &g_kbData[jj];
                        if (e3.isRuntimeModifier() and !e3.isReleased()) {
                            e3.cf(FLAG_MOD_ACT);
                            e3.actionType = .modifier_used;
                        }
                    }
                    clear_active_virtual_modifiers();
                    return;
                }
            }
        }
        if (unrelMods < 2) {
            for (0..g_kbLen) |i| {
                const evk = g_kbVK[i];
                const ekd = &g_kbData[i];
                if (!ekd.isRuntimeModifier() or ekd.isReleased() or ekd.modifierActivated() or ekd.chordPending()) continue;
                if (activeContextDerived().keyModType[@intCast(evk)] != modType) continue;
                const timeDiff = currentTime - ekd.downTime;
                if (timeDiff < g_SingleKeyHoldThreshold) {
                    var nd5 = KeyData{};
                    nd5.downTime = currentTime;
                    nd5.sf(RUNTIME_CURRENT_VK_IS_ACTIVE_MODIFIER);
                    nd5.sameModPartnerVK = evk;
                    nd5.bf(FLAG_QUIET, inQuietPeriod);
                    kbPut(keyVK, nd5);
                    ordAppend(keyVK);
                    const remaining = @as(i32, @intFromFloat(@as(f64, @floatFromInt(g_SingleKeyHoldThreshold - timeDiff)) * g_qpcToMs));
                    const pkN = cachedNameFromVK(evk) orelse return;
                    const nameRef = keyNameRef orelse return;
                    var tidBuf: [TID_LEN]u16 = [_]u16{0} ** TID_LEN;
                    const tidH = buildTid(&tidBuf, pkN, "_sameMod_", nameRef);
                    ekd.sameModTidHash = tidH;
                    queueTimer(&tidBuf, tidH, remaining, 1, pkN, nameRef, currentTime);
                    return;
                }
                add_active_virtual_modifier(evk);
                ekd.sf(FLAG_MOD_ACT | FLAG_MOD_TRIG);
                sendModifiedKey(keyVK);
                ekd.cf(FLAG_MOD_ACT);
                ekd.actionType = .modifier_used;
                remove_active_virtual_modifier(evk);
                return;
            }
        }
    }

    // UNIVERSAL FALLTHROUGH — add key to buffer
    var nd6 = KeyData{};
    nd6.downTime = currentTime;
    nd6.bf(RUNTIME_CURRENT_VK_IS_ACTIVE_MODIFIER, isVirtualModKey);
    nd6.bf(FLAG_QUIET, inQuietPeriod);
    kbPut(keyVK, nd6);
    ordAppend(keyVK);
    if (g_ordLen > @as(usize, @intCast(g_MaxBufferSize))) {
        const f = ordAt(0);
        ordRemoveFirst();
        _ = kbRemove(f);
    }
    if (isVirtualModKey) {
        g_unrelModCount += 1;
        // A modifier enters the buffer with no interfering keys — it is "clean".
        g_cleanUnrelModCount += 1;
        rfSet(RF_UNREL_MODS | RF_CLEAN_UNREL_MODS); // FSM-lite
    }
}

fn bufferKeyUp(keyVK: i32) void {
    if (keyVK <= 0 or keyVK >= VK_COUNT) {
        return;
    }

    const prof_start = profStart();
    defer profRecord(&g_profiling.keyUpProcessing, prof_start);

    const vki: usize = @intCast(keyVK);
    const currentTime = timeFromProfStart(prof_start);

    if (repeatIsActive() and repeatVK() != keyVK and repeatRequiredContains(keyVK)) {
        @branchHint(.unlikely);
        stopRepeatThread();
    }
    if (repeatIsActive() and repeatVK() == keyVK) {
        @branchHint(.unlikely);
        const first_emit_was_pending = @atomicRmw(i32, &g_repeat.first_emit_pending, .Xchg, 0, .acq_rel) != 0;
        const ku167_start = profStartSect();
        stopRepeatThread();
        profSpan(KU_BASE + 167, ku167_start); // ku167 span: repeat keyup stopRepeatThread

        var releasedRepeatMod = false;
        if (kbGet(keyVK)) |kd| {
            const wasUnreleasedMod = kd.isRuntimeModifier() and !kd.isReleased();
            const owedModifierUp = kd.modifierActivated();

            if (owedModifierUp) {
                const modVK = g_virtual_modifier_output_vk[vki];
                if (modVK != 0) {
                    ringReset();
                    ringAddKey(modVK, KEYEVENTF_KEYUP);
                    ringSend();
                    releasedRepeatMod = true;
                }
            }

            if (g_active_virtual_modifier_count != 0) {
                remove_active_virtual_modifier(keyVK);
            }

            if (wasUnreleasedMod) {
                if (g_unrelModCount > 0) g_unrelModCount -= 1;
                if (!kd.hasInterferingKeys() and g_cleanUnrelModCount > 0) {
                    g_cleanUnrelModCount -= 1;
                }
            }

            if (kd.tidCount != 0) {
                const ku168_start = profStartSect();
                cancelKeyTimers(keyVK);
                profSpan(KU_BASE + 168, ku168_start); // ku168 span: repeat keyup cancelKeyTimers(keyVK)
            }
            if (kd.sameModTidHash != 0) {
                cancelTimer(kd.sameModTidHash);
                kd.sameModTidHash = 0;
            }

            _ = kbRemove(keyVK);
            removeFromKeyOrder(keyVK);
        }
        // A repeat that never reached its first timer tick must not synthesize a
        // key on release. QMK_ProcessKeyEvent clears physical-key truth before
        // bufferKeyUp runs, so a key-up here means the repeat key is no longer
        // actually held. The repeat worker remains the only path allowed to emit
        // repeat taps, and it gates on physicalKeyDownVK immediately before send.
        _ = first_emit_was_pending;
        const modVK = g_virtual_modifier_output_vk[vki];
        if (!releasedRepeatMod and activeModContains(keyVK) and modVK != 0) {
            ringReset();
            ringAddKey(modVK, KEYEVENTF_KEYUP);
            const ku169_start = profStartSect();
            ringSend();
            profSpan(KU_BASE + 169, ku169_start); // ku169 span: repeat keyup ringSend modifier up
            remove_active_virtual_modifier(keyVK);
            restoreSystemModBitmaskFromPhysicalState();
        }
        return;
    }

    if ((g_hotFlags & HF_IGNORED_KEYS) != 0) {
        @branchHint(.unlikely);
        if (keyVK >= 0 and keyVK < 256 and g_keyVKIgnored[@intCast(keyVK)]) {
            ignRemoveVK(keyVK);
            return;
        }
    }

    if (pendingRollActive()) {
        if (g_pendingRollVKs[0] == keyVK) {
            const headDuration = currentTime - g_pendingRollDownTimes[0];
            const suppressHead = releaseOverMaxSuppressed(headDuration);
            const headFlags = g_pendingRollFlags[0];
            if ((headFlags & PSF_DOUBLE_TAP) != 0) {
                if (kdtGet(keyVK)) |dt| {
                    const dur = currentTime - dt;
                    if (!suppressHead and dur < g_DoubleTapThreshold and g_unrelModCount == 0) kutPut(keyVK, currentTime) else kutRemove(keyVK);
                    kdtRemove(keyVK);
                }
            }
            const rollWillBeOne = g_pendingRollLen == 2;
            if (g_keyNamePtr[vki]) |headNameRef| {
                pendingRollPopHead();
                if (rollWillBeOne) {
                    const tailVK = g_pendingRollVKs[0];
                    const tailDown = g_pendingRollDownTimes[0];
                    const tailFlags = g_pendingRollFlags[0];
                    pendingRollClear();
                    pendingSoloStoreFlags(tailVK, tailDown, tailFlags);
                }
                if (!suppressHead) {
                    const ku170_start = profStartSect();
                    queueDirectTapCallback(keyVK, headNameRef);
                    profSpan(KU_BASE + 170, ku170_start); // ku170 span: pending roll direct tap queue
                }
                return;
            }
        }
        const ku171_start = profStartSect();
        pendingRollTapHeadDirect(false);
        profSpan(KU_BASE + 171, ku171_start); // ku171 span: pendingRollTapHeadDirect
    }

    if (pendingSoloActive() and g_pendingSoloVK == keyVK) {
        const soloDuration = currentTime - g_pendingSoloDownTime;
        const soloOverMax = releaseOverMaxSuppressed(soloDuration);
        if ((g_pendingSoloFlags & PSF_DOUBLE_TAP) != 0) {
            if (kdtGet(keyVK)) |dt| {
                const dur = currentTime - dt;
                if (!soloOverMax and dur < g_DoubleTapThreshold and g_unrelModCount == 0) kutPut(keyVK, currentTime) else kutRemove(keyVK);
                kdtRemove(keyVK);
            }
        }
        const fastEnough = durationFastEnough(currentTime, g_pendingSoloDownTime);
        const soloHasHold = callbackIdUsable(effectiveHoldCallbackId(@intCast(keyVK)));
        const soloHoldInterfered = soloHasHold and holdHadLaterPhysicalKeyDown(keyVK);
        if (!soloOverMax and ((g_pendingSoloFlags & PSF_INTERFERING) != 0 or soloHoldInterfered or fastEnough)) {
            if (g_keyNamePtr[vki]) |keyNameRefPending| {
                pendingSoloDeactivate();
                const ku172_start = profStartSect();
                queueDirectTapCallback(keyVK, keyNameRefPending);
                profSpan(KU_BASE + 172, ku172_start); // ku172 span: pending solo direct tap queue
                return;
            }
        }
        const ku173_start = profStartSect();
        pendingSoloMaterialize();
        profSpan(KU_BASE + 173, ku173_start); // ku173 span: pendingSoloMaterialize on keyup
    }

    const gate = &activeContextDerived().gate[vki];
    const kuMask = gate.kuMask;
    const kuDoubleTap = (kuMask & KU_DOUBLE_TAP) != 0;
    const kuSkipAllBufferUp = (kuMask & KU_SKIP_ALL_BUFFER_UP) != 0;
    const kuAction = gate.kuAction;

    if (kuAction == .phys_mod_up) {
        const physicalBit: u16 = @intCast(g_vk_is_physical_modifier[vki]);
        if (physicalBit != 0) {
            _ = apply_physical_modifier_event(keyVK, false);
            return;
        }
    } else if (kuAction == .sys_mod_up) {
        const keySysBit: i32 = @intCast(g_vk_windows_facing_modifiers[vki]);
        if (keySysBit != 0) {
            @branchHint(.unlikely);
            g_active_physical_and_windows_facing_modifiers &= ~keySysBit;
            rfSetIf(RF_SYS_MODS, g_active_physical_and_windows_facing_modifiers != 0); // FSM-lite
            return;
        }
    }

    if (g_any_physical_modifiers_active) {
        return;
    }

    if (pendingSoloActive()) {
        pendingSoloMaterialize();
    }

    const keyIndex = g_kbIdx[vki];
    if (keyIndex < 0) {
        return;
    }
    const keyData = &g_kbData[@intCast(keyIndex)];

    if (pendingChordContains(keyVK)) {
        markKeyReleased(keyVK, keyData);
        keyData.releaseTime = currentTime;
        if ((kuMask & KU_NEEDS_ACTIVE_PRIMARY_SYNC) != 0) {
            activePrimaryBitsSync(keyVK, keyData.*);
        }
        if (firePendingChord()) {
            _ = kbRemove(keyVK);
            removeFromKeyOrder(keyVK);
            return;
        }
    }

    // SAME-MOD SECONDARY RELEASE: bypass ordinary FIFO release ordering.
    //
    // A secondary recorded with sameModPartnerVK is not ordinary buffered text:
    // it is the prospective output key of a same-type virtual-mod gesture. If
    // the later-pressed secondary releases while its recorded primary is still
    // cleanly held, release order has resolved the ambiguity. Send the secondary
    // immediately with the primary modifier instead of waiting for earlier held
    // keys in g_keyOrder to release. Ordinary typing keeps the normal FIFO path.
    if (keyData.sameModPartnerVK != 0 and
        keyData.actionType == .undecided and
        !keyData.hasInterferingKeys() and
        !keyData.comboTriggered())
    {
        const partnerVK = keyData.sameModPartnerVK;
        if (kbGet(partnerVK)) |pt| {
            if (!pt.isReleased() and
                !pt.hasInterferingKeys() and
                !pt.comboTriggered() and
                !pt.modifierActivated() and
                !pt.modifierTriggered() and
                pt.actionType == .undecided)
            {
                if (pt.sameModTidHash != 0) {
                    cancelTimer(pt.sameModTidHash);
                    pt.sameModTidHash = 0;
                }
                if (keyData.tidCount != 0) {
                    cancelKeyTimers(keyVK);
                }

                markKeyReleased(keyVK, keyData);
                keyData.releaseTime = currentTime;
                if ((kuMask & KU_NEEDS_ACTIVE_PRIMARY_SYNC) != 0) {
                    activePrimaryBitsSync(keyVK, keyData.*);
                }

                keyData.sf(FLAG_MOD_TRIG);
                keyData.actionType = .modifier_used;
                keyData.sameModPartnerVK = 0;
                add_active_virtual_modifier(partnerVK);
                pt.sf(FLAG_MOD_ACT | FLAG_MOD_TRIG);
                sendModifiedKey(keyVK);
                pt.cf(FLAG_MOD_ACT);
                pt.actionType = .modifier_used;
                remove_active_virtual_modifier(partnerVK);

                _ = kbRemove(keyVK);
                removeFromKeyOrder(keyVK);
                processQueueAfterKeyUp();
                return;
            }
        }
        keyData.sameModPartnerVK = 0;
    }

    if (g_kbLen == 1 and
        g_ordLen == 1 and
        ordAt(0) == keyVK and
        g_unreleasedKeyCount == 1 and
        g_active_virtual_modifier_count == 0 and
        g_active_physical_and_windows_facing_modifiers == 0 and
        keyData.actionType == .undecided and
        !keyData.hasInterferingKeys() and
        !keyData.comboTriggered() and
        !keyData.modifierPressed() and
        !keyData.modifierActivated() and
        !keyData.modifierTriggered() and
        keyData.tidCount == 0 and
        keyData.sameModTidHash == 0 and
        durationFastEnough(currentTime, keyData.downTime))
    {
        if (g_keyNamePtr[vki]) |keyNameRefSolo| {
            const isModKeySoloUp = keyData.isRuntimeModifier();
            markKeyReleased(keyVK, keyData);
            keyData.releaseTime = currentTime;
            keyData.actionType = .tap;
            if (isModKeySoloUp and g_unrelModCount > 0) {
                g_unrelModCount -= 1;
                if (g_cleanUnrelModCount > 0) g_cleanUnrelModCount -= 1;
                rfSetIf(RF_UNREL_MODS, g_unrelModCount != 0);
                rfSetIf(RF_CLEAN_UNREL_MODS, g_cleanUnrelModCount != 0);
            }
            ordRemoveFirst();
            const directTapDuration = currentTime - keyData.downTime;
            _ = kbRemove(keyVK);
            if ((activeContextDerived().gate[vki].kuMask & KU_DOUBLE_TAP) != 0) {
                if (kdtGet(keyVK)) |dt| {
                    const dur = currentTime - dt;
                    if (!releaseOverMaxSuppressed(directTapDuration) and dur < g_DoubleTapThreshold and g_unrelModCount == 0) kutPut(keyVK, currentTime) else kutRemove(keyVK);
                    kdtRemove(keyVK);
                }
            }
            const ku174_start = profStartSect();
            queueDirectTapCallback(keyVK, keyNameRefSolo);
            profSpan(KU_BASE + 174, ku174_start); // ku174 span: solo keyup direct tap queue
            return;
        }
    }

    if (kuSkipAllBufferUp and
        keyData.actionType == .undecided and
        (g_runtimeFlags & RB_KEYUP_SKIP_ALL) == 0 and
        durationFastEnough(currentTime, keyData.downTime))
    {
        const skipAllDuration = currentTime - keyData.downTime;
        if (kuDoubleTap) {
            if (kdtGet(keyVK)) |dt| {
                const dur = currentTime - dt;
                if (!releaseOverMaxSuppressed(skipAllDuration) and
                    dur < g_DoubleTapThreshold and
                    g_unrelModCount == 0)
                    kutPut(keyVK, currentTime)
                else
                    kutRemove(keyVK);
                kdtRemove(keyVK);
            }
        }
        markKeyReleased(keyVK, keyData);
        keyData.releaseTime = currentTime;
        keyData.actionType = .tap;
        const ku175_start = profStartSect();
        processQueueAfterKeyUp();
        profSpan(KU_BASE + 175, ku175_start); // ku175 span: early skip-all processQueueAfterKeyUp
        return;
    }

    const kuComboSecondary = (kuMask & KU_COMBO_SECONDARY) != 0;
    const kuInstantSecondary = (kuMask & KU_INSTANT_SECONDARY) != 0;
    const kuSameMod = (kuMask & KU_SAME_MOD) != 0;
    const kuModifierLogic = (kuMask & KU_MODIFIER_LOGIC) != 0;
    const kuHold = (kuMask & KU_HOLD) != 0;
    const kuRetroModAct = (kuMask & KU_RETRO_MOD_ACT) != 0;
    const kuRetroTimer = (kuMask & KU_RETRO_TIMER) != 0;
    const kuFastTapPlain = (kuMask & KU_FAST_TAP_PLAIN) != 0;

    if (g_active_virtual_modifier_count != 0) {
        remove_active_virtual_modifier(keyVK);
    }
    if (g_active_physical_and_windows_facing_modifiers > 0) {
        @branchHint(.unlikely);
        return;
    }
    if (kuSameMod or kuRetroModAct or kuRetroTimer or kuModifierLogic) rebuildUnreleasedModifierCounters();
    const isModKey = (gate.kdPlan & KDP_HAS_VIRTUAL_MODIFIER_ROLE) != 0;
    const modType: i8 = modTypeFromKdPlan(gate.kdPlan);
    markKeyReleased(keyVK, keyData);
    if ((kuMask & KU_NEEDS_ACTIVE_PRIMARY_SYNC) != 0) {
        activePrimaryBitsSync(keyVK, keyData.*);
    }
    keyData.releaseTime = currentTime;
    const duration = currentTime - keyData.downTime;
    // A same-mod secondary (sameModPartnerVK != 0) was deliberately not
    // counted in g_unrelModCount when buffered: it represents the prospective
    // output key, not another held modifier. Do not decrement the primary's
    // count when that secondary releases before the same-mod timer fires.
    if (keyData.isRuntimeModifier() and keyData.sameModPartnerVK == 0 and g_unrelModCount > 0) {
        g_unrelModCount -= 1;
        if (!keyData.hasInterferingKeys() and g_cleanUnrelModCount > 0)
            g_cleanUnrelModCount -= 1;
        rfSetIf(RF_UNREL_MODS, g_unrelModCount != 0);
        rfSetIf(RF_CLEAN_UNREL_MODS, g_cleanUnrelModCount != 0);
    }
    if (kuDoubleTap) {
        if (kdtGet(keyVK)) |dt| {
            const dur = currentTime - dt;
            const effUnrel = g_unrelModCount;
            if (!releaseOverMaxSuppressed(duration) and dur < g_DoubleTapThreshold and effUnrel == 0) kutPut(keyVK, currentTime) else kutRemove(keyVK);
            kdtRemove(keyVK);
        }
    }
    if (keyData.tidCount != 0) {
        const ku176_start = profStartSect();
        cancelKeyTimers(keyVK);
        profSpan(KU_BASE + 176, ku176_start); // ku176 span: general keyup cancelKeyTimers(keyVK)
    }

    if (!keyData.comboTriggered() and
        keyData.actionType != .modifier_used and
        fireExactHeldChordFromKeyUp(keyVK, currentTime))
    {
        _ = kbRemove(keyVK);
        removeFromKeyOrder(keyVK);
        return;
    }

    if (keyData.comboTriggered()) {
        if (keyData.inComboRepeatMode()) {
            _ = kbRemove(keyVK);
            removeFromKeyOrder(keyVK);
            const ku177_start = profStartSect();
            processQueueAfterKeyUp();
            profSpan(KU_BASE + 177, ku177_start); // ku177 span: combo repeat processQueueAfterKeyUp
            return;
        }
        keyData.cf(FLAG_COMBO_TRIG);
    }
    if (keyData.actionType == .modifier_used) {
        _ = kbRemove(keyVK);
        removeFromKeyOrder(keyVK);
        const ku178_start = profStartSect();
        processQueueAfterKeyUp();
        profSpan(KU_BASE + 178, ku178_start); // ku178 span: modifier_used processQueueAfterKeyUp
        return;
    }

    const keyNameRef = g_keyNamePtr[vki];
    const scanFlags = gate.scanFlags;
    const runComboScan =
        (g_runtimeFlags & RF_ACTIVE_COMBO_PRIMARY) != 0 and
        kuComboSecondary and
        (scanFlags & KFS_KU_RELATION_CHECK) != 0 and
        hasActiveComboPrimaryForSecondary(keyVK);
    const runInstantScan =
        (g_runtimeFlags & RF_ACTIVE_INSTANT_PRIMARY) != 0 and
        kuInstantSecondary and
        (scanFlags & KFS_KU_RELATION_CHECK) != 0 and
        hasActiveInstantPrimaryForSecondary(keyVK);
    if (kuSameMod and keyData.sameModPartnerVK != 0) {
        const partnerVK = keyData.sameModPartnerVK;
        if (kbGet(partnerVK)) |pt| {
            if (pt.sameModTidHash != 0) {
                cancelTimer(pt.sameModTidHash);
                pt.sameModTidHash = 0;
            }

        }
    }
    if (runComboScan and duration < g_SingleKeyHoldThreshold and !keyData.comboTriggered()) {
        for (0..g_kbLen) |i| {
            const pvk = g_kbVK[i];
            const pkd = &g_kbData[i];
            if (pkd.isReleased() or !pkd.comboTriggered()) continue;

            if (comboPrimaryAllowedForSecondary(pvk, keyVK)) {
                const pkN = cachedNameFromVK(pvk) orelse continue;
                const nameRef = keyNameRef orelse return;
                triggerComboImmediate(pvk, keyVK, pkN, nameRef, nameRef);
                keyData.sf(FLAG_COMBO_TRIG);
                pkd.sf(FLAG_COMBO_TRIG);
                return;
            }
        }
    }
    if (kuSameMod) {
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
    }
    if (duration < g_SingleKeyHoldThreshold and g_kbLen > 1) {
        var singleModVK: i32 = 0;
        var unrelModsBeforeKey: usize = 0;

        for (0..g_kbLen) |i| {
            const evk = g_kbVK[i];
            const ekd = &g_kbData[i];
            if (!ekd.isRuntimeModifier() or ekd.isReleased() or ekd.chordPending()) continue;
            if (ekd.downTime >= keyData.downTime) continue;
            if (ekd.inQuietPeriod() or keyData.inQuietPeriod()) continue;
            unrelModsBeforeKey += 1;
            singleModVK = evk;
        }

        if (unrelModsBeforeKey != 1) singleModVK = 0;

        if (singleModVK != 0) {
            const singleModType = activeContextDerived().keyModType[@intCast(singleModVK)];
            const isDiffTypeMod = !isModKey or singleModType != modType;

            if (isDiffTypeMod and
                !secondaryAllowsPrimaryFast(singleModVK, keyVK, runComboScan, runInstantScan))
            {
                const modMask: u16 = @intCast(g_key_virtual_modifier_mask[@intCast(singleModVK)]);
                const ku179_start = profStartSect();
                const ku179_matched = queueCompiledHotkeyIfMatchedSingleModProfiled(keyVK, modMask, true);
                profSpan(KU_BASE + 179, ku179_start); // ku179 span: single-mod compiled hotkey match
                if (!ku179_matched) {
                    const ku180_start = profStartSect();
                    sendKeyDirectSingleModProfiled(keyVK, modMask);
                    profSpan(KU_BASE + 180, ku180_start); // ku180 span: single-mod sendKeyDirect
                    const ku181_start = profStartSect();
                    queueCallbackEmpty(-4, 4);
                    profSpan(KU_BASE + 181, ku181_start); // ku181 span: single-mod queueCallbackEmpty
                }

                const ku221_start = profStartSect();
                remove_active_virtual_modifier(singleModVK);
                profSpan(KU_BASE + 221, ku221_start); // ku221 span: single-mod remove_active_virtual_modifier(singleModVK)
                const ku182_start = profStartSect();
                cancelKeyTimers(singleModVK);
                profSpan(KU_BASE + 182, ku182_start); // ku182 span: single-mod cancelKeyTimers(singleModVK)

                keyData.actionType = .modifier_used;
                const ku183_start = profStartSect();
                cancelKeyTimers(keyVK);
                profSpan(KU_BASE + 183, ku183_start); // ku183 span: single-mod cancelKeyTimers(keyVK)

                const ku222_start = profStartSect();
                _ = kbRemove(keyVK);
                profSpan(KU_BASE + 222, ku222_start); // ku222 span: single-mod kbRemove(keyVK)
                const ku223_start = profStartSect();
                removeFromKeyOrder(keyVK);
                profSpan(KU_BASE + 223, ku223_start); // ku223 span: single-mod removeFromKeyOrder(keyVK)

                const ku224_start = profStartSect();
                if (kbGet(singleModVK)) |sm| {
                    sm.actionType = .modifier_used;
                    sm.sf(FLAG_MOD_TRIG | FLAG_COMBO_TRIG);
                    sm.cf(FLAG_MOD_ACT);
                }
                profSpan(KU_BASE + 224, ku224_start); // ku224 span: single-mod kbGet re-poison body

                restoreSystemModBitmaskFromPhysicalState();

                const ku184_start = profStartSect();
                processQueueAfterKeyUp();
                profSpan(KU_BASE + 184, ku184_start); // ku184 span: single-mod processQueueAfterKeyUp
                return;
            }
        }
    }
    if ((duration < g_SingleKeyHoldThreshold and g_unrelModCount >= 2) or keyData.inSendModifiedRepeatMode()) {
        var quickMods: [8]i32 = undefined;
        var qmCount: usize = 0;
        var chordMods: [8]i32 = undefined;
        var chordCount: usize = 0;

        for (0..g_kbLen) |i| {
            const evk = g_kbVK[i];
            const ekd = &g_kbData[i];
            if (!ekd.isRuntimeModifier() or ekd.isReleased() or ekd.downTime >= keyData.downTime) continue;
            // Quiet-origin modifier-role keys are protected typing, not
            // fallback modifiers. This prevents the "a+s+e" tail of "please"
            // from becoming Ctrl+Shift+E while preserving idle-origin gestures.
            if (ekd.inQuietPeriod()) continue;
            const timeDiff = keyData.downTime - ekd.downTime;
            const isQuickChord = timeDiff < g_ModifierGestureWindow;
            const isEstablished = timeDiff >= g_SingleKeyHoldThreshold or ekd.actionType == .modifier_used;
            if (!ekd.chordPending() and (isQuickChord or isEstablished) and qmCount < 8) {
                quickMods[qmCount] = evk;
                qmCount += 1;
            }
            if (isQuickChord and chordCount < 8) {
                chordMods[chordCount] = evk;
                chordCount += 1;
            }
        }

        if (!keyData.comboTriggered() and
            chordCount >= 2 and fireExactChordFromKeyUp(keyVK, chordMods[0..chordCount], currentTime))
        {
            _ = kbRemove(keyVK);
            removeFromKeyOrder(keyVK);
            return;
        }

        if (qmCount >= 2) {
            var hasComboAny = false;
            for (quickMods[0..qmCount]) |qvk| {
                if (secondaryAllowsPrimaryFast(qvk, keyVK, runComboScan, runInstantScan)) {
                    hasComboAny = true;
                    break;
                }
            }
            if (!hasComboAny and !keyData.comboTriggered() and !keyData.modifierTriggered()) {
                const ku185_start = profStartSect();
                for (quickMods[0..qmCount]) |qvk| cancelKeyTimers(qvk);
                profSpan(KU_BASE + 185, ku185_start); // ku185 span: multi-mod cancelKeyTimers loop
                var multiModMask: u16 = 0;
                for (quickMods[0..qmCount]) |qvk| {
                    multiModMask |= @intCast(g_key_virtual_modifier_mask[@intCast(qvk)]);
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
                const ku186_start = profStartSect();
                const ku186_matched = queueCompiledHotkeyIfMatched(keyVK, multiModMask, true);
                profSpan(KU_BASE + 186, ku186_start); // ku186 span: multi-mod compiled hotkey match
                if (!ku186_matched) {
                    const ku187_start = profStartSect();
                    sendKeyDirect(keyVK, multiModMask);
                    profSpan(KU_BASE + 187, ku187_start); // ku187 span: multi-mod sendKeyDirect
                }
                _ = kbRemove(keyVK);
                removeFromKeyOrder(keyVK);
                return;
            }
        }

        if (chordCount >= 2) {
            var hasComboAny = false;
            for (chordMods[0..chordCount]) |qvk|
                if (secondaryAllowsPrimaryFast(qvk, keyVK, runComboScan, runInstantScan)) {
                    hasComboAny = true;
                    break;
                };
            if (!hasComboAny and !keyData.comboTriggered() and !keyData.modifierTriggered()) {
                const ku188_start = profStartSect();
                for (chordMods[0..chordCount]) |qvk| cancelKeyTimers(qvk);
                profSpan(KU_BASE + 188, ku188_start); // ku188 span: chord cancelKeyTimers loop
                var chordModMask: u16 = 0;
                for (chordMods[0..chordCount]) |qvk| {
                    chordModMask |= @intCast(g_key_virtual_modifier_mask[@intCast(qvk)]);
                }
                for (chordMods[0..chordCount]) |qvk| {
                    cancelKeyTimers(qvk);
                    if (kbGet(qvk)) |kd| {
                        kd.sf(FLAG_MOD_TRIG);
                        kd.cf(FLAG_MOD_ACT);
                        kd.actionType = .modifier_used;
                    }
                }
                cancelKeyTimers(keyVK);
                const ku189_start = profStartSect();
                const ku189_matched = queueCompiledHotkeyIfMatched(keyVK, chordModMask, true);
                profSpan(KU_BASE + 189, ku189_start); // ku189 span: chord compiled hotkey match
                if (!ku189_matched) {
                    const ku190_start = profStartSect();
                    sendKeyDirect(keyVK, chordModMask);
                    profSpan(KU_BASE + 190, ku190_start); // ku190 span: chord sendKeyDirect
                }
                _ = kbRemove(keyVK);
                removeFromKeyOrder(keyVK);
                return;
            }
        }
    }
    if (kuModifierLogic) {
        if (keyData.modifierActivated()) {
            const modVK: u16 = switch (modType) {
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
            remove_active_virtual_modifier(keyVK);
            keyData.cf(FLAG_MOD_ACT | FLAG_MOD_TRIG);
        }

        if (keyData.actionType == .modifier_used) {
            _ = kbRemove(keyVK);
            removeFromKeyOrder(keyVK);
            processQueueAfterKeyUp();
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
                if (ekd.isRuntimeModifier() and !ekd.chordPending() and ekd.modifierActivated() and omhCount < 8) {
                    otherModsHeld[omhCount] = evk;
                    omhCount += 1;
                }
            }
            if (omhCount == 0) {
                for (0..g_kbLen) |i| {
                    const evk = g_kbVK[i];
                    const ekd = &g_kbData[i];
                    if (evk == keyVK or ekd.isReleased() or !ekd.isRuntimeModifier() or ekd.chordPending()) continue;
                    if (isModKey and activeContextDerived().keyModType[@intCast(evk)] == modType) continue;
                    if (isModKey) continue;
                    const elapsed = currentTime - ekd.downTime;
                    if (elapsed >= g_SingleKeyHoldThreshold and !ekd.modifierActivated()) {
                        if (secondaryAllowsPrimaryFast(evk, keyVK, runComboScan, runInstantScan)) continue;
                        if (ekd.releaseTime > 0) continue;
                        add_active_virtual_modifier(evk);
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
                    if (secondaryAllowsPrimaryFast(heldVK, keyVK, runComboScan, runInstantScan)) {
                        const pkN = cachedNameFromVK(heldVK) orelse {
                            const ku191_start = profStartSect();
                            processQueueAfterKeyUp();
                            profSpan(KU_BASE + 191, ku191_start); // ku191 span: single-held missing-name processQueueAfterKeyUp
                            return;
                        };
                        const nameRef = keyNameRef orelse return;
                        const ku192_start = profStartSect();
                        triggerComboImmediate(heldVK, keyVK, pkN, nameRef, nameRef);
                        profSpan(KU_BASE + 192, ku192_start); // ku192 span: single-held triggerComboImmediate
                        return;
                    }
                }
                for (otherModsHeld[0..omhCount]) |mv| if (kbGet(mv)) |mm| mm.sf(FLAG_MOD_TRIG);
                const ku193_start = profStartSect();
                sendModifiedKey(keyVK);
                profSpan(KU_BASE + 193, ku193_start); // ku193 span: multi-mod release sendModifiedKey
                _ = kbRemove(keyVK);
                removeFromKeyOrder(keyVK);
                return;
            }
            for (0..g_kbLen) |i| {
                const evk = g_kbVK[i];
                const ekd = &g_kbData[i];
                if (evk == keyVK or !ekd.isRuntimeModifier() or !ekd.isReleased() or ekd.chordPending()) continue;
                if (ekd.downTime >= keyData.downTime) continue;
                if (activeContextDerived().keyModType[@intCast(evk)] != modType) continue;
                if ((keyData.downTime - ekd.downTime) < g_ModifierGestureWindow) {
                    if (!activeModContains(evk)) {
                        add_active_virtual_modifier(evk);
                        ekd.sf(FLAG_MOD_ACT);
                    }
                    ekd.sf(FLAG_MOD_TRIG);
                    const ku194_start = profStartSect();
                    sendModifiedKey(keyVK);
                    profSpan(KU_BASE + 194, ku194_start); // ku194 span: same-type chain sendModifiedKey
                    _ = kbRemove(keyVK);
                    removeFromKeyOrder(keyVK);
                    return;
                }
            }
        }
        const kdR = kbGet(keyVK) orelse {
            const ku195_start = profStartSect();
            processQueueAfterKeyUp();
            profSpan(KU_BASE + 195, ku195_start); // ku195 span: missing kdR processQueueAfterKeyUp
            return;
        };
        if (duration < g_SingleKeyHoldThreshold and kdR.modifierActivated() and !kdR.modifierTriggered()) {
            var smCount: usize = 0;
            for (0..g_kbLen) |i| {
                const evk = g_kbVK[i];
                const ekd = &g_kbData[i];
                if (evk == keyVK) continue;
                if (ekd.isRuntimeModifier() and ekd.modifierActivated() and !ekd.modifierTriggered() and
                    !ekd.isReleased() and @abs(ekd.downTime - kdR.downTime) < g_ModifierGestureWindow) smCount += 1;
            }
            if (smCount > 0) {
                const ku196_start = profStartSect();
                processQueueAfterKeyUp();
                profSpan(KU_BASE + 196, ku196_start); // ku196 span: same-time mod processQueueAfterKeyUp
                return;
            }
            kdR.actionType = .tap;
            const ku197_start = profStartSect();
            processQueueAfterKeyUp();
            profSpan(KU_BASE + 197, ku197_start); // ku197 span: activated-under-threshold tap processQueueAfterKeyUp
            return;
        }
        const kdF = kbGet(keyVK) orelse {
            const ku198_start = profStartSect();
            processQueueAfterKeyUp();
            profSpan(KU_BASE + 198, ku198_start); // ku198 span: missing kdF processQueueAfterKeyUp
            return;
        };
        if (kdF.comboTriggered() or kdF.modifierTriggered()) {
            if (kuHold and !kdF.comboTriggered() and !kdF.isContaminated() and !holdHadLaterPhysicalKeyDown(keyVK) and duration >= g_SingleKeyHoldThreshold and duration <= g_MaxHoldThreshold) {
                kdF.actionType = .hold;
                const ku199_start = profStartSect();
                processQueueAfterKeyUp();
                profSpan(KU_BASE + 199, ku199_start); // ku199 span: triggered hold processQueueAfterKeyUp
                return;
            }
            kdF.actionType = .modifier_used;
            const ku200_start = profStartSect();
            processQueueAfterKeyUp();
            profSpan(KU_BASE + 200, ku200_start); // ku200 span: triggered modifier_used processQueueAfterKeyUp
            return;
        }
        if (kdF.modifierActivated() and !kdF.modifierTriggered()) {
            if (kuHold and !kdF.isContaminated() and !holdHadLaterPhysicalKeyDown(keyVK) and duration >= g_SingleKeyHoldThreshold and duration <= g_MaxHoldThreshold) {
                kdF.actionType = .hold;
                const ku201_start = profStartSect();
                processQueueAfterKeyUp();
                profSpan(KU_BASE + 201, ku201_start); // ku201 span: activated hold processQueueAfterKeyUp
                return;
            }
            const ku202_start = profStartSect();
            processQueueAfterKeyUp();
            profSpan(KU_BASE + 202, ku202_start); // ku202 span: activated fallback processQueueAfterKeyUp
            return;
        }
        if (kdF.inQuietPeriod() and !kdF.modifierTriggered() and !kdF.comboTriggered()) {
            kdF.actionType = .tap;
            const ku203_start = profStartSect();
            processQueueAfterKeyUp();
            profSpan(KU_BASE + 203, ku203_start); // ku203 span: quiet tap processQueueAfterKeyUp
            return;
        }
        if (kdF.hasInterferingKeys() or duration < g_SingleKeyHoldThreshold) {
            kdF.actionType = .tap;
            const ku204_start = profStartSect();
            processQueueAfterKeyUp();
            profSpan(KU_BASE + 204, ku204_start); // ku204 span: interfering/short tap processQueueAfterKeyUp
            return;
        }
        // Max-hold suppression is a solo-hold policy only. Once this key has
        // participated in a combo/chord or activated a modifier chain, its
        // later release must still resolve the chain even if it was held for
        // longer than the solo threshold. This preserves the configured
        // modifier path for long-held-modifier + W (for example, Ctrl+W).
        if (duration > g_MaxHoldThreshold and
            g_kbLen == 1 and
            !kdF.comboTriggered() and
            !kdF.modifierTriggered() and
            !kdF.modifierActivated() and
            !kdF.hasInterferingKeys()) {
            kdF.actionType = if (g_MaxThresholdSupress) .none else .tap;
            const ku205_start = profStartSect();
            processQueueAfterKeyUp();
            profSpan(KU_BASE + 205, ku205_start); // ku205 span: over-max processQueueAfterKeyUp
            return;
        }
        if (kdF.isContaminated()) {
            kdF.actionType = .modifier_used;
            const ku206_start = profStartSect();
            processQueueAfterKeyUp();
            profSpan(KU_BASE + 206, ku206_start); // ku206 span: contaminated processQueueAfterKeyUp
            return;
        }
        kdF.actionType = if (kuHold) .hold else .tap;
        const ku207_start = profStartSect();
        processQueueAfterKeyUp();
        profSpan(KU_BASE + 207, ku207_start); // ku207 span: final classified processQueueAfterKeyUp
        return;
    }
    if ((kuRetroModAct or kuRetroTimer) and g_unrelModCount > 0) {
        for (0..g_kbLen) |i| {
            const evk = g_kbVK[i];
            const ekd = &g_kbData[i];
            if (evk != keyVK and ekd.isRuntimeModifier() and !ekd.chordPending() and !ekd.isReleased()) {
                const ku208_start = profStartSect();
                processQueueAfterKeyUp();
                profSpan(KU_BASE + 208, ku208_start); // ku208 span: other-homerow-mod processQueueAfterKeyUp
                return;
            }
        }
    }
    if (kuRetroModAct and
        (scanFlags & KFS_KU_RETRO_MOD_CHECK) != 0 and
        g_unrelModCount > 0 and
        !keyData.comboTriggered() and
        !keyData.modifierPressed())
    {
        var mta: [8]i32 = undefined;
        var mtaCount: usize = 0;
        for (0..g_kbLen) |i| {
            const evk = g_kbVK[i];
            const ekd = &g_kbData[i];
            if (!ekd.isRuntimeModifier() or ekd.isReleased() or ekd.chordPending()) continue;
            if (secondaryAllowsPrimaryFast(evk, keyVK, runComboScan, runInstantScan)) continue;
            if ((currentTime - ekd.downTime) < g_SingleKeyHoldThreshold) continue;
            if (mtaCount < 8) {
                mta[mtaCount] = evk;
                mtaCount += 1;
            }
        }
        if (mtaCount > 0) {
            const ku209_start = profStartSect();
            for (mta[0..mtaCount]) |mv| {
                if (!activeModContains(mv)) {
                    add_active_virtual_modifier(mv);
                    if (kbGet(mv)) |mm| mm.sf(FLAG_MOD_ACT);
                }
                if (kbGet(mv)) |mm| mm.sf(FLAG_MOD_TRIG);
            }
            profSpan(KU_BASE + 209, ku209_start); // ku209 span: retro-mod activation loop
            const ku210_start = profStartSect();
            sendModifiedKey(keyVK);
            profSpan(KU_BASE + 210, ku210_start); // ku210 span: retro-mod sendModifiedKey
            _ = kbRemove(keyVK);
            removeFromKeyOrder(keyVK);
            return;
        }
    }
    if (kuRetroTimer and !keyData.hasInterferingKeys()) {
        if (g_unreleasedKeyCount == 1) {
            for (0..g_kbLen) |i| {
                const evk = g_kbVK[i];
                const ekd = &g_kbData[i];
                if (ekd.isReleased() or ekd.downTime >= keyData.downTime) continue;
                if (!secondaryAllowsPrimaryFast(evk, keyVK, runComboScan, runInstantScan)) continue;
                if ((currentTime - ekd.downTime) >= g_SingleKeyHoldThreshold) continue;
                const rem = @as(i32, @intFromFloat(@as(f64, @floatFromInt(g_SingleKeyHoldThreshold - (currentTime - ekd.downTime))) * g_qpcToMs));
                const pkN = cachedNameFromVK(evk) orelse continue;
                const nameRef = keyNameRef orelse return;
                var tidBuf: [TID_LEN]u16 = [_]u16{0} ** TID_LEN;
                const tidH = buildTid(&tidBuf, pkN, "_retroCombo_", nameRef);
                const ku211_start = profStartSect();
                queueTimer(&tidBuf, tidH, rem, 2, pkN, nameRef, currentTime);
                profSpan(KU_BASE + 211, ku211_start); // ku211 span: queue retro combo timer
            }
        }
        if (g_unrelModCount > 0) {
            for (0..g_kbLen) |i| {
                const evk = g_kbVK[i];
                const ekd = &g_kbData[i];
                if (!ekd.isRuntimeModifier() or ekd.isReleased() or ekd.modifierActivated() or ekd.chordPending()) continue;
                if (secondaryAllowsPrimaryFast(evk, keyVK, runComboScan, runInstantScan)) continue;
                if ((currentTime - ekd.downTime) >= g_SingleKeyHoldThreshold) continue;
                const rem = @as(i32, @intFromFloat(@as(f64, @floatFromInt(g_SingleKeyHoldThreshold - (currentTime - ekd.downTime))) * g_qpcToMs));
                const pkN = cachedNameFromVK(evk) orelse continue;
                const nameRef = keyNameRef orelse return;
                var tidBuf: [TID_LEN]u16 = [_]u16{0} ** TID_LEN;
                const tidH = buildTid(&tidBuf, pkN, "_retroMod_", nameRef);
                const ku212_start = profStartSect();
                queueTimer(&tidBuf, tidH, rem, 3, pkN, nameRef, currentTime);
                profSpan(KU_BASE + 212, ku212_start); // ku212 span: queue retro modifier timer
            }
        }
    }
    if (!isModKey and
        g_kbLen == g_ordLen and
        g_ordLen > 0 and
        ordAt(0) == keyVK and
        g_active_virtual_modifier_count == 0 and
        g_active_physical_and_windows_facing_modifiers == 0 and
        keyData.actionType == .undecided and
        !keyData.comboTriggered() and
        !keyData.modifierPressed() and
        !keyData.modifierActivated() and
        !keyData.modifierTriggered() and
        keyData.tidCount == 0 and
        keyData.sameModTidHash == 0)
    {
        if (keyNameRef) |nameRefHead| {
            const actionHead = classifyReleasedNonModAction(keyVK, kuHold, duration, keyData.hasInterferingKeys(), false);
            const contaminatedHead = keyData.isContaminated();

            ordRemoveFirst();
            _ = kbRemove(keyVK);
            if (actionHead == .tap) {
                const ku213_start = profStartSect();
                queueDirectTapCallback(keyVK, nameRefHead);
                profSpan(KU_BASE + 213, ku213_start); // ku213 span: head-oldest tap queueDirectTapCallback
                const ku214_start = profStartSect();
                while (drainHeadOldestKeyupTap()) {}
                profSpan(KU_BASE + 214, ku214_start); // ku214 span: head-oldest tap drain loop
            } else if (actionHead == .hold) {
                if (!contaminatedHead) {
                    if (queueHoldCallbackOnce(keyVK, nameRefHead)) {
                        const ku215_start = profStartSect();
                        profSpan(KU_BASE + 215, ku215_start); // ku215 span: head-oldest hold queueCallback
                    } else {
                        const ku216_start = profStartSect();
                        queueDirectTapCallback(keyVK, nameRefHead);
                        profSpan(KU_BASE + 216, ku216_start); // ku216 span: head-oldest hold fallback direct tap
                    }
                }
                const ku217_start = profStartSect();
                while (drainHeadOldestKeyupTap()) {}
                profSpan(KU_BASE + 217, ku217_start); // ku217 span: head-oldest hold drain loop
            }
            return;
        }
    }
    if (duration < g_SingleKeyHoldThreshold and !keyData.hasInterferingKeys() and !keyData.comboTriggered()) {
        if (kuFastTapPlain) {
            keyData.actionType = .tap;
            if (keyData.tidCount != 0) {
                const ku218_start = profStartSect();
                cancelKeyTimers(keyVK);
                profSpan(KU_BASE + 218, ku218_start); // ku218 span: fast tap cancelKeyTimers
            }
            const ku219_start = profStartSect();
            processQueueAfterKeyUp();
            profSpan(KU_BASE + 219, ku219_start); // ku219 span: fast tap processQueueAfterKeyUp
            return;
        }
    }
    const ku220_start = profStartSect();
    processQueueAfterKeyUp();
    profSpan(KU_BASE + 220, ku220_start); // ku220 span: final processQueueAfterKeyUp
}
// ============================================================================
// Section 20 — DLL exports: lifecycle & configuration
// ============================================================================
var g_is_initialized: bool = false;
var g_precompiledShortcutsApplied: bool = false;
var g_precompiledShortcutsLoadStarted: bool = false;
// Compiled callback fields are stable zero-based slots from the generated
// module, not runtime callback IDs.  AHK binds those slots after QMK.Init()
// has preloaded the compiled rows.  The published lengths below delimit the
// compiled prefix so runtime rows are never rewritten by this bridge.
const COMPILED_CALLBACK_SLOT_MAX: usize = 4096;
var g_compiledCallbackBindings: [COMPILED_CALLBACK_SLOT_MAX]i32 = [_]i32{-1} ** COMPILED_CALLBACK_SLOT_MAX;
const COMPILED_ZIG_CALLBACK_ID_BASE: i32 = -0x3000_0000;

fn precompiledCallbackId(slot: i32) i32 {
    if (slot < 0) return slot;
    if (comptime has_compiled_user_shortcuts_build and @hasDecl(compiled_user_shortcuts, "Compiled_Callbacks")) {
        // Large generated callback tables are intentionally compile-time data.
        // Raise Zig's evaluator budget for this lookup; this does not add a
        // runtime loop or change the callback ABI.
        @setEvalBranchQuota(1_000_000);
        inline for (compiled_user_shortcuts.Compiled_Callbacks.zig) |descriptor| {
            if (descriptor.slot == @as(u32, @intCast(slot))) return COMPILED_ZIG_CALLBACK_ID_BASE - slot;
        }
        inline for (compiled_user_shortcuts.Compiled_Callbacks.ahk) |descriptor| {
            if (descriptor.slot == @as(u32, @intCast(slot))) return COMPILED_ZIG_CALLBACK_ID_BASE - slot;
        }
    }
    return slot;
}

inline fn isCompiledZigCallbackId(callback_id: i32) bool {
    return callback_id <= COMPILED_ZIG_CALLBACK_ID_BASE and
        callback_id > COMPILED_ZIG_CALLBACK_ID_BASE - @as(i32, @intCast(COMPILED_CALLBACK_SLOT_MAX));
}
// Test-only observability. This remains disabled for normal build-options
// modules and records only the family counts successfully preloaded by the
// typed compiled-shortcut adapter. The public fixture taxonomy keeps normal
// and instant combos, external and internal chords, and the two native
// controls distinct even though some runtime stores are shared.
var g_precompiledFamilyCounts: [14]u32 = [_]u32{0} ** 14;
// Set to true the first time QMK_SetUserConfig is called. Prevents the
// post-warmup defaults in QMK_SetInterceptionCallbacks from overwriting
// user settings in any call-order scenario.
var g_userConfigApplied: bool = false;
var g_physModBitTable: [256]u16 = [_]u16{0} ** 256;

// ============================================================================
// Modifier poll thread state (Idea 7 — unified single thread)
// One background thread polls ALL 8 modifier VKs via GetAsyncKeyState.
// On any new PhysModDown, g_modPollGeneration is bumped — the running thread
// sees the change and restarts its down-time/VK capture, so only one thread
// ever runs at a time.  When all 8 VKs are physically up, the thread clears
// g_active_physical_modifiers entirely and exits.
// ============================================================================
const ALL_MOD_VKS = [8]i32{ 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0x5B, 0x5C };
// LShift, RShift, LCtrl, RCtrl, LAlt, RAlt, LWin, RWin
// Collapsed mask for each VK above (same order)
const ALL_MOD_MASKS = [8]u16{ 0x04, 0x04, 0x01, 0x01, 0x02, 0x02, 0x08, 0x08 };
const MOD_POLL_TIMEOUT_MS: u32 = 5000;
const MOD_POLL_INTERVAL_MS: u32 = 3;
// 0 = no thread running, 1 = thread running
var g_modPollActive: i32 = 0;
// Bumped on every PhysModDown. Thread compares its local copy each iteration;
// if changed, a new modifier was pressed so it re-captures down state.
var g_modPollGeneration: i32 = 0;
var g_modPollStopGeneration: i32 = 0;

fn modPollThreadProc(_: ?*anyopaque) callconv(.winapi) u32 {
    var elapsed: u32 = 0;
    var seenGen: i32 = @atomicLoad(i32, &g_modPollGeneration, .acquire);
    const stopGen = @atomicLoad(i32, &g_modPollStopGeneration, .acquire);

    while (true) {
        Sleep(MOD_POLL_INTERVAL_MS);
        if (stopGen != @atomicLoad(i32, &g_modPollStopGeneration, .acquire)) {
            @atomicStore(i32, &g_modPollActive, 0, .release);
            return 0;
        }
        elapsed += MOD_POLL_INTERVAL_MS;

        // If a new key was pressed since we last checked, reset the timeout
        // so we don't cut out while modifiers are still being used.
        const curGen = @atomicLoad(i32, &g_modPollGeneration, .acquire);
        if (curGen != seenGen) {
            seenGen = curGen;
            elapsed = 0;
        }

        // Check all 8 modifier VKs physically
        var anyDown = false;
        inline for (ALL_MOD_VKS) |vk| {
            if ((GetAsyncKeyState(vk) & @as(i16, -0x8000)) != 0) {
                anyDown = true;
                break;
            }
        }
        if (!anyDown) {
            if (hiddenPhysicalModsFromOs() != 0) {
                @atomicStore(i32, &g_modPollActive, 0, .release);
                return 0;
            }
            const gen_before_clear = @atomicLoad(i32, &g_modPollGeneration, .acquire);
            if (gen_before_clear != seenGen) {
                seenGen = gen_before_clear;
                elapsed = 0;
                continue;
            }
            if (stopGen != @atomicLoad(i32, &g_modPollStopGeneration, .acquire)) {
                @atomicStore(i32, &g_modPollActive, 0, .release);
                return 0;
            }
            // All modifiers physically released — check every modifier VK independently.
            // This ensures LCtrl, RCtrl, LAlt, etc. each get their own double-tap test
            // with no shared slot that one side can overwrite for another.
            const releaseTime = getTime();
            for (ALL_MOD_VKS) |vk| {
                const downTime = g_modPollDownTime[@intCast(vk)];
                if (downTime == 0.0) continue; // this VK was never pressed in this cycle
                // Resolve the runtime overlay first.  The derived key-gate
                // snapshot is optimized for ordinary key dispatch, but the
                // physical-modifier poll path must use the same effective
                // callback selection as the runtime takeover path.
                const cbId = effectiveDoubleTapCallbackId(@intCast(vk));
                if (cbId != -1) {
                    const pressDuration = releaseTime - downTime;
                    const priorUp = g_modPollLastUpTime[@intCast(vk)];
                    if (pressDuration < g_DoubleTapThreshold and
                        priorUp > 0.0 and (downTime - priorUp) < g_DoubleTapThreshold)
                    {
                        if (cachedNameFromVK(vk)) |nr| {
                            queueCallback(cbId, nr, @ptrCast(&[_:0]u16{0}), 6);
                            notifyAHK(true, false);
                        }
                    }
                }
                g_modPollLastUpTime[@intCast(vk)] = releaseTime;
                g_modPollDownTime[@intCast(vk)] = 0.0; // clear so next cycle starts fresh
            }
            const gen_before_sync = @atomicLoad(i32, &g_modPollGeneration, .acquire);
            if (gen_before_sync != seenGen) {
                seenGen = gen_before_sync;
                elapsed = 0;
                continue;
            }
            if (stopGen != @atomicLoad(i32, &g_modPollStopGeneration, .acquire)) {
                @atomicStore(i32, &g_modPollActive, 0, .release);
                return 0;
            }
            // GetAsyncKeyState is not authoritative for QMK physical truth here;
            // real event ingress owns g_physicalKeyDown/g_lr_active_physical_modifiers.
            @atomicStore(i32, &g_modPollActive, 0, .release);
            return 0;
        }
        if (elapsed >= MOD_POLL_TIMEOUT_MS) {
            const gen_before_timeout_clear = @atomicLoad(i32, &g_modPollGeneration, .acquire);
            if (gen_before_timeout_clear != seenGen) {
                seenGen = gen_before_timeout_clear;
                elapsed = 0;
                continue;
            }
            if (stopGen != @atomicLoad(i32, &g_modPollStopGeneration, .acquire)) {
                @atomicStore(i32, &g_modPollActive, 0, .release);
                return 0;
            }
            const gen_before_timeout_sync = @atomicLoad(i32, &g_modPollGeneration, .acquire);
            if (gen_before_timeout_sync != seenGen) {
                seenGen = gen_before_timeout_sync;
                elapsed = 0;
                continue;
            }
            break;
        }
    }
    // Timeout stops the helper thread only. It must not overwrite live
    // event-driven physical state from a possibly stale Windows async table.
    @atomicStore(i32, &g_modPollActive, 0, .release);
    return 0;
}

fn stopModPollThread() bool {
    _ = @atomicRmw(i32, &g_modPollStopGeneration, .Add, 1, .acq_rel);
    _ = @atomicRmw(i32, &g_modPollGeneration, .Add, 1, .acq_rel);
    var spin: u32 = 0;
    while (@atomicLoad(i32, &g_modPollActive, .acquire) != 0 and spin < 200) : (spin += 1) {
        Sleep(1);
    }
    return @atomicLoad(i32, &g_modPollActive, .acquire) == 0;
}

fn isSubscribedKeyboard(dev: InterceptionDevice) callconv(.c) i32 {
    return interception_is_keyboard(dev);
}

inline fn isModVK(vk: i32) bool {
    return vk == 0x10 or vk == 0x11 or vk == 0x12 or vk == 0xA0 or vk == 0xA1 or vk == 0xA2 or vk == 0xA3 or vk == 0xA4 or vk == 0xA5 or vk == 0x5B or vk == 0x5C;
}

inline fn normalizeModVK(vk: i32, stroke: *const InterceptionKeyStroke) i32 {
    if (vk == VK_SHIFT) {
        // Shift left/right is encoded by scan code 0x2A/0x36.
        if (stroke.code == 0x36) return 0xA1;
        return 0xA0;
    }
    if (vk == VK_CONTROL) {
        if ((stroke.state & IKEY_E0) != 0) return 0xA3;
        return 0xA2;
    }
    if (vk == VK_MENU) {
        if ((stroke.state & IKEY_E0) != 0) return 0xA5;
        return 0xA4;
    }
    // AHK `#` means either Win key. Disambiguate LWin/RWin from scan code when MVK is vague.
    if (vk == VK_LWIN or vk == 0x5C) {
        if (stroke.code == 0x5C) return 0x5C;
        if (stroke.code == 0x5B) return 0x5B;
        return vk;
    }
    return vk;
}

inline fn strokeVKCacheIndex(stroke: *const InterceptionKeyStroke) usize {
    return @as(usize, stroke.code & 0xFF) |
        (if ((stroke.state & IKEY_E0) != 0) @as(usize, 256) else 0);
}

inline fn strokeToVKRaw(stroke: *const InterceptionKeyStroke) i32 {
    var scanEx: u32 = stroke.code;
    if ((stroke.state & IKEY_E0) != 0) scanEx |= 0xE000;

    // Primary translation path for interception scan-code strokes.
    var mapped: u32 = MapVirtualKeyW(scanEx, MAPVK_VSC_TO_VK_EX);
    if (mapped == 0) {
        // Fallback path for devices/drivers that do not surface EX mapping.
        mapped = MapVirtualKeyW(scanEx & 0xFF, MAPVK_VSC_TO_VK);
    }
    if (mapped == 0) {
        // Win keys are E0-prefixed; recover when MVK returns nothing.
        if ((stroke.state & IKEY_E0) != 0) {
            return switch (stroke.code) {
                0x5B => 0x5B,
                0x5C => 0x5C,
                else => 0,
            };
        }
        return 0;
    }

    const vk: i32 = @intCast(mapped & 0xFF);
    return normalizeModVK(vk, stroke);
}

inline fn strokeToVK(stroke: *const InterceptionKeyStroke) i32 {
    const idx = strokeVKCacheIndex(stroke);
    const cached = g_strokeVKCache[idx];
    if (cached >= 0) return cached;
    const mapped = strokeToVKRaw(stroke);
    g_strokeVKCache[idx] = @intCast(mapped);
    return mapped;
}

fn warmStrokeVKCache() void {
    var code: u16 = 0;
    while (code < 256) : (code += 1) {
        var stroke = InterceptionKeyStroke{ .code = code, .state = 0, .information = 0 };
        g_strokeVKCache[@as(usize, code)] = @intCast(strokeToVKRaw(&stroke));
        stroke.state = IKEY_E0;
        g_strokeVKCache[@as(usize, code) | 256] = @intCast(strokeToVKRaw(&stroke));
    }
}

inline fn backendAllowsInterceptionCapture() bool {
    return g_inputBackend == INPUT_BACKEND_AUTO or g_inputBackend == INPUT_BACKEND_INTERCEPTION;
}

inline fn backendAllowsLLHookCapture() bool {
    return g_inputBackend == INPUT_BACKEND_AUTO or g_inputBackend == INPUT_BACKEND_LLHOOK;
}

inline fn normalizeInputBackend(mode: i32) i32 {
    return switch (mode) {
        INPUT_BACKEND_INTERCEPTION => INPUT_BACKEND_INTERCEPTION,
        INPUT_BACKEND_LLHOOK => INPUT_BACKEND_LLHOOK,
        INPUT_BACKEND_AHK_HOTKEYS => INPUT_BACKEND_AHK_HOTKEYS,
        else => INPUT_BACKEND_AUTO,
    };
}

inline fn backendWantsAhkHotkeys() bool {
    if (g_inputBackend == INPUT_BACKEND_AHK_HOTKEYS) return true;
    if (g_inputBackend == INPUT_BACKEND_INTERCEPTION) return !g_interceptionCaptureReady;
    return !g_interceptionCaptureReady and !g_llHookReady;
}

inline fn configuredInputBackendName() []const u8 {
    return switch (g_inputBackend) {
        INPUT_BACKEND_INTERCEPTION => "Interception Driver Capture",
        INPUT_BACKEND_LLHOOK => "Zig Low-Level Hook",
        INPUT_BACKEND_AHK_HOTKEYS => "AutoHotkey Hotkeys",
        else => "Auto",
    };
}

inline fn configuredSendModeName() []const u8 {
    if (g_sendModeAuto) return "Auto sends (Interception driver if available)";
    return if (g_useKernel) "Interception driver sends" else "DLL SendInput only";
}

inline fn activeInputBackendName() []const u8 {
    if (g_interceptionCaptureReady) return "Interception Driver Capture";
    if (g_llHookReady) return "Zig Low-Level Hook";
    if (backendWantsAhkHotkeys()) return "AutoHotkey Hotkeys";
    return "Native capture inactive";
}

inline fn activeInputBackendCode() i32 {
    if (g_interceptionCaptureReady) return INPUT_BACKEND_INTERCEPTION;
    if (g_llHookReady) return INPUT_BACKEND_LLHOOK;
    if (backendWantsAhkHotkeys()) return INPUT_BACKEND_AHK_HOTKEYS;
    return -1;
}

inline fn llHookEventToVK(info: *const KBDLLHOOKSTRUCT, is_down: bool) i32 {
    var state: u16 = if (is_down) IKEY_DOWN else IKEY_UP;
    if ((info.flags & LLKHF_EXTENDED) != 0) state |= IKEY_E0;
    const stroke = InterceptionKeyStroke{
        .code = @intCast(info.scanCode & 0xFFFF),
        .state = state,
        .information = @intCast(info.dwExtraInfo & 0xFFFF_FFFF),
    };
    const raw_vk: i32 = @intCast(info.vkCode & 0xFF);
    return normalizeModVK(raw_vk, &stroke);
}

fn processNativeCapturedVK(vk: i32, is_down: bool) bool {
    beginHotPathActivity();
    defer endHotPathActivity(is_down);
    if (isModVK(vk)) {
        const incoming_tracked_vk = physicalModifierTrackingVK(vk);
        const hidden_up = !is_down and physicalModifierHiddenFromOs(incoming_tracked_vk);
        const tracked_vk = apply_physical_modifier_event(vk, is_down);
        if (is_down) cancelRepeatForDifferentKeyDown(tracked_vk);
        if (!is_down) cancelRepeatForRequiredKeyUp(tracked_vk);
        if (is_down) markPhysicalModifierHiddenFromOs(tracked_vk);
        markGenericTapHoldInterrupted(tracked_vk, is_down);
        const modMask = compute_modifiers_to_send();
        handleNativePanicExitIfMatched(tracked_vk, modMask, is_down);
        handleNativeReloadIfMatched(tracked_vk, modMask, is_down);
        if (handleNativeSuspendIfMatched(tracked_vk, modMask, is_down)) return true;
        const consumed = if (is_down)
            queueReversePhysicalModHotkeyIfMatched(tracked_vk, modMask) or queueAnyHotkeyIfMatchedWithGenericModFallback(tracked_vk, modMask, true)
        else
            queueAnyHotkeyIfMatchedWithGenericModFallback(tracked_vk, modMask, false);
        if (consumed and !is_down) cleanupBufferedKeyAfterConsumedKeyUp(tracked_vk);
        if (is_down) {
            if (consumed) {
                markPhysicalModifierHiddenFromOs(tracked_vk);
            } else if (!g_physical_modifier_passthrough) {
                markPhysicalModifierHiddenFromOs(tracked_vk);
            } else {
                clearPhysicalModifierHiddenFromOs(tracked_vk);
            }
        } else if (hidden_up) {
            clearPhysicalModifierHiddenFromOs(tracked_vk);
        }
        return consumed or hidden_up or !g_physical_modifier_passthrough;
    }
    prepareStructuralModifierContext(vk, is_down);
    setPhysicalKeyDownState(vk, is_down);
    markGenericTapHoldInterrupted(vk, is_down);
    const qmk_mod_mask = compute_modifiers_to_send();
    // Contextual tap/hold and double-tap rows use the same candidate-first
    // rule as ordinary hotkeys. Do not rely on the context-filtered callback
    // bank to decide that the VK has no contextual registration.
    if (shouldPrepareStructuralHotkeyContext(vk, is_down))
        _ = prepareStructuralHotkeyContext(vk, qmk_mod_mask, is_down);
    prepareStructuralContextAction(vk);
    handleNativePanicExitIfMatched(vk, qmk_mod_mask, is_down);
    handleNativeReloadIfMatched(vk, qmk_mod_mask, is_down);
    if (handleNativeSuspendIfMatched(vk, qmk_mod_mask, is_down)) return true;

    if (@atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire) != 0) {
        const consumed = queueAnyHotkeyIfMatchedWithGenericModFallback(vk, qmk_mod_mask, is_down);
        if (consumed and !is_down) cleanupBufferedKeyAfterConsumedKeyUp(vk);
        return consumed;
    }

    const tap_hold_owns_release = !is_down and vk > 0 and vk < VK_COUNT and
        g_tapHoldArmed[@intCast(vk)];
    const contextual_tap_owns_release = !is_down and vk > 0 and vk < VK_COUNT and
        g_contextualTapArmed[@intCast(vk)];
    // Solo contextual tap rows (including SetupTaps 1:1 remaps) are kept out
    // of the ordinary matcher by shouldDeferRuntimeContextualTapHotkey.  They
    // therefore must be offered to this arming path independently of whether
    // the key also has a generic tap/hold registration.  The matcher itself
    // enforces the solo-only rule, so chords, modifiers, and buffered keys
    // continue through the normal hotkey/tap-hold paths.
    if (shouldArmRuntimeContextualTapHotkey(vk, is_down) and qmk_mod_mask == 0 and
        tryArmRuntimeContextualTapHotkey(vk, qmk_mod_mask))
    {
        return true;
    }
    if (genericTapHoldConfigured(vk) and !contextual_tap_owns_release and
        (!is_down or !keySequenceActive()) and
        (qmk_mod_mask == 0 or tap_hold_owns_release)) {
        return handleGenericTapHold(vk, is_down);
    }

    if (isPassthroughVK(vk)) {
        const consumed = queueAnyHotkeyIfMatched(vk, qmk_mod_mask, is_down);
        if (consumed and !is_down) cleanupBufferedKeyAfterConsumedKeyUp(vk);
        if (!consumed) observePassthroughHotstring(vk, is_down);
        return consumed;
    }

    const modMask = compute_modifiers_to_send();
    if (queueAnyHotkeyIfMatched(vk, modMask, is_down)) {
        if (is_down) hotstringRecordConsumedKeyDown(vk);
        if (!is_down) cleanupBufferedKeyAfterConsumedKeyUp(vk);
        if (!is_down and vk > 0 and vk < VK_COUNT) g_native_passthrough_to_windows[@intCast(vk)] = false;
        return true;
    }
    if (shouldForwardNativeModifiedStroke(vk, is_down)) {
        if (is_down) sendPhysicalModsBeforeNativeForward(AHK_SENDLEVEL_2, true);
        recordNativeModifiedStrokeForwarded(vk, is_down);
        return false;
    }
    processKeyEventHot(vk, if (is_down) 1 else 0);
    return true;
}

fn lowLevelKeyboardProc(nCode: i32, wParam: usize, lParam: isize) callconv(.winapi) isize {
    if (nCode < 0) return CallNextHookEx(g_llHookHandle, nCode, wParam, lParam);
    const info: *const KBDLLHOOKSTRUCT = @ptrFromInt(@as(usize, @bitCast(lParam)));

    // Let synthetic events pass through without re-entering QMK. DLL SendInput
    // uses our extra-info tag; AHK callback SendInput usually only has the
    // Windows injected flag, which matters for media keys that also have QMK rows.
    if (info.dwExtraInfo == AHK_SENDLEVEL_2 or (info.flags & LLKHF_INJECTED) != 0) {
        return CallNextHookEx(g_llHookHandle, nCode, wParam, lParam);
    }

    const is_down = wParam == WM_KEYDOWN or wParam == WM_SYSKEYDOWN;
    const is_up = wParam == WM_KEYUP or wParam == WM_SYSKEYUP or (info.flags & LLKHF_UP) != 0;
    if (!is_down and !is_up) return CallNextHookEx(g_llHookHandle, nCode, wParam, lParam);

    const vk = llHookEventToVK(info, is_down);
    if (vk <= 0 or vk >= VK_COUNT) return CallNextHookEx(g_llHookHandle, nCode, wParam, lParam);

    ensureQmkInputThreadPriority();
    const consumed = processNativeCapturedVK(vk, is_down);
    g_llHookEventCount +%= 1;
    g_llHookLastVK = vk;
    g_llHookLastScan = @intCast(info.scanCode & 0xFFFF);
    g_llHookLastFlags = @intCast(info.flags & 0xFFFF);
    g_llHookLastIsDown = if (is_down) 1 else 0;
    g_llHookLastMods = compute_modifiers_to_send();
    g_llHookLastConsumed = if (consumed) 1 else 0;
    if (consumed) return 1;
    return CallNextHookEx(g_llHookHandle, nCode, wParam, lParam);
}

fn llHookThreadProc(_: ?*anyopaque) callconv(.winapi) u32 {
    _ = SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);
    g_llHookThreadId = GetCurrentThreadId();
    const startGen = @atomicLoad(i32, &g_llHookStopGeneration, .acquire);
    var bootstrap_msg: MSG = undefined;
    _ = PeekMessageW(&bootstrap_msg, null, 0, 0, PM_NOREMOVE);
    const hook = SetWindowsHookExW(WH_KEYBOARD_LL, lowLevelKeyboardProc, null, 0) orelse {
        g_llHookReady = false;
        @atomicStore(i32, &g_llHookThreadActive, 0, .release);
        return 0;
    };
    g_llHookHandle = hook;
    g_llHookReady = true;

    var msg: MSG = undefined;
    while (@atomicLoad(i32, &g_llHookStopGeneration, .acquire) == startGen) {
        const got = GetMessageW(&msg, null, 0, 0);
        if (got <= 0) break;
        _ = TranslateMessage(&msg);
        _ = DispatchMessageW(&msg);
    }

    if (g_llHookHandle) |hh| {
        _ = UnhookWindowsHookEx(hh);
    }
    g_llHookHandle = null;
    g_llHookReady = false;
    g_llHookThreadId = 0;
    @atomicStore(i32, &g_llHookThreadActive, 0, .release);
    return 0;
}

fn startLLHookCapture() bool {
    if (@atomicRmw(i32, &g_llHookThreadActive, .Xchg, 1, .acq_rel) != 0) return g_llHookReady;
    if (CreateThread(null, 0, llHookThreadProc, null, 0, null)) |hThread| {
        _ = CloseHandle(hThread);
        var spin: u32 = 0;
        while (!g_llHookReady and @atomicLoad(i32, &g_llHookThreadActive, .acquire) != 0 and spin < 200) : (spin += 1) {
            Sleep(1);
        }
        return g_llHookReady;
    }
    @atomicStore(i32, &g_llHookThreadActive, 0, .release);
    return false;
}

fn stopLLHookCapture() bool {
    _ = @atomicRmw(i32, &g_llHookStopGeneration, .Add, 1, .acq_rel);
    const tid = g_llHookThreadId;
    if (tid != 0) {
        _ = PostThreadMessageW(tid, WM_QUIT, 0, 0);
    }
    var spin: u32 = 0;
    while (@atomicLoad(i32, &g_llHookThreadActive, .acquire) != 0 and spin < 200) : (spin += 1) {
        Sleep(1);
    }
    return @atomicLoad(i32, &g_llHookThreadActive, .acquire) == 0;
}

fn stopInterceptionCaptureOnly(preserve_send_context: bool) bool {
    _ = @atomicRmw(i32, &g_pollStopGeneration, .Add, 1, .acq_rel);
    _ = @atomicRmw(i32, &g_interceptionInitGeneration, .Add, 1, .acq_rel);
    var init_spin: u32 = 0;
    while (@atomicLoad(i32, &g_interceptionInitActive, .acquire) != 0 and init_spin < 500) : (init_spin += 1) {
        Sleep(1);
    }
    const init_still_active = @atomicLoad(i32, &g_interceptionInitActive, .acquire) != 0;
    if (!init_still_active and g_captureCtx != null) {
        const ctx = g_captureCtx.?;
        if (fp_set_filter != null) interception_set_filter(ctx, isSubscribedKeyboard, INTERCEPTION_FILTER_KEY_NONE);
        // The capture thread blocks in interception_wait_with_timeout(INFINITE).
        // Destroying only the capture context wakes it without disturbing the
        // long-lived send context used by ringSend().
        interception_destroy_context(ctx);
        g_captureCtx = null;
    } else if (g_captureCtx != null and fp_set_filter != null) {
        interception_set_filter(g_captureCtx.?, isSubscribedKeyboard, INTERCEPTION_FILTER_KEY_NONE);
    }
    var spin: u32 = 0;
    while (@atomicLoad(i32, &g_pollThreadActive, .acquire) != 0 and spin < 200) : (spin += 1) {
        Sleep(1);
    }
    const poll_stopped = @atomicLoad(i32, &g_pollThreadActive, .acquire) == 0;
    const stopped = !init_still_active and poll_stopped;
    if (!stopped) {
        if (g_captureCtx != null and fp_set_filter != null) {
            interception_set_filter(g_captureCtx.?, isSubscribedKeyboard, INTERCEPTION_FILTER_KEY_ALL);
        }
        g_interceptionCaptureReady = g_captureCtx != null and @atomicLoad(i32, &g_pollThreadActive, .acquire) != 0;
        if (preserve_send_context) {
            g_interceptionSendReady = g_useKernel and g_sendCtx != null and g_sendDev > 0;
        }
        return false;
    }
    g_interceptionCaptureReady = false;
    if (!preserve_send_context) {
        acquireSendRingLock();
        defer releaseSendRingLock();
        if (!init_still_active and poll_stopped and g_sendCtx != null) {
            interception_destroy_context(g_sendCtx.?);
            g_sendCtx = null;
        }
        if (!init_still_active and poll_stopped) {
            g_sendDev = 0;
            g_interceptionSendReady = false;
        }
    } else {
        g_interceptionSendReady = g_useKernel and g_sendCtx != null and g_sendDev > 0;
    }
    return true;
}

fn notifyInputBackendState() void {
    if (backendWantsAhkHotkeys()) {
        _ = pushIpcControl(ipc.IPC_REGISTER_KEYS);
    } else {
        _ = pushIpcControl(ipc.IPC_UNREGISTER_KEYS);
    }
}

fn haveInterceptionCallbacks() bool {
    return fp_create_context != null and
        fp_destroy_context != null and
        fp_send != null and
        fp_is_keyboard != null and
        fp_set_filter != null and
        fp_receive != null and
        fp_wait_with_timeout != null;
}

fn interceptionInitAlreadySatisfied() bool {
    if (g_sendCtx == null or g_sendDev <= 0) return false;
    if (!backendAllowsInterceptionCapture()) return true;
    return g_interceptionCaptureReady and @atomicLoad(i32, &g_pollThreadActive, .acquire) != 0;
}

fn clearNativeCaptureStateOnly() void {
    QMK_ReleaseStuckModifiers();
    pendingSoloClear();
    pendingRollClear();
    kbClear();
    ordClear();
    timerClear();
    clear_active_virtual_modifiers();
    @memset(&g_activeModPresent, false);
    @memset(&g_activeModIdx, -1);
    clearPhysicalKeyDownState();
    @memset(&g_foreignPhysicalKeyDown, false);
    g_foreignPhysicalQuarantineArmed = false;
    g_trackedPhysicalKeysDown = 0;
    @memset(&g_native_passthrough_to_windows, false);
    @memset(&g_hotkey_consumed_down, false);
    @memset(&g_contextualTapArmed, false);
    @memset(&g_contextualTapCallbackId, -1);
    @memset(&g_contextualTapHoldCallbackId, -1);
    @memset(&g_contextualTapCleanupCallbackId, -1);
    @memset(&g_contextualTapThreshold, 0);
    @memset(&g_contextualTapDownTime, 0);
    g_active_physical_modifiers = 0;
    g_any_physical_modifiers_active = false;
    g_which_physical_modifiers_to_send = 0;
    g_lr_active_physical_modifiers = 0;
    @memset(&g_active_physical_modifier_key_counts_by_category, 0);
    g_unreleasedKeyCount = 0;
    g_unreleasedNonModCount = 0;
    g_unrelModCount = 0;
    g_cleanUnrelModCount = 0;
    g_activeModKeyCnt = 0;
    g_modStackDirty = false;
}

fn startInterceptionInitAsync() bool {
    if (!haveInterceptionCallbacks()) return false;
    if (interceptionInitAlreadySatisfied()) return true;
    if (@atomicRmw(i32, &g_interceptionInitActive, .Xchg, 1, .acq_rel) != 0) return true;
    g_interceptionInitThreadGeneration = @atomicLoad(i32, &g_interceptionInitGeneration, .acquire);
    if (CreateThread(null, 0, initInterceptionThreadProc, null, 0, null)) |hThread| {
        _ = CloseHandle(hThread);
        return true;
    }
    @atomicStore(i32, &g_interceptionInitActive, 0, .release);
    return false;
}

fn reconcileInputBackend() void {
    if (g_inputBackend == INPUT_BACKEND_LLHOOK or g_inputBackend == INPUT_BACKEND_AHK_HOTKEYS) {
        if (!stopInterceptionCaptureOnly(g_useKernel)) {
            notifyInputBackendState();
            return;
        }
    }
    if (g_inputBackend == INPUT_BACKEND_AHK_HOTKEYS or g_inputBackend == INPUT_BACKEND_INTERCEPTION) {
        if (!stopLLHookCapture()) {
            notifyInputBackendState();
            return;
        }
    }
    if (!g_is_initialized) {
        notifyInputBackendState();
        return;
    }
    if (g_inputBackend == INPUT_BACKEND_INTERCEPTION or (g_inputBackend == INPUT_BACKEND_AHK_HOTKEYS and g_useKernel)) {
        _ = startInterceptionInitAsync();
    } else if (g_inputBackend == INPUT_BACKEND_LLHOOK) {
        if (g_useKernel) _ = startInterceptionInitAsync();
        _ = startLLHookCapture();
    } else if (backendAllowsLLHookCapture() and !g_interceptionCaptureReady) {
        const started_interception = startInterceptionInitAsync();
        if (!started_interception) _ = startLLHookCapture();
    }
    notifyInputBackendState();
}

fn ensureAsyncSendWorker() void {
    if (g_async_thread) |th| {
        const wait_result = WaitForSingleObject(th, 0);
        if (wait_result == WAIT_OBJECT_0) {
            _ = CloseHandle(th);
            g_async_thread = null;
            if (g_async_event) |ev| {
                _ = CloseHandle(ev);
                g_async_event = null;
            }
            @atomicStore(u32, &g_async_head, 0, .release);
            @atomicStore(u32, &g_async_tail, 0, .release);
        } else {
            return;
        }
    }
    g_async_event = CreateEventW(null, FALSE, FALSE, null);
    if (g_async_event == null) return;
    @atomicStore(i32, &g_async_active, 1, .release);
    g_async_thread = CreateThread(null, 0, asyncSendThreadProc, null, 0, null);
    if (g_async_thread == null) {
        @atomicStore(i32, &g_async_active, 0, .release);
        if (g_async_event) |ev| {
            _ = CloseHandle(ev);
        }
        g_async_event = null;
    }
}

// fn subscriptionPollThreadProc(_: ?*anyopaque) callconv(.winapi) u32 {
//     _ = SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);
//     _ = SetThreadAffinityMask(GetCurrentThread(), POLL_AFFINITY_MASK);

//     const startGen = @atomicLoad(i32, &g_pollStopGeneration, .acquire);
//     if (g_ictx == null) {
//         @atomicStore(i32, &g_pollThreadActive, 0, .release);
//         return 0;
//     }

//     var stroke: InterceptionKeyStroke = .{ .code = 0, .state = 0, .information = 0 };
//     var device: InterceptionDevice = 0;
//     while (@atomicLoad(i32, &g_pollStopGeneration, .acquire) == startGen) {
//         const ctx = g_ictx orelse break;
//         const waitedDev = interception_wait_with_timeout(ctx, POLL_WAIT_TIMEOUT_MS);
//         if (@atomicLoad(i32, &g_pollStopGeneration, .acquire) != startGen) break;
//         if (waitedDev <= 0) continue;
//         device = waitedDev;

//         while (@atomicLoad(i32, &g_pollStopGeneration, .acquire) == startGen) {
//             if (interception_receive(ctx, device, @ptrCast(&stroke), 1) <= 0) break;

//             const isSynthetic = (@as(usize, stroke.information) == AHK_SENDLEVEL_2);
//             if (isSynthetic) {
//                 _ = interception_send(ctx, device, @ptrCast(&stroke), 1);
//             } else {
//                 const vk = strokeToVK(&stroke);
//                 if (vk <= 0) {
//                     _ = interception_send(ctx, device, @ptrCast(&stroke), 1);
//                 }
//                 else {
//                     const isDown = (stroke.state & IKEY_UP) == 0;
//                     if (vk >= 0 and vk < VK_COUNT) g_physicalKeyDown[@intCast(vk)] = isDown;

//                     if (isPassthroughVK(vk)) {
//                         _ = interception_send(ctx, device, @ptrCast(&stroke), 1);
//                     } else if (isModVK(vk)) {
//                         if (isDown) QMK_PhysModDownVK(vk) else QMK_PhysModUp(getSysModBit(vk));
//                         _ = interception_send(ctx, device, @ptrCast(&stroke), 1);
//                     } else {
//                         QMK_ProcessKeyEvent(vk, if (isDown) 1 else 0);
//                     }
//                 }
//             }

//             // Drain buffered strokes immediately to reduce wake/sleep jitter.
//             const nextDev = interception_wait_with_timeout(ctx, 0);
//             if (nextDev <= 0) break;
//             device = nextDev;
//         }
//     }

//     @atomicStore(i32, &g_pollThreadActive, 0, .release);
//     return 0;
// }

fn subscriptionPollThreadProc(_: ?*anyopaque) callconv(.winapi) u32 {
    _ = SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);
    _ = SetThreadAffinityMask(GetCurrentThread(), POLL_AFFINITY_MASK);

    const startGen = @atomicLoad(i32, &g_pollStopGeneration, .acquire);
    if (g_captureCtx == null) {
        @atomicStore(i32, &g_pollThreadActive, 0, .release);
        return 0;
    }

    var stroke: InterceptionKeyStroke = .{ .code = 0, .state = 0, .information = 0 };
    var device: InterceptionDevice = 0;
    while (@atomicLoad(i32, &g_pollStopGeneration, .acquire) == startGen) {
        const ctx = g_captureCtx orelse break;
        const waitedDev = interception_wait_with_timeout(ctx, POLL_WAIT_TIMEOUT_MS);
        if (@atomicLoad(i32, &g_pollStopGeneration, .acquire) != startGen) break;
        if (waitedDev <= 0) continue;
        device = waitedDev;

        while (@atomicLoad(i32, &g_pollStopGeneration, .acquire) == startGen) {
            if (interception_receive(ctx, device, @ptrCast(&stroke), 1) <= 0) break;

            const isSynthetic = (@as(usize, stroke.information) == AHK_SENDLEVEL_2);
            if (isSynthetic) {
                _ = interception_send(ctx, device, @ptrCast(&stroke), 1);
            } else {
                const vk = strokeToVK(&stroke);
                if (vk <= 0) {
                    _ = interception_send(ctx, device, @ptrCast(&stroke), 1);
                } else {
                    const isDown = (stroke.state & IKEY_UP) == 0;
                    beginHotPathActivity();
                    defer endHotPathActivity(isDown);
                    if (isModVK(vk)) {
                        const incoming_tracked_vk = physicalModifierTrackingVK(vk);
                        const hidden_up = !isDown and physicalModifierHiddenFromOs(incoming_tracked_vk);
                        const tracked_vk = apply_physical_modifier_event(vk, isDown);
                        if (isDown) cancelRepeatForDifferentKeyDown(tracked_vk);
                        if (!isDown) cancelRepeatForRequiredKeyUp(tracked_vk);
                        if (isDown) markPhysicalModifierHiddenFromOs(tracked_vk);
                        markGenericTapHoldInterrupted(tracked_vk, isDown);
                        const modMask = compute_modifiers_to_send();
                        handleNativePanicExitIfMatched(tracked_vk, modMask, isDown);
                        handleNativeReloadIfMatched(tracked_vk, modMask, isDown);
                        if (handleNativeSuspendIfMatched(tracked_vk, modMask, isDown)) continue;
                        const suppress = if (isDown)
                            queueReversePhysicalModHotkeyIfMatched(tracked_vk, modMask) or queueAnyHotkeyIfMatched(tracked_vk, modMask, true)
                        else
                            queueAnyHotkeyIfMatched(tracked_vk, modMask, false);
                        if (suppress and !isDown) cleanupBufferedKeyAfterConsumedKeyUp(tracked_vk);
                        if (isDown) {
                            if (suppress) {
                                markPhysicalModifierHiddenFromOs(tracked_vk);
                            } else if (!g_physical_modifier_passthrough) {
                                markPhysicalModifierHiddenFromOs(tracked_vk);
                            } else {
                                clearPhysicalModifierHiddenFromOs(tracked_vk);
                            }
                        } else if (hidden_up) {
                            clearPhysicalModifierHiddenFromOs(tracked_vk);
                        }
                        if (!suppress and !hidden_up and g_physical_modifier_passthrough) _ = interception_send(ctx, device, @ptrCast(&stroke), 1);
                        continue;
                    }
                    prepareStructuralModifierContext(vk, isDown);
                    setPhysicalKeyDownState(vk, isDown);
                    markGenericTapHoldInterrupted(vk, isDown);
                    const qmk_mod_mask = compute_modifiers_to_send();
                    if (shouldPrepareStructuralHotkeyContext(vk, isDown))
                        _ = prepareStructuralHotkeyContext(vk, qmk_mod_mask, isDown);
                    prepareStructuralContextAction(vk);
                    handleNativePanicExitIfMatched(vk, qmk_mod_mask, isDown);
                    handleNativeReloadIfMatched(vk, qmk_mod_mask, isDown);
                    if (handleNativeSuspendIfMatched(vk, qmk_mod_mask, isDown)) continue;
                    if (@atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire) != 0) {
                        const suppress = queueAnyHotkeyIfMatched(vk, qmk_mod_mask, isDown);
                        if (suppress and !isDown) cleanupBufferedKeyAfterConsumedKeyUp(vk);
                        if (!suppress) _ = interception_send(ctx, device, @ptrCast(&stroke), 1);
                        continue;
                    }

                    const tap_hold_owns_release = !isDown and vk > 0 and vk < VK_COUNT and
                        g_tapHoldArmed[@intCast(vk)];
                    const contextual_tap_owns_release = !isDown and vk > 0 and vk < VK_COUNT and
                        g_contextualTapArmed[@intCast(vk)];
                    if (shouldArmRuntimeContextualTapHotkey(vk, isDown) and qmk_mod_mask == 0 and
                        tryArmRuntimeContextualTapHotkey(vk, qmk_mod_mask))
                    {
                        continue;
                    }
                    if (genericTapHoldConfigured(vk) and !contextual_tap_owns_release and
                        (!isDown or !keySequenceActive()) and
                        (qmk_mod_mask == 0 or tap_hold_owns_release)) {
                        // An unmodified tap/hold key owns the full press lifetime. If another
                        // key/modifier interrupts it, its key-up still resolves here so both
                        // tap and hold callbacks are canceled (cleanup-only, if configured).
                        if (!handleGenericTapHold(vk, isDown)) _ = interception_send(ctx, device, @ptrCast(&stroke), 1);
                    } else if (isPassthroughVK(vk)) {
                        const suppress = queueAnyHotkeyIfMatched(vk, qmk_mod_mask, isDown);
                        if (suppress and !isDown) cleanupBufferedKeyAfterConsumedKeyUp(vk);
                        if (!suppress) observePassthroughHotstring(vk, isDown);
                        if (!suppress) _ = interception_send(ctx, device, @ptrCast(&stroke), 1);
                    } else {
                        const modMask = compute_modifiers_to_send();
                        const suppress = queueAnyHotkeyIfMatched(vk, modMask, isDown);
                        const vki: usize = @intCast(vk);
                        if (suppress) {
                            if (isDown) hotstringRecordConsumedKeyDown(vk);
                            if (!isDown) cleanupBufferedKeyAfterConsumedKeyUp(vk);
                            if (!isDown) g_native_passthrough_to_windows[vki] = false;
                        } else if (shouldForwardNativeModifiedStroke(vk, isDown)) {
                            recordNativeModifiedStrokeForwarded(vk, isDown);
                            if (isDown) {
                                sendInterceptionNativeForwardBatch(ctx, device, &stroke);
                            } else {
                                _ = interception_send(ctx, device, @ptrCast(&stroke), 1);
                            }
                        } else {
                            processKeyEventHot(vk, if (isDown) 1 else 0);
                        }
                    }
                }
            }

            // Drain buffered strokes immediately to reduce wake/sleep jitter.
            const nextDev = interception_wait_with_timeout(ctx, 0);
            if (nextDev <= 0) break;
            device = nextDev;
        }
    }

    @atomicStore(i32, &g_pollThreadActive, 0, .release);
    return 0;
}

// Bind one generated callback slot to the runtime callback ID assigned by
// AutoHotkey.  Compiled rows and runtime rows share these stores.  Bind only
// the published prefix: the unpublished tail is setup scratch space and must
// not be mistaken for a compiled row during callback registration.
export fn QMK_BindCompiledCallback(slot_in: i32, runtime_id: i32) callconv(.c) i32 {
    if (slot_in < 0 or runtime_id < 0) return 0;
    const slot: usize = @intCast(slot_in);
    const compiled_id = COMPILED_ZIG_CALLBACK_ID_BASE - slot_in;
    if (slot >= COMPILED_CALLBACK_SLOT_MAX) return 0;
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    g_compiledCallbackBindings[slot] = runtime_id;
    var changed: usize = 0;
    var runtime_exempt = false;
    var i: usize = 0;
    // Binding is an initialization-time operation.  Only the published
    // compiled prefix is eligible for slot replacement; scanning the live
    // tail can accidentally rewrite a later runtime callback whose positive
    // ID happens to equal a compiled slot number.
    while (i < g_runtimeHotkeysPublishedLen) : (i += 1) {
        if (g_runtimeHotkeys[i].callbackId == slot_in or g_runtimeHotkeys[i].callbackId == compiled_id) { g_runtimeHotkeys[i].callbackId = runtime_id; changed += 1; runtime_exempt = runtime_exempt or g_runtimeHotkeys[i].suspendExempt; }
        if (g_runtimeHotkeys[i].holdCallbackId == slot_in or g_runtimeHotkeys[i].holdCallbackId == compiled_id) { g_runtimeHotkeys[i].holdCallbackId = runtime_id; changed += 1; runtime_exempt = runtime_exempt or g_runtimeHotkeys[i].suspendExempt; }
        if (g_runtimeHotkeys[i].cleanupCallbackId == slot_in or g_runtimeHotkeys[i].cleanupCallbackId == compiled_id) { g_runtimeHotkeys[i].cleanupCallbackId = runtime_id; changed += 1; runtime_exempt = runtime_exempt or g_runtimeHotkeys[i].suspendExempt; }
    }
    i = 0;
    while (i < g_runtimeContextActionsPublishedLen) : (i += 1) {
        if (g_runtimeContextActions[i].callbackId == slot_in or g_runtimeContextActions[i].callbackId == compiled_id) { g_runtimeContextActions[i].callbackId = runtime_id; changed += 1; runtime_exempt = runtime_exempt or g_runtimeContextActions[i].suspendExempt; }
        if (g_runtimeContextActions[i].tapCallbackId == slot_in or g_runtimeContextActions[i].tapCallbackId == compiled_id) { g_runtimeContextActions[i].tapCallbackId = runtime_id; changed += 1; runtime_exempt = runtime_exempt or g_runtimeContextActions[i].suspendExempt; }
        if (g_runtimeContextActions[i].holdCallbackId == slot_in or g_runtimeContextActions[i].holdCallbackId == compiled_id) { g_runtimeContextActions[i].holdCallbackId = runtime_id; changed += 1; runtime_exempt = runtime_exempt or g_runtimeContextActions[i].suspendExempt; }
    }
    i = 0;
    while (i < g_runtimeCombosPublishedLen) : (i += 1) {
        if (g_runtimeCombos[i].callbackId == slot_in or g_runtimeCombos[i].callbackId == compiled_id) { g_runtimeCombos[i].callbackId = runtime_id; changed += 1; runtime_exempt = runtime_exempt or g_runtimeCombos[i].suspendExempt; }
    }
    i = 0;
    while (i < g_runtimeInstantCombosPublishedLen) : (i += 1) {
        if (g_runtimeInstantCombos[i].callbackId == slot_in or g_runtimeInstantCombos[i].callbackId == compiled_id) { g_runtimeInstantCombos[i].callbackId = runtime_id; changed += 1; runtime_exempt = runtime_exempt or g_runtimeInstantCombos[i].suspendExempt; }
    }
    i = 0;
    while (i < g_runtimeChordsPublishedLen) : (i += 1) {
        if (g_runtimeChords[i].callbackId == slot_in or g_runtimeChords[i].callbackId == compiled_id) { g_runtimeChords[i].callbackId = runtime_id; changed += 1; runtime_exempt = runtime_exempt or g_runtimeChords[i].suspendExempt; }
    }
    i = 0;
    while (i < g_runtimeHotstringPublishedLen) : (i += 1) {
        if (g_runtimeHotstringCallbackIds[i] == slot_in or g_runtimeHotstringCallbackIds[i] == compiled_id) { g_runtimeHotstringCallbackIds[i] = runtime_id; changed += 1; runtime_exempt = runtime_exempt or g_runtimeHotstringSuspendExempt[i]; }
    }
    if (changed != 0) {
        // The callback ID is now the live AHK callback ID, not the generated
        // compiled slot.  Mark it immediately so a suspend transition cannot
        // race the deferred runtime-store publish and suppress an exempt
        // callback such as Ctrl+Alt+S on the next press.
        _ = markRuntimeCallbackSuspendExempt(runtime_id, runtime_exempt);
        g_bulkRuntimeHotkeysDirty = true;
        g_bulkRuntimeContextActionsDirty = true;
        g_bulkRuntimeCombosDirty = true;
        g_bulkRuntimeChordsDirty = true;
        g_bulkRuntimeHotstringsDirty = true;
        requestRuntimePublish(RUNTIME_PUBLISH_SETUP);
    }
    return @intCast(changed);
}

export fn QMK_SetInterceptionCallbacks(
    createCtx: ?*const fn () callconv(.c) InterceptionContext,
    destroyCtx: ?*const fn (InterceptionContext) callconv(.c) void,
    send: ?*const fn (InterceptionContext, InterceptionDevice, [*]const InterceptionKeyStroke, u32) callconv(.c) i32,
    isKeyboard: ?*const fn (InterceptionDevice) callconv(.c) i32,
    setFilter: ?*const fn (InterceptionContext, InterceptionPredicate, u16) callconv(.c) void,
    receive: ?*const fn (InterceptionContext, InterceptionDevice, [*]InterceptionKeyStroke, u32) callconv(.c) i32,
    waitWithTimeout: ?*const fn (InterceptionContext, u32) callconv(.c) InterceptionDevice,
) callconv(.c) void {
    const callbacks_changed = (fp_create_context != null or
        fp_destroy_context != null or
        fp_send != null or
        fp_is_keyboard != null or
        fp_set_filter != null or
        fp_receive != null or
        fp_wait_with_timeout != null) and
        (fp_create_context != createCtx or
        fp_destroy_context != destroyCtx or
        fp_send != send or
        fp_is_keyboard != isKeyboard or
        fp_set_filter != setFilter or
        fp_receive != receive or
        fp_wait_with_timeout != waitWithTimeout);
    const have_interception_callbacks = createCtx != null and destroyCtx != null and send != null and isKeyboard != null and setFilter != null and receive != null and waitWithTimeout != null;
    if ((callbacks_changed or !have_interception_callbacks) and !stopInterceptionCaptureOnly(false)) {
        return;
    }

    fp_create_context = createCtx;
    fp_destroy_context = destroyCtx;
    fp_send = send;
    fp_is_keyboard = isKeyboard;
    fp_set_filter = setFilter;
    fp_receive = receive;
    fp_wait_with_timeout = waitWithTimeout;

    // --- 1. SILENT MEMORY INITIALIZATION ---
    if (!g_is_initialized) {
        initTimer();
        clearRuntimePublishStateForReset();

        kbClear();
        ordClear(); // also resets g_ordIdx via @memset inside ordClear
        @memset(&g_kbIdx, -1);
        g_recentKeyUpCount = 0;
        g_activeComboPrimaryCount = 0;
        g_activeComboPrimaryBits = .{ 0, 0, 0, 0 };
        g_activeInstantPrimaryBits = .{ 0, 0, 0, 0 };
        g_activeAnyPrimaryBits = .{ 0, 0, 0, 0 };
        @memset(&g_comboPrimaryFlat, false);
        @memset(&g_instantComboPrimaryFlat, false);
        @memset(&g_runtimeComboPrimaryFlat, false);
        @memset(&g_runtimeInstantComboPrimaryFlat, false);
        @memset(&g_keyNamePtr, null);
        @memset(&g_keyHoldCallbackId, -1);
        @memset(&g_keyDoubleTapCallbackId, -1);

        // Flat tables: only canonical copies for combo/chord relation setup.
        if (g_icTable.len != 0) @memset(g_icTable, IcEntry{});
        if (g_ccTable.len != 0) @memset(g_ccTable, CcEntry{});
        if (g_iccTable.len != 0) @memset(g_iccTable, IccEntry{});
        g_icLen = 0;
        g_ccLen = 0;
        g_iccLen = 0;
        if (g_chordHotTable.len != 0) @memset(g_chordHotTable, ChordHotEntry{});
        g_chordHotLen = 0;
        clearActiveRuntimeChordTables();
        g_runtimeChordsLen = 0;
        // Reset bool matrices
        for (&g_comboMatrix) |*row| @memset(row, false);
        for (&g_instantComboMatrix) |*row| @memset(row, false);
        clearActiveRuntimeComboTables();
        g_runtimeCombosLen = 0;
        g_runtimeInstantCombosLen = 0;
    g_runtimeComboRegistrationSeq = 0;
        for (&g_pairRelationMask) |*row| @memset(row, 0);

        timerClear();
        ignClear();
        pcbClear();
        if (g_runtimeCallbackSuspendExempt.len != 0) @memset(g_runtimeCallbackSuspendExempt, false);
        if (g_runtimeHotstringSuspendExempt.len != 0) @memset(g_runtimeHotstringSuspendExempt, false);
        if (g_runtimeModifiers.len != 0) @memset(g_runtimeModifiers, RuntimeModifier{});
        if (g_runtimeModifierTexts.len != 0) @memset(g_runtimeModifierTexts, [_]u16{0} ** RUNTIME_CONTEXT_ACTION_CHARS);
        g_runtimeModifiersLen = 0;
        if (g_runtimePassthroughs.len != 0) @memset(g_runtimePassthroughs, RuntimePassthrough{});
        if (g_runtimePassthroughTexts.len != 0) @memset(g_runtimePassthroughTexts, [_]u16{0} ** RUNTIME_CONTEXT_ACTION_CHARS);
        g_runtimePassthroughsLen = 0;
        g_bulkRuntimePassthroughsDirty = false;
        @memset(&g_runtimeModifierTouched, false);
        @memset(&g_runtimeModifierBaseType, MOD_NONE);
        ptmClear();
        kdtClear();
        kutClear();
        clear_active_virtual_modifiers();
        @memset(&g_activeModPresent, false);
        @memset(&g_activeModIdx, -1);
        @memset(&g_vkToRegIdx, -1);
        @memset(&g_scPacked, 0);

        // Reset name?VK keyed table.
        for (&g_nkvkName) |*s| @memset(s, 0);
        @memset(&g_nkvkVK, 0);

        g_keyCount = 0;
        g_active_physical_and_windows_facing_modifiers = 0;
        g_active_physical_modifiers = 0;
        g_any_physical_modifiers_active = false;
        clearPhysicalKeyDownState();
        @memset(&g_foreignPhysicalKeyDown, false);
        g_foreignPhysicalQuarantineArmed = false;
        g_trackedPhysicalKeysDown = 0;
        g_lastPhysicalDownVK = 0;
        g_which_physical_modifiers_to_send = 0;
        g_lr_active_physical_modifiers = 0;
        @memset(&g_active_physical_modifier_key_counts_by_category, 0);
        @memset(&g_hotkey_consumed_down, false);
        @memset(&g_contextualTapArmed, false);
        @memset(&g_contextualTapCallbackId, -1);
        @memset(&g_contextualTapHoldCallbackId, -1);
        @memset(&g_contextualTapCleanupCallbackId, -1);
        @memset(&g_contextualTapThreshold, 0);
        @memset(&g_contextualTapDownTime, 0);
        @memset(&g_native_passthrough_to_windows, false);
        g_lastKeyTime = 0;
        g_typingMode = false;
        g_typingModeUntil = 0;
        g_hotFlags = 0;
        g_runtimeFlags = 0; // FSM-lite
        g_unreleasedKeyCount = 0; // FSM-lite
        g_unreleasedNonModCount = 0; // FSM-lite
        g_activeInstantPrimaryCount = 0; // FSM-lite
        g_activeAnyPrimaryCount = 0; // FSM-lite
        g_unrelModCount = 0;
        g_cleanUnrelModCount = 0;
        g_activeModKeyCnt = 0;
        g_modStackDirty = false;
        g_hasInternalChords = false;
        g_hasExternalChords = false;
        g_hasAnyChord = false;
        g_hasInternalCombos = false;
        @memset(&g_hcFlat, -1);
        @memset(&g_modDtFlat, -1);
        @memset(&g_holdRegisteredFlat, false);
        @memset(&g_doubleTapRegisteredFlat, false);
        if (stopModPollThread()) {
            g_modPollActive = 0;
            g_modPollGeneration = 0;
            g_modPollStopGeneration = 0;
        }
        if (@atomicLoad(i32, &g_pollThreadActive, .acquire) == 0 and
            @atomicLoad(i32, &g_interceptionInitActive, .acquire) == 0)
        {
            g_pollStopGeneration = 0;
            g_interceptionInitGeneration = 0;
            g_interceptionInitThreadGeneration = 0;
        }
        if (@atomicLoad(i32, &g_llHookThreadActive, .acquire) == 0) {
            g_llHookStopGeneration = 0;
            g_llHookThreadId = 0;
            g_llHookReady = false;
        }
        @memset(&g_modPollDownTime, 0);
        @memset(&g_modPollLastUpTime, 0);
        g_extChordCacheLen = 0;

        registerDefaultKeys();
        applyPrecompiledShortcuts();
        // The compiled preload uses the same unpublished -> published runtime
        // transaction as QMK_Setup*.  Force that transaction to finish before
        // taking the initialization key-gate snapshot.  This is normally a
        // no-op because requestRuntimePublish() flushes synchronously, but it
        // prevents a deferred worker publish from leaving compiled families
        // absent from the active banks during first initialization.
        acquireSetupPublishLock();
        flushRuntimePublishIfIdleLocked();
        releaseSetupPublishLock();

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
        g_physModBitTable[0x11] = 0x01; // Ctrl fallback
        g_physModBitTable[0xA2] = 0x01; // LCtrl
        g_physModBitTable[0xA3] = 0x01; // RCtrl
        g_physModBitTable[0x12] = 0x02; // Alt fallback
        g_physModBitTable[0xA4] = 0x02; // LAlt
        g_physModBitTable[0xA5] = 0x02; // RAlt
        g_physModBitTable[0x10] = 0x04; // Shift fallback
        g_physModBitTable[0xA0] = 0x04; // LShift
        g_physModBitTable[0xA1] = 0x04; // RShift
        g_physModBitTable[0x5B] = 0x08; // LWin
        g_physModBitTable[0x5C] = 0x08; // RWin
        rebuild_runtime_vk_plan();
        g_keyGateDirty = false;
        syncColdPhysicalStateFromSystem();
        warmHotTables();
        warmStrokeVKCache();
        g_is_initialized = true;
    }
    if (!have_interception_callbacks) {
        g_interceptionSendReady = false;
        g_interceptionCaptureReady = false;
    } else if (g_sendCtx == null or g_sendDev <= 0) {
        g_interceptionSendReady = false;
        g_interceptionCaptureReady = false;
    }
    ensureAsyncSendWorker();
    initRepeatWorker();
    initSchedThread();
    const needs_interception_init = g_useKernel or backendAllowsInterceptionCapture();
    const started_interception_init = if (needs_interception_init) startInterceptionInitAsync() else false;
    if (g_inputBackend == INPUT_BACKEND_LLHOOK or ((!started_interception_init or !g_interceptionCaptureReady) and backendAllowsLLHookCapture())) {
        _ = startLLHookCapture();
        notifyInputBackendState();
    }
    // --- 4. SENDINPUT WARMUP ---
    // Now that the async thread is live, prime user32.dll, win32k.sys, and
    // the ring-buffer dispatch path. g_interceptionSendReady is false here so
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
        // g_interceptionSendReady is already governed by g_useKernel (default true)
        // and will be flipped on by initInterceptionThreadProc once the driver
        // is confirmed present, so no explicit set is needed here.
    }
    armForeignPhysicalKeyQuarantine();
}
fn initInterceptionThreadProc(_: ?*anyopaque) callconv(.winapi) u32 {
    // Elevate so the driver poll and warmup finish before the first real
    // keystroke can arrive on the main thread.
    _ = SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_HIGHEST);
    const startGen = g_interceptionInitThreadGeneration;
    defer @atomicStore(i32, &g_interceptionInitActive, 0, .release);
    if (startGen != @atomicLoad(i32, &g_interceptionInitGeneration, .acquire)) return 0;

    // 1. Create the long-lived send context. Capture gets its own context
    // below so stopping a blocking poll never disturbs batched sends.
    if (g_sendCtx == null) g_sendCtx = interception_create_context();
    if (startGen != @atomicLoad(i32, &g_interceptionInitGeneration, .acquire)) return 0;

    var found_dev: InterceptionDevice = 0;
    // 2. Do the slow hardware poll
    if (g_sendCtx != null) {
        var i: InterceptionDevice = 1;
        while (i <= 11) : (i += 1) {
            if (startGen != @atomicLoad(i32, &g_interceptionInitGeneration, .acquire)) return 0;
            if (interception_is_keyboard(i) != 0) {
                found_dev = i;
                break;
            }
        }
    }
    if (startGen != @atomicLoad(i32, &g_interceptionInitGeneration, .acquire)) return 0;

    // 3. Update globals
    g_sendDev = found_dev;
    // 4. Flip the switch to enable Kernel routing in ringSend, but keep the
    // user's UseInterception setting authoritative.
    g_interceptionSendReady = (g_useKernel and g_sendCtx != null and g_sendDev > 0);
    const use_interception_capture = g_sendCtx != null and g_sendDev > 0 and backendAllowsInterceptionCapture();
    g_interceptionCaptureReady = false;
    if (use_interception_capture and fp_set_filter != null and fp_receive != null and fp_wait_with_timeout != null) {
        if (g_captureCtx == null) g_captureCtx = interception_create_context();
        if (g_captureCtx != null) interception_set_filter(g_captureCtx, isSubscribedKeyboard, INTERCEPTION_FILTER_KEY_ALL);
        if (startGen != @atomicLoad(i32, &g_interceptionInitGeneration, .acquire)) return 0;
        if (g_captureCtx != null and @atomicRmw(i32, &g_pollThreadActive, .Xchg, 1, .acq_rel) == 0) {
            if (CreateThread(null, 0, subscriptionPollThreadProc, null, 0, null)) |hThread| {
                _ = CloseHandle(hThread);
                g_interceptionCaptureReady = true;
            } else {
                @atomicStore(i32, &g_pollThreadActive, 0, .release);
            }
        } else {
            g_interceptionCaptureReady = true;
        }
    }
    if (!g_interceptionCaptureReady and backendAllowsLLHookCapture()) {
        _ = startLLHookCapture();
    }
    if (startGen != @atomicLoad(i32, &g_interceptionInitGeneration, .acquire)) return 0;

    // 5. Interception warmup — now that g_interceptionSendReady is set, prime the
    //    kernel driver's send path before any real keystroke can arrive.
    //    VK 0xFF (unassigned) is silently dropped by all applications.
    //    Three iterations warm:
    //      - the Interception driver's IRP dispatch queue
    //      - the ringSend encode loop that builds InterceptionKeyStroke structs
    //      - the fp_send indirect call site's branch predictor and i-cache
    //    If the driver wasn't found (SendInput fallback mode), g_interceptionSendReady
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
    if (startGen != @atomicLoad(i32, &g_interceptionInitGeneration, .acquire)) return 0;

    // 6. Clear warmup noise from the profiling counters so it is never visible
    //    in the report. Do NOT touch g_profilingEnabled here — QMK_SetUserConfig
    //    runs concurrently on the main thread and owns that flag. Overwriting it
    //    here would race against (and silently undo) the user's config.
    g_profiling = .{};

    // 7. Notify AHK whether it needs to register fallback hotkeys.
    //    - Interception ready  ? 0x8004 (UnregisterAllKeys) — AHK hotkeys would double-fire.
    //    - Interception absent ? 0x8003 (RegisterAllKeys)   — AHK hotkeys are the only path.
    //
    //    Bulletproof retry: QMK_SetAHKThreadId is called on the AHK main thread shortly
    //    after QMK_SetInterceptionCallbacks, but this background thread may finish the
    //    hardware poll before that call completes.  We spin up to ~500 ms (50 × 10 ms)
    //    waiting for g_ahkThreadId to be populated before giving up.
    {
        const msg: i64 = if (!backendWantsAhkHotkeys())
            ipc.IPC_UNREGISTER_KEYS
        else
            ipc.IPC_REGISTER_KEYS;

        var attempts: u32 = 0;
        while (attempts < 50) : (attempts += 1) {
            if (g_ipcRing != null) {
                _ = pushIpcControl(msg);
                break;
            }
            // g_ahkThreadId not set yet — yield for 10 ms and retry.
            _ = Sleep(10);
        }
        // If tid is still 0 after 500 ms the AHK side never called QMK_SetAHKThreadId,
        // which means the process is shutting down or something is very wrong.
        // Silently drop the notification rather than hang.
    }

    // Returning 0 cleanly and permanently terminates this thread.
    return 0;
}

export fn QMK_SetStartupInputConfig(mode: i32, UseInterception: i32, ProfilingEnabled: i32) callconv(.c) void {
    g_inputBackend = normalizeInputBackend(mode);
    g_sendModeAuto = UseInterception < 0;
    g_useKernel = UseInterception != 0;
    g_profilingEnabled = (ProfilingEnabled != 0);
    if (g_is_initialized) reconcileInputBackend();
}

export fn QMK_ApplyInputConfig(mode: i32, UseInterception: i32, ProfilingEnabled: i32, ApplyNow: i32) callconv(.c) i32 {
    if (ApplyNow == 0) return QMK_GetInputBackendStatus();
    const old_backend = g_inputBackend;
    const old_send_mode = g_useKernel;
    const old_send_auto = g_sendModeAuto;
    const new_backend = normalizeInputBackend(mode);
    const new_send_auto = UseInterception < 0;
    const new_send_mode = UseInterception != 0;
    const changing = old_backend != new_backend or old_send_mode != new_send_mode or old_send_auto != new_send_auto;
    g_inputBackend = new_backend;
    g_sendModeAuto = UseInterception < 0;
    g_useKernel = UseInterception != 0;
    g_profilingEnabled = (ProfilingEnabled != 0);
    if (changing) {
        const state_busy = reconcileTrackedPhysicalKeysDown() != 0 or
            @atomicLoad(i32, &g_hotPathActiveCount, .acquire) != 0;
        if (state_busy) {
            g_inputBackend = old_backend;
            g_sendModeAuto = old_send_auto;
            g_useKernel = old_send_mode;
            return QMK_GetInputBackendStatus();
        }
        const ll_stopped = stopLLHookCapture();
        const interception_stopped = stopInterceptionCaptureOnly(g_useKernel);
        if (!ll_stopped or !interception_stopped) {
            g_inputBackend = old_backend;
            g_sendModeAuto = old_send_auto;
            g_useKernel = old_send_mode;
            reconcileInputBackend();
            return QMK_GetInputBackendStatus();
        }
        clearNativeCaptureStateOnly();
    }
    reconcileInputBackend();
    return QMK_GetInputBackendStatus();
}

// applyConfig: 0 = store only, 1 = apply now (pass 0 during setup, 1 to activate)
// SendModeInterception/UseInterception: -1 = auto, 1 = Interception driver sends, 0 = DLL SendInput only
// profilingOn: 1 = enabled (default), 0 = disabled
export fn QMK_SetUserConfig(
    ApplyConfig: i32,
    UseInterception: i32,
    ProfilingEnabled: i32,
    SingleKeyHoldThreshold: f64,
    MaxHoldThreshold: f64,
    MaxThresholdSuppress: i32,
    MaxBufferSize: i32,
    QuietPeriodDuration: f64,
    ModifierGestureWindow: f64,
    DoubleTapThreshold: f64,
    RepeatInitialDelay: i32,
    RepeatInterval: i32,
) callconv(.c) void {
    if (ApplyConfig == 0) return;

    g_userConfigApplied = true; // lock out post-warmup defaults from QMK_SetInterceptionCallbacks
    g_sendModeAuto = UseInterception < 0;
    g_useKernel = UseInterception != 0;
    g_profilingEnabled = (ProfilingEnabled != 0);
    reconcileInputBackend();

    // Convert ms to ticks (ms * qpcFreq / 1000)
    const msToTicks = struct {
        fn f(ms: f64) i64 {
            return @intFromFloat(ms * @as(f64, @floatFromInt(g_qpcFreq)) / 1000.0);
        }
    }.f;

    // --- TIMING & BUFFER CAPS ---
    // @min sets the ceiling (maximum), @max sets the floor (minimum).
    // Capped between 50ms and 1000ms
    g_SingleKeyHoldThreshold = msToTicks(@min(1000.0, @max(50.0, SingleKeyHoldThreshold)));
    // Capped between 300ms and 2000ms
    g_MaxHoldThreshold = msToTicks(@min(2000.0, @max(300.0, MaxHoldThreshold)));
    // Capped between 5 and 100 slots
    g_MaxBufferSize = @min(100, @max(5, MaxBufferSize));
    // Capped between 0ms and 2000ms
    g_QuietPeriodDuration = msToTicks(@min(2000.0, @max(0.0, QuietPeriodDuration)));
    // Capped between 0ms and 1000ms
    g_ModifierGestureWindow = msToTicks(@min(1000.0, @max(0.0, ModifierGestureWindow)));
    // Capped between 100ms and 600ms
    g_DoubleTapThreshold = msToTicks(@min(600.0, @max(100.0, DoubleTapThreshold)));
    // Uncapped / boolean flags
    g_MaxThresholdSupress = (MaxThresholdSuppress != 0);
    // --- REPEAT SAFETY CAPS ---
    // Prevent OS-crashing tight loops
    g_RepeatInitialDelay = @max(50, RepeatInitialDelay);
    g_RepeatInterval = @max(5, RepeatInterval);
    g_RepeatInitialDelayTicks = @divTrunc(@as(i64, g_RepeatInitialDelay) * g_qpcFreq, 1000);
    g_RepeatIntervalTicks = @divTrunc(@as(i64, g_RepeatInterval) * g_qpcFreq, 1000);
}

export fn QMK_SetPhysicalModifierPassthrough(enabled: i32) callconv(.c) i32 {
    const should_passthrough = enabled != 0;
    if (g_physical_modifier_passthrough == should_passthrough) return 1;

    const held = snapshotPhysicalMods();
    if (!should_passthrough) {
        const visible = held & ~hiddenPhysicalModsFromOs();
        if (visible != 0) {
            ringReset();
            ringAddModifierRelease(visible, AHK_SENDLEVEL_2);
            ringSendAtomic();
            markPhysicalModsHiddenFromOs(visible);
        }
    } else {
        const hidden = held & hiddenPhysicalModsFromOs();
        if (hidden != 0) {
            ringReset();
            ringAddModifierRestore(hidden, AHK_SENDLEVEL_2);
            ringSendAtomic();
            clearPhysicalModsHiddenFromOs(hidden);
        }
    }

    g_physical_modifier_passthrough = should_passthrough;
    return 1;
}

export fn QMK_DestroyInterception() callconv(.c) void {
    _ = stopModPollThread();
    _ = stopInterceptionCaptureOnly(false);
    stopAsyncThread();
    stopRepeatWorker();
    stopSchedThread();
}

export fn QMK_SetInputBackend(mode: i32) callconv(.c) i32 {
    return QMK_ApplyInputConfig(mode, if (g_sendModeAuto) -1 else if (g_useKernel) 1 else 0, if (g_profilingEnabled) 1 else 0, 1);
}

export fn QMK_StartLLHook() callconv(.c) i32 {
    g_inputBackend = INPUT_BACKEND_LLHOOK;
    reconcileInputBackend();
    return if (g_llHookReady) 1 else 0;
}

export fn QMK_StopLLHook() callconv(.c) void {
    _ = stopLLHookCapture();
    notifyInputBackendState();
}

export fn QMK_GetInputBackendStatus() callconv(.c) i32 {
    return activeInputBackendCode();
}

export fn QMK_ToggleKernelInjection() callconv(.c) void {
    g_sendModeAuto = false;
    g_useKernel = !g_useKernel;
    reconcileInputBackend();
}
export fn QMK_EmergencyReset() callconv(.c) void {
    // Release any logically stuck modifiers in the OS before clearing local state.
    QMK_ReleaseStuckModifiers();
    pendingSoloClear();
    pendingRollClear();
    kbClear();
    ordClear();
    clear_active_virtual_modifiers();
    timerClear();
    kdtClear();
    kutClear();
    g_active_physical_and_windows_facing_modifiers = 0;
    g_active_physical_modifiers = 0;
    g_any_physical_modifiers_active = false;
    clearPhysicalKeyDownState();
    @memset(&g_foreignPhysicalKeyDown, false);
    g_foreignPhysicalQuarantineArmed = false;
    g_trackedPhysicalKeysDown = 0;
    g_lastPhysicalDownVK = 0;
    g_which_physical_modifiers_to_send = 0;
    g_lr_active_physical_modifiers = 0;
    @memset(&g_active_physical_modifier_key_counts_by_category, 0);
    @memset(&g_hotkey_consumed_down, false);
    @memset(&g_contextualTapArmed, false);
    @memset(&g_contextualTapCallbackId, -1);
    @memset(&g_contextualTapHoldCallbackId, -1);
    @memset(&g_contextualTapCleanupCallbackId, -1);
    @memset(&g_contextualTapThreshold, 0);
    @memset(&g_contextualTapDownTime, 0);
    @memset(&g_native_passthrough_to_windows, false);
    @memset(&g_tapHoldDownTime, 0);
    @memset(&g_tapHoldArmed, false);
    @memset(&g_tapHoldInterrupted, false);
    @memset(&g_tapHoldCallbackQueued, false);
    @memset(&g_tapHoldArmedTapCallbackId, -1);
    @memset(&g_tapHoldArmedHoldCallbackId, -1);
    @memset(&g_tapHoldArmedCleanupCallbackId, -1);
    @memset(&g_tapHoldArmedThreshold, 0);
    g_lastKeyTime = 0;
    g_typingMode = false;
    g_typingModeUntil = 0;
    g_hotFlags &= ~HF_TYPING;
    pcbClear();
    ptmClear();
    g_unrelModCount = 0;
    g_cleanUnrelModCount = 0;
    g_activeModKeyCnt = 0;
    g_modStackDirty = false;
    // FSM-lite: rebuild runtime flags from scratch after emergency reset
    g_runtimeFlags = 0;
    g_unreleasedKeyCount = 0;
    g_unreleasedNonModCount = 0;
    g_hotstringMatcher.reset();
    if (g_is_initialized) armForeignPhysicalKeyQuarantine();
}

export fn QMK_EmergencyExit() callconv(.c) noreturn {
    QMK_EmergencyReset();
    ExitProcess(0);
}

fn wideZLen(ptr: [*:0]const u16) usize {
    var len: usize = 0;
    while (ptr[len] != 0) : (len += 1) {}
    return len;
}

fn stripUiAccessSuffixInPlace(buffer: *[8192:0]u16, len: usize) void {
    var out: usize = 0;
    var i: usize = 0;
    while (i < len) {
        if (i + 4 <= len and
            buffer[i] == '_' and
            (buffer[i + 1] == 'U' or buffer[i + 1] == 'u') and
            (buffer[i + 2] == 'I' or buffer[i + 2] == 'i') and
            (buffer[i + 3] == 'A' or buffer[i + 3] == 'a'))
        {
            i += 4;
            continue;
        }
        buffer[out] = buffer[i];
        out += 1;
        i += 1;
    }
    buffer[out] = 0;
}

export fn QMK_NativeReload() callconv(.c) noreturn {
    var command_line: [8192:0]u16 = [_:0]u16{0} ** 8192;
    const source = GetCommandLineW();
    const source_len = wideZLen(source);
    if (source_len == 0 or source_len >= command_line.len) {
        QMK_EmergencyReset();
        ExitProcess(1);
    }

    for (source[0..source_len], 0..) |ch, i| {
        command_line[i] = ch;
    }
    command_line[source_len] = 0;
    stripUiAccessSuffixInPlace(&command_line, source_len);

    var startup_info: windows.STARTUPINFOW = undefined;
    @memset(std.mem.asBytes(&startup_info), 0);
    startup_info.cb = @sizeOf(windows.STARTUPINFOW);

    var process_info: windows.PROCESS.INFORMATION = undefined;
    @memset(std.mem.asBytes(&process_info), 0);

    QMK_EmergencyReset();
    const created = CreateProcessW(null, @ptrCast(&command_line), null, null, FALSE, 0, null, null, &startup_info, &process_info);
    if (created != FALSE) {
        _ = CloseHandle(process_info.hThread);
        _ = CloseHandle(process_info.hProcess);
        ExitProcess(0);
    }
    ExitProcess(1);
}

fn wideZSpan(ptr: [*:0]const u16) []const u16 {
    var len: usize = 0;
    while (ptr[len] != 0) : (len += 1) {}
    return ptr[0..len];
}

export fn QMK_SetPanicExitHotkey(vk: i32, mods_required: u16, mods_forbidden: u16, enabled: i32) callconv(.c) i32 {
    if (vk <= 0 or vk >= VK_COUNT) {
        @atomicStore(i32, &g_panicExitEnabled, 0, .release);
        return 0;
    }
    @atomicStore(i32, &g_panicExitVK, vk, .release);
    @atomicStore(u16, &g_panicExitModsRequired, mods_required, .release);
    @atomicStore(u16, &g_panicExitModsForbidden, mods_forbidden, .release);
    @atomicStore(i32, &g_panicExitEnabled, if (enabled != 0) 1 else 0, .release);
    return 1;
}

export fn QMK_SetPanicExitHotkeyEntry(hotkeySpec: [*:0]const u16, enabled: i32) callconv(.c) i32 {
    const spec = wideZSpan(hotkeySpec);
    const parsed = parseRuntimeHotkeySpecText16(spec) orelse {
        @atomicStore(i32, &g_panicExitEnabled, 0, .release);
        return 0;
    };
    if (parsed.vk <= 0 or parsed.vk >= VK_COUNT) {
        @atomicStore(i32, &g_panicExitEnabled, 0, .release);
        return 0;
    }
    @atomicStore(i32, &g_panicExitVK, parsed.vk, .release);
    @atomicStore(u16, &g_panicExitModsRequired, parsed.modsRequired, .release);
    @atomicStore(u16, &g_panicExitModsForbidden, parsed.modsForbidden, .release);
    @atomicStore(i32, &g_panicExitEnabled, if (enabled != 0) 1 else 0, .release);
    return 1;
}

export fn QMK_SetNativeReloadHotkey(vk: i32, mods_required: u16, mods_forbidden: u16, enabled: i32) callconv(.c) i32 {
    if (vk <= 0 or vk >= VK_COUNT) {
        @atomicStore(i32, &g_nativeReloadEnabled, 0, .release);
        return 0;
    }
    @atomicStore(i32, &g_nativeReloadVK, vk, .release);
    @atomicStore(u16, &g_nativeReloadModsRequired, mods_required, .release);
    @atomicStore(u16, &g_nativeReloadModsForbidden, mods_forbidden, .release);
    @atomicStore(i32, &g_nativeReloadEnabled, if (enabled != 0) 1 else 0, .release);
    return 1;
}

export fn QMK_SetNativeReloadHotkeyEntry(hotkeySpec: [*:0]const u16, enabled: i32) callconv(.c) i32 {
    const spec = wideZSpan(hotkeySpec);
    const parsed = parseRuntimeHotkeySpecText16(spec) orelse {
        @atomicStore(i32, &g_nativeReloadEnabled, 0, .release);
        return 0;
    };
    if (parsed.vk <= 0 or parsed.vk >= VK_COUNT) {
        @atomicStore(i32, &g_nativeReloadEnabled, 0, .release);
        return 0;
    }
    @atomicStore(i32, &g_nativeReloadVK, parsed.vk, .release);
    @atomicStore(u16, &g_nativeReloadModsRequired, parsed.modsRequired, .release);
    @atomicStore(u16, &g_nativeReloadModsForbidden, parsed.modsForbidden, .release);
    @atomicStore(i32, &g_nativeReloadEnabled, if (enabled != 0) 1 else 0, .release);
    return 1;
}

fn refreshSuspendSensitiveRuntimeState() void {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    g_bulkRuntimeHotkeysDirty = true;
    g_bulkRuntimeContextActionsDirty = true;
    g_bulkRuntimeModifiersDirty = true;
    g_bulkRuntimeCombosDirty = true;
    g_bulkRuntimeChordsDirty = true;
    g_bulkRuntimeHotstringsDirty = true;
    g_bulkRuntimeKeyGateDirty = true;
    requestRuntimePublish(RUNTIME_PUBLISH_SETUP);
}

export fn QMK_SetRuntimeHotkeysSuspended(suspended: i32) callconv(.c) i32 {
    const value: i32 = if (suspended != 0) 1 else 0;
    @atomicStore(i32, &g_runtimeHotkeysSuspended, value, .release);
    refreshSuspendSensitiveRuntimeState();
    if (value != 0) QMK_EmergencyReset();
    return value;
}

export fn QMK_ToggleRuntimeHotkeysSuspended() callconv(.c) i32 {
    const old = @atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire);
    const value: i32 = if (old == 0) 1 else 0;
    @atomicStore(i32, &g_runtimeHotkeysSuspended, value, .release);
    refreshSuspendSensitiveRuntimeState();
    if (value != 0) QMK_EmergencyReset();
    return value;
}

export fn QMK_GetRuntimeHotkeysSuspended() callconv(.c) i32 {
    return @atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire);
}

export fn QMK_SetCallbackSuspendExempt(callbackId: i32, exempt: i32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    if (callbackId < 0) return 0;
    const id: usize = @intCast(callbackId);
    if (!ensureRuntimeCallbackSuspendExemptCapacity(id + 1)) return 0;
    g_runtimeCallbackSuspendExempt[id] = exempt != 0;
    return 1;
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
        const modVK: u16 = g_virtual_modifier_output_vk[@intCast(g_kbVK[i])];
        if (modVK != 0) {
            ringReset();
            ringAddKey(modVK, KEYEVENTF_KEYUP);
            ringSend();
        }
        ekd.cf(FLAG_MOD_ACT | FLAG_MOD_TRIG);
    }
    // Second pass: send key-up for every modifier type that has an entry in
    // g_active_virtual_modifiers_by_vk but is no longer physically in the key buffer.
    const modVKs = [_]u16{ VK_CONTROL, VK_MENU, VK_SHIFT, VK_LWIN };
    const modTypes = [_]i8{ MOD_CTRL, MOD_ALT, MOD_SHIFT, MOD_WIN };
    for (modVKs, modTypes) |mvk, mt| {
        var found = false;
        for (0..@intCast(g_active_virtual_modifier_count)) |j| {
            if (activeContextDerived().keyModType[@intCast(g_active_virtual_modifiers_by_vk[j])] == mt) {
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
    clear_active_virtual_modifiers();
    g_unrelModCount = 0;
    g_cleanUnrelModCount = 0;
    rfClear(RF_UNREL_MODS | RF_CLEAN_UNREL_MODS); // FSM-lite
}
export fn QMK_ForceResetModifiers() callconv(.c) void {
    QMK_ReleaseStuckModifiers();
    clear_active_virtual_modifiers();
    g_active_physical_and_windows_facing_modifiers = 0;
    g_active_physical_modifiers = 0;
    g_any_physical_modifiers_active = false;
    var toDelete: [VK_COUNT]i32 = undefined;
    var tdCount: usize = 0;
    for (0..g_kbLen) |i| if (g_kbData[i].isRuntimeModifier()) {
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
    g_cleanUnrelModCount = 0;
    g_activeModKeyCnt = 0;
    // FSM-lite: clear RF flags for all zeroed state
    rfClear(RF_SYS_MODS | RF_PHYSICAL_MODS | RF_UNREL_MODS | RF_CLEAN_UNREL_MODS);
}

// ============================================================================
// Section 21 — DLL exports: registration
// ============================================================================
// Elevate the calling thread (AHK's keyboard hook thread) to TIME_CRITICAL.
// Call this once from AHK immediately after QMK_SetInterceptionCallbacks.
// This eliminates scheduler jitter on the critical path that handles every
// physical keystroke before it reaches any application.
export fn QMK_ElevateCallerThread() callconv(.c) void {
    _ = SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);
}
export fn QMK_RegisterVK(vk: i32, keyName: [*:0]const u16) callconv(.c) void {
    registerVK(vk, keyName);
    markKeyGateDirty();
    refreshReplayKeyGate();
}
fn refreshReplayKeyGate() void {
    // Most setup callers already rebuilt through markKeyGateDirty(). Do not
    // rebuild a second time; only cover the rare deferred-dirty caller here.
    if (g_keyGateDirty) {
        rebuild_runtime_vk_plan();
        g_keyGateDirty = false;
    }
    warmHotTables();
}
fn setupStaticModifierText(key: [*:0]const u16, modName: [*:0]const u16) void {
    const vk = getVKFromName(key);
    if (vk == 0) return;
    const mt = parseModTypeName(modName);
    setModTypeForVK(vk, mt);
    for (0..g_keyCount) |i| if (g_keyVKs[i] == vk) {
        g_modTypes[i] = mt;
        break;
    };
    markKeyGateDirty();
    refreshReplayKeyGate();
}
fn readU16LE(bytes: [*]const u8, offset: usize) u16 {
    return @as(u16, bytes[offset]) |
        (@as(u16, bytes[offset + 1]) << 8);
}
fn readU32LE(bytes: [*]const u8, offset: usize) u32 {
    return @as(u32, bytes[offset]) |
        (@as(u32, bytes[offset + 1]) << 8) |
        (@as(u32, bytes[offset + 2]) << 16) |
        (@as(u32, bytes[offset + 3]) << 24);
}
fn readI32LE(bytes: [*]const u8, offset: usize) i32 {
    return @bitCast(readU32LE(bytes, offset));
}
fn setupModifierVK(vk: i32, mt: i8) void {
    if (vk == 0) return;
    setModTypeForVK(vk, mt);
    for (0..g_keyCount) |i| if (g_keyVKs[i] == vk) {
        g_modTypes[i] = mt;
        break;
    };
}
fn setupHoldVK(vk: i32, callbackId: i32) void {
    if (vk >= 0 and vk < VK_COUNT) {
        g_holdRegisteredFlat[@intCast(vk)] = true;
        g_hcFlat[@intCast(vk)] = callbackId;
    }
}
fn setupDoubleTapVK(vk: i32, callbackId: i32) void {
    if (vk >= 0 and vk < VK_COUNT) {
        g_doubleTapRegisteredFlat[@intCast(vk)] = true;
        g_modDtFlat[@intCast(vk)] = callbackId;
    }
}
fn setupComboVK(pkVK: i32, skVK: i32, callbackId: i32) void {
    if (pkVK == 0 or skVK == 0) return;
    const ck = makeComboKey(pkVK, skVK);
    if (!ccPut(ck, callbackId)) return;
    comboPrimaryBitSet(pkVK);
    if (pkVK < VK_COUNT and skVK < VK_COUNT)
        g_comboMatrix[@intCast(pkVK)][@intCast(skVK)] = true;
}
fn setupInstantComboVK(pkVK: i32, skVK: i32, callbackId: i32) void {
    if (pkVK == 0 or skVK == 0) return;
    const ck = makeComboKey(pkVK, skVK);
    if (!iccPut(ck, callbackId)) return;
    instantComboPrimaryBitSet(pkVK);
    if (pkVK < VK_COUNT and skVK < VK_COUNT)
        g_instantComboMatrix[@intCast(pkVK)][@intCast(skVK)] = true;
}
fn setupInternalComboVK(pkVK: i32, skVK: i32, targetVK: i32, mask: u16, isInstant: bool) void {
    if (pkVK == 0 or skVK == 0 or targetVK == 0) return;
    const ck = makeComboKey(pkVK, skVK);
    if (isInstant) {
        if (!icPut(ck, .{ .targetVK = targetVK, .modMask = mask, .isInstant = isInstant })) return;
        if (!iccPut(ck, -1)) return;
        g_hasInternalCombos = true;
        instantComboPrimaryBitSet(pkVK);
        if (pkVK < VK_COUNT and skVK < VK_COUNT)
            g_instantComboMatrix[@intCast(pkVK)][@intCast(skVK)] = true;
    } else {
        if (!icPut(ck, .{ .targetVK = targetVK, .modMask = mask, .isInstant = isInstant })) return;
        if (!ccPut(ck, -1)) return;
        g_hasInternalCombos = true;
        comboPrimaryBitSet(pkVK);
        if (pkVK < VK_COUNT and skVK < VK_COUNT)
            g_comboMatrix[@intCast(pkVK)][@intCast(skVK)] = true;
    }
}

inline fn markRuntimeCallbackSuspendExempt(callback_id: i32, suspend_exempt: bool) bool {
    if (!suspend_exempt or callback_id < 0) return true;
    const cb: usize = @intCast(callback_id);
    if (!ensureRuntimeCallbackSuspendExemptCapacity(cb + 1)) return false;
    g_runtimeCallbackSuspendExempt[cb] = true;
    return true;
}

inline fn ensureRuntimeCallbackSuspendExemptFor(callback_id: i32, suspend_exempt: bool) bool {
    if (!suspend_exempt or callback_id < 0) return true;
    return ensureRuntimeCallbackSuspendExemptCapacity(@as(usize, @intCast(callback_id)) + 1);
}

inline fn ensureRuntimeCallbackSuspendExemptFor3(a: i32, b: i32, c: i32, suspend_exempt: bool) bool {
    if (!ensureRuntimeCallbackSuspendExemptFor(a, suspend_exempt)) return false;
    if (!ensureRuntimeCallbackSuspendExemptFor(b, suspend_exempt)) return false;
    if (!ensureRuntimeCallbackSuspendExemptFor(c, suspend_exempt)) return false;
    return true;
}

fn ensureRuntimeCallbackSuspendExemptCapacity(required: usize) bool {
    if (required <= g_runtimeCallbackSuspendExempt.len) return true;
    var new_cap: usize = if (g_runtimeCallbackSuspendExempt.len == 0) RUNTIME_CALLBACK_EXEMPT_INITIAL_CAP else g_runtimeCallbackSuspendExempt.len * 2;
    while (new_cap < required) : (new_cap *= 2) {}
    const new_rows = gAlloc.alloc(bool, new_cap) catch return false;
    @memset(new_rows, false);
    if (g_runtimeCallbackSuspendExempt.len != 0) {
        @memcpy(new_rows[0..g_runtimeCallbackSuspendExempt.len], g_runtimeCallbackSuspendExempt);
    }
    const old_rows = g_runtimeCallbackSuspendExempt;
    g_runtimeCallbackSuspendExempt = new_rows;
    retireSlice(bool, old_rows);
    return true;
}

inline fn includeRuntimeSuspendExemptCallback(max_id: *usize, callback_id: i32, suspend_exempt: bool) void {
    if (!suspend_exempt or callback_id < 0) return;
    const cb: usize = @intCast(callback_id);
    if (cb > max_id.*) max_id.* = cb;
}

fn rebuildRuntimeCallbackSuspendExemptFromPublished() bool {
    var max_id: usize = 0;
    var any = false;
    var i: usize = 0;
    while (i < g_runtimeHotkeysPublishedLen) : (i += 1) {
        const row = g_runtimeHotkeys[i];
        if (!row.suspendExempt) continue;
        any = true;
        includeRuntimeSuspendExemptCallback(&max_id, row.callbackId, true);
        includeRuntimeSuspendExemptCallback(&max_id, row.holdCallbackId, true);
        includeRuntimeSuspendExemptCallback(&max_id, row.cleanupCallbackId, true);
    }
    i = 0;
    while (i < g_runtimeContextActionsPublishedLen) : (i += 1) {
        const row = g_runtimeContextActions[i];
        if (!row.suspendExempt) continue;
        any = true;
        includeRuntimeSuspendExemptCallback(&max_id, row.callbackId, true);
        includeRuntimeSuspendExemptCallback(&max_id, row.tapCallbackId, true);
        includeRuntimeSuspendExemptCallback(&max_id, row.holdCallbackId, true);
    }
    i = 0;
    while (i < g_runtimeCombosPublishedLen) : (i += 1) {
        const row = g_runtimeCombos[i];
        if (!row.suspendExempt) continue;
        any = true;
        includeRuntimeSuspendExemptCallback(&max_id, row.callbackId, true);
    }
    i = 0;
    while (i < g_runtimeInstantCombosPublishedLen) : (i += 1) {
        const row = g_runtimeInstantCombos[i];
        if (!row.suspendExempt) continue;
        any = true;
        includeRuntimeSuspendExemptCallback(&max_id, row.callbackId, true);
    }
    i = 0;
    while (i < g_runtimeChordsPublishedLen) : (i += 1) {
        const row = g_runtimeChords[i];
        if (!row.suspendExempt) continue;
        any = true;
        includeRuntimeSuspendExemptCallback(&max_id, row.callbackId, true);
    }
    i = 0;
    while (i < g_runtimeHotstringPublishedLen) : (i += 1) {
        if (!g_runtimeHotstringSuspendExempt[i]) continue;
        any = true;
        includeRuntimeSuspendExemptCallback(&max_id, g_runtimeHotstringCallbackIds[i], true);
    }

    if (any and !ensureRuntimeCallbackSuspendExemptCapacity(max_id + 1)) return false;
    if (g_runtimeCallbackSuspendExempt.len != 0) @memset(g_runtimeCallbackSuspendExempt, false);
    i = 0;
    while (i < g_runtimeHotkeysPublishedLen) : (i += 1) {
        const row = g_runtimeHotkeys[i];
        _ = markRuntimeCallbackSuspendExempt(row.callbackId, row.suspendExempt);
        _ = markRuntimeCallbackSuspendExempt(row.holdCallbackId, row.suspendExempt);
        _ = markRuntimeCallbackSuspendExempt(row.cleanupCallbackId, row.suspendExempt);
    }
    i = 0;
    while (i < g_runtimeContextActionsPublishedLen) : (i += 1) {
        const row = g_runtimeContextActions[i];
        _ = markRuntimeCallbackSuspendExempt(row.callbackId, row.suspendExempt);
        _ = markRuntimeCallbackSuspendExempt(row.tapCallbackId, row.suspendExempt);
        _ = markRuntimeCallbackSuspendExempt(row.holdCallbackId, row.suspendExempt);
    }
    i = 0;
    while (i < g_runtimeCombosPublishedLen) : (i += 1) {
        _ = markRuntimeCallbackSuspendExempt(g_runtimeCombos[i].callbackId, g_runtimeCombos[i].suspendExempt);
    }
    i = 0;
    while (i < g_runtimeInstantCombosPublishedLen) : (i += 1) {
        _ = markRuntimeCallbackSuspendExempt(g_runtimeInstantCombos[i].callbackId, g_runtimeInstantCombos[i].suspendExempt);
    }
    i = 0;
    while (i < g_runtimeChordsPublishedLen) : (i += 1) {
        _ = markRuntimeCallbackSuspendExempt(g_runtimeChords[i].callbackId, g_runtimeChords[i].suspendExempt);
    }
    i = 0;
    while (i < g_runtimeHotstringPublishedLen) : (i += 1) {
        _ = markRuntimeCallbackSuspendExempt(g_runtimeHotstringCallbackIds[i], g_runtimeHotstringSuspendExempt[i]);
    }
    return true;
}

fn runtimeModifierDuplicate(vk: i32, mod_type: i8, context_kind: u8, context_negated: bool, context_text: []const u16, suspend_exempt: bool) bool {
    var i: usize = 0;
    while (i < g_runtimeModifiersLen) : (i += 1) {
        const row = g_runtimeModifiers[i];
        if (row.vk != vk or row.modType != mod_type or row.contextKind != context_kind or
            row.contextNegated != context_negated or row.suspendExempt != suspend_exempt) continue;
        const len: usize = @intCast(row.contextLen);
        if (runtimeContextTextEqual(g_runtimeModifierTexts[i][0..len], context_text)) return true;
    }
    return false;
}

fn ensureRuntimeModifierCapacity(required: usize) bool {
    if (required <= g_runtimeModifiersCap) return true;
    var new_cap: usize = if (g_runtimeModifiersCap == 0) RUNTIME_MODIFIER_INITIAL_CAP else g_runtimeModifiersCap * 2;
    while (new_cap < required) : (new_cap *= 2) {}
    const new_rows = gAlloc.alloc(RuntimeModifier, new_cap) catch return false;
    const new_texts = gAlloc.alloc(RuntimeContextActionText, new_cap) catch {
        gAlloc.free(new_rows);
        return false;
    };
    if (g_runtimeModifiersLen != 0) {
        @memcpy(new_rows[0..g_runtimeModifiersLen], g_runtimeModifiers[0..g_runtimeModifiersLen]);
        @memcpy(new_texts[0..g_runtimeModifiersLen], g_runtimeModifierTexts[0..g_runtimeModifiersLen]);
    }
    if (new_cap > g_runtimeModifiersLen) {
        @memset(new_rows[g_runtimeModifiersLen..new_cap], RuntimeModifier{});
        @memset(new_texts[g_runtimeModifiersLen..new_cap], [_]u16{0} ** RUNTIME_CONTEXT_ACTION_CHARS);
    }
    const old_rows = g_runtimeModifiers;
    const old_texts = g_runtimeModifierTexts;
    g_runtimeModifiers = new_rows;
    g_runtimeModifierTexts = new_texts;
    g_runtimeModifiersCap = new_cap;
    retireSlice(RuntimeModifier, old_rows);
    retireSlice(RuntimeContextActionText, old_texts);
    return true;
}

fn appendRuntimeModifier(vk: i32, mod_type: i8, context_kind: u8, context_negated: bool, context_text: []const u16, suspend_exempt: bool) bool {
    if (!ensureRuntimeModifierCapacity(g_runtimeModifiersLen + 1)) return false;
    if (vk <= 0 or vk >= VK_COUNT) return false;
    if (mod_type < MOD_NONE or mod_type > MOD_WIN) return false;
    // Compiled modifiers are published into the same runtime store before
    // normal AHK setup runs.  Re-submitting an identical runtime row must be
    // an idempotent success, not a failed insertion that makes SetupModifiers
    // report the entire family as broken.
    if (runtimeModifierDuplicate(vk, mod_type, context_kind, context_negated, context_text, suspend_exempt)) return true;

    const vk_idx: usize = @intCast(vk);
    if (!g_runtimeModifierTouched[vk_idx]) {
        g_runtimeModifierTouched[vk_idx] = true;
        g_runtimeModifierBaseType[vk_idx] = g_modTypeFlat[vk_idx];
    }

    const slot = g_runtimeModifiersLen;
    @memset(&g_runtimeModifierTexts[slot], 0);
    if (context_text.len >= RUNTIME_CONTEXT_ACTION_CHARS) return false;
    const text_len = context_text.len;
    if (text_len != 0) @memcpy(g_runtimeModifierTexts[slot][0..text_len], context_text[0..text_len]);
    g_runtimeModifiers[slot] = .{
        .vk = vk,
        .modType = mod_type,
        .contextKind = context_kind,
        .contextNegated = context_negated,
        .contextLen = @intCast(text_len),
        .specificityMask = runtimeHotkeySpecificityMask(context_kind, g_runtimeModifierTexts[slot][0..text_len]),
        .suspendExempt = suspend_exempt,
    };
    g_runtimeModifierDependencyMask |= g_runtimeModifiers[slot].specificityMask;
    g_runtimeModifiersLen += 1;
    return true;
}
/// Context-aware passthrough keys. Record layout (20 bytes): vk:i32,
/// contextKind:u8, negated:u8, suspendExempt:u8, reserved:u8,
/// textOffset:u32 at +12, textLen:u16 at +16.
export fn QMK_SetupPassthroughs(records: [*]const u8, count: u32, contextChars: [*]const u16, contextCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimePassthroughFamily();
    if (!ensureRuntimePassthroughCapacity(g_runtimePassthroughsLen + @as(usize, @intCast(count)))) return 0;
    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 20;
        const vk = readI32LE(records, off);
        const text_offset: usize = @intCast(readU32LE(records, off + 12));
        var text_len: usize = @intCast(readU16LE(records, off + 16));
        if (text_offset > contextCharsLen) continue;
        const remaining: usize = @intCast(contextCharsLen - @as(u32, @intCast(text_offset)));
        if (text_len > remaining) text_len = remaining;
        if (appendRuntimePassthrough(vk, records[off + 4], records[off + 5] != 0, contextChars[text_offset..][0..text_len], records[off + 6] != 0)) loaded += 1;
    }
    finishRuntimePassthroughSetup();
    return loaded;
}

export fn QMK_SetupPassthroughEntries(records: [*]const u8, count: u32, textChars: [*]const u16, textCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimePassthroughFamily();
    if (!ensureRuntimePassthroughCapacity(g_runtimePassthroughsLen + @as(usize, @intCast(count)))) return 0;
    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 24;
        const key_offset: usize = @intCast(readU32LE(records, off));
        var key_len: usize = @intCast(readU16LE(records, off + 4));
        const context_offset: usize = @intCast(readU32LE(records, off + 8));
        var context_len: usize = @intCast(readU16LE(records, off + 12));
        if (key_offset > textCharsLen or context_offset > textCharsLen) continue;
        const key_remaining: usize = @intCast(textCharsLen - @as(u32, @intCast(key_offset)));
        const context_remaining: usize = @intCast(textCharsLen - @as(u32, @intCast(context_offset)));
        if (key_len > key_remaining) key_len = key_remaining;
        if (context_len > context_remaining) context_len = context_remaining;
        const vk = getVKFromText16(textChars[key_offset..][0..key_len]);
        var row_loaded = false;
        var contexts = RuntimeContextListIterator{ .raw = textChars[context_offset..][0..context_len] };
        while (contexts.next()) |context_part| {
            const context = parseRuntimeContextSpec(context_part);
            if (appendRuntimePassthrough(vk, context.kind, context.negated, context.text, records[off + 14] != 0)) row_loaded = true;
        }
        if (row_loaded) loaded += 1;
    }
    finishRuntimePassthroughSetup();
    return loaded;
}

/// Context-aware homerow modifiers. AHK only serializes rows; Zig owns
/// specificity ordering, active-context selection, suspend filtering, and
/// key-gate rebuilds. Record layout (20 bytes): vk:i32, modType:i32,
/// contextKind:u8, negated:u8, suspendExempt:u8, reserved:u8,
/// textOffset:u32, textLen:u16.
export fn QMK_SetupModifiers(records: [*]const u8, count: u32, contextChars: [*]const u16, contextCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeModifierFamily();
    if (!ensureRuntimeModifierCapacity(g_runtimeModifiersLen + @as(usize, @intCast(count)))) return 0;
    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 20;
        const vk = readI32LE(records, off);
        const mod_type: i8 = @intCast(readI32LE(records, off + 4));
        if (vk <= 0 or vk >= VK_COUNT) continue;
        if (mod_type < MOD_NONE or mod_type > MOD_WIN) continue;
        const text_offset: usize = @intCast(readU32LE(records, off + 12));
        var text_len: usize = @intCast(readU16LE(records, off + 16));
        if (text_offset > contextCharsLen) continue;
        const remaining: usize = @intCast(contextCharsLen - @as(u32, @intCast(text_offset)));
        if (text_len > remaining) text_len = remaining;
        if (text_len >= RUNTIME_CONTEXT_ACTION_CHARS) continue;
        if (appendRuntimeModifier(vk, mod_type, records[off + 8], records[off + 9] != 0, contextChars[text_offset..][0..text_len], records[off + 10] != 0))
            loaded += 1;
    }
    finishRuntimeModifierSetup();
    return loaded;
}
/// Higher-level modifier entries. AHK sends only UTF-16 strings and flags;
/// Zig parses key names, modifier names, context kinds, negation, specificity,
/// active-row rebuilds, and suspension. Record layout (32 bytes):
/// keyOffset:u32, keyLen:u16, reserved:u16, modOffset:u32, modLen:u16,
/// suspendExempt:u8, reserved:u8, contextOffset:u32, contextLen:u16, reserved.
export fn QMK_SetupModifierEntries(records: [*]const u8, count: u32, textChars: [*]const u16, textCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeModifierFamily();
    if (!ensureRuntimeModifierCapacity(g_runtimeModifiersLen + @as(usize, @intCast(count)))) return 0;
    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 32;
        const key_offset: usize = @intCast(readU32LE(records, off));
        var key_len: usize = @intCast(readU16LE(records, off + 4));
        const mod_offset: usize = @intCast(readU32LE(records, off + 8));
        var mod_len: usize = @intCast(readU16LE(records, off + 12));
        const suspend_exempt = records[off + 14] != 0;
        const context_offset: usize = @intCast(readU32LE(records, off + 16));
        var context_len: usize = @intCast(readU16LE(records, off + 20));
        if (key_offset > textCharsLen or mod_offset > textCharsLen or context_offset > textCharsLen) continue;

        const key_remaining: usize = @intCast(textCharsLen - @as(u32, @intCast(key_offset)));
        const mod_remaining: usize = @intCast(textCharsLen - @as(u32, @intCast(mod_offset)));
        const context_remaining: usize = @intCast(textCharsLen - @as(u32, @intCast(context_offset)));
        if (key_len > key_remaining) key_len = key_remaining;
        if (mod_len > mod_remaining) mod_len = mod_remaining;
        if (context_len > context_remaining) context_len = context_remaining;

        const vk = getVKFromText16(textChars[key_offset..][0..key_len]);
        const mod_type = parseModTypeText16(textChars[mod_offset..][0..mod_len]);
        const context_parts = runtimeContextPartCount(textChars[context_offset..][0..context_len]);
        if (!ensureRuntimeModifierCapacity(g_runtimeModifiersLen + context_parts)) {
            truncateRuntimeModifiersToPublished();
            return 0;
        }
        var contexts = RuntimeContextListIterator{ .raw = textChars[context_offset..][0..context_len] };
        var row_loaded = false;
        while (contexts.next()) |context_part| {
            const context = parseRuntimeContextSpec(context_part);
            if (appendRuntimeModifier(vk, mod_type, context.kind, context.negated, context.text, suspend_exempt))
                row_loaded = true;
        }
        if (row_loaded)
            loaded += 1;
    }
    finishRuntimeModifierSetup();
    return loaded;
}

/// Typed-cell modifier entries. AHK sends row cells; Zig owns key/modifier,
/// context-list parsing, duplicate handling, and active-row rebuilds.
/// Record layout (68 bytes): cellCount:u8 at 0; four 16-byte cells at 4.
export fn QMK_SetupModifierCellEntries(records: [*]const u8, count: u32, textChars: [*]const u16, textCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeModifierFamily();
    if (!ensureRuntimeModifierCapacity(g_runtimeModifiersLen + @as(usize, @intCast(count)))) return 0;
    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 68;
        const raw_cell_count = records[off];
        if (raw_cell_count < 2) continue;
        const cell_count: usize = @min(@as(usize, @intCast(raw_cell_count)), 4);
        var cells = [_]RuntimeHotkeyCell{.{}} ** 4;
        var c: usize = 0;
        var valid = true;
        var suspend_exempt = false;
        while (c < cell_count) : (c += 1) {
            cells[c] = readRuntimeHotkeyCell(records, off, c, textChars, textCharsLen) orelse {
                valid = false;
                break;
            };
            suspend_exempt = suspend_exempt or ((cells[c].flags & 1) != 0);
        }
        if (!valid or cells[0].tag != HOTKEY_CELL_TEXT or cells[1].tag != HOTKEY_CELL_TEXT) continue;

        var context_text: []const u16 = &[_]u16{};
        if (cell_count >= 3) {
            if (cells[2].tag != HOTKEY_CELL_TEXT) continue;
            context_text = cells[2].text;
        }
        if (cell_count >= 4) suspend_exempt = suspend_exempt or runtimeHotkeyBoolCell(cells[3]);

        const vk = getVKFromText16(cells[0].text);
        const mod_type = parseModTypeText16(cells[1].text);
        const context_parts = runtimeContextPartCount(context_text);
        if (!ensureRuntimeModifierCapacity(g_runtimeModifiersLen + context_parts)) {
            truncateRuntimeModifiersToPublished();
            return 0;
        }
        var contexts = RuntimeContextListIterator{ .raw = context_text };
        var row_loaded = false;
        while (contexts.next()) |context_text_part| {
            const context = parseRuntimeContextSpec(context_text_part);
            if (appendRuntimeModifier(vk, mod_type, context.kind, context.negated, context.text, suspend_exempt))
                row_loaded = true;
        }
        if (row_loaded)
            loaded += 1;
    }
    finishRuntimeModifierSetup();
    return loaded;
}
export fn QMK_SetupHolds(records: [*]const u8, count: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 8;
        setupHoldVK(readI32LE(records, off), readI32LE(records, off + 4));
    }
    markKeyGateDirty();
    refreshReplayKeyGate();
    return @intCast(count);
}
export fn QMK_SetupDoubleTaps(records: [*]const u8, count: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 8;
        setupDoubleTapVK(readI32LE(records, off), readI32LE(records, off + 4));
    }
    markKeyGateDirty();
    refreshReplayKeyGate();
    return @intCast(count);
}
fn runtimeContextActionTextMatches(index: usize, context_text: []const u16) bool {
    const len: usize = @intCast(g_runtimeContextActions[index].contextLen);
    return runtimeContextTextEqual(g_runtimeContextActionTexts[index][0..len], context_text);
}

fn runtimeContextActionDuplicate(
    vk: i32, callback_id: i32, action_kind: u8,
    context_kind: u8, context_negated: bool, context_text: []const u16,
    suspend_exempt: bool,
) bool {
    var i: usize = 0;
    while (i < g_runtimeContextActionsLen) : (i += 1) {
        const row = g_runtimeContextActions[i];
        if (row.triggerVK != vk or row.actionKind != action_kind or row.contextKind != context_kind or row.contextNegated != context_negated) continue;
        if (row.callbackId != callback_id or row.suspendExempt != suspend_exempt) continue;
        if (runtimeContextActionTextMatches(i, context_text)) return true;
    }
    return false;
}

fn runtimeTapHoldRegistrationDuplicate(
    vk: i32, tap_callback_id: i32, hold_callback_id: i32, cleanup_callback_id: i32, threshold_ms: i32,
    context_kind: u8, context_negated: bool, context_text: []const u16, suspend_exempt: bool,
) bool {
    const threshold_ticks = msToTicksInt(@max(50, @min(2000, threshold_ms)));
    var i: usize = 0;
    while (i < g_runtimeContextActionsLen) : (i += 1) {
        const row = g_runtimeContextActions[i];
        if (row.triggerVK != vk or row.actionKind != 4 or row.contextKind != context_kind or row.contextNegated != context_negated) continue;
        if (row.tapCallbackId != tap_callback_id or row.holdCallbackId != hold_callback_id or
            row.callbackId != cleanup_callback_id or row.thresholdTicks != threshold_ticks or
            row.suspendExempt != suspend_exempt) continue;
        if (runtimeContextActionTextMatches(i, context_text)) return true;
    }
    return false;
}

fn ensureRuntimeContextActionCapacity(required: usize) bool {
    if (required <= g_runtimeContextActionsCap) return true;
    var new_cap: usize = if (g_runtimeContextActionsCap == 0) RUNTIME_CONTEXT_ACTION_INITIAL_CAP else g_runtimeContextActionsCap * 2;
    while (new_cap < required) : (new_cap *= 2) {}
    const new_rows = gAlloc.alloc(RuntimeContextAction, new_cap) catch return false;
    const new_texts = gAlloc.alloc(RuntimeContextActionText, new_cap) catch {
        gAlloc.free(new_rows);
        return false;
    };
    if (g_runtimeContextActionsLen != 0) {
        @memcpy(new_rows[0..g_runtimeContextActionsLen], g_runtimeContextActions[0..g_runtimeContextActionsLen]);
        @memcpy(new_texts[0..g_runtimeContextActionsLen], g_runtimeContextActionTexts[0..g_runtimeContextActionsLen]);
    }
    if (new_cap > g_runtimeContextActionsLen) {
        @memset(new_rows[g_runtimeContextActionsLen..new_cap], RuntimeContextAction{});
        @memset(new_texts[g_runtimeContextActionsLen..new_cap], [_]u16{0} ** RUNTIME_CONTEXT_ACTION_CHARS);
    }
    const old_rows = g_runtimeContextActions;
    const old_texts = g_runtimeContextActionTexts;
    g_runtimeContextActions = new_rows;
    g_runtimeContextActionTexts = new_texts;
    g_runtimeContextActionsCap = new_cap;
    retireSlice(RuntimeContextAction, old_rows);
    retireSlice(RuntimeContextActionText, old_texts);
    return true;
}

fn appendRuntimeContextAction(vk: i32, callback_id: i32, action_kind: u8, context_kind: u8, context_negated: bool, context_text: []const u16, suspend_exempt: bool) bool {
    if (!ensureRuntimeContextActionCapacity(g_runtimeContextActionsLen + 1)) return false;
    if (vk <= 0 or vk >= VK_COUNT or (callback_id < 0 and !isCompiledZigCallbackId(callback_id)) or action_kind > 3) return false;
    if (runtimeContextActionDuplicate(vk, callback_id, action_kind, context_kind, context_negated, context_text, suspend_exempt)) return false;
    if (!ensureRuntimeCallbackSuspendExemptFor(callback_id, suspend_exempt)) return false;

    const slot = g_runtimeContextActionsLen;
    @memset(&g_runtimeContextActionTexts[slot], 0);
    if (context_text.len >= RUNTIME_CONTEXT_ACTION_CHARS) return false;
    const text_len = context_text.len;
    if (text_len != 0) @memcpy(g_runtimeContextActionTexts[slot][0..text_len], context_text[0..text_len]);
    g_runtimeContextActions[slot] = .{
        .triggerVK = vk,
        .callbackId = callback_id,
        .actionKind = action_kind,
        .contextKind = context_kind,
        .contextNegated = context_negated,
        .contextLen = @intCast(text_len),
        .specificityMask = runtimeHotkeySpecificityMask(context_kind, g_runtimeContextActionTexts[slot][0..text_len]),
        .suspendExempt = suspend_exempt,
    };
    if (g_runtimeContextActions[slot].specificityMask != 0)
        g_runtimeContextActionGate[@intCast(vk)] = true;
    _ = markRuntimeCallbackSuspendExempt(callback_id, suspend_exempt);
    switch (action_kind) {
        0 => g_runtimeHoldTouched[@intCast(vk)] = true,
        1 => g_runtimeDoubleTapTouched[@intCast(vk)] = true,
        2 => g_runtimeTapHoldTapTouched[@intCast(vk)] = true,
        else => g_runtimeTapHoldHoldTouched[@intCast(vk)] = true,
    }
    g_runtimeContextActionDependencyMask |= g_runtimeContextActions[slot].specificityMask;
    g_runtimeContextActionsLen += 1;
    return true;
}

fn appendRuntimeTapHoldRegistration(
    vk: i32, tap_callback_id: i32, hold_callback_id: i32, cleanup_callback_id: i32, threshold_ms: i32,
    context_kind: u8, context_negated: bool, context_text: []const u16, suspend_exempt: bool,
) bool {
    if (!ensureRuntimeContextActionCapacity(g_runtimeContextActionsLen + 1)) return false;
    if (vk <= 0 or vk >= VK_COUNT) return false;
    if (tap_callback_id < 0 and hold_callback_id < 0 and
        !isCompiledZigCallbackId(tap_callback_id) and !isCompiledZigCallbackId(hold_callback_id)) return false;
    if (runtimeTapHoldRegistrationDuplicate(
        vk, tap_callback_id, hold_callback_id, cleanup_callback_id, threshold_ms,
        context_kind, context_negated, context_text, suspend_exempt)) return false;
    if (!ensureRuntimeCallbackSuspendExemptFor3(tap_callback_id, hold_callback_id, cleanup_callback_id, suspend_exempt)) return false;

    const slot = g_runtimeContextActionsLen;
    @memset(&g_runtimeContextActionTexts[slot], 0);
    if (context_text.len >= RUNTIME_CONTEXT_ACTION_CHARS) return false;
    const text_len = context_text.len;
    if (text_len != 0) @memcpy(g_runtimeContextActionTexts[slot][0..text_len], context_text[0..text_len]);
    g_runtimeContextActions[slot] = .{
        .triggerVK = vk,
        .callbackId = cleanup_callback_id,
        .tapCallbackId = tap_callback_id,
        .holdCallbackId = hold_callback_id,
        .actionKind = 4,
        .thresholdTicks = msToTicksInt(@max(50, @min(2000, threshold_ms))),
        .contextKind = context_kind,
        .contextNegated = context_negated,
        .contextLen = @intCast(text_len),
        .specificityMask = runtimeHotkeySpecificityMask(context_kind, g_runtimeContextActionTexts[slot][0..text_len]),
        .suspendExempt = suspend_exempt,
    };
    if (g_runtimeContextActions[slot].specificityMask != 0)
        g_runtimeContextActionGate[@intCast(vk)] = true;
    _ = markRuntimeCallbackSuspendExempt(tap_callback_id, suspend_exempt);
    _ = markRuntimeCallbackSuspendExempt(hold_callback_id, suspend_exempt);
    _ = markRuntimeCallbackSuspendExempt(cleanup_callback_id, suspend_exempt);
    if (tap_callback_id >= 0 or isCompiledZigCallbackId(tap_callback_id))
        g_runtimeTapHoldTapTouched[@intCast(vk)] = true;
    if (hold_callback_id >= 0 or isCompiledZigCallbackId(hold_callback_id))
        g_runtimeTapHoldHoldTouched[@intCast(vk)] = true;
    g_runtimeContextActionDependencyMask |= g_runtimeContextActions[slot].specificityMask;
    g_runtimeContextActionsLen += 1;
    return true;
}

// Context-aware holds and modifier double-taps. AHK only serializes raw
// registrations; Zig owns specificity ordering, active-context selection, and
// global fallback. Record layout (20 bytes): vk:i32, callback:i32, action:u8,
// contextKind:u8, negated:u8, suspendExempt:u8, textOffset:u32, textLen:u16.
export fn QMK_SetupContextActions(records: [*]const u8, count: u32, contextChars: [*]const u16, contextCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeContextActionFamily();
    if (!ensureRuntimeContextActionCapacity(g_runtimeContextActionsLen + @as(usize, @intCast(count)))) return 0;
    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 20;
        const vk = readI32LE(records, off);
        const callback_id = readI32LE(records, off + 4);
        const action_kind = records[off + 8];
        const context_kind = records[off + 9];
        const negated = records[off + 10] != 0;
        const suspend_exempt = records[off + 11] != 0;
        const text_offset: usize = @intCast(readU32LE(records, off + 12));
        var text_len: usize = @intCast(readU16LE(records, off + 16));
        if (vk <= 0 or vk >= VK_COUNT or callback_id < 0 or action_kind > 3) continue;
        if (text_offset > contextCharsLen) continue;
        const remaining: usize = @intCast(contextCharsLen - @as(u32, @intCast(text_offset)));
        if (text_len > remaining) text_len = remaining;
        if (text_len >= RUNTIME_CONTEXT_ACTION_CHARS) continue;
        if (appendRuntimeContextAction(vk, callback_id, action_kind, context_kind, negated, contextChars[text_offset..][0..text_len], suspend_exempt))
            loaded += 1;
    }
    finishRuntimeContextActionSetup();
    return loaded;
}
/// Higher-level hold/double-tap/tap-hold context action entries. AHK sends a
/// key string, callback id, action kind, context string, and suspend flag.
/// Record layout (32 bytes): keyOffset:u32, keyLen:u16, reserved:u16,
/// callbackId:i32, actionKind:u8, suspendExempt:u8, reserved:u16,
/// contextOffset:u32, contextLen:u16, reserved.
export fn QMK_SetupContextActionEntries(records: [*]const u8, count: u32, textChars: [*]const u16, textCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeContextActionFamily();
    if (!ensureRuntimeContextActionCapacity(g_runtimeContextActionsLen + @as(usize, @intCast(count)))) return 0;
    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 32;
        const key_offset: usize = @intCast(readU32LE(records, off));
        var key_len: usize = @intCast(readU16LE(records, off + 4));
        const callback_id = readI32LE(records, off + 8);
        const action_kind = records[off + 12];
        const suspend_exempt = records[off + 13] != 0;
        const context_offset: usize = @intCast(readU32LE(records, off + 16));
        var context_len: usize = @intCast(readU16LE(records, off + 20));
        if (key_offset > textCharsLen or context_offset > textCharsLen) continue;
        const key_remaining: usize = @intCast(textCharsLen - @as(u32, @intCast(key_offset)));
        const context_remaining: usize = @intCast(textCharsLen - @as(u32, @intCast(context_offset)));
        if (key_len > key_remaining) key_len = key_remaining;
        if (context_len > context_remaining) context_len = context_remaining;
        const vk = getVKFromText16(textChars[key_offset..][0..key_len]);
        const context_parts = runtimeContextPartCount(textChars[context_offset..][0..context_len]);
        if (!ensureRuntimeContextActionCapacity(g_runtimeContextActionsLen + context_parts)) {
            truncateRuntimeContextActionsToPublished();
            return 0;
        }
        if (!ensureRuntimeCallbackSuspendExemptFor(callback_id, suspend_exempt)) {
            truncateRuntimeContextActionsToPublished();
            return 0;
        }
        var contexts = RuntimeContextListIterator{ .raw = textChars[context_offset..][0..context_len] };
        var row_loaded = false;
        while (contexts.next()) |context_part| {
            const context = parseRuntimeContextSpec(context_part);
            if (appendRuntimeContextAction(vk, callback_id, action_kind, context.kind, context.negated, context.text, suspend_exempt))
                row_loaded = true;
        }
        if (row_loaded)
            loaded += 1;
    }
    finishRuntimeContextActionSetup();
    return loaded;
}

/// Typed-cell hold/double-tap context action entries. AHK sends cells and the
/// family action kind; Zig owns key/context/callback/suspend interpretation.
/// Record layout (68 bytes): cellCount:u8 at 0; four 16-byte cells at 4.
export fn QMK_SetupContextActionCellEntries(records: [*]const u8, count: u32, rawActionKind: u32, textChars: [*]const u16, textCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeContextActionFamily();
    if (rawActionKind > 3) return 0;
    if (!ensureRuntimeContextActionCapacity(g_runtimeContextActionsLen + @as(usize, @intCast(count)))) return 0;
    const action_kind: u8 = @intCast(rawActionKind);
    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 68;
        const raw_cell_count = records[off];
        if (raw_cell_count < 2) continue;
        const cell_count: usize = @min(@as(usize, @intCast(raw_cell_count)), 4);
        var cells = [_]RuntimeHotkeyCell{.{}} ** 4;
        var c: usize = 0;
        var valid = true;
        var suspend_exempt = false;
        while (c < cell_count) : (c += 1) {
            cells[c] = readRuntimeHotkeyCell(records, off, c, textChars, textCharsLen) orelse {
                valid = false;
                break;
            };
            suspend_exempt = suspend_exempt or ((cells[c].flags & 1) != 0);
        }
        if (!valid or cells[0].tag != HOTKEY_CELL_TEXT) continue;

        var context_text: []const u16 = &[_]u16{};
        var callback_cell: RuntimeHotkeyCell = .{};
        if (cell_count == 2) {
            callback_cell = cells[1];
        } else if (cell_count == 3 and runtimeHotkeyCellIsPlainCallback(cells[1])) {
            callback_cell = cells[1];
            suspend_exempt = suspend_exempt or runtimeHotkeyBoolCell(cells[2]);
        } else {
            if (cells[1].tag != HOTKEY_CELL_TEXT) continue;
            context_text = cells[1].text;
            callback_cell = cells[2];
            if (cell_count >= 4) suspend_exempt = suspend_exempt or runtimeHotkeyBoolCell(cells[3]);
        }
        if (!runtimeHotkeyCellIsPlainCallback(callback_cell) or callback_cell.callbackId < 0) continue;

        const vk = getVKFromText16(cells[0].text);
        const context_parts = runtimeContextPartCount(context_text);
        if (!ensureRuntimeContextActionCapacity(g_runtimeContextActionsLen + context_parts)) {
            truncateRuntimeContextActionsToPublished();
            return 0;
        }
        if (!ensureRuntimeCallbackSuspendExemptFor(callback_cell.callbackId, suspend_exempt)) {
            truncateRuntimeContextActionsToPublished();
            return 0;
        }
        var contexts = RuntimeContextListIterator{ .raw = context_text };
        var row_loaded = false;
        while (contexts.next()) |context_text_part| {
            const context = parseRuntimeContextSpec(context_text_part);
            if (appendRuntimeContextAction(vk, callback_cell.callbackId, action_kind, context.kind, context.negated, context.text, suspend_exempt))
                row_loaded = true;
        }
        if (row_loaded)
            loaded += 1;
    }
    finishRuntimeContextActionSetup();
    return loaded;
}
fn runtimeComboDuplicate(row: RuntimeCombo, context_text: []const u16) bool {
    var i: usize = 0;
    while (i < g_runtimeCombosLen) : (i += 1) {
        const existing = g_runtimeCombos[i];
        if (existing.primaryVK != row.primaryVK or existing.secondaryVK != row.secondaryVK or
            existing.contextKind != row.contextKind or existing.contextNegated != row.contextNegated) continue;
        if (existing.callbackId != row.callbackId or existing.targetVK != row.targetVK or
            existing.modMask != row.modMask or existing.mode != row.mode or
            existing.suspendExempt != row.suspendExempt) continue;
        if (runtimeContextTextEqual(
            g_runtimeComboTexts[i][0..@as(usize, @intCast(existing.contextLen))], context_text)) return true;
    }
    i = 0;
    while (i < g_runtimeInstantCombosLen) : (i += 1) {
        const existing = g_runtimeInstantCombos[i];
        if (existing.primaryVK != row.primaryVK or existing.secondaryVK != row.secondaryVK or
            existing.contextKind != row.contextKind or existing.contextNegated != row.contextNegated) continue;
        if (existing.callbackId != row.callbackId or existing.targetVK != row.targetVK or
            existing.modMask != row.modMask or existing.mode != row.mode or
            existing.suspendExempt != row.suspendExempt) continue;
        if (runtimeContextTextEqual(
            g_runtimeInstantComboTexts[i][0..@as(usize, @intCast(existing.contextLen))], context_text)) return true;
    }
    return false;
}

fn ensureRuntimeComboCapacity(required: usize) bool {
    if (required <= g_runtimeCombosCap) return true;
    var new_cap: usize = if (g_runtimeCombosCap == 0) RUNTIME_COMBO_INITIAL_CAP else g_runtimeCombosCap * 2;
    while (new_cap < required) : (new_cap *= 2) {}
    const new_rows = gAlloc.alloc(RuntimeCombo, new_cap) catch return false;
    const new_texts = gAlloc.alloc(RuntimeComboText, new_cap) catch {
        gAlloc.free(new_rows);
        return false;
    };
    if (g_runtimeCombosLen != 0) {
        @memcpy(new_rows[0..g_runtimeCombosLen], g_runtimeCombos[0..g_runtimeCombosLen]);
        @memcpy(new_texts[0..g_runtimeCombosLen], g_runtimeComboTexts[0..g_runtimeCombosLen]);
    }
    if (new_cap > g_runtimeCombosLen) {
        @memset(new_rows[g_runtimeCombosLen..new_cap], RuntimeCombo{});
        @memset(new_texts[g_runtimeCombosLen..new_cap], [_]u16{0} ** RUNTIME_COMBO_CONTEXT_CHARS);
    }
    const old_rows = g_runtimeCombos;
    const old_texts = g_runtimeComboTexts;
    g_runtimeCombos = new_rows;
    g_runtimeComboTexts = new_texts;
    g_runtimeCombosCap = new_cap;
    retireSlice(RuntimeCombo, old_rows);
    retireSlice(RuntimeComboText, old_texts);
    return true;
}

fn ensureRuntimeInstantComboCapacity(required: usize) bool {
    if (required <= g_runtimeInstantCombosCap) return true;
    var new_cap: usize = if (g_runtimeInstantCombosCap == 0) RUNTIME_COMBO_INITIAL_CAP else g_runtimeInstantCombosCap * 2;
    while (new_cap < required) : (new_cap *= 2) {}
    const new_rows = gAlloc.alloc(RuntimeCombo, new_cap) catch return false;
    const new_texts = gAlloc.alloc(RuntimeComboText, new_cap) catch {
        gAlloc.free(new_rows);
        return false;
    };
    if (g_runtimeInstantCombosLen != 0) {
        @memcpy(new_rows[0..g_runtimeInstantCombosLen], g_runtimeInstantCombos[0..g_runtimeInstantCombosLen]);
        @memcpy(new_texts[0..g_runtimeInstantCombosLen], g_runtimeInstantComboTexts[0..g_runtimeInstantCombosLen]);
    }
    if (new_cap > g_runtimeInstantCombosLen) {
        @memset(new_rows[g_runtimeInstantCombosLen..new_cap], RuntimeCombo{});
        @memset(new_texts[g_runtimeInstantCombosLen..new_cap], [_]u16{0} ** RUNTIME_COMBO_CONTEXT_CHARS);
    }
    const old_rows = g_runtimeInstantCombos;
    const old_texts = g_runtimeInstantComboTexts;
    g_runtimeInstantCombos = new_rows;
    g_runtimeInstantComboTexts = new_texts;
    g_runtimeInstantCombosCap = new_cap;
    retireSlice(RuntimeCombo, old_rows);
    retireSlice(RuntimeComboText, old_texts);
    return true;
}

fn appendRuntimeCombo(row_in: RuntimeCombo, context_text: []const u16) bool {
    var row = row_in;
    if (row.primaryVK <= 0 or row.primaryVK >= VK_COUNT or row.secondaryVK <= 0 or row.secondaryVK >= VK_COUNT) return false;
    if (row.mode > 3) return false;
    if ((row.mode == 0 or row.mode == 1) and row.callbackId < 0 and !isCompiledZigCallbackId(row.callbackId)) return false;
    if ((row.mode == 2 or row.mode == 3) and row.targetVK == 0) return false;
    if (runtimeComboDuplicate(row, context_text)) return false;
    if (!ensureRuntimeCallbackSuspendExemptFor(row.callbackId, row.suspendExempt)) return false;
    if (row.mode == 1 or row.mode == 3) {
        if (!ensureRuntimeInstantComboCapacity(g_runtimeInstantCombosLen + 1)) return false;
    } else {
        if (!ensureRuntimeComboCapacity(g_runtimeCombosLen + 1)) return false;
    }

    if (context_text.len >= RUNTIME_COMBO_CONTEXT_CHARS) return false;
    const text_len = context_text.len;
    row.contextLen = @intCast(text_len);
    row.registrationOrder = g_runtimeComboRegistrationSeq;
    g_runtimeComboRegistrationSeq +%= 1;
    _ = markRuntimeCallbackSuspendExempt(row.callbackId, row.suspendExempt);
    if (row.mode == 1 or row.mode == 3) {
        const slot = g_runtimeInstantCombosLen;
        @memset(&g_runtimeInstantComboTexts[slot], 0);
        if (text_len != 0) @memcpy(g_runtimeInstantComboTexts[slot][0..text_len], context_text[0..text_len]);
        row.specificityMask = runtimeHotkeySpecificityMask(row.contextKind, g_runtimeInstantComboTexts[slot][0..text_len]);
        g_runtimeInstantCombos[slot] = row;
        g_runtimeInstantCombosLen += 1;
    } else {
        const slot = g_runtimeCombosLen;
        @memset(&g_runtimeComboTexts[slot], 0);
        if (text_len != 0) @memcpy(g_runtimeComboTexts[slot][0..text_len], context_text[0..text_len]);
        row.specificityMask = runtimeHotkeySpecificityMask(row.contextKind, g_runtimeComboTexts[slot][0..text_len]);
        g_runtimeCombos[slot] = row;
        g_runtimeCombosLen += 1;
    }
    g_runtimeComboDependencyMask |= row.specificityMask;
    return true;
}
export fn QMK_SetupCombos(records: [*]const u8, count: u32, contextChars: [*]const u16, contextCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeComboFamily();
    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 32;
        const row = RuntimeCombo{
            .primaryVK = readI32LE(records, off),
            .secondaryVK = readI32LE(records, off + 4),
            .callbackId = readI32LE(records, off + 8),
            .targetVK = readI32LE(records, off + 12),
            .modMask = readU16LE(records, off + 16),
            .mode = records[off + 18],
            .contextKind = records[off + 19],
            .contextNegated = records[off + 20] != 0,
            .suspendExempt = records[off + 21] != 0,
        };
        const text_offset: usize = @intCast(readU32LE(records, off + 24));
        var text_len: usize = @intCast(readU16LE(records, off + 28));
        if (text_offset > contextCharsLen) continue;
        const remaining: usize = @intCast(contextCharsLen - @as(u32, @intCast(text_offset)));
        if (text_len > remaining) text_len = remaining;
        if (text_len >= RUNTIME_COMBO_CONTEXT_CHARS) continue;
        if (!ensureRuntimeCallbackSuspendExemptFor(row.callbackId, row.suspendExempt)) {
            truncateRuntimeCombosToPublished();
            return 0;
        }
        if (appendRuntimeCombo(row, contextChars[text_offset..][0..text_len])) loaded += 1;
    }
    finishRuntimeComboSetup();
    return loaded;
}
/// Higher-level combo entries. AHK sends strings for keys/context/mode/mod/target
/// plus an optional callback id; Zig parses and stores the active combo rows.
/// Record layout (56 bytes): primaryOff:u32, primaryLen:u16, secondaryOff:u32,
/// secondaryLen:u16, callbackId:i32, targetOff:u32, targetLen:u16,
/// modeOff:u32, modeLen:u16, modOff:u32, modLen:u16, suspendExempt:u8,
/// contextOff:u32, contextLen:u16.
export fn QMK_SetupComboEntries(records: [*]const u8, count: u32, textChars: [*]const u16, textCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeComboFamily();
    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 56;
        const p_off: usize = @intCast(readU32LE(records, off));
        var p_len: usize = @intCast(readU16LE(records, off + 4));
        const s_off: usize = @intCast(readU32LE(records, off + 8));
        var s_len: usize = @intCast(readU16LE(records, off + 12));
        const callback_id = readI32LE(records, off + 16);
        const target_off: usize = @intCast(readU32LE(records, off + 20));
        var target_len: usize = @intCast(readU16LE(records, off + 24));
        const mode_off: usize = @intCast(readU32LE(records, off + 28));
        var mode_len: usize = @intCast(readU16LE(records, off + 32));
        const mod_off: usize = @intCast(readU32LE(records, off + 36));
        var mod_len: usize = @intCast(readU16LE(records, off + 40));
        const suspend_exempt = records[off + 42] != 0;
        const context_off: usize = @intCast(readU32LE(records, off + 44));
        var context_len: usize = @intCast(readU16LE(records, off + 48));
        if (p_off > textCharsLen or s_off > textCharsLen or target_off > textCharsLen or mode_off > textCharsLen or mod_off > textCharsLen or context_off > textCharsLen) continue;
        const p_rem: usize = @intCast(textCharsLen - @as(u32, @intCast(p_off)));
        const s_rem: usize = @intCast(textCharsLen - @as(u32, @intCast(s_off)));
        const target_rem: usize = @intCast(textCharsLen - @as(u32, @intCast(target_off)));
        const mode_rem: usize = @intCast(textCharsLen - @as(u32, @intCast(mode_off)));
        const mod_rem: usize = @intCast(textCharsLen - @as(u32, @intCast(mod_off)));
        const context_rem: usize = @intCast(textCharsLen - @as(u32, @intCast(context_off)));
        if (p_len > p_rem) p_len = p_rem;
        if (s_len > s_rem) s_len = s_rem;
        if (target_len > target_rem) target_len = target_rem;
        if (mode_len > mode_rem) mode_len = mode_rem;
        if (mod_len > mod_rem) mod_len = mod_rem;
        if (context_len > context_rem) context_len = context_rem;
        const mode_text = textChars[mode_off..][0..mode_len];
        const mod_text = textChars[mod_off..][0..mod_len];
        const mode = parseComboModeText16(mode_text);
        if (mode == 255) continue;
        const parsed_send = if (comboModeRequiresSendDirectSpec(mode_text))
            parseSendKeyDirectInternalTarget(textChars[target_off..][0..target_len], mod_text) orelse continue
        else
            parseLegacyInternalTarget(textChars[target_off..][0..target_len], mod_text);
        const target_vk = if (mode == 2 or mode == 3) parsed_send.target_vk else 0;
        const primary_vk = getVKFromText16(textChars[p_off..][0..p_len]);
        const secondary_vk = getVKFromText16(textChars[s_off..][0..s_len]);
        const mod_mask = if (mode == 2 or mode == 3) parsed_send.mod_mask else parseModifierMaskText16(mod_text);
        const context_parts = runtimeContextPartCount(textChars[context_off..][0..context_len]);
        if (!ensureRuntimeComboCapacity(g_runtimeCombosLen + context_parts) or
            !ensureRuntimeInstantComboCapacity(g_runtimeInstantCombosLen + context_parts) or
            !ensureRuntimeCallbackSuspendExemptFor(callback_id, suspend_exempt))
        {
            truncateRuntimeCombosToPublished();
            return 0;
        }
        var contexts = RuntimeContextListIterator{ .raw = textChars[context_off..][0..context_len] };
        var row_loaded = false;
        while (contexts.next()) |context_text| {
            const context = parseRuntimeContextSpec(context_text);
            if (appendRuntimeCombo(.{
                .primaryVK = primary_vk,
                .secondaryVK = secondary_vk,
                .callbackId = callback_id,
                .targetVK = target_vk,
                .modMask = mod_mask,
                .mode = mode,
                .contextKind = context.kind,
                .contextNegated = context.negated,
                .suspendExempt = suspend_exempt,
            }, context.text)) row_loaded = true;
        }
        if (row_loaded) loaded += 1;
    }
    finishRuntimeComboSetup();
    return loaded;
}
fn comboBuildRowFromCells(cells: []const RuntimeHotkeyCell, payload_base: usize) ?struct {
    primary_vk: i32,
    secondary_vk: i32,
    context_text: []const u16,
    callback_id: i32,
    target_vk: i32,
    mod_mask: u16,
    mode: u8,
    suspend_exempt: bool,
} {
    if (cells.len < 3 or cells[0].tag != HOTKEY_CELL_TEXT or cells[1].tag != HOTKEY_CELL_TEXT) return null;
    const primary_vk = getVKFromText16(cells[0].text);
    const secondary_vk = getVKFromText16(cells[1].text);
    if (primary_vk == 0 or secondary_vk == 0) return null;

    var index: usize = 2;
    var context_text: []const u16 = &[_]u16{};
    var mode_text: []const u16 = &[_]u16{};
    var mod_text: []const u16 = &[_]u16{};
    var action_cell: RuntimeHotkeyCell = .{};
    var suspend_exempt = false;
    for (cells) |cell| suspend_exempt = suspend_exempt or ((cell.flags & 1) != 0);

    if (index + 1 < cells.len and cells[index].tag == HOTKEY_CELL_TEXT and chordCellIsAction(cells[index + 1])) {
        context_text = cells[index].text;
        index += 1;
    }
    if (index >= cells.len or !chordCellIsAction(cells[index])) return null;
    action_cell = cells[index];
    index += 1;

    if (index < cells.len and chordCellLooksBool(cells[index]) and index + 1 == cells.len) {
        suspend_exempt = suspend_exempt or runtimeHotkeyBoolCell(cells[index]);
        index += 1;
    }
    if (index < cells.len and cells[index].tag == HOTKEY_CELL_TEXT) {
        mode_text = cells[index].text;
        index += 1;
    }
    if (index < cells.len and cells[index].tag == HOTKEY_CELL_TEXT) {
        mod_text = cells[index].text;
        index += 1;
    }
    if (index < cells.len) suspend_exempt = suspend_exempt or runtimeHotkeyBoolCell(cells[index]);

    const mode = parseComboModeText16(mode_text);
    if (mode == 255) return null;
    const callback_id = switch (action_cell.tag) {
        HOTKEY_CELL_CALLBACK => action_cell.callbackId,
        HOTKEY_CELL_TEXT => if (mode == 2 or mode == 3) NATIVE_PAYLOAD_ID_BASE - @as(i32, @intCast(payload_base + action_cell.textOffset)) else -1,
        else => -1,
    };
    const parsed_send = if (comboModeRequiresSendDirectSpec(mode_text))
        parseSendKeyDirectInternalTarget(action_cell.text, mod_text) orelse return null
    else
        parseLegacyInternalTarget(action_cell.text, mod_text);
    const target_vk = if ((mode == 2 or mode == 3) and action_cell.tag == HOTKEY_CELL_TEXT) parsed_send.target_vk else 0;
    const mod_mask = if ((mode == 2 or mode == 3) and action_cell.tag == HOTKEY_CELL_TEXT) parsed_send.mod_mask else parseModifierMaskText16(mod_text);
    if ((mode == 0 or mode == 1) and callback_id < 0) return null;
    if ((mode == 2 or mode == 3) and target_vk == 0) return null;
    return .{
        .primary_vk = primary_vk,
        .secondary_vk = secondary_vk,
        .context_text = context_text,
        .callback_id = callback_id,
        .target_vk = target_vk,
        .mod_mask = mod_mask,
        .mode = mode,
        .suspend_exempt = suspend_exempt,
    };
}

/// Typed-cell combo entries. The cell envelope is shared, but the combo grammar
/// stays family-specific: primary, secondary, optional context, action, mode,
/// mod, suspend flag.
/// Record layout (116 bytes): cellCount:u8 at 0; seven 16-byte cells at 4.
export fn QMK_SetupComboCellEntries(records: [*]const u8, count: u32, textChars: [*]const u16, textCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeComboFamily();
    if (!ensureRuntimeComboCapacity(g_runtimeCombosLen + @as(usize, @intCast(count)))) return 0;
    if (!ensureRuntimeInstantComboCapacity(g_runtimeInstantCombosLen + @as(usize, @intCast(count)))) return 0;
    const payload_base = if (textCharsLen == 0) g_nativeHotkeyPayloads.len else appendNativeHotkeyPayloads(textChars, textCharsLen);
    if (payload_base == NATIVE_PAYLOAD_APPEND_FAILED) return 0;
    if (textCharsLen != 0 and g_nativeHotkeyPayloads.len != 0) initNativePasteThread();
    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 116;
        const raw_cell_count = records[off];
        if (raw_cell_count < 3) continue;
        const cell_count: usize = @min(@as(usize, @intCast(raw_cell_count)), 7);
        var cells = [_]RuntimeHotkeyCell{.{}} ** 7;
        var c: usize = 0;
        var valid = true;
        while (c < cell_count) : (c += 1) {
            cells[c] = readRuntimeHotkeyCell(records, off, c, textChars, textCharsLen) orelse {
                valid = false;
                break;
            };
        }
        if (!valid) continue;
        const parsed = comboBuildRowFromCells(cells[0..cell_count], payload_base) orelse continue;
        const context_parts = runtimeContextPartCount(parsed.context_text);
        if (!ensureRuntimeComboCapacity(g_runtimeCombosLen + context_parts) or
            !ensureRuntimeInstantComboCapacity(g_runtimeInstantCombosLen + context_parts) or
            !ensureRuntimeCallbackSuspendExemptFor(parsed.callback_id, parsed.suspend_exempt))
        {
            truncateRuntimeCombosToPublished();
            return 0;
        }
        var contexts = RuntimeContextListIterator{ .raw = parsed.context_text };
        var row_loaded = false;
        while (contexts.next()) |context_text| {
            const context = parseRuntimeContextSpec(context_text);
            if (appendRuntimeCombo(.{
                .primaryVK = parsed.primary_vk,
                .secondaryVK = parsed.secondary_vk,
                .callbackId = parsed.callback_id,
                .targetVK = parsed.target_vk,
                .modMask = parsed.mod_mask,
                .mode = parsed.mode,
                .contextKind = context.kind,
                .contextNegated = context.negated,
                .suspendExempt = parsed.suspend_exempt,
            }, context.text)) row_loaded = true;
        }
        if (row_loaded) loaded += 1;
    }
    finishRuntimeComboSetup();
    return loaded;
}
fn runtimeHotkeyDuplicate(
    vk: i32, mods_required: u16, mods_forbidden: u16, trigger_kind: u8,
    callback_id: i32, hold_callback_id: i32, cleanup_callback_id: i32, threshold_ticks: i64,
    action_kind: u8, suspend_exempt: bool,
    context_kind: u8, context_negated: bool, context_text: []const u16,
    physical_mod_vk: u8, physical_mods_required: u8, physical_mods_forbidden: u8,
) bool {
    var i: usize = 0;
    while (i < g_runtimeHotkeysLen) : (i += 1) {
        const row = g_runtimeHotkeys[i];
        if (row.triggerVK != vk or row.modsRequired != mods_required or row.modsForbidden != mods_forbidden or
            row.triggerKind != trigger_kind or row.actionKind != action_kind or row.contextKind != context_kind or row.contextNegated != context_negated or
            row.callbackId != callback_id or row.suspendExempt != suspend_exempt or
            row.holdCallbackId != hold_callback_id or row.cleanupCallbackId != cleanup_callback_id or row.thresholdTicks != threshold_ticks or
            row.physicalModVK != physical_mod_vk or row.physicalModsRequired != physical_mods_required or
            row.physicalModsForbidden != physical_mods_forbidden) continue;
        if (runtimeContextTextEqual(runtimeContextText(i), context_text)) return true;
    }
    return false;
}

fn ensureRuntimeHotkeyCapacity(required: usize) bool {
    if (required <= g_runtimeHotkeysCap) return true;
    var new_cap: usize = if (g_runtimeHotkeysCap == 0) RUNTIME_HOTKEY_INITIAL_CAP else g_runtimeHotkeysCap * 2;
    while (new_cap < required) : (new_cap *= 2) {}
    return resizeRuntimeHotkeyCapacity(new_cap);
}

fn resizeRuntimeHotkeyCapacity(new_cap: usize) bool {
    if (new_cap <= g_runtimeHotkeysCap) return true;

    const new_rows = gAlloc.alloc(RuntimeHotkey, new_cap) catch return false;
    const new_contexts = gAlloc.alloc(RuntimeHotkeyText, new_cap) catch {
        gAlloc.free(new_rows);
        return false;
    };
    const new_title_matched = gAlloc.alloc(bool, new_cap) catch {
        gAlloc.free(new_rows);
        gAlloc.free(new_contexts);
        return false;
    };
    const new_website_matched = gAlloc.alloc(bool, new_cap) catch {
        gAlloc.free(new_rows);
        gAlloc.free(new_contexts);
        gAlloc.free(new_title_matched);
        return false;
    };
    const new_ac_fallback = gAlloc.alloc(bool, new_cap) catch {
        gAlloc.free(new_rows);
        gAlloc.free(new_contexts);
        gAlloc.free(new_title_matched);
        gAlloc.free(new_website_matched);
        return false;
    };

    if (g_runtimeHotkeysLen != 0) {
        @memcpy(new_rows[0..g_runtimeHotkeysLen], g_runtimeHotkeys[0..g_runtimeHotkeysLen]);
        @memcpy(new_contexts[0..g_runtimeHotkeysLen], g_runtimeHotkeyContexts[0..g_runtimeHotkeysLen]);
    }
    if (new_cap > g_runtimeHotkeysLen) {
        @memset(new_rows[g_runtimeHotkeysLen..new_cap], RuntimeHotkey{});
        @memset(new_contexts[g_runtimeHotkeysLen..new_cap], [_]u16{0} ** RUNTIME_HOTKEY_CONTEXT_CHARS);
    }
    @memset(new_title_matched, false);
    @memset(new_website_matched, false);
    @memset(new_ac_fallback, false);
    const old_rows = g_runtimeHotkeys;
    const old_contexts = g_runtimeHotkeyContexts;
    const old_title_matched = g_runtimeTitleMatched;
    const old_website_matched = g_runtimeWebsiteMatched;
    const old_ac_fallback = g_runtimeAcFallback;
    g_runtimeHotkeys = new_rows;
    g_runtimeHotkeyContexts = new_contexts;
    g_runtimeTitleMatched = new_title_matched;
    g_runtimeWebsiteMatched = new_website_matched;
    g_runtimeAcFallback = new_ac_fallback;
    g_runtimeHotkeysCap = new_cap;
    retireSlice(RuntimeHotkey, old_rows);
    retireSlice(RuntimeHotkeyText, old_contexts);
    retireSlice(bool, old_title_matched);
    retireSlice(bool, old_website_matched);
    retireSlice(bool, old_ac_fallback);
    return true;
}

fn ensureRuntimeHotkeyExactAdditionalCapacity(additional: usize) bool {
    if (additional == 0) return true;
    const required = g_runtimeHotkeysLen + additional;
    if (required <= g_runtimeHotkeysCap) return true;
    return ensureRuntimeHotkeyCapacity(required);
}

fn clearRuntimeHotkeyReadyIndex(index: *RuntimeHotkeyReadyIndex) void {
    for (&index.ranges) |*row| @memset(row, RuntimeHotkeyRange{});
    @memset(&index.activeGate, false);
    if (index.sourceIndexes.len != 0) @memset(index.sourceIndexes, 0);
}

fn ensureRuntimeHotkeyReadyIndexCapacity(index: *RuntimeHotkeyReadyIndex, required: usize) bool {
    if (required <= index.sourceIndexes.len) return true;
    const new_len = if (required == 0) 1 else required;
    const new_indexes = gAlloc.alloc(u32, new_len) catch return false;
    @memset(new_indexes, 0);
    const old_indexes = index.sourceIndexes;
    index.sourceIndexes = new_indexes;
    retireSlice(u32, old_indexes);
    return true;
}

fn ensureRuntimeAcOutputCapacity(ac: *RuntimeAcIndex, required: usize) bool {
    if (required <= ac.outputHotkey.len and required <= ac.nextOutput.len) return true;
    if (required > 0xFFFFFFFE) return false;
    var new_len: usize = if (ac.outputHotkey.len == 0) @max(RUNTIME_AC_EDGE_INITIAL_CAP, required) else ac.outputHotkey.len * 2;
    while (new_len < required) : (new_len *= 2) {}
    const new_output = gAlloc.alloc(u32, new_len) catch return false;
    const new_next = gAlloc.alloc(u32, new_len) catch {
        gAlloc.free(new_output);
        return false;
    };
    const used: usize = @min(@as(usize, @intCast(ac.outputCount)), ac.outputHotkey.len);
    if (used != 0) {
        @memcpy(new_output[0..used], ac.outputHotkey[0..used]);
        @memcpy(new_next[0..used], ac.nextOutput[0..used]);
    }
    if (new_len > used) {
        @memset(new_output[used..new_len], 0);
        @memset(new_next[used..new_len], RUNTIME_AC_NONE_U32);
    }
    const old_output = ac.outputHotkey;
    const old_next = ac.nextOutput;
    ac.outputHotkey = new_output;
    ac.nextOutput = new_next;
    retireSlice(u32, old_output);
    retireSlice(u32, old_next);
    return true;
}

fn ensureRuntimeAcNodeCapacity(ac: *RuntimeAcIndex, required: usize) bool {
    if (required <= ac.firstEdge.len and required <= ac.failure.len and required <= ac.outputLink.len and required <= ac.firstOutput.len) return true;
    if (required > 0xFFFFFFFE) return false;
    var new_cap: usize = if (ac.firstEdge.len == 0) RUNTIME_AC_NODE_INITIAL_CAP else ac.firstEdge.len * 2;
    while (new_cap < required) : (new_cap *= 2) {}

    const new_first_edge = gAlloc.alloc(u32, new_cap) catch return false;
    const new_failure = gAlloc.alloc(u32, new_cap) catch {
        gAlloc.free(new_first_edge);
        return false;
    };
    const new_output_link = gAlloc.alloc(u32, new_cap) catch {
        gAlloc.free(new_first_edge);
        gAlloc.free(new_failure);
        return false;
    };
    const new_first_output = gAlloc.alloc(u32, new_cap) catch {
        gAlloc.free(new_first_edge);
        gAlloc.free(new_failure);
        gAlloc.free(new_output_link);
        return false;
    };

    const used: usize = @min(@as(usize, @intCast(ac.nodeCount)), ac.firstEdge.len);
    if (used != 0) {
        @memcpy(new_first_edge[0..used], ac.firstEdge[0..used]);
        @memcpy(new_failure[0..used], ac.failure[0..used]);
        @memcpy(new_output_link[0..used], ac.outputLink[0..used]);
        @memcpy(new_first_output[0..used], ac.firstOutput[0..used]);
    }
    if (new_cap > used) {
        @memset(new_first_edge[used..new_cap], RUNTIME_AC_NONE_U32);
        @memset(new_failure[used..new_cap], 0);
        @memset(new_output_link[used..new_cap], RUNTIME_AC_NONE_U32);
        @memset(new_first_output[used..new_cap], RUNTIME_AC_NONE_U32);
    }

    const old_first_edge = ac.firstEdge;
    const old_failure = ac.failure;
    const old_output_link = ac.outputLink;
    const old_first_output = ac.firstOutput;
    ac.firstEdge = new_first_edge;
    ac.failure = new_failure;
    ac.outputLink = new_output_link;
    ac.firstOutput = new_first_output;
    retireSlice(u32, old_first_edge);
    retireSlice(u32, old_failure);
    retireSlice(u32, old_output_link);
    retireSlice(u32, old_first_output);
    return true;
}

fn ensureRuntimeAcEdgeCapacity(ac: *RuntimeAcIndex, required: usize) bool {
    if (required <= ac.edgeChar.len and required <= ac.edgeNode.len and required <= ac.nextEdge.len) return true;
    if (required > 0xFFFFFFFE) return false;
    var new_cap: usize = if (ac.edgeChar.len == 0) RUNTIME_AC_EDGE_INITIAL_CAP else ac.edgeChar.len * 2;
    while (new_cap < required) : (new_cap *= 2) {}

    const new_char = gAlloc.alloc(u16, new_cap) catch return false;
    const new_node = gAlloc.alloc(u32, new_cap) catch {
        gAlloc.free(new_char);
        return false;
    };
    const new_next = gAlloc.alloc(u32, new_cap) catch {
        gAlloc.free(new_char);
        gAlloc.free(new_node);
        return false;
    };

    const used: usize = @min(@as(usize, @intCast(ac.edgeCount)), ac.edgeChar.len);
    if (used != 0) {
        @memcpy(new_char[0..used], ac.edgeChar[0..used]);
        @memcpy(new_node[0..used], ac.edgeNode[0..used]);
        @memcpy(new_next[0..used], ac.nextEdge[0..used]);
    }
    if (new_cap > used) {
        @memset(new_char[used..new_cap], 0);
        @memset(new_node[used..new_cap], 0);
        @memset(new_next[used..new_cap], RUNTIME_AC_NONE_U32);
    }

    const old_char = ac.edgeChar;
    const old_node = ac.edgeNode;
    const old_next = ac.nextEdge;
    ac.edgeChar = new_char;
    ac.edgeNode = new_node;
    ac.nextEdge = new_next;
    retireSlice(u16, old_char);
    retireSlice(u32, old_node);
    retireSlice(u32, old_next);
    return true;
}

fn ensureRuntimeAcQueueCapacity(required: usize) bool {
    if (required <= g_runtimeAcQueue.len) return true;
    if (required > 0xFFFFFFFE) return false;
    var new_cap: usize = if (g_runtimeAcQueue.len == 0) RUNTIME_AC_NODE_INITIAL_CAP else g_runtimeAcQueue.len * 2;
    while (new_cap < required) : (new_cap *= 2) {}
    const new_queue = gAlloc.alloc(u32, new_cap) catch return false;
    @memset(new_queue, 0);
    const old_queue = g_runtimeAcQueue;
    g_runtimeAcQueue = new_queue;
    retireSlice(u32, old_queue);
    return true;
}

fn appendRuntimeHotkey(
    vk: i32,
    mods_required: u16,
    mods_forbidden: u16,
    callback_id: i32,
    hold_callback_id: i32,
    cleanup_callback_id: i32,
    threshold_ms: i32,
    trigger_kind: u8,
    action_kind: u8,
    requested_suppress: bool,
    context_kind: u8,
    context_negated: bool,
    context_text: []const u16,
    option_bits: u32,
    physical_mod_vk: u8,
    physical_mods_required: u8,
    physical_mods_forbidden: u8,
) bool {
    if (vk <= 0 or vk >= VK_COUNT) return false;
    if (@as(usize, physical_mod_vk) >= VK_COUNT) return false;
    if (!ensureRuntimeHotkeyCapacity(g_runtimeHotkeysLen + 1)) return false;
    const suspend_exempt = runtimeHotkeySuspendExemptFromOptions(option_bits);
    if (!ensureRuntimeCallbackSuspendExemptFor3(callback_id, hold_callback_id, cleanup_callback_id, suspend_exempt)) return false;
    const threshold_ticks = if (threshold_ms > 0) msToTicksInt(threshold_ms) else 0;
    if (runtimeHotkeyDuplicate(
        vk, mods_required, mods_forbidden, trigger_kind, callback_id, hold_callback_id, cleanup_callback_id, threshold_ticks,
        action_kind, suspend_exempt,
        context_kind, context_negated, context_text, physical_mod_vk, physical_mods_required, physical_mods_forbidden,
    )) return false;
    const slot = g_runtimeHotkeysLen;
    if (context_text.len >= RUNTIME_HOTKEY_CONTEXT_CHARS) return false;
    const context_len: usize = context_text.len;
    @memset(&g_runtimeHotkeyContexts[slot], 0);
    if (context_len != 0) @memcpy(g_runtimeHotkeyContexts[slot][0..context_len], context_text[0..context_len]);
    g_runtimeHotkeys[slot] = .{
        .triggerVK = vk,
        .modsRequired = mods_required,
        .modsForbidden = mods_forbidden,
        .callbackId = callback_id,
        .holdCallbackId = hold_callback_id,
        .cleanupCallbackId = cleanup_callback_id,
        .thresholdTicks = threshold_ticks,
        .triggerKind = trigger_kind,
        .actionKind = action_kind,
        .suppressOriginal = runtimeHotkeyDefaultSuppressOriginal(vk, mods_required, physical_mod_vk, requested_suppress),
        .contextKind = context_kind,
        .contextNegated = context_negated,
        .contextLen = @intCast(context_len),
        .specificityMask = runtimeHotkeySpecificityMask(context_kind, g_runtimeHotkeyContexts[slot][0..context_len]),
        .physicalModVK = physical_mod_vk,
        .physicalModsRequired = physical_mods_required,
        .physicalModsForbidden = physical_mods_forbidden,
        .suspendExempt = suspend_exempt,
    };
    _ = markRuntimeCallbackSuspendExempt(callback_id, suspend_exempt);
    _ = markRuntimeCallbackSuspendExempt(hold_callback_id, suspend_exempt);
    _ = markRuntimeCallbackSuspendExempt(cleanup_callback_id, suspend_exempt);
    g_runtimeHotkeyGate[@intCast(vk)] = true;
    if (g_runtimeHotkeys[slot].specificityMask != 0)
        g_runtimeContextHotkeyGate[@intCast(vk)] = true;
    g_runtimeHotkeyDependencyMask |= g_runtimeHotkeys[slot].specificityMask;
    g_runtimeHotkeysLen += 1;
    return true;
}

export fn QMK_SetupHotkeys(
    records: [*]const u8,
    count: u32,
    contextChars: [*]const u16,
    contextCharsLen: u32,
    payloadChars: [*]const u16,
    payloadCharsLen: u32,
) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeHotkeyFamily();
    if (!ensureRuntimeHotkeyExactAdditionalCapacity(count)) return 0;
    const payload_base = if (payloadCharsLen == 0) g_nativeHotkeyPayloads.len else appendNativeHotkeyPayloads(payloadChars, payloadCharsLen);
    if (payload_base == NATIVE_PAYLOAD_APPEND_FAILED) return 0;
    if (payloadCharsLen != 0 and g_nativeHotkeyPayloads.len != 0) initNativePasteThread();

    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 32;
        const vk = readI32LE(records, off);
        if (vk <= 0 or vk >= VK_COUNT) continue;
        const context_off = readU32LE(records, off + 16);
        const raw_context_len = readU16LE(records, off + 20);
        if (context_off > contextCharsLen) continue;
        if (@as(u32, raw_context_len) > contextCharsLen - context_off) continue;

        const context_len: usize = @intCast(raw_context_len);
        if (context_len >= RUNTIME_HOTKEY_CONTEXT_CHARS) continue;
        const start: usize = @intCast(context_off);
        const raw_callback_id = rebaseNativePayloadId(readI32LE(records, off + 8), payload_base);
        if (!ensureRuntimeCallbackSuspendExemptFor3(raw_callback_id, -1, -1, runtimeHotkeySuspendExemptFromOptions(readU32LE(records, off + 24)))) {
            truncateRuntimeHotkeysToPublished();
            return 0;
        }
        if (appendRuntimeHotkey(
            vk,
            readU16LE(records, off + 4),
            readU16LE(records, off + 6),
            raw_callback_id,
            -1,
            -1,
            0,
            records[off + 12],
            0,
            records[off + 13] != 0,
            records[off + 14],
            records[off + 15] != 0,
            contextChars[start..][0..context_len],
            readU32LE(records, off + 24),
            records[off + 28],
            records[off + 29],
            records[off + 30],
        )) loaded += 1;
    }
    finishRuntimeHotkeySetup(loaded);
    return loaded;
}

const ParsedRuntimeHotkeySpec = struct {
    vk: i32 = 0,
    modsRequired: u16 = 0,
    modsForbidden: u16 = 0,
    triggerKind: u8 = 0,
    suppressOriginal: bool = true,
    allowExtraMods: bool = false,
    forceHook: bool = false,
    physicalModVK: u8 = 0,
    physicalModsRequired: u8 = 0,
    physicalModsForbidden: u8 = 0,
};

fn stripHotkeyBraces(spec: []const u16) []const u16 {
    const s = trimSpaces16(spec);
    if (s.len >= 2 and s[0] == '{' and s[s.len - 1] == '}') return trimSpaces16(s[1 .. s.len - 1]);
    return s;
}

fn endsWithAsciiIgnoreCase16(text: []const u16, comptime suffix: []const u8) bool {
    if (text.len < suffix.len) return false;
    return equalsAsciiIgnoreCase16(text[text.len - suffix.len ..], suffix);
}

fn parsePhysicalPrefixKeyText16(prefix_spec: []const u16) i32 {
    var spec = stripHotkeyBraces(prefix_spec);
    while (spec.len != 0) {
        switch (spec[0]) {
            '~', '$', '*' => spec = trimSpaces16(spec[1..]),
            else => break,
        }
    }
    if (endsWithAsciiIgnoreCase16(spec, " up")) return 0;
    return getVKFromText16(spec);
}

fn hotkeyOptionBitsFromParsed(parsed: ParsedRuntimeHotkeySpec, suspend_exempt: bool) u32 {
    var bits: u32 = 1;
    if (parsed.allowExtraMods) bits |= 1 << 1;
    if (!parsed.suppressOriginal) bits |= 1 << 2;
    if (parsed.forceHook) bits |= 1 << 3;
    if (parsed.triggerKind == 1) bits |= 1 << 4;
    if (suspend_exempt) bits |= 1 << 5;
    return bits;
}

fn parseRuntimeHotkeySpecText16(raw_spec: []const u16) ?ParsedRuntimeHotkeySpec {
    var spec = stripHotkeyBraces(raw_spec);
    if (spec.len == 0) return null;

    if (containsChar16(spec, '&')) {
        var last_amp: usize = 0;
        var i: usize = 0;
        while (i < spec.len) : (i += 1) {
            if (spec[i] == '&') last_amp = i;
        }
        if (last_amp == 0 or last_amp + 1 >= spec.len) return null;
        var suffix = parseRuntimeHotkeySpecText16(spec[last_amp + 1 ..]) orelse return null;
        var physical_required: u8 = 0;
        var neutral_required: u16 = 0;
        var first_physical_vk: u8 = 0;
        var start: usize = 0;
        while (start < last_amp) {
            var end = start;
            while (end < last_amp and spec[end] != '&') : (end += 1) {}
            const physical_vk = parsePhysicalPrefixKeyText16(spec[start..end]);
            if (physical_vk <= 0 or physical_vk >= VK_COUNT) return null;
            if (first_physical_vk == 0) first_physical_vk = @intCast(physical_vk);
            const lr_bit = physicalModifierLRBitForVK(physical_vk);
            // AHK custom hotkeys allow any valid keyboard key as the prefix.
            // Modifier prefixes additionally contribute their left/right and
            // collapsed modifier masks; ordinary key prefixes are represented
            // by physicalModVK and checked through physical key state.
            physical_required |= lr_bit;
            neutral_required |= getCollapsedPhysicalModBit(physical_vk);
            start = end + 1;
        }
        suffix.physicalModVK = first_physical_vk;
        suffix.physicalModsRequired = physical_required;
        suffix.modsRequired |= neutral_required;
        if (!suffix.allowExtraMods) suffix.modsForbidden = 0x0F & ~(suffix.modsRequired | getCollapsedPhysicalModBit(suffix.vk));
        suffix.physicalModsForbidden = if (suffix.allowExtraMods) 0 else @as(u8, 0xFF) & ~(physical_required | physicalModifierLRBitForVK(suffix.vk));
        return suffix;
    }

    var suppress = true;
    var force_hook = false;
    var allow_extra_mods = false;
    while (spec.len != 0) {
        switch (spec[0]) {
            '~' => suppress = false,
            '$' => force_hook = true,
            '*' => allow_extra_mods = true,
            else => break,
        }
        spec = trimSpaces16(spec[1..]);
    }

    var trigger_kind: u8 = 0;
    if (endsWithAsciiIgnoreCase16(spec, " up")) {
        trigger_kind = 1;
        spec = trimSpaces16(spec[0 .. spec.len - 3]);
    }
    if (spec.len == 0 or containsAsciiIgnoreCase16(spec, "Wheel") or containsAsciiIgnoreCase16(spec, "Button")) return null;

    var mods: u16 = 0;
    var pos: usize = 0;
    while (pos < spec.len) : (pos += 1) {
        switch (spec[pos]) {
            '^' => mods |= 0x01,
            '!' => mods |= 0x02,
            '+' => mods |= 0x04,
            '#' => mods |= 0x08,
            else => break,
        }
    }
    const key_text = trimSpaces16(spec[pos..]);
    const vk = getVKFromText16(key_text);
    if (vk == 0) return null;
    const trigger_mod_bit = getCollapsedPhysicalModBit(vk);
    return .{
        .vk = vk,
        .modsRequired = mods,
        .modsForbidden = if (allow_extra_mods) 0 else 0x0F & ~(mods | trigger_mod_bit),
        .triggerKind = trigger_kind,
        .suppressOriginal = suppress,
        .allowExtraMods = allow_extra_mods,
        .forceHook = force_hook,
    };
}

const HOTKEY_CELL_TEXT: u8 = 1;
const HOTKEY_CELL_CALLBACK: u8 = 2;
const HOTKEY_CELL_TAP_CALLBACK: u8 = 3;
const HOTKEY_CELL_TAP_TEXT: u8 = 4;

const RuntimeHotkeyCell = struct {
    tag: u8 = 0,
    flags: u8 = 0,
    textOffset: usize = 0,
    text: []const u16 = &[_]u16{},
    callbackId: i32 = -1,
};

const RuntimeHotkeyActionCell = struct {
    callbackId: i32 = -1,
    actionKind: u8 = 0,
};

inline fn runtimeHotkeyCellIsAction(cell: RuntimeHotkeyCell) bool {
    return cell.tag == HOTKEY_CELL_CALLBACK or cell.tag == HOTKEY_CELL_TAP_CALLBACK or
        cell.tag == HOTKEY_CELL_TEXT or cell.tag == HOTKEY_CELL_TAP_TEXT;
}

inline fn runtimeHotkeyCellIsCallbackAction(cell: RuntimeHotkeyCell) bool {
    return cell.tag == HOTKEY_CELL_CALLBACK or cell.tag == HOTKEY_CELL_TAP_CALLBACK;
}

inline fn runtimeHotkeyCellIsPlainCallback(cell: RuntimeHotkeyCell) bool {
    return cell.tag == HOTKEY_CELL_CALLBACK;
}

inline fn runtimeHotkeyCellIsExplicitBool(cell: RuntimeHotkeyCell) bool {
    return (cell.flags & 2) != 0;
}

fn runtimeHotkeyBoolCell(cell: RuntimeHotkeyCell) bool {
    if (runtimeHotkeyCellIsExplicitBool(cell)) return (cell.flags & 4) != 0;
    if ((cell.flags & 1) != 0) return true;
    if (cell.tag != HOTKEY_CELL_TEXT) return false;
    const text = trimSpaces16(cell.text);
    if (text.len == 0) return false;
    if (text.len == 1 and text[0] == '1') return true;
    return equalsAsciiIgnoreCase16(text, "true") or
        equalsAsciiIgnoreCase16(text, "yes") or
        equalsAsciiIgnoreCase16(text, "on");
}

fn runtimeHotkeyActionFromCell(cell: RuntimeHotkeyCell, payload_base: usize) ?RuntimeHotkeyActionCell {
    return switch (cell.tag) {
        HOTKEY_CELL_CALLBACK => if (cell.callbackId >= 0)
            .{ .callbackId = cell.callbackId, .actionKind = 0 }
        else
            null,
        HOTKEY_CELL_TAP_CALLBACK => if (cell.callbackId >= 0)
            .{ .callbackId = cell.callbackId, .actionKind = 1 }
        else
            null,
        HOTKEY_CELL_TEXT => .{
            .callbackId = NATIVE_PAYLOAD_ID_BASE - @as(i32, @intCast(payload_base + cell.textOffset)),
            .actionKind = 0,
        },
        HOTKEY_CELL_TAP_TEXT => .{
            .callbackId = NATIVE_PAYLOAD_ID_BASE - @as(i32, @intCast(payload_base + cell.textOffset)),
            .actionKind = 1,
        },
        else => null,
    };
}

fn hotkeyEntriesNeedNativePayload(records: [*]const u8, count: u32) bool {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (records[i * 44 + 29] != 0) return true;
    }
    return false;
}

fn readRuntimeHotkeyCell(records: [*]const u8, record_off: usize, cell_index: usize, textChars: [*]const u16, textCharsLen: u32) ?RuntimeHotkeyCell {
    const cell_off = record_off + 4 + cell_index * 16;
    const tag = records[cell_off];
    if (tag == 0) return null;
    const text_offset: usize = @intCast(readU32LE(records, cell_off + 4));
    var text_len: usize = @intCast(readU16LE(records, cell_off + 8));
    if (text_offset > textCharsLen) return null;
    const remaining: usize = @intCast(textCharsLen - @as(u32, @intCast(text_offset)));
    if (text_len > remaining) text_len = remaining;
    return .{
        .tag = tag,
        .flags = records[cell_off + 1],
        .textOffset = text_offset,
        .text = textChars[text_offset..][0..text_len],
        .callbackId = readI32LE(records, cell_off + 12),
    };
}

/// Compatibility hotkey entries. AHK sends spec/context/action strings and a
/// callback id; Zig parses the hotkey spec, context, native payload id, and
/// suspend behavior.
/// Record layout (44 bytes): spec at 0; context at 8; action at 16;
/// callbackId:i32 at 24; suspendExempt:u8 at 28; nativePayload:u8 at 29;
/// actionKind:u8 at 30; holdCallbackId:i32 at 32; cleanupCallbackId:i32 at 36;
/// thresholdMs:i32 at 40.
export fn QMK_SetupHotkeyEntries(records: [*]const u8, count: u32, textChars: [*]const u16, textCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeHotkeyFamily();
    if (!ensureRuntimeHotkeyExactAdditionalCapacity(count)) return 0;
    const needs_native_payload = hotkeyEntriesNeedNativePayload(records, count);
    const payload_base = if (!needs_native_payload or textCharsLen == 0) g_nativeHotkeyPayloads.len else appendNativeHotkeyPayloads(textChars, textCharsLen);
    if (payload_base == NATIVE_PAYLOAD_APPEND_FAILED) return 0;
    if (needs_native_payload and textCharsLen != 0 and g_nativeHotkeyPayloads.len != 0) initNativePasteThread();

    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 44;
        const spec_off: usize = @intCast(readU32LE(records, off));
        var spec_len: usize = @intCast(readU16LE(records, off + 4));
        const context_off: usize = @intCast(readU32LE(records, off + 8));
        var context_len: usize = @intCast(readU16LE(records, off + 12));
        const action_off: usize = @intCast(readU32LE(records, off + 16));
        const action_len: usize = @intCast(readU16LE(records, off + 20));
        const raw_callback_id = readI32LE(records, off + 24);
        const suspend_exempt = records[off + 28] != 0;
        const native_payload = records[off + 29] != 0;
        const action_kind = records[off + 30];
        const hold_callback_id = readI32LE(records, off + 32);
        const cleanup_callback_id = readI32LE(records, off + 36);
        const threshold_ms = readI32LE(records, off + 40);
        if (spec_off > textCharsLen or context_off > textCharsLen or action_off > textCharsLen) continue;
        const spec_rem: usize = @intCast(textCharsLen - @as(u32, @intCast(spec_off)));
        const context_rem: usize = @intCast(textCharsLen - @as(u32, @intCast(context_off)));
        const action_rem: usize = @intCast(textCharsLen - @as(u32, @intCast(action_off)));
        if (spec_len > spec_rem) spec_len = spec_rem;
        if (context_len > context_rem) context_len = context_rem;
        if (action_len > action_rem) continue;
        if (native_payload and action_len >= action_rem) continue;

        const parsed = parseRuntimeHotkeySpecText16(textChars[spec_off..][0..spec_len]) orelse continue;
        const callback_id = if (native_payload)
            NATIVE_PAYLOAD_ID_BASE - @as(i32, @intCast(payload_base + action_off))
        else
            raw_callback_id;
        if (!native_payload and callback_id < 0) continue;
        const context_parts = runtimeContextPartCount(textChars[context_off..][0..context_len]);
        if (!ensureRuntimeHotkeyExactAdditionalCapacity(context_parts) or
            !ensureRuntimeCallbackSuspendExemptFor3(callback_id, hold_callback_id, cleanup_callback_id, suspend_exempt))
        {
            truncateRuntimeHotkeysToPublished();
            return 0;
        }
        var contexts = RuntimeContextListIterator{ .raw = textChars[context_off..][0..context_len] };
        var row_loaded = false;
        while (contexts.next()) |context_part| {
            const context = parseRuntimeContextSpec(context_part);
            if (appendRuntimeHotkey(
                parsed.vk,
                parsed.modsRequired,
                parsed.modsForbidden,
                callback_id,
                hold_callback_id,
                cleanup_callback_id,
                threshold_ms,
                parsed.triggerKind,
                action_kind,
                parsed.suppressOriginal,
                context.kind,
                context.negated,
                context.text,
                hotkeyOptionBitsFromParsed(parsed, suspend_exempt),
                parsed.physicalModVK,
                parsed.physicalModsRequired,
                parsed.physicalModsForbidden,
            )) row_loaded = true;
        }
        if (row_loaded) loaded += 1;
    }
    finishRuntimeHotkeySetup(loaded);
    return loaded;
}

/// Typed-cell hotkey entries. AHK sends typed cells; Zig owns positional row
/// interpretation, hotkey spec parsing, context parsing, native payload ids, and
/// suspend behavior.
/// Record layout (68 bytes): cellCount:u8 at 0; four 16-byte cells at 4.
/// Cell layout: tag:u8, flags:u8, reserved:u16, textOffset:u32, textLen:u16,
/// reserved:u16, callbackId:i32.
export fn QMK_SetupHotkeyCellEntries(records: [*]const u8, count: u32, textChars: [*]const u16, textCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeHotkeyFamily();
    if (!ensureRuntimeHotkeyExactAdditionalCapacity(count)) return 0;
    const payload_base = if (textCharsLen == 0) g_nativeHotkeyPayloads.len else appendNativeHotkeyPayloads(textChars, textCharsLen);
    if (payload_base == NATIVE_PAYLOAD_APPEND_FAILED) return 0;
    if (textCharsLen != 0 and g_nativeHotkeyPayloads.len != 0) initNativePasteThread();

    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 68;
        const raw_cell_count = records[off];
        if (raw_cell_count < 2) continue;
        const cell_count: usize = @min(@as(usize, @intCast(raw_cell_count)), 4);
        var cells = [_]RuntimeHotkeyCell{.{}} ** 4;
        var c: usize = 0;
        var valid = true;
        var suspend_exempt = false;
        while (c < cell_count) : (c += 1) {
            cells[c] = readRuntimeHotkeyCell(records, off, c, textChars, textCharsLen) orelse {
                valid = false;
                break;
            };
            suspend_exempt = suspend_exempt or ((cells[c].flags & 1) != 0);
        }
        if (!valid or cells[0].tag != HOTKEY_CELL_TEXT) continue;

        var raw_context_text: []const u16 = &[_]u16{};
        var action_cell: RuntimeHotkeyCell = .{};
        if (cell_count == 2) {
            action_cell = cells[1];
        } else if (cell_count == 3 and runtimeHotkeyCellIsAction(cells[1]) and chordCellLooksBool(cells[2])) {
            action_cell = cells[1];
            suspend_exempt = suspend_exempt or runtimeHotkeyBoolCell(cells[2]);
        } else {
            if (cells[1].tag != HOTKEY_CELL_TEXT) continue;
            raw_context_text = cells[1].text;
            action_cell = cells[2];
            if (cell_count >= 4) suspend_exempt = suspend_exempt or runtimeHotkeyBoolCell(cells[3]);
        }
        if (!runtimeHotkeyCellIsAction(action_cell)) continue;

        const parsed = parseRuntimeHotkeySpecText16(cells[0].text) orelse continue;
        const action = runtimeHotkeyActionFromCell(action_cell, payload_base) orelse continue;
        const context_parts = runtimeContextPartCount(raw_context_text);
        if (!ensureRuntimeHotkeyExactAdditionalCapacity(context_parts) or
            !ensureRuntimeCallbackSuspendExemptFor(action.callbackId, suspend_exempt))
        {
            truncateRuntimeHotkeysToPublished();
            return 0;
        }
        var contexts = RuntimeContextListIterator{ .raw = raw_context_text };
        var row_loaded = false;
        while (contexts.next()) |context_part| {
            const context = parseRuntimeContextSpec(context_part);
            if (appendRuntimeHotkey(
                parsed.vk,
                parsed.modsRequired,
                parsed.modsForbidden,
                action.callbackId,
                -1,
                -1,
                0,
                parsed.triggerKind,
                action.actionKind,
                parsed.suppressOriginal,
                context.kind,
                context.negated,
                context.text,
                hotkeyOptionBitsFromParsed(parsed, suspend_exempt),
                parsed.physicalModVK,
                parsed.physicalModsRequired,
                parsed.physicalModsForbidden,
            )) row_loaded = true;
        }
        if (row_loaded) loaded += 1;
    }
    finishRuntimeHotkeySetup(loaded);
    return loaded;
}
export fn QMK_BeginBulkSetup() callconv(.c) void {
    if (g_bulkSetupDepth == 0) {
        acquireSetupPublishLock();
        g_bulkSetupSerial +%= 1;
    }
    g_bulkSetupDepth += 1;
}

export fn QMK_EndBulkSetup() callconv(.c) void {
    if (g_bulkSetupDepth == 0) return;
    g_bulkSetupDepth -= 1;
    if (g_bulkSetupDepth == 0) {
        defer releaseSetupPublishLock();
        requestRuntimePublish(RUNTIME_PUBLISH_SETUP);
    }
}

fn finishRuntimeHotkeySetup(loaded: i32) void {
    if (loaded <= 0) return;
    g_runtimeHotkeyContextsDirty = true;
    g_bulkRuntimeHotkeysDirty = true;
    g_bulkRuntimeKeyGateDirty = true;
    if (g_bulkSetupDepth == 0) requestRuntimePublish(RUNTIME_PUBLISH_SETUP);
}

fn truncateRuntimeHotkeysToPublished() void {
    if (g_runtimeHotkeysLen > g_runtimeHotkeysPublishedLen) {
        g_runtimeHotkeysLen = g_runtimeHotkeysPublishedLen;
        g_runtimeHotkeyContextsDirty = false;
        g_bulkRuntimeHotkeysDirty = false;
        g_bulkRuntimeKeyGateDirty = true;
        rebuildRuntimeDependencyMasksFromPublished();
        _ = rebuildRuntimeCallbackSuspendExemptFromPublished();
    }
}

fn truncateRuntimeModifiersToPublished() void {
    if (g_runtimeModifiersLen > g_runtimeModifiersPublishedLen) {
        g_runtimeModifiersLen = g_runtimeModifiersPublishedLen;
        g_bulkRuntimeModifiersDirty = false;
        g_bulkRuntimeKeyGateDirty = true;
        rebuildRuntimeDependencyMasksFromPublished();
    }
}

fn truncateRuntimePassthroughsToPublished() void {
    if (g_runtimePassthroughsLen > g_runtimePassthroughsPublishedLen) {
        g_runtimePassthroughsLen = g_runtimePassthroughsPublishedLen;
        g_bulkRuntimePassthroughsDirty = false;
        g_bulkRuntimeKeyGateDirty = true;
        rebuildRuntimeDependencyMasksFromPublished();
    }
}

fn truncateRuntimeContextActionsToPublished() void {
    if (g_runtimeContextActionsLen > g_runtimeContextActionsPublishedLen) {
        g_runtimeContextActionsLen = g_runtimeContextActionsPublishedLen;
        g_bulkRuntimeContextActionsDirty = false;
        g_bulkRuntimeKeyGateDirty = true;
        rebuildRuntimeDependencyMasksFromPublished();
        _ = rebuildRuntimeCallbackSuspendExemptFromPublished();
    }
}

fn truncateRuntimeCombosToPublished() void {
    if (g_runtimeCombosLen > g_runtimeCombosPublishedLen or
        g_runtimeInstantCombosLen > g_runtimeInstantCombosPublishedLen)
    {
        g_runtimeCombosLen = g_runtimeCombosPublishedLen;
        g_runtimeInstantCombosLen = g_runtimeInstantCombosPublishedLen;
        g_runtimeComboRegistrationSeq = g_runtimeComboPublishedRegistrationSeq;
        g_bulkRuntimeCombosDirty = false;
        g_bulkRuntimeKeyGateDirty = true;
        rebuildRuntimeDependencyMasksFromPublished();
        _ = rebuildRuntimeCallbackSuspendExemptFromPublished();
    }
}

fn truncateRuntimeChordsToPublished() void {
    if (g_runtimeChordsLen > g_runtimeChordsPublishedLen) {
        g_runtimeChordsLen = g_runtimeChordsPublishedLen;
        g_bulkRuntimeChordsDirty = false;
        g_bulkRuntimeKeyGateDirty = true;
        rebuildRuntimeDependencyMasksFromPublished();
        _ = rebuildRuntimeCallbackSuspendExemptFromPublished();
    }
}

fn truncateRuntimeHotstringsToPublished() void {
    if (g_runtimeHotstringLen > g_runtimeHotstringPublishedLen) {
        var i = g_runtimeHotstringPublishedLen;
        while (i < g_runtimeHotstringLen) : (i += 1) {
            if (g_runtimeHotstringEntries[i].replacement.len != 0) {
                gAlloc.free(g_runtimeHotstringEntries[i].replacement);
            }
            g_runtimeHotstringEntries[i] = .{ .trigger = "" };
            if (i < g_runtimeHotstringTriggerBytes.len) g_runtimeHotstringTriggerBytes[i] = [_]u8{0} ** hotstrings.MAX_HOTSTRING_TRIGGER_BYTES;
            if (i < g_runtimeHotstringCallbackIds.len) g_runtimeHotstringCallbackIds[i] = 0;
            if (i < g_runtimeHotstringSuspendExempt.len) g_runtimeHotstringSuspendExempt[i] = false;
            if (i < g_runtimeHotstringUserEnabled.len) g_runtimeHotstringUserEnabled[i] = true;
            if (i < g_runtimeHotstringCtxStart.len) g_runtimeHotstringCtxStart[i] = 0;
            if (i < g_runtimeHotstringCtxCount.len) g_runtimeHotstringCtxCount[i] = 0;
        }
        g_runtimeHotstringLen = g_runtimeHotstringPublishedLen;
    }
    if (g_hsCtxRowsLen > g_hsCtxRowsPublishedLen) {
        var c = g_hsCtxRowsPublishedLen;
        while (c < g_hsCtxRowsLen) : (c += 1) {
            g_hsCtxRows[c] = .{};
            g_hsCtxTexts[c] = [_]u16{0} ** RUNTIME_HOTSTRING_CONTEXT_CHARS;
        }
        g_hsCtxRowsLen = g_hsCtxRowsPublishedLen;
    }
    if (g_nativeHotstringPayloads.len > g_nativeHotstringPayloadsPublishedLen) {
        if (g_nativeHotstringPayloadsPublishedLen == 0) {
            retireSlice(u16, g_nativeHotstringPayloads);
            g_nativeHotstringPayloads = &[_]u16{};
        } else {
            if (gAlloc.alloc(u16, g_nativeHotstringPayloadsPublishedLen) catch null) |compact| {
                @memcpy(compact, g_nativeHotstringPayloads[0..g_nativeHotstringPayloadsPublishedLen]);
                const old_payloads = g_nativeHotstringPayloads;
                g_nativeHotstringPayloads = compact;
                retireSlice(u16, old_payloads);
            }
        }
    }
    if (g_runtimeHotstringLen == g_runtimeHotstringPublishedLen and g_hsCtxRowsLen == g_hsCtxRowsPublishedLen)
        g_hsContextIndexDirty = false;
    g_bulkRuntimeHotstringsDirty = false;
    rebuildRuntimeDependencyMasksFromPublished();
    _ = rebuildRuntimeCallbackSuspendExemptFromPublished();
}

fn shouldPrepareRuntimeFamily(prepared_serial: *u32) bool {
    if (g_bulkSetupDepth == 0) g_bulkSetupSerial +%= 1;
    return prepared_serial.* != g_bulkSetupSerial;
}

inline fn markRuntimeFamilyPrepared(prepared_serial: *u32) void {
    prepared_serial.* = g_bulkSetupSerial;
}

inline fn compiledRuntimePreloadStillPublishing() bool {
    if (comptime !has_compiled_user_shortcuts_build) return false;
    // Runtime setup callers already hold the setup lock. Drain an idle
    // compiled publish here so published lengths are authoritative before
    // truncating a family or accepting new runtime rows.
    flushRuntimePublishIfIdleLocked();
    return !g_precompiledShortcutsApplied and
        @atomicLoad(u32, &g_runtimePublishPendingMask, .acquire) != 0;
}

fn prepareRuntimeHotkeyFamily() void {
    if (compiledRuntimePreloadStillPublishing()) return;
    if (!shouldPrepareRuntimeFamily(&g_hotkeysPreparedSerial)) return;
    markRuntimeFamilyPrepared(&g_hotkeysPreparedSerial);
    truncateRuntimeHotkeysToPublished();
}

fn prepareRuntimeModifierFamily() void {
    if (compiledRuntimePreloadStillPublishing()) return;
    if (!shouldPrepareRuntimeFamily(&g_modifiersPreparedSerial)) return;
    markRuntimeFamilyPrepared(&g_modifiersPreparedSerial);
    truncateRuntimeModifiersToPublished();
}

fn prepareRuntimePassthroughFamily() void {
    if (compiledRuntimePreloadStillPublishing()) return;
    if (!shouldPrepareRuntimeFamily(&g_passthroughsPreparedSerial)) return;
    markRuntimeFamilyPrepared(&g_passthroughsPreparedSerial);
    truncateRuntimePassthroughsToPublished();
}

fn prepareRuntimeContextActionFamily() void {
    if (compiledRuntimePreloadStillPublishing()) return;
    if (!shouldPrepareRuntimeFamily(&g_contextActionsPreparedSerial)) return;
    markRuntimeFamilyPrepared(&g_contextActionsPreparedSerial);
    truncateRuntimeContextActionsToPublished();
}

fn prepareRuntimeComboFamily() void {
    if (compiledRuntimePreloadStillPublishing()) return;
    if (!shouldPrepareRuntimeFamily(&g_combosPreparedSerial)) return;
    markRuntimeFamilyPrepared(&g_combosPreparedSerial);
    truncateRuntimeCombosToPublished();
}

fn prepareRuntimeChordFamily() void {
    if (compiledRuntimePreloadStillPublishing()) return;
    if (!shouldPrepareRuntimeFamily(&g_chordsPreparedSerial)) return;
    markRuntimeFamilyPrepared(&g_chordsPreparedSerial);
    truncateRuntimeChordsToPublished();
}

fn prepareRuntimeHotstringFamily() void {
    if (compiledRuntimePreloadStillPublishing()) return;
    if (!shouldPrepareRuntimeFamily(&g_hotstringsPreparedSerial)) return;
    markRuntimeFamilyPrepared(&g_hotstringsPreparedSerial);
    truncateRuntimeHotstringsToPublished();
}

fn finishRuntimeModifierSetup() void {
    g_bulkRuntimeModifiersDirty = true;
    g_bulkRuntimeKeyGateDirty = true;
    if (g_bulkSetupDepth == 0) requestRuntimePublish(RUNTIME_PUBLISH_SETUP);
}

fn finishRuntimePassthroughSetup() void {
    g_bulkRuntimePassthroughsDirty = true;
    g_bulkRuntimeKeyGateDirty = true;
    if (g_bulkSetupDepth == 0) requestRuntimePublish(RUNTIME_PUBLISH_SETUP);
}

fn finishRuntimeContextActionSetup() void {
    g_bulkRuntimeContextActionsDirty = true;
    g_bulkRuntimeKeyGateDirty = true;
    if (g_bulkSetupDepth == 0) requestRuntimePublish(RUNTIME_PUBLISH_SETUP);
}

fn finishRuntimeComboSetup() void {
    g_bulkRuntimeCombosDirty = true;
    g_bulkRuntimeKeyGateDirty = true;
    if (g_bulkSetupDepth == 0) requestRuntimePublish(RUNTIME_PUBLISH_SETUP);
}

fn finishRuntimeChordSetup() void {
    g_bulkRuntimeChordsDirty = true;
    g_bulkRuntimeKeyGateDirty = true;
    if (g_bulkSetupDepth == 0) requestRuntimePublish(RUNTIME_PUBLISH_SETUP);
}

fn finishRuntimeHotstringSetup() void {
    g_bulkRuntimeHotstringsDirty = true;
    // Hotstrings are matched from text already captured by the key path; they
    // do not add VKs to the keygate themselves.
    if (g_bulkSetupDepth == 0) requestRuntimePublish(RUNTIME_PUBLISH_SETUP);
}

fn clearIdleTransientStateForPublish() void {
    if (reconcileTrackedPhysicalKeysDown() != 0) return;
    if (@atomicLoad(i32, &g_hotPathActiveCount, .acquire) != 0) return;
    if (g_active_virtual_modifier_count != 0 or g_unrelModCount != 0 or g_cleanUnrelModCount != 0) {
        QMK_ReleaseStuckModifiers();
    }

    timerClear();
    g_directTapCaptureActive = false;
}

fn rebuildRuntimeDependencyMasksFromPublished() void {
    g_runtimeHotkeyDependencyMask = 0;
    var i: usize = 0;
    while (i < g_runtimeHotkeysPublishedLen) : (i += 1) {
        g_runtimeHotkeyDependencyMask |= g_runtimeHotkeys[i].specificityMask;
    }

    g_runtimeContextActionDependencyMask = 0;
    i = 0;
    while (i < g_runtimeContextActionsPublishedLen) : (i += 1) {
        g_runtimeContextActionDependencyMask |= g_runtimeContextActions[i].specificityMask;
    }

    g_runtimeModifierDependencyMask = 0;
    i = 0;
    while (i < g_runtimeModifiersPublishedLen) : (i += 1) {
        g_runtimeModifierDependencyMask |= g_runtimeModifiers[i].specificityMask;
    }

    g_runtimePassthroughDependencyMask = 0;
    i = 0;
    while (i < g_runtimePassthroughsPublishedLen) : (i += 1) {
        g_runtimePassthroughDependencyMask |= g_runtimePassthroughs[i].specificityMask;
    }

    g_runtimeComboDependencyMask = 0;
    i = 0;
    while (i < g_runtimeCombosPublishedLen) : (i += 1) {
        g_runtimeComboDependencyMask |= g_runtimeCombos[i].specificityMask;
    }
    i = 0;
    while (i < g_runtimeInstantCombosPublishedLen) : (i += 1) {
        g_runtimeComboDependencyMask |= g_runtimeInstantCombos[i].specificityMask;
    }

    g_runtimeChordDependencyMask = 0;
    i = 0;
    while (i < g_runtimeChordsPublishedLen) : (i += 1) {
        g_runtimeChordDependencyMask |= g_runtimeChords[i].specificityMask;
    }

    g_runtimeHotstringDependencyMask = 0;
    i = 0;
    while (i < g_hsCtxRowsPublishedLen) : (i += 1) {
        g_runtimeHotstringDependencyMask |= g_hsCtxRows[i].specificityMask;
    }
}

fn publishDeferredRuntimeSetup() bool {
    clearIdleTransientStateForPublish();
    var ok = true;
    var keygate_committed = false;
    var published_changed = false;
    if (g_bulkRuntimeHotkeysDirty or g_runtimeHotkeyContextsDirty) {
        if (rebuildActiveRuntimeHotkeyIndex()) {
            g_runtimeHotkeysPublishedLen = g_runtimeHotkeysLen;
            g_bulkRuntimeHotkeysDirty = false;
            keygate_committed = true;
            published_changed = true;
        } else {
            ok = false;
        }
    }
    if (g_bulkRuntimeContextActionsDirty) {
        const context_actions_ok = rebuildActiveRuntimeContextActions();
        ok = context_actions_ok and ok;
        if (context_actions_ok) {
            g_runtimeContextActionsPublishedLen = g_runtimeContextActionsLen;
            g_bulkRuntimeContextActionsDirty = false;
            keygate_committed = true;
            published_changed = true;
        }
    }
    if (g_bulkRuntimeModifiersDirty) {
        const modifiers_ok = rebuildActiveRuntimeModifiers();
        ok = modifiers_ok and ok;
        if (modifiers_ok) {
            g_runtimeModifiersPublishedLen = g_runtimeModifiersLen;
            g_bulkRuntimeModifiersDirty = false;
            keygate_committed = true;
            published_changed = true;
        }
    }
    if (g_bulkRuntimeCombosDirty) {
        const combos_ok = rebuildActiveRuntimeCombos();
        ok = combos_ok and ok;
        if (combos_ok) {
            g_runtimeCombosPublishedLen = g_runtimeCombosLen;
            g_runtimeInstantCombosPublishedLen = g_runtimeInstantCombosLen;
            g_runtimeComboPublishedRegistrationSeq = g_runtimeComboRegistrationSeq;
            g_bulkRuntimeCombosDirty = false;
            keygate_committed = true;
            published_changed = true;
        }
    }
    if (g_bulkRuntimeChordsDirty) {
        const chords_ok = rebuildActiveRuntimeChords();
        ok = chords_ok and ok;
        if (chords_ok) {
            g_runtimeChordsPublishedLen = g_runtimeChordsLen;
            g_bulkRuntimeChordsDirty = false;
            keygate_committed = true;
            published_changed = true;
        }
    }
    if (g_bulkRuntimeHotstringsDirty) {
        rebuildRuntimeHotstringContextIndex();
        const hotstrings_ok = rebuildRuntimeHotstringContexts();
        ok = hotstrings_ok and ok;
        if (hotstrings_ok) {
            g_hotstringMatcher.reset();
            g_runtimeHotstringPublishedLen = g_runtimeHotstringLen;
            g_hsCtxRowsPublishedLen = g_hsCtxRowsLen;
            g_nativeHotstringPayloadsPublishedLen = g_nativeHotstringPayloads.len;
            g_bulkRuntimeHotstringsDirty = false;
            published_changed = true;
        }
    }
    if (g_bulkRuntimePassthroughsDirty) {
        const passthroughs_ok = rebuildActiveRuntimePassthroughs();
        ok = passthroughs_ok and ok;
        if (passthroughs_ok) {
            g_runtimePassthroughsPublishedLen = g_runtimePassthroughsLen;
            g_bulkRuntimePassthroughsDirty = false;
            keygate_committed = true;
            published_changed = true;
        }
    }
    if (published_changed or ok) rebuildRuntimeDependencyMasksFromPublished();
    if (g_bulkRuntimeKeyGateDirty and (ok or keygate_committed)) {
        markKeyGateDirty();
        refreshReplayKeyGate();
        if (ok) g_bulkRuntimeKeyGateDirty = false;
    }
    return ok;
}

fn setupStaticHoldText(key: [*:0]const u16, callbackId: i32) void {
    const vk = getVKFromName(key);
    if (vk == 0) return;
    setupHoldVK(vk, callbackId);
    markKeyGateDirty();
    refreshReplayKeyGate();
}
export fn QMK_SetupTapHolds(records: [*]const u8, count: u32, contextChars: [*]const u16, contextCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeContextActionFamily();
    if (!ensureRuntimeContextActionCapacity(g_runtimeContextActionsLen + @as(usize, @intCast(count)))) return 0;
    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 32;
        const vk = readI32LE(records, off);
        if (vk <= 0 or vk >= VK_COUNT) continue;
        const tap_callback_id = readI32LE(records, off + 4);
        const hold_callback_id = readI32LE(records, off + 8);
        const cleanup_callback_id = readI32LE(records, off + 12);
        if (tap_callback_id < 0 and hold_callback_id < 0) continue;
        const threshold_ms = readI32LE(records, off + 16);
        const context_kind = records[off + 20];
        const negated = records[off + 21] != 0;
        const suspend_exempt = records[off + 22] != 0;
        const context_off: usize = @intCast(readU32LE(records, off + 24));
        var context_len: usize = @intCast(readU16LE(records, off + 28));
        if (context_off > contextCharsLen) continue;
        const remaining: usize = @intCast(contextCharsLen - @as(u32, @intCast(context_off)));
        if (context_len > remaining) context_len = remaining;
        if (context_len >= RUNTIME_CONTEXT_ACTION_CHARS) continue;
        if (!ensureRuntimeCallbackSuspendExemptFor3(tap_callback_id, hold_callback_id, cleanup_callback_id, suspend_exempt)) {
            truncateRuntimeContextActionsToPublished();
            return 0;
        }

        const row_loaded = appendRuntimeTapHoldRegistration(
            vk, tap_callback_id, hold_callback_id, cleanup_callback_id, threshold_ms,
            context_kind, negated, contextChars[context_off..][0..context_len], suspend_exempt);
        if (row_loaded) loaded += 1;
    }
    finishRuntimeContextActionSetup();
    return loaded;
}

/// Higher-level tap-hold entries. AHK sends key/context strings plus callback
/// ids and timing; Zig parses key/context and owns all active action rows.
/// Record layout (40 bytes): keyOffset:u32, keyLen:u16, reserved:u16,
/// tapId:i32, holdId:i32, cleanupId:i32, thresholdMs:i32,
/// suspendExempt:u8, reserved[3], contextOffset:u32, contextLen:u16.
export fn QMK_SetupTapHoldEntries(records: [*]const u8, count: u32, textChars: [*]const u16, textCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeContextActionFamily();
    if (!ensureRuntimeContextActionCapacity(g_runtimeContextActionsLen + @as(usize, @intCast(count)))) return 0;
    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 40;
        const key_offset: usize = @intCast(readU32LE(records, off));
        var key_len: usize = @intCast(readU16LE(records, off + 4));
        const tap_callback_id = readI32LE(records, off + 8);
        const hold_callback_id = readI32LE(records, off + 12);
        const cleanup_callback_id = readI32LE(records, off + 16);
        const threshold_ms = readI32LE(records, off + 20);
        const suspend_exempt = records[off + 24] != 0;
        const context_offset: usize = @intCast(readU32LE(records, off + 28));
        var context_len: usize = @intCast(readU16LE(records, off + 32));
        if (key_offset > textCharsLen or context_offset > textCharsLen) continue;
        const key_remaining: usize = @intCast(textCharsLen - @as(u32, @intCast(key_offset)));
        const context_remaining: usize = @intCast(textCharsLen - @as(u32, @intCast(context_offset)));
        if (key_len > key_remaining) key_len = key_remaining;
        if (context_len > context_remaining) context_len = context_remaining;

        const vk = getVKFromText16(textChars[key_offset..][0..key_len]);
        if (vk <= 0 or vk >= VK_COUNT) continue;
        if (tap_callback_id < 0 and hold_callback_id < 0) continue;
        const context_parts = runtimeContextPartCount(textChars[context_offset..][0..context_len]);
        if (!ensureRuntimeContextActionCapacity(g_runtimeContextActionsLen + context_parts)) {
            truncateRuntimeContextActionsToPublished();
            return 0;
        }
        if (!ensureRuntimeCallbackSuspendExemptFor3(tap_callback_id, hold_callback_id, cleanup_callback_id, suspend_exempt)) {
            truncateRuntimeContextActionsToPublished();
            return 0;
        }
        var contexts = RuntimeContextListIterator{ .raw = textChars[context_offset..][0..context_len] };
        var row_loaded = false;
        while (contexts.next()) |context_text| {
            const context = parseRuntimeContextSpec(context_text);
            if (appendRuntimeTapHoldRegistration(
                vk, tap_callback_id, hold_callback_id, cleanup_callback_id, threshold_ms,
                context.kind, context.negated, context.text, suspend_exempt)) row_loaded = true;
        }
        if (row_loaded) loaded += 1;
    }
    finishRuntimeContextActionSetup();
    return loaded;
}

fn parseI32Text16(raw: []const u16, fallback: i32) i32 {
    const text = trimSpaces16(raw);
    if (text.len == 0) return fallback;
    var next_index: usize = 0;
    const value = readHotstringOptionInteger16(text, 0, &next_index);
    return if (next_index == 0) fallback else value;
}

fn tapHoldCellsNeedNativePayload(records: [*]const u8, count: u32) bool {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 116;
        const cell_count: usize = @min(@as(usize, @intCast(records[off])), 7);
        var c: usize = 0;
        while (c < cell_count) : (c += 1) {
            if (records[off + 4 + c * 16] == HOTKEY_CELL_TAP_TEXT) return true;
        }
    }
    return false;
}

fn tapHoldCallbackIdFromCell(cell: RuntimeHotkeyCell, payload_base: usize) i32 {
    return switch (cell.tag) {
        HOTKEY_CELL_CALLBACK, HOTKEY_CELL_TAP_CALLBACK => if (cell.callbackId >= 0) cell.callbackId else -1,
        HOTKEY_CELL_TAP_TEXT => NATIVE_PAYLOAD_ID_BASE - @as(i32, @intCast(payload_base + cell.textOffset)),
        else => -1,
    };
}

/// Typed-cell tap-hold entries. Transport is shared, but tap-hold lifecycle
/// semantics remain in the existing runtime state machine.
/// Record layout (116 bytes): cellCount:u8 at 0; seven 16-byte cells at 4.
export fn QMK_SetupTapHoldCellEntries(records: [*]const u8, count: u32, textChars: [*]const u16, textCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeContextActionFamily();
    if (!ensureRuntimeContextActionCapacity(g_runtimeContextActionsLen + @as(usize, @intCast(count)))) return 0;
    const needs_native_payload = tapHoldCellsNeedNativePayload(records, count);
    const payload_base = if (!needs_native_payload or textCharsLen == 0)
        g_nativeHotkeyPayloads.len
    else
        appendNativeHotkeyPayloads(textChars, textCharsLen);
    if (payload_base == NATIVE_PAYLOAD_APPEND_FAILED) return 0;
    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 116;
        const raw_cell_count = records[off];
        if (raw_cell_count < 4) continue;
        const cell_count: usize = @min(@as(usize, @intCast(raw_cell_count)), 7);
        var cells = [_]RuntimeHotkeyCell{.{}} ** 7;
        var c: usize = 0;
        var valid = true;
        var suspend_exempt = false;
        while (c < cell_count) : (c += 1) {
            cells[c] = readRuntimeHotkeyCell(records, off, c, textChars, textCharsLen) orelse {
                valid = false;
                break;
            };
            suspend_exempt = suspend_exempt or ((cells[c].flags & 1) != 0);
        }
        if (!valid or cells[0].tag != HOTKEY_CELL_TEXT) continue;

        const vk = getVKFromText16(cells[0].text);
        if (vk <= 0 or vk >= VK_COUNT) continue;

        const legacy_order = runtimeHotkeyCellIsPlainCallback(cells[1]);
        if (!legacy_order and (cells[1].tag != HOTKEY_CELL_TEXT or cells[2].tag != HOTKEY_CELL_TEXT)) continue;
        const context_cell_index: usize = if (legacy_order) 5 else 1;
        const threshold_cell_index: usize = if (legacy_order) 3 else 2;
        const tap_cell_index: usize = if (legacy_order) 1 else 3;
        const hold_cell_index: usize = if (legacy_order) 2 else 4;
        const cleanup_cell_index: usize = if (legacy_order) 4 else 5;
        const suspend_cell_index: usize = if (legacy_order) 6 else 6;

        if (cell_count <= threshold_cell_index or cells[threshold_cell_index].tag != HOTKEY_CELL_TEXT) continue;
        const threshold_ms = parseI32Text16(cells[threshold_cell_index].text, 200);
        const tap_callback_id = if (cell_count > tap_cell_index) tapHoldCallbackIdFromCell(cells[tap_cell_index], payload_base) else -1;
        const hold_callback_id = if (cell_count > hold_cell_index) tapHoldCallbackIdFromCell(cells[hold_cell_index], payload_base) else -1;
        const cleanup_callback_id = if (cell_count > cleanup_cell_index) tapHoldCallbackIdFromCell(cells[cleanup_cell_index], payload_base) else -1;
        if (tap_callback_id < 0 and hold_callback_id < 0) continue;
        if (cell_count > suspend_cell_index) suspend_exempt = suspend_exempt or runtimeHotkeyBoolCell(cells[suspend_cell_index]);
        var tap_hold_context_text: []const u16 = &[_]u16{};
        if (cell_count > context_cell_index and cells[context_cell_index].tag == HOTKEY_CELL_TEXT)
            tap_hold_context_text = cells[context_cell_index].text;
        const context_parts = runtimeContextPartCount(tap_hold_context_text);
        if (!ensureRuntimeContextActionCapacity(g_runtimeContextActionsLen + context_parts)) {
            truncateRuntimeContextActionsToPublished();
            return 0;
        }
        if (!ensureRuntimeCallbackSuspendExemptFor3(tap_callback_id, hold_callback_id, cleanup_callback_id, suspend_exempt)) {
            truncateRuntimeContextActionsToPublished();
            return 0;
        }

        var contexts = RuntimeContextListIterator{ .raw = tap_hold_context_text };
        var row_loaded = false;
        while (contexts.next()) |context_text| {
            const context = parseRuntimeContextSpec(context_text);
            if (appendRuntimeTapHoldRegistration(
                vk, tap_callback_id, hold_callback_id, cleanup_callback_id, threshold_ms,
                context.kind, context.negated, context.text, suspend_exempt)) row_loaded = true;
        }
        if (row_loaded) loaded += 1;
    }
    finishRuntimeContextActionSetup();
    return loaded;
}

fn copyHotstringTriggerUtf16Ascii(trigger: [*:0]const u16, out: *[hotstrings.MAX_HOTSTRING_TRIGGER_BYTES]u8) usize {
    var len: usize = 0;
    while (trigger[len] != 0 and len < out.len) : (len += 1) {
        const ch = trigger[len];
        out[len] = if (ch <= 0x7f) @intCast(ch) else '?';
    }
    return len;
}

fn copyHotstringTriggerText16Ascii(trigger: []const u16, out: *[hotstrings.MAX_HOTSTRING_TRIGGER_BYTES]u8) usize {
    const limit = @min(trigger.len, out.len);
    var len: usize = 0;
    while (len < limit) : (len += 1) {
        const ch = trigger[len];
        out[len] = if (ch <= 0x7f) @intCast(ch) else '?';
    }
    return len;
}

inline fn asciiUpper16(ch: u16) u16 {
    return if (ch >= 'a' and ch <= 'z') ch - 32 else ch;
}

fn readHotstringOptionInteger16(text: []const u16, start: usize, next_index: *usize) i32 {
    var sign: i32 = 1;
    var i = start;
    if (i < text.len and text[i] == '-') {
        sign = -1;
        i += 1;
    }
    var value: i32 = 0;
    var saw_digit = false;
    while (i < text.len) : (i += 1) {
        const ch = text[i];
        if (ch < '0' or ch > '9') break;
        saw_digit = true;
        value = value * 10 + @as(i32, @intCast(ch - '0'));
    }
    next_index.* = i;
    return if (saw_digit) value * sign else 0;
}

fn applyHotstringOptionsText16(options: *hotstrings.HotstringOptions, option_text: []const u16) void {
    var i: usize = 0;
    while (i < option_text.len) : (i += 1) {
        const ch = asciiUpper16(option_text[i]);
        const next = if (i + 1 < option_text.len) option_text[i + 1] else 0;
        switch (ch) {
            '*' => {
                options.end_char_required = next == '0';
                if (next == '0') i += 1;
            },
            '?' => {
                options.detect_inside_word = next != '0';
                if (next == '0') i += 1;
            },
            'B' => {
                options.do_backspace = next != '0';
                if (next == '0') i += 1;
            },
            'C' => {
                if (next == '0') {
                    options.conform_to_case = true;
                    options.case_sensitive = false;
                    i += 1;
                } else if (next == '1') {
                    options.conform_to_case = false;
                    options.case_sensitive = false;
                    i += 1;
                } else {
                    options.conform_to_case = false;
                    options.case_sensitive = true;
                }
            },
            'O' => {
                options.omit_end_char = next != '0';
                if (next == '0') i += 1;
            },
            'K' => {
                var next_index: usize = i + 1;
                _ = readHotstringOptionInteger16(option_text, i + 1, &next_index);
                i = if (next_index == 0) i else next_index - 1;
            },
            'P' => {
                var next_index: usize = i + 1;
                _ = readHotstringOptionInteger16(option_text, i + 1, &next_index);
                i = if (next_index == 0) i else next_index - 1;
            },
            'R' => {
                options.send_raw = if (next != '0') 1 else 0;
                if (next == '0') i += 1;
            },
            'T' => {
                options.send_raw = if (next != '0') 2 else 0;
                if (next == '0') i += 1;
            },
            'S' => {
                const sub = asciiUpper16(next);
                if (sub == 'I') {
                    options.send_mode = 1;
                    i += 1;
                } else if (sub == 'E') {
                    options.send_mode = 2;
                    i += 1;
                } else if (sub == 'P') {
                    options.send_mode = 3;
                    i += 1;
                } else {
                    options.suspend_exempt = next != '0';
                    if (next == '0') i += 1;
                }
            },
            'Z' => {
                options.reset_after_fire = next != '0';
                if (next == '0') i += 1;
            },
            'X' => {
                options.execute_action = next != '0';
                if (next == '0') i += 1;
            },
            else => {},
        }
    }
}

const ParsedHotstringSpec = struct {
    trigger: []const u16,
    optionBits: u32,
};

fn parseHotstringSpecText16(spec: []const u16, extra_options: []const u16, suspend_exempt: bool) ParsedHotstringSpec {
    var options = hotstrings.HotstringOptions{};
    var trigger = spec;
    if (spec.len >= 2 and spec[0] == ':') {
        var option_end: usize = 1;
        while (option_end < spec.len and spec[option_end] != ':') : (option_end += 1) {}
        if (option_end < spec.len) {
            applyHotstringOptionsText16(&options, spec[1..option_end]);
            trigger = spec[option_end + 1 ..];
        }
    }
    if (extra_options.len != 0) applyHotstringOptionsText16(&options, extra_options);
    if (suspend_exempt) options.suspend_exempt = true;
    return .{ .trigger = trigger, .optionBits = options.toBits() };
}

export fn QMK_GetRuntimeHotstringCount() callconv(.c) i32 {
    return @intCast(g_runtimeHotstringLen);
}

/// Test-only family visibility. The export is present in the DLL ABI for a
/// stable probe, but returns -1 unless the build-options module explicitly
/// enables compiled_shortcuts_test_observability.
/// Family IDs: 0 modifiers, 1 passthroughs, 2 hotkeys, 3 holds, 4 double taps,
/// 5 taps, 6 tap-holds, 7 normal combos, 8 instant combos, 9 external chords,
/// 10 internal chords, 11 hotstrings, 12 panic control, 13 reload control.
export fn QMK_TestGetPrecompiledFamilyCount(family: i32) callconv(.c) i32 {
    if (!compiled_shortcuts_test_observability or family < 0 or family >= 14) return -1;
    return @intCast(g_precompiledFamilyCounts[@intCast(family)]);
}

/// Returns the current QMKCore-owned runtime storage length for the family.
/// Holds, double taps, and tap-holds share the context-action store and thus
/// return its aggregate length; their precompiled subtype counts are reported
/// separately by QMK_TestGetPrecompiledFamilyCount.
export fn QMK_TestGetRuntimeFamilyCount(family: i32) callconv(.c) i32 {
    if (!compiled_shortcuts_test_observability or family < 0 or family >= 14) return -1;
    return switch (family) {
        0 => @intCast(g_runtimeModifiersLen),
        1 => @intCast(g_runtimePassthroughsLen),
        2 => @intCast(g_runtimeHotkeysLen),
        3, 4, 6 => @intCast(g_runtimeContextActionsLen),
        5 => @intCast(g_runtimeHotkeysLen),
        7 => @intCast(g_runtimeCombosLen),
        8 => @intCast(g_runtimeInstantCombosLen),
        9 => countRuntimeChordsByMode(0),
        10 => countRuntimeChordsByMode(1),
        11 => @intCast(g_runtimeHotstringLen),
        12 => @atomicLoad(i32, &g_panicExitEnabled, .acquire),
        13 => @atomicLoad(i32, &g_nativeReloadEnabled, .acquire),
        else => -1,
    };
}

fn countRuntimeChordsByMode(mode: u8) i32 {
    var count: i32 = 0;
    var i: usize = 0;
    while (i < g_runtimeChordsLen) : (i += 1) {
        if (g_runtimeChords[i].mode == mode) count += 1;
    }
    return count;
}

/// Test-only identity accessor for the compiled-shape gate.  It exposes only
/// stable key/mode fields from QMK-owned runtime rows; it does not participate
/// in dispatch and is unavailable unless test observability is enabled.
/// `which` is family-specific: combos use 0/1 for primary/secondary and 2 for
/// mode; chords use 0 for key_count and 1..5 for sorted VKs; all other families
/// return their leading VK/key field.
export fn QMK_TestGetRuntimeFamilyKey(family: i32, index_in: i32, which: i32) callconv(.c) i32 {
    if (!compiled_shortcuts_test_observability or family < 0 or family >= 14 or index_in < 0 or which < 0)
        return -1;
    const index: usize = @intCast(index_in);
    return switch (family) {
        0 => if (index < g_runtimeModifiersLen) g_runtimeModifiers[index].vk else -1,
        1 => if (index < g_runtimePassthroughsLen) g_runtimePassthroughs[index].vk else -1,
        2, 5 => if (index < g_runtimeHotkeysLen) g_runtimeHotkeys[index].triggerVK else -1,
        3, 4, 6 => if (index < g_runtimeContextActionsLen) g_runtimeContextActions[index].triggerVK else -1,
        7 => if (index < g_runtimeCombosLen) switch (which) {
            0 => g_runtimeCombos[index].primaryVK,
            1 => g_runtimeCombos[index].secondaryVK,
            2 => @intCast(g_runtimeCombos[index].mode),
            else => -1,
        } else -1,
        8 => if (index < g_runtimeInstantCombosLen) switch (which) {
            0 => g_runtimeInstantCombos[index].primaryVK,
            1 => g_runtimeInstantCombos[index].secondaryVK,
            2 => @intCast(g_runtimeInstantCombos[index].mode),
            else => -1,
        } else -1,
        9, 10 => if (runtimeChordIndexForMode(family - 9, index)) |chord_index| switch (which) {
            0 => @intCast(g_runtimeChords[chord_index].keyCount),
            1...5 => g_runtimeChords[chord_index].vks[@intCast(which - 1)],
            else => -1,
        } else -1,
        11 => if (index < g_runtimeHotstringLen and which == 0)
            @intCast(g_runtimeHotstringTriggerBytes[index][0])
        else -1,
        12 => if (index == 0 and which == 0) @atomicLoad(i32, &g_panicExitVK, .acquire) else -1,
        13 => if (index == 0 and which == 0) @atomicLoad(i32, &g_nativeReloadVK, .acquire) else -1,
        else => -1,
    };
}

/// Test-only input-state probes used by the mixed compiled/runtime parity
/// runner. They expose no production behavior and are enabled only by the
/// same explicit observability build option as the family counters.
export fn QMK_TestGetPendingSoloVK() callconv(.c) i32 {
    if (!compiled_shortcuts_test_observability) return -1;
    return g_pendingSoloVK;
}

export fn QMK_TestGetRuntimeFlags() callconv(.c) u32 {
    if (!compiled_shortcuts_test_observability) return 0;
    return g_runtimeFlags;
}

fn runtimeChordIndexForMode(mode: i32, wanted: usize) ?usize {
    var seen: usize = 0;
    var i: usize = 0;
    while (i < g_runtimeChordsLen) : (i += 1) {
        if (@as(i32, g_runtimeChords[i].mode) != mode) continue;
        if (seen == wanted) return i;
        seen += 1;
    }
    return null;
}

fn mixedCoreHasCompiledRows() bool {
    for (g_precompiledFamilyCounts) |count| if (count != 0) return true;
    return false;
}

fn mixedCoreHasRuntimeSuffix() bool {
    return g_runtimeHotkeysLen > g_runtimeHotkeysPublishedLen or
        g_runtimeContextActionsLen > g_runtimeContextActionsPublishedLen or
        g_runtimeModifiersLen > g_runtimeModifiersPublishedLen or
        g_runtimePassthroughsLen > g_runtimePassthroughsPublishedLen or
        g_runtimeCombosLen > g_runtimeCombosPublishedLen or
        g_runtimeInstantCombosLen > g_runtimeInstantCombosPublishedLen or
        g_runtimeChordsLen > g_runtimeChordsPublishedLen or
        g_runtimeHotstringLen > g_runtimeHotstringPublishedLen;
}

fn mixedCoreHasExactRuntimeOverride() bool {
    var i: usize = 0;
    while (i < g_runtimeHotkeysPublishedLen) : (i += 1)
        if (runtimeHotkeyOverriddenByRuntime(i)) return true;
    i = 0;
    while (i < g_runtimeContextActionsPublishedLen) : (i += 1)
        if (runtimeContextActionOverriddenByRuntime(i)) return true;
    i = 0;
    while (i < g_runtimeModifiersPublishedLen) : (i += 1)
        if (runtimeModifierOverriddenByRuntime(i)) return true;
    i = 0;
    while (i < g_runtimePassthroughsPublishedLen) : (i += 1)
        if (runtimePassthroughOverriddenByRuntime(i)) return true;
    i = 0;
    while (i < g_runtimeChordsPublishedLen) : (i += 1)
        if (runtimeChordOverriddenByRuntime(i)) return true;
    i = 0;
    while (i < g_runtimeHotstringPublishedLen) : (i += 1)
        if (runtimeHotstringOverriddenByRuntime(i)) return true;
    return false;
}

fn mixedCoreHasContextSpecificCoexistence() bool {
    var i: usize = 0;
    while (i < g_runtimeHotkeysPublishedLen) : (i += 1) {
        const compiled = g_runtimeHotkeys[i];
        if (compiled.specificityMask != 0) continue;
        var j: usize = g_runtimeHotkeysPublishedLen;
        while (j < g_runtimeHotkeysLen) : (j += 1) {
            const runtime = g_runtimeHotkeys[j];
            if (runtime.triggerVK == compiled.triggerVK and runtime.specificityMask != 0) return true;
        }
    }
    return false;
}

fn mixedCoreHasHeldEFixture() bool {
    var i: usize = 0;
    while (i < g_runtimeHotkeysLen) : (i += 1) {
        const row = g_runtimeHotkeys[i];
        if (row.triggerVK == 0x45 and (row.physicalModVK == 0x14 or row.physicalModsRequired != 0)) return true;
    }
    return false;
}

/// QMKCore-only coexistence audit. The excluded runner supplies deterministic
/// registrations and replay; this export reports what the loaded DLL can
/// prove from its current state without mutating it. `out_total` is 5 and the
/// checks are: compiled prefix, runtime suffix, exact override, contextual
/// coexistence/compiled fallback, and held-e plus clean lifecycle. `out_flags`
/// reports missing evidence: bit 0 compiled rows, bit 1 runtime suffix, bit 2
/// exact override, bit 3 contextual coexistence, bit 4 held-e, bit 5 lifecycle.
export fn QMK_TestGetMixedCoexistencePassTotal(out_passed: *i32, out_total: *i32, out_flags: *u32) callconv(.c) i32 {
    if (!compiled_shortcuts_test_observability) return 0;
    out_passed.* = 0;
    out_total.* = 5;
    out_flags.* = 0;
    if (mixedCoreHasCompiledRows()) out_passed.* += 1 else out_flags.* |= 1 << 0;
    if (mixedCoreHasRuntimeSuffix()) out_passed.* += 1 else out_flags.* |= 1 << 1;
    if (mixedCoreHasExactRuntimeOverride()) out_passed.* += 1 else out_flags.* |= 1 << 2;
    if (mixedCoreHasContextSpecificCoexistence()) out_passed.* += 1 else out_flags.* |= 1 << 3;
    const lifecycle_clean = g_trackedPhysicalKeysDown == 0 and g_active_physical_modifiers == 0 and
        g_pendingCBsLen == 0 and g_keyCount == 0 and g_unreleasedKeyCount == 0;
    if (mixedCoreHasHeldEFixture() and lifecycle_clean) out_passed.* += 1 else {
        if (!mixedCoreHasHeldEFixture()) out_flags.* |= 1 << 4;
        if (!lifecycle_clean) out_flags.* |= 1 << 5;
    }
    return 1;
}

export fn QMK_SetNativeSuspendHotkeyEntry(hotkeySpec: [*:0]const u16, enabled: i32) callconv(.c) i32 {
    const spec = wideZSpan(hotkeySpec);
    const parsed = parseRuntimeHotkeySpecText16(spec) orelse {
        @atomicStore(i32, &g_nativeSuspendEnabled, 0, .release);
        return 0;
    };
    return QMK_SetNativeSuspendHotkey(parsed.vk, parsed.modsRequired, parsed.modsForbidden, enabled);
}

export fn QMK_SetNativeSuspendHotkey(vk: i32, mods_required: u16, mods_forbidden: u16, enabled: i32) callconv(.c) i32 {
    if (vk <= 0 or vk >= VK_COUNT) {
        @atomicStore(i32, &g_nativeSuspendEnabled, 0, .release);
        return 0;
    }
    @atomicStore(i32, &g_nativeSuspendVK, vk, .release);
    @atomicStore(u16, &g_nativeSuspendModsRequired, mods_required, .release);
    @atomicStore(u16, &g_nativeSuspendModsForbidden, mods_forbidden, .release);
    @atomicStore(i32, &g_nativeSuspendEnabled, if (enabled != 0) 1 else 0, .release);
    return 1;
}

/// Test-only native-control probe. Control IDs are 0 = panic-exit and
/// 1 = native-reload; unlike row-backed families these controls intentionally
/// have one active slot, so expose their configured identity directly.
export fn QMK_TestGetNativeControl(control: i32, field: i32) callconv(.c) i32 {
    if (!compiled_shortcuts_test_observability or control < 0 or control > 1 or field < 0 or field > 3)
        return -1;
    return switch (control) {
        0 => switch (field) {
            0 => @atomicLoad(i32, &g_panicExitVK, .acquire),
            1 => @atomicLoad(u16, &g_panicExitModsRequired, .acquire),
            2 => @atomicLoad(u16, &g_panicExitModsForbidden, .acquire),
            3 => @atomicLoad(i32, &g_panicExitEnabled, .acquire),
            else => -1,
        },
        1 => switch (field) {
            0 => @atomicLoad(i32, &g_nativeReloadVK, .acquire),
            1 => @atomicLoad(u16, &g_nativeReloadModsRequired, .acquire),
            2 => @atomicLoad(u16, &g_nativeReloadModsForbidden, .acquire),
            3 => @atomicLoad(i32, &g_nativeReloadEnabled, .acquire),
            else => -1,
        },
        else => -1,
    };
}

/// Test-only contextual-tap probe.  This reports the first runtime row for a
/// trigger whose action kind is the contextual tap kind, plus the arm state
/// for that VK.  It is observational only and is not used by dispatch.
export fn QMK_TestGetContextualTapDebug(
    trigger_vk: i32,
    out_callback_id: *i32,
    out_specificity_mask: *u8,
    out_context_kind: *u8,
    out_armed: *u8,
    out_last_down_vk: *i32,
    out_context_allowed: *u8,
    out_ready_match: *i32,
    out_global_match: *i32,
) callconv(.c) i32 {
    if (!compiled_shortcuts_test_observability or trigger_vk < 0 or trigger_vk >= VK_COUNT) return -1;
    out_callback_id.* = -1;
    out_specificity_mask.* = 0;
    out_context_kind.* = 0;
    out_armed.* = if (g_contextualTapArmed[@intCast(trigger_vk)]) 1 else 0;
    out_last_down_vk.* = g_lastPhysicalDownVK;
    out_context_allowed.* = 0;
    out_ready_match.* = matchRuntimeContextualTapHotkeyPass(trigger_vk, 0, false);
    out_global_match.* = matchRuntimeContextualTapHotkeyPass(trigger_vk, 0, true);
    var i: usize = 0;
    while (i < g_runtimeHotkeysLen) : (i += 1) {
        const row = g_runtimeHotkeys[i];
        if (row.triggerVK != trigger_vk or row.actionKind != 1) continue;
        out_callback_id.* = row.callbackId;
        out_specificity_mask.* = row.specificityMask;
        out_context_kind.* = row.contextKind;
        out_context_allowed.* = if (runtimeHotkeyContextAllows(i)) 1 else 0;
        return 1;
    }
    return 0;
}

/// Reports what the DLL actually stored for a runtime hotstring, so a
/// registration problem can be separated from a paste problem instead of
/// inferred from behavior.
///
/// `outAction` is HotstringActionKind: 0 = paste_withbackup, 1 =
/// interception_text, 2 = ahk_callback. A native-payload row reads back as 2
/// with 0 replacement bytes and a callbackId at or below NATIVE_PAYLOAD_ID_BASE;
/// the hotstring fire path resolves that id directly to the DLL payload buffer.
///
/// Returns the slot index, or -1 when the trigger is not registered.
export fn QMK_GetRuntimeHotstringDebug(
    trigger: [*:0]const u16,
    outAction: *u32,
    outReplacementBytes: *u32,
    outCallbackId: *i32,
    outEnabled: *u32,
    outCtxCount: *u32,
) callconv(.c) i32 {
    outAction.* = 0xFFFF_FFFF;
    outReplacementBytes.* = 0;
    outCallbackId.* = 0;
    outEnabled.* = 0;
    outCtxCount.* = 0;

    var scratch: [hotstrings.MAX_HOTSTRING_TRIGGER_BYTES]u8 = undefined;
    const trigger_len = copyHotstringTriggerUtf16Ascii(trigger, &scratch);
    if (trigger_len == 0) return -1;

    var i: usize = 0;
    while (i < g_runtimeHotstringLen) : (i += 1) {
        const entry = g_runtimeHotstringEntries[i];
        if (entry.trigger.len != trigger_len) continue;
        if (!hotstrings.bytesEqual(entry.trigger, scratch[0..trigger_len], false)) continue;
        outAction.* = @intFromEnum(entry.action);
        outReplacementBytes.* = @intCast(entry.replacement.len);
        outCallbackId.* = g_runtimeHotstringCallbackIds[i];
        const runtime_view = activeRuntimeHotstrings();
        outEnabled.* = if (i < runtime_view.len and runtime_view.entries[i].options.enabled) 1 else 0;
        outCtxCount.* = g_runtimeHotstringCtxCount[i];
        return @intCast(i);
    }
    return -1;
}

/// Copies back the stored replacement so the exact bytes the DLL will paste can
/// be compared against what AutoHotkey handed over. Returns the number of UTF-8
/// bytes copied, or -1 if the trigger is unknown.
export fn QMK_GetRuntimeHotstringReplacement(
    trigger: [*:0]const u16,
    outUtf8: [*]u8,
    outCapacity: u32,
) callconv(.c) i32 {
    var scratch: [hotstrings.MAX_HOTSTRING_TRIGGER_BYTES]u8 = undefined;
    const trigger_len = copyHotstringTriggerUtf16Ascii(trigger, &scratch);
    if (trigger_len == 0) return -1;

    var i: usize = 0;
    while (i < g_runtimeHotstringLen) : (i += 1) {
        const entry = g_runtimeHotstringEntries[i];
        if (entry.trigger.len != trigger_len) continue;
        if (!hotstrings.bytesEqual(entry.trigger, scratch[0..trigger_len], false)) continue;
        if (outCapacity == 0) return @intCast(entry.replacement.len);
        const room: usize = @intCast(outCapacity - 1);
        const n = @min(room, entry.replacement.len);
        @memcpy(outUtf8[0..n], entry.replacement[0..n]);
        outUtf8[n] = 0;
        return @intCast(n);
    }
    return -1;
}

/// Test-only indexed view of the published hotstring bank.  The trigger-based
/// debug export intentionally returns the first matching row, which is not
/// enough to prove compiled-prefix/runtime-suffix takeover when both rows have
/// the same trigger.  This export exposes the active bit and payload identity
/// for one stable storage index without changing production dispatch.
export fn QMK_TestGetRuntimeHotstringDebugAt(
    index_in: i32,
    outAction: *u32,
    outReplacementBytes: *u32,
    outCallbackId: *i32,
    outEnabled: *u32,
    outCtxCount: *u32,
) callconv(.c) i32 {
    outAction.* = 0xFFFF_FFFF;
    outReplacementBytes.* = 0;
    outCallbackId.* = 0;
    outEnabled.* = 0;
    outCtxCount.* = 0;
    if (!compiled_shortcuts_test_observability or index_in < 0) return 0;
    const index: usize = @intCast(index_in);
    if (index >= g_runtimeHotstringLen) return 0;
    const entry = g_runtimeHotstringEntries[index];
    outAction.* = @intFromEnum(entry.action);
    outReplacementBytes.* = @intCast(entry.replacement.len);
    outCallbackId.* = g_runtimeHotstringCallbackIds[index];
    outCtxCount.* = g_runtimeHotstringCtxCount[index];
    const runtime_view = activeRuntimeHotstrings();
    if (index < runtime_view.len)
        outEnabled.* = if (runtime_view.entries[index].options.enabled) 1 else 0;
    return 1;
}

fn utf16ToUtf8Alloc(utf16: []const u16) ![]const u8 {
    if (utf16.len == 0) return "";
    var utf8 = try gAlloc.alloc(u8, utf16.len * 3 + 1);
    errdefer gAlloc.free(utf8);

    var utf8_idx: usize = 0;
    var i: usize = 0;
    while (i < utf16.len) {
        const cp = cp: {
            const w1 = utf16[i];
            i += 1;
            if (w1 >= 0xD800 and w1 <= 0xDBFF and i < utf16.len) {
                const w2 = utf16[i];
                if (w2 >= 0xDC00 and w2 <= 0xDFFF) {
                    i += 1;
                    break :cp (@as(u21, w1 - 0xD800) << 10) + (w2 - 0xDC00) + 0x10000;
                }
            }
            break :cp w1;
        };

        if (cp < 0x80) {
            utf8[utf8_idx] = @intCast(cp);
            utf8_idx += 1;
        } else if (cp < 0x800) {
            utf8[utf8_idx] = @intCast(0xC0 | (cp >> 6));
            utf8[utf8_idx + 1] = @intCast(0x80 | (cp & 0x3F));
            utf8_idx += 2;
        } else if (cp < 0x10000) {
            utf8[utf8_idx] = @intCast(0xE0 | (cp >> 12));
            utf8[utf8_idx + 1] = @intCast(0x80 | ((cp >> 6) & 0x3F));
            utf8[utf8_idx + 2] = @intCast(0x80 | (cp & 0x3F));
            utf8_idx += 3;
        } else {
            utf8[utf8_idx] = @intCast(0xF0 | (cp >> 18));
            utf8[utf8_idx + 1] = @intCast(0x80 | ((cp >> 12) & 0x3F));
            utf8[utf8_idx + 2] = @intCast(0x80 | ((cp >> 6) & 0x3F));
            utf8[utf8_idx + 3] = @intCast(0x80 | (cp & 0x3F));
            utf8_idx += 4;
        }
    }
    utf8[utf8_idx] = 0;
    const result = gAlloc.realloc(utf8, utf8_idx) catch utf8[0..utf8_idx];
    return result;
}

fn runtimeHotstringIdentityMatches(existing: hotstrings.HotstringEntry, trigger: []const u8, options: hotstrings.HotstringOptions) bool {
    if (existing.options.case_sensitive != options.case_sensitive) return false;
    if (existing.options.detect_inside_word != options.detect_inside_word) return false;
    return hotstrings.bytesEqual(existing.trigger, trigger, options.case_sensitive);
}

fn runtimeHotstringContextsEquivalent(a: usize, b: usize) bool {
    const ac: usize = @intCast(g_runtimeHotstringCtxCount[a]);
    const bc: usize = @intCast(g_runtimeHotstringCtxCount[b]);
    if (ac != bc) return false;
    if (ac == 0) return true;
    const as: usize = @intCast(g_runtimeHotstringCtxStart[a]);
    const bs: usize = @intCast(g_runtimeHotstringCtxStart[b]);
    var ai: usize = 0;
    while (ai < ac) : (ai += 1) {
        const ar = g_hsCtxRows[as + ai];
        const at = g_hsCtxTexts[as + ai][0..@as(usize, @intCast(ar.contextLen))];
        var found = false;
        var bi: usize = 0;
        while (bi < bc) : (bi += 1) {
            const br = g_hsCtxRows[bs + bi];
            if (ar.contextKind != br.contextKind or ar.contextNegated != br.contextNegated or ar.specificityMask != br.specificityMask) continue;
            const bt = g_hsCtxTexts[bs + bi][0..@as(usize, @intCast(br.contextLen))];
            if (runtimeContextTextEqual(at, bt)) { found = true; break; }
        }
        if (!found) return false;
    }
    return true;
}

fn runtimeHotstringDuplicateAt(index: usize) bool {
    if (index >= g_runtimeHotstringLen) return false;
    const entry = g_runtimeHotstringEntries[index];
    var i: usize = 0;
    while (i < index) : (i += 1) {
        if (!runtimeHotstringIdentityMatches(g_runtimeHotstringEntries[i], entry.trigger, entry.options)) continue;
        if (g_runtimeHotstringCallbackIds[i] != g_runtimeHotstringCallbackIds[index]) continue;
        if (runtimeHotstringContextsEquivalent(i, index)) return true;
    }
    return false;
}

fn runtimeHotstringOverriddenByRuntime(index: usize) bool {
    if (index >= g_compiledHotstringsLen) return false;
    const compiled = g_runtimeHotstringEntries[index];
    var runtime_index = g_compiledHotstringsLen;
    while (runtime_index < g_runtimeHotstringLen) : (runtime_index += 1) {
        const runtime = g_runtimeHotstringEntries[runtime_index];
        if (!hotstrings.bytesEqual(compiled.trigger, runtime.trigger, false)) continue;
        if (runtimeHotstringContextsEquivalent(index, runtime_index)) return true;
    }
    return false;
}

fn resizeRuntimeHotstringCapacity(new_cap: usize) bool {
    if (new_cap <= g_runtimeHotstringEntries.len) return true;
    const new_entries = gAlloc.alloc(hotstrings.HotstringEntry, new_cap) catch return false;
    const new_triggers = gAlloc.alloc(RuntimeHotstringTrigger, new_cap) catch {
        gAlloc.free(new_entries);
        return false;
    };
    const new_callbacks = gAlloc.alloc(i32, new_cap) catch {
        gAlloc.free(new_entries);
        gAlloc.free(new_triggers);
        return false;
    };
    const new_suspend = gAlloc.alloc(bool, new_cap) catch {
        gAlloc.free(new_entries);
        gAlloc.free(new_triggers);
        gAlloc.free(new_callbacks);
        return false;
    };
    const new_enabled = gAlloc.alloc(bool, new_cap) catch {
        gAlloc.free(new_entries);
        gAlloc.free(new_triggers);
        gAlloc.free(new_callbacks);
        gAlloc.free(new_suspend);
        return false;
    };
    const new_ctx_start = gAlloc.alloc(u32, new_cap) catch {
        gAlloc.free(new_entries);
        gAlloc.free(new_triggers);
        gAlloc.free(new_callbacks);
        gAlloc.free(new_suspend);
        gAlloc.free(new_enabled);
        return false;
    };
    const new_ctx_count = gAlloc.alloc(u32, new_cap) catch {
        gAlloc.free(new_entries);
        gAlloc.free(new_triggers);
        gAlloc.free(new_callbacks);
        gAlloc.free(new_suspend);
        gAlloc.free(new_enabled);
        gAlloc.free(new_ctx_start);
        return false;
    };

    if (g_runtimeHotstringLen != 0) {
        @memcpy(new_entries[0..g_runtimeHotstringLen], g_runtimeHotstringEntries[0..g_runtimeHotstringLen]);
        @memcpy(new_triggers[0..g_runtimeHotstringLen], g_runtimeHotstringTriggerBytes[0..g_runtimeHotstringLen]);
        @memcpy(new_callbacks[0..g_runtimeHotstringLen], g_runtimeHotstringCallbackIds[0..g_runtimeHotstringLen]);
        @memcpy(new_suspend[0..g_runtimeHotstringLen], g_runtimeHotstringSuspendExempt[0..g_runtimeHotstringLen]);
        @memcpy(new_enabled[0..g_runtimeHotstringLen], g_runtimeHotstringUserEnabled[0..g_runtimeHotstringLen]);
        @memcpy(new_ctx_start[0..g_runtimeHotstringLen], g_runtimeHotstringCtxStart[0..g_runtimeHotstringLen]);
        @memcpy(new_ctx_count[0..g_runtimeHotstringLen], g_runtimeHotstringCtxCount[0..g_runtimeHotstringLen]);
        var i: usize = 0;
        while (i < g_runtimeHotstringLen) : (i += 1) {
            const trigger_len = new_entries[i].trigger.len;
            new_entries[i].trigger = new_triggers[i][0..trigger_len];
        }
    }
    if (new_cap > g_runtimeHotstringLen) {
        @memset(new_entries[g_runtimeHotstringLen..new_cap], .{ .trigger = "" });
        @memset(new_triggers[g_runtimeHotstringLen..new_cap], [_]u8{0} ** hotstrings.MAX_HOTSTRING_TRIGGER_BYTES);
        @memset(new_callbacks[g_runtimeHotstringLen..new_cap], 0);
        @memset(new_suspend[g_runtimeHotstringLen..new_cap], false);
        @memset(new_enabled[g_runtimeHotstringLen..new_cap], true);
        @memset(new_ctx_start[g_runtimeHotstringLen..new_cap], 0);
        @memset(new_ctx_count[g_runtimeHotstringLen..new_cap], 0);
    }
    const old_entries = g_runtimeHotstringEntries;
    const old_triggers = g_runtimeHotstringTriggerBytes;
    const old_callbacks = g_runtimeHotstringCallbackIds;
    const old_suspend = g_runtimeHotstringSuspendExempt;
    const old_enabled = g_runtimeHotstringUserEnabled;
    const old_ctx_start = g_runtimeHotstringCtxStart;
    const old_ctx_count = g_runtimeHotstringCtxCount;
    g_runtimeHotstringEntries = new_entries;
    g_runtimeHotstringTriggerBytes = new_triggers;
    g_runtimeHotstringCallbackIds = new_callbacks;
    g_runtimeHotstringSuspendExempt = new_suspend;
    g_runtimeHotstringUserEnabled = new_enabled;
    g_runtimeHotstringCtxStart = new_ctx_start;
    g_runtimeHotstringCtxCount = new_ctx_count;
    retireSlice(hotstrings.HotstringEntry, old_entries);
    retireSlice(RuntimeHotstringTrigger, old_triggers);
    retireSlice(i32, old_callbacks);
    retireSlice(bool, old_suspend);
    retireSlice(bool, old_enabled);
    retireSlice(u32, old_ctx_start);
    retireSlice(u32, old_ctx_count);
    return true;
}

fn ensureRuntimeHotstringCapacity(required: usize) bool {
    if (required <= g_runtimeHotstringEntries.len) return true;
    var new_cap: usize = if (g_runtimeHotstringEntries.len == 0) RUNTIME_HOTSTRING_INITIAL_CAP else g_runtimeHotstringEntries.len * 2;
    while (new_cap < required) : (new_cap *= 2) {}
    return resizeRuntimeHotstringCapacity(new_cap);
}

fn ensureRuntimeHotstringExactAdditionalCapacity(additional: usize) bool {
    if (additional == 0) return true;
    const required = g_runtimeHotstringLen + additional;
    if (required <= g_runtimeHotstringEntries.len) return true;
    return ensureRuntimeHotstringCapacity(required);
}

fn resizeRuntimeHotstringContextCapacity(new_cap: usize) bool {
    if (new_cap <= g_hsCtxRows.len) return true;
    const new_rows = gAlloc.alloc(RuntimeHotstringContext, new_cap) catch return false;
    const new_texts = gAlloc.alloc(RuntimeHotstringContextText, new_cap) catch {
        gAlloc.free(new_rows);
        return false;
    };
    const new_bound = gAlloc.alloc(u32, new_cap) catch {
        gAlloc.free(new_rows);
        gAlloc.free(new_texts);
        return false;
    };
    if (g_hsCtxRowsLen != 0) {
        @memcpy(new_rows[0..g_hsCtxRowsLen], g_hsCtxRows[0..g_hsCtxRowsLen]);
        @memcpy(new_texts[0..g_hsCtxRowsLen], g_hsCtxTexts[0..g_hsCtxRowsLen]);
    }
    if (new_cap > g_hsCtxRowsLen) {
        @memset(new_rows[g_hsCtxRowsLen..new_cap], RuntimeHotstringContext{});
        @memset(new_texts[g_hsCtxRowsLen..new_cap], [_]u16{0} ** RUNTIME_HOTSTRING_CONTEXT_CHARS);
    }
    @memset(new_bound, 0);
    const old_rows = g_hsCtxRows;
    const old_texts = g_hsCtxTexts;
    const old_bound = g_hsContextBoundIdx;
    g_hsCtxRows = new_rows;
    g_hsCtxTexts = new_texts;
    g_hsContextBoundIdx = new_bound;
    retireSlice(RuntimeHotstringContext, old_rows);
    retireSlice(RuntimeHotstringContextText, old_texts);
    retireSlice(u32, old_bound);
    return true;
}

fn ensureRuntimeHotstringContextCapacity(required: usize) bool {
    if (required <= g_hsCtxRows.len) return true;
    var new_cap: usize = if (g_hsCtxRows.len == 0) RUNTIME_HOTSTRING_CONTEXT_INITIAL_CAP else g_hsCtxRows.len * 2;
    while (new_cap < required) : (new_cap *= 2) {}
    return resizeRuntimeHotstringContextCapacity(new_cap);
}

fn ensureRuntimeHotstringContextExactAdditionalCapacity(additional: usize) bool {
    if (additional == 0) return true;
    const required = g_hsCtxRowsLen + additional;
    if (required <= g_hsCtxRows.len) return true;
    return ensureRuntimeHotstringContextCapacity(required);
}

fn ensureRuntimeHotstringActiveBankCapacity(bank_index: u32, required: usize) bool {
    const idx: usize = @intCast(bank_index);
    if (required <= g_runtimeHotstringActiveBanks[idx].len) return true;
    const new_cap = if (required == 0) 1 else required;
    const new_bank = gAlloc.alloc(hotstrings.HotstringEntry, new_cap) catch return false;
    @memset(new_bank, .{ .trigger = "" });
    const old_bank = g_runtimeHotstringActiveBanks[idx];
    g_runtimeHotstringActiveBanks[idx] = new_bank;
    retireSlice(hotstrings.HotstringEntry, old_bank);
    return true;
}

fn rollbackRuntimeHotstring(index: usize) void {
    if (index + 1 != g_runtimeHotstringLen) return;
    if (g_runtimeHotstringEntries[index].replacement.len != 0) {
        gAlloc.free(g_runtimeHotstringEntries[index].replacement);
    }
    g_runtimeHotstringEntries[index] = .{ .trigger = "" };
    g_runtimeHotstringLen -= 1;
}

fn setupRuntimeHotstringBytes(
    trigger: []const u8,
    callbackId: i32,
    optionBits: u32,
    payloadChars: ?[*]const u16,
    payloadCharsLen: u32,
    payloadBase: usize,
) i32 {
    if (trigger.len == 0 or trigger.len > hotstrings.MAX_HOTSTRING_TRIGGER_BYTES) return -1;

    const options = hotstrings.HotstringOptions.fromBits(optionBits);
    if (!ensureRuntimeHotstringCapacity(g_runtimeHotstringLen + 1)) return -2;
    if (!ensureRuntimeCallbackSuspendExemptFor(callbackId, options.suspend_exempt)) return -2;
    const slot: usize = g_runtimeHotstringLen;
    g_runtimeHotstringLen += 1;

    @memcpy(g_runtimeHotstringTriggerBytes[slot][0..trigger.len], trigger);

    var replacement: []const u8 = "";
    var action: hotstrings.HotstringActionKind = .ahk_callback;

    if (callbackId <= NATIVE_PAYLOAD_ID_BASE and payloadChars != null) {
        const global_offset: usize = @intCast(@as(i64, NATIVE_PAYLOAD_ID_BASE) - @as(i64, callbackId));
        if (global_offset >= payloadBase) {
            const payload_offset = global_offset - payloadBase;
            if (payload_offset < payloadCharsLen) {
                var u16_len: usize = 0;
                while (payload_offset + u16_len < payloadCharsLen and payloadChars.?[payload_offset + u16_len] != 0) : (u16_len += 1) {}
                const payload_slice = payloadChars.?[payload_offset .. payload_offset + u16_len];
                if (utf16ToUtf8Alloc(payload_slice)) |utf8_str| {
                    replacement = utf8_str;
                    action = .paste_withbackup;
                } else |_| {}
            }
        }
    }

    g_runtimeHotstringEntries[slot] = .{
        .trigger = g_runtimeHotstringTriggerBytes[slot][0..trigger.len],
        .replacement = replacement,
        .action = action,
        .options = options,
    };
    g_runtimeHotstringCallbackIds[slot] = callbackId;
    g_runtimeHotstringSuspendExempt[slot] = options.suspend_exempt;
    g_runtimeHotstringUserEnabled[slot] = options.enabled;
    if (g_runtimeHotstringCtxCount[slot] != 0) g_hsContextIndexDirty = true;
    g_runtimeHotstringCtxStart[slot] = 0;
    g_runtimeHotstringCtxCount[slot] = 0;
    return @intCast(slot);
}

fn commitRuntimeHotstringCallbackExemption(slot: usize) bool {
    return markRuntimeCallbackSuspendExempt(g_runtimeHotstringCallbackIds[slot], g_runtimeHotstringSuspendExempt[slot]);
}

fn hotstringEntriesNeedNativePayload(records: [*]const u8, count: u32) bool {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        if (records[i * 40 + 37] != 0) return true;
    }
    return false;
}

export fn QMK_ResetHotstringBuffer() callconv(.c) void {
    g_hotstringMatcher.reset();
}

export fn QMK_SetHotstringMouseReset(enabled: i32) callconv(.c) void {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    g_hotstringMouseReset = enabled != 0;
}

export fn QMK_SetHotstringEndChars(end_chars: [*:0]const u16) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    var len: usize = 0;
    while (end_chars[len] != 0 and len < g_runtimeHotstringEndChars.len) : (len += 1) {
        const ch = end_chars[len];
        g_runtimeHotstringEndChars[len] = if (ch <= 0x7f) @intCast(ch) else '?';
    }
    g_runtimeHotstringEndCharsLen = len;
    return @intCast(len);
}

fn setupStaticHotstringCallbackOptions(trigger: [*:0]const u16, callbackId: i32, optionBits: u32) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    var scratch: [hotstrings.MAX_HOTSTRING_TRIGGER_BYTES]u8 = undefined;
    const trigger_len = copyHotstringTriggerUtf16Ascii(trigger, &scratch);
    const slot = setupRuntimeHotstringBytes(scratch[0..trigger_len], callbackId, optionBits, null, 0, 0);
    if (slot < 0) return slot;
    const slot_idx: usize = @intCast(slot);
    if (runtimeHotstringDuplicateAt(slot_idx)) {
        rollbackRuntimeHotstring(slot_idx);
        return -3;
    }
    if (!commitRuntimeHotstringCallbackExemption(slot_idx)) {
        rollbackRuntimeHotstring(slot_idx);
        return -2;
    }
    finishRuntimeHotstringSetup();
    return slot;
}

export fn QMK_SetupHotstrings(
    records: [*]const u8,
    count: u32,
    triggerBytes: [*]const u8,
    triggerBytesLen: u32,
    ctxRecords: [*]const u8,
    ctxCount: u32,
    contextChars: [*]const u16,
    contextCharsLen: u32,
    payloadChars: [*]const u16,
    payloadCharsLen: u32,
) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeHotstringFamily();
    if (!ensureRuntimeHotstringExactAdditionalCapacity(count)) return 0;
    if (!ensureRuntimeHotstringContextExactAdditionalCapacity(ctxCount)) return 0;
    const payload_base = if (payloadCharsLen == 0) g_nativeHotstringPayloads.len else appendNativeHotstringPayloads(payloadChars, payloadCharsLen);
    if (payload_base == NATIVE_PAYLOAD_APPEND_FAILED) return 0;
    if (payloadCharsLen != 0 and g_nativeHotstringPayloads.len != 0) initNativePasteThread();
    return setupHotstringsImpl(records, count, triggerBytes, triggerBytesLen, ctxRecords, ctxCount, contextChars, contextCharsLen, payloadChars, payloadCharsLen, payload_base);
}

/// Higher-level hotstring entries. AHK sends trigger spec, context, action text,
/// and extra options as strings; Zig parses options/context and registers the
/// whole batch with one context rebuild.
/// Record layout (40 bytes):
/// triggerSpec off:u32,len:u16 at 0; context at 8; action at 16; options at 24;
/// callbackId:i32 at 32; suspendExempt:u8 at 36; nativePayload:u8 at 37.
export fn QMK_SetupHotstringEntries(records: [*]const u8, count: u32, textChars: [*]const u16, textCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeHotstringFamily();
    if (!ensureRuntimeHotstringExactAdditionalCapacity(count)) return 0;
    if (!ensureRuntimeHotstringContextExactAdditionalCapacity(count)) return 0;
    const needs_native_payload = hotstringEntriesNeedNativePayload(records, count);
    const payload_base = if (!needs_native_payload or textCharsLen == 0) g_nativeHotstringPayloads.len else appendNativeHotstringPayloads(textChars, textCharsLen);
    if (payload_base == NATIVE_PAYLOAD_APPEND_FAILED) return 0;
    if (needs_native_payload and textCharsLen != 0 and g_nativeHotstringPayloads.len != 0) initNativePasteThread();

    g_hsContextIndexDirty = true;

    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 40;
        const spec_off: usize = @intCast(readU32LE(records, off));
        var spec_len: usize = @intCast(readU16LE(records, off + 4));
        const context_off: usize = @intCast(readU32LE(records, off + 8));
        var context_len: usize = @intCast(readU16LE(records, off + 12));
        const action_off: usize = @intCast(readU32LE(records, off + 16));
        const action_len: usize = @intCast(readU16LE(records, off + 20));
        const options_off: usize = @intCast(readU32LE(records, off + 24));
        var options_len: usize = @intCast(readU16LE(records, off + 28));
        const raw_callback_id = readI32LE(records, off + 32);
        const suspend_exempt = records[off + 36] != 0;
        const native_payload = records[off + 37] != 0;
        if (spec_off > textCharsLen or context_off > textCharsLen or action_off > textCharsLen or options_off > textCharsLen) continue;
        const spec_rem: usize = @intCast(textCharsLen - @as(u32, @intCast(spec_off)));
        const context_rem: usize = @intCast(textCharsLen - @as(u32, @intCast(context_off)));
        const action_rem: usize = @intCast(textCharsLen - @as(u32, @intCast(action_off)));
        const options_rem: usize = @intCast(textCharsLen - @as(u32, @intCast(options_off)));
        if (spec_len > spec_rem) spec_len = spec_rem;
        if (context_len > context_rem) context_len = context_rem;
        if (action_len > action_rem) continue;
        if (native_payload and action_len >= action_rem) continue;
        if (options_len > options_rem) options_len = options_rem;

        const parsed = parseHotstringSpecText16(
            textChars[spec_off..][0..spec_len],
            textChars[options_off..][0..options_len],
            suspend_exempt,
        );
        var scratch: [hotstrings.MAX_HOTSTRING_TRIGGER_BYTES]u8 = undefined;
        const trigger_len = copyHotstringTriggerText16Ascii(parsed.trigger, &scratch);
        if (trigger_len == 0) continue;

        const callback_id = if (native_payload)
            NATIVE_PAYLOAD_ID_BASE - @as(i32, @intCast(payload_base + action_off))
        else
            raw_callback_id;
        if (!native_payload and callback_id < 0) continue;
        const non_global_context_parts = runtimeHotstringNonGlobalContextPartCount(textChars[context_off..][0..context_len]);
        if (!ensureRuntimeHotstringContextExactAdditionalCapacity(non_global_context_parts)) {
            truncateRuntimeHotstringsToPublished();
            return 0;
        }

        const slot = setupRuntimeHotstringBytes(
            scratch[0..trigger_len],
            callback_id,
            parsed.optionBits,
            textChars,
            textCharsLen,
            payload_base,
        );
        if (slot < 0) continue;
        const slot_idx: usize = @intCast(slot);

        var contexts = RuntimeContextListIterator{ .raw = textChars[context_off..][0..context_len] };
        const ctx_start = g_hsCtxRowsLen;
        var ctx_count: u32 = 0;
        var has_global_context = false;
        while (contexts.next()) |context_text| {
            const context = parseRuntimeContextSpec(context_text);
            if (context.kind == RUNTIME_CONTEXT_GLOBAL_KIND) {
                has_global_context = true;
                continue;
            }
            if (!ensureRuntimeHotstringContextCapacity(g_hsCtxRowsLen + 1)) {
                rollbackRuntimeHotstring(slot_idx);
                g_hsCtxRowsLen = ctx_start;
                truncateRuntimeHotstringsToPublished();
                return 0;
            }
            const ctx_slot = g_hsCtxRowsLen;
            if (context.text.len >= RUNTIME_HOTSTRING_CONTEXT_CHARS) continue;
            const text_len = context.text.len;
            @memset(&g_hsCtxTexts[ctx_slot], 0);
            if (text_len != 0) @memcpy(g_hsCtxTexts[ctx_slot][0..text_len], context.text[0..text_len]);
            g_hsCtxRows[ctx_slot] = .{
                .contextKind = context.kind,
                .contextNegated = context.negated,
                .contextLen = @intCast(text_len),
                .specificityMask = runtimeHotkeySpecificityMask(context.kind, g_hsCtxTexts[ctx_slot][0..text_len]),
                .allowed = true,
            };
            g_runtimeHotstringDependencyMask |= g_hsCtxRows[ctx_slot].specificityMask;
            g_hsCtxRowsLen += 1;
            ctx_count += 1;
        }
        if (!has_global_context and ctx_count != 0) {
            g_runtimeHotstringCtxStart[slot_idx] = @intCast(ctx_start);
            g_runtimeHotstringCtxCount[slot_idx] = ctx_count;
        } else if (!has_global_context and non_global_context_parts != 0) {
            rollbackRuntimeHotstring(slot_idx);
            g_hsCtxRowsLen = ctx_start;
            truncateRuntimeHotstringsToPublished();
            return 0;
        }
        if (runtimeHotstringDuplicateAt(slot_idx)) {
            rollbackRuntimeHotstring(slot_idx);
            g_hsCtxRowsLen = ctx_start;
            continue;
        }
        if (!commitRuntimeHotstringCallbackExemption(slot_idx)) {
            rollbackRuntimeHotstring(slot_idx);
            g_hsCtxRowsLen = ctx_start;
            truncateRuntimeHotstringsToPublished();
            return 0;
        }
        loaded += 1;
    }
    finishRuntimeHotstringSetup();
    return loaded;
}

/// Typed-cell hotstring entries. AHK sends row cells; Zig owns the hotstring
/// row grammar while sharing the setup-time 16-byte cell envelope.
/// Record layout (84 bytes): cellCount:u8 at 0; five 16-byte cells at 4.
export fn QMK_SetupHotstringCellEntries(records: [*]const u8, count: u32, textChars: [*]const u16, textCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeHotstringFamily();
    if (!ensureRuntimeHotstringExactAdditionalCapacity(count)) return 0;
    if (!ensureRuntimeHotstringContextExactAdditionalCapacity(count)) return 0;
    const payload_base = if (textCharsLen == 0) g_nativeHotstringPayloads.len else appendNativeHotstringPayloads(textChars, textCharsLen);
    if (payload_base == NATIVE_PAYLOAD_APPEND_FAILED) return 0;
    if (textCharsLen != 0 and g_nativeHotstringPayloads.len != 0) initNativePasteThread();

    g_hsContextIndexDirty = true;

    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 84;
        const raw_cell_count = records[off];
        if (raw_cell_count < 2) continue;
        const cell_count: usize = @min(@as(usize, @intCast(raw_cell_count)), 5);
        var cells = [_]RuntimeHotkeyCell{.{}} ** 5;
        var c: usize = 0;
        var valid = true;
        var suspend_exempt = false;
        while (c < cell_count) : (c += 1) {
            cells[c] = readRuntimeHotkeyCell(records, off, c, textChars, textCharsLen) orelse {
                valid = false;
                break;
            };
            suspend_exempt = suspend_exempt or ((cells[c].flags & 1) != 0);
        }
        if (!valid or cells[0].tag != HOTKEY_CELL_TEXT) continue;

        var context_text: []const u16 = &[_]u16{};
        var action_cell: RuntimeHotkeyCell = .{};
        var options_text: []const u16 = &[_]u16{};
        if (cell_count == 2) {
            action_cell = cells[1];
        } else if (cell_count == 3 and (cells[1].tag == HOTKEY_CELL_CALLBACK or cells[1].tag == HOTKEY_CELL_TEXT) and runtimeHotkeyCellIsExplicitBool(cells[2])) {
            action_cell = cells[1];
            suspend_exempt = suspend_exempt or runtimeHotkeyBoolCell(cells[2]);
        } else {
            if (cells[1].tag != HOTKEY_CELL_TEXT) continue;
            context_text = cells[1].text;
            action_cell = cells[2];
            if (cell_count >= 4) {
                if (cell_count == 4 and runtimeHotkeyCellIsExplicitBool(cells[3])) {
                    suspend_exempt = suspend_exempt or runtimeHotkeyBoolCell(cells[3]);
                } else {
                    if (cells[3].tag != HOTKEY_CELL_TEXT) continue;
                    options_text = cells[3].text;
                }
            }
            if (cell_count >= 5) suspend_exempt = suspend_exempt or runtimeHotkeyBoolCell(cells[4]);
        }
        if (!(action_cell.tag == HOTKEY_CELL_CALLBACK or action_cell.tag == HOTKEY_CELL_TEXT)) continue;

        const parsed = parseHotstringSpecText16(cells[0].text, options_text, suspend_exempt);
        var scratch: [hotstrings.MAX_HOTSTRING_TRIGGER_BYTES]u8 = undefined;
        const trigger_len = copyHotstringTriggerText16Ascii(parsed.trigger, &scratch);
        if (trigger_len == 0) continue;

        const callback_id = switch (action_cell.tag) {
            HOTKEY_CELL_CALLBACK => action_cell.callbackId,
            HOTKEY_CELL_TEXT => NATIVE_PAYLOAD_ID_BASE - @as(i32, @intCast(payload_base + action_cell.textOffset)),
            else => -1,
        };
        if (action_cell.tag == HOTKEY_CELL_CALLBACK and callback_id < 0) continue;
        const non_global_context_parts = runtimeHotstringNonGlobalContextPartCount(context_text);
        if (!ensureRuntimeHotstringContextExactAdditionalCapacity(non_global_context_parts)) {
            truncateRuntimeHotstringsToPublished();
            return 0;
        }

        const slot = setupRuntimeHotstringBytes(
            scratch[0..trigger_len],
            callback_id,
            parsed.optionBits,
            textChars,
            textCharsLen,
            payload_base,
        );
        if (slot < 0) continue;
        const slot_idx: usize = @intCast(slot);

        var contexts = RuntimeContextListIterator{ .raw = context_text };
        const ctx_start = g_hsCtxRowsLen;
        var ctx_count: u32 = 0;
        var has_global_context = false;
        while (contexts.next()) |context_part| {
            const context = parseRuntimeContextSpec(context_part);
            if (context.kind == RUNTIME_CONTEXT_GLOBAL_KIND) {
                has_global_context = true;
                continue;
            }
            if (!ensureRuntimeHotstringContextCapacity(g_hsCtxRowsLen + 1)) {
                rollbackRuntimeHotstring(slot_idx);
                g_hsCtxRowsLen = ctx_start;
                truncateRuntimeHotstringsToPublished();
                return 0;
            }
            const ctx_slot = g_hsCtxRowsLen;
            if (context.text.len >= RUNTIME_HOTSTRING_CONTEXT_CHARS) continue;
            const text_len = context.text.len;
            @memset(&g_hsCtxTexts[ctx_slot], 0);
            if (text_len != 0) @memcpy(g_hsCtxTexts[ctx_slot][0..text_len], context.text[0..text_len]);
            g_hsCtxRows[ctx_slot] = .{
                .contextKind = context.kind,
                .contextNegated = context.negated,
                .contextLen = @intCast(text_len),
                .specificityMask = runtimeHotkeySpecificityMask(context.kind, g_hsCtxTexts[ctx_slot][0..text_len]),
                .allowed = true,
            };
            g_runtimeHotstringDependencyMask |= g_hsCtxRows[ctx_slot].specificityMask;
            g_hsCtxRowsLen += 1;
            ctx_count += 1;
        }
        if (!has_global_context and ctx_count != 0) {
            g_runtimeHotstringCtxStart[slot_idx] = @intCast(ctx_start);
            g_runtimeHotstringCtxCount[slot_idx] = ctx_count;
        } else if (!has_global_context and non_global_context_parts != 0) {
            rollbackRuntimeHotstring(slot_idx);
            g_hsCtxRowsLen = ctx_start;
            truncateRuntimeHotstringsToPublished();
            return 0;
        }
        if (runtimeHotstringDuplicateAt(slot_idx)) {
            rollbackRuntimeHotstring(slot_idx);
            g_hsCtxRowsLen = ctx_start;
            continue;
        }
        if (!commitRuntimeHotstringCallbackExemption(slot_idx)) {
            rollbackRuntimeHotstring(slot_idx);
            g_hsCtxRowsLen = ctx_start;
            truncateRuntimeHotstringsToPublished();
            return 0;
        }
        loaded += 1;
    }
    finishRuntimeHotstringSetup();
    return loaded;
}
/// Reports native paste activity so a silent clipboard failure stays visible.
/// `payloadChars` is the buffer size including its terminator.
export fn QMK_GetNativePasteStats(
    outFired: *u32,
    outDropped: *u32,
    outFailed: *u32,
    outPayloadChars: *u32,
) callconv(.c) void {
    outFired.* = @atomicLoad(u32, &g_nativePasteFired, .monotonic);
    outDropped.* = @atomicLoad(u32, &g_nativePasteDropped, .monotonic);
    outFailed.* = @atomicLoad(u32, &g_nativePasteFailed, .monotonic);
    outPayloadChars.* = @intCast(g_nativeHotstringPayloads.len + g_nativeHotkeyPayloads.len);
}

/// Test-only count for calls that reach the existing direct key-send helper.
export fn QMK_TestGetDirectKeySendCount() callconv(.c) u32 {
    if (!compiled_shortcuts_test_observability) return 0;
    return @atomicLoad(u32, &g_testDirectKeySendCount, .monotonic);
}

export fn QMK_TestGetLastDirectKeyVK() callconv(.c) i32 {
    if (!compiled_shortcuts_test_observability) return -1;
    return g_testLastDirectKeyVK;
}

export fn QMK_TestGetLastDirectModifierMask() callconv(.c) u16 {
    if (!compiled_shortcuts_test_observability) return 0;
    return g_testLastDirectModifierMask;
}


/// Copies the matcher's committed-character buffer out as UTF-16 so a caller
/// can see exactly which keystrokes reached the hotstring engine. The buffer
/// is only fed from the key-up direct-tap path, so a key emitted through any
/// other route is invisible here, which is what this export exists to expose.
export fn QMK_GetHotstringBuffer(
    outText: [*]u16,
    outCapacityChars: u32,
) callconv(.c) i32 {
    const view = g_hotstringMatcher.view();
    if (outCapacityChars == 0) return @intCast(view.len);
    const limit = @min(view.len, @as(usize, outCapacityChars) - 1);
    for (view[0..limit], 0..) |byte, i| {
        outText[i] = byte;
    }
    outText[limit] = 0;
    return @intCast(view.len);
}

fn setupHotstringsImpl(
    records: [*]const u8,
    count: u32,
    triggerBytes: [*]const u8,
    triggerBytesLen: u32,
    ctxRecords: [*]const u8,
    ctxCount: u32,
    contextChars: [*]const u16,
    contextCharsLen: u32,
    payloadChars: ?[*]const u16,
    payloadCharsLen: u32,
    payloadBase: usize,
) i32 {
    if (!ensureRuntimeHotstringExactAdditionalCapacity(count)) return 0;
    if (!ensureRuntimeHotstringContextExactAdditionalCapacity(ctxCount)) return 0;
    // Append context rows for this batch; prior setup calls remain registered.
    const ctx_base: usize = g_hsCtxRowsLen;
    var c: usize = 0;
    while (c < ctxCount) : (c += 1) {
        const off = c * 12;
        const text_offset: usize = @intCast(readU32LE(ctxRecords, off));
        var text_len: usize = @intCast(readU16LE(ctxRecords, off + 4));
        const context_kind = ctxRecords[off + 6];
        const negated = ctxRecords[off + 7] != 0;
        if (text_offset > contextCharsLen) continue;
        if (!ensureRuntimeHotstringContextCapacity(g_hsCtxRowsLen + 1)) {
            g_hsCtxRowsLen = ctx_base;
            truncateRuntimeHotstringsToPublished();
            return 0;
        }
        const remaining: usize = @intCast(contextCharsLen - @as(u32, @intCast(text_offset)));
        if (text_len > remaining) text_len = remaining;
        if (text_len >= RUNTIME_HOTSTRING_CONTEXT_CHARS) continue;
        const slot = g_hsCtxRowsLen;
        @memset(&g_hsCtxTexts[slot], 0);
        if (text_len != 0) @memcpy(g_hsCtxTexts[slot][0..text_len], contextChars[text_offset..][0..text_len]);
        g_hsCtxRows[slot] = .{
            .contextKind = context_kind,
            .contextNegated = negated,
            .contextLen = @intCast(text_len),
            .specificityMask = runtimeHotkeySpecificityMask(context_kind, g_hsCtxTexts[slot][0..text_len]),
            .allowed = true,
        };
        g_runtimeHotstringDependencyMask |= g_hsCtxRows[slot].specificityMask;
        g_hsCtxRowsLen += 1;
    }

    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 20;
        const trigger_off = readU32LE(records, off);
        const trigger_len = readU16LE(records, off + 4);
        const ctx_start = readU16LE(records, off + 6);
        const callback_id = rebaseNativePayloadId(readI32LE(records, off + 8), payloadBase);
        const option_bits = readU32LE(records, off + 12);
        const ctx_len = readU16LE(records, off + 16);
        if (trigger_len == 0) continue;
        if (trigger_off > triggerBytesLen) continue;
        if (@as(u32, trigger_len) > triggerBytesLen - trigger_off) continue;
        const start: usize = @intCast(trigger_off);
        const len: usize = @intCast(trigger_len);
        const slot = setupRuntimeHotstringBytes(triggerBytes[start..][0..len], callback_id, option_bits, payloadChars, payloadCharsLen, payloadBase);
        if (slot < 0) continue;
        const slot_idx: usize = @intCast(slot);
        if (ctx_len != 0 and ctx_base + @as(usize, ctx_start) < g_hsCtxRowsLen) {
            g_runtimeHotstringCtxStart[slot_idx] = @intCast(ctx_base + @as(usize, ctx_start));
            g_runtimeHotstringCtxCount[slot_idx] = ctx_len;
        }
        if (runtimeHotstringDuplicateAt(slot_idx)) {
            rollbackRuntimeHotstring(slot_idx);
            continue;
        }
        if (!commitRuntimeHotstringCallbackExemption(slot_idx)) {
            rollbackRuntimeHotstring(slot_idx);
            truncateRuntimeHotstringsToPublished();
            return 0;
        }
        loaded += 1;
    }
    finishRuntimeHotstringSetup();
    return loaded;
}

fn setRuntimeHotstringIdentityEnabled(trigger: []const u8, options: hotstrings.HotstringOptions, toggle: i32) i32 {
    var first_index: i32 = -1;
    var next_enabled = false;
    var i: usize = 0;
    while (i < g_runtimeHotstringLen) : (i += 1) {
        if (!runtimeHotstringIdentityMatches(g_runtimeHotstringEntries[i], trigger, options)) continue;
        if (first_index < 0) {
            first_index = @intCast(i);
            next_enabled = switch (toggle) {
                -1 => !g_runtimeHotstringUserEnabled[i],
                0 => false,
                else => true,
            };
        }
        // Context alternatives are one logical hotstring identity. Enabling or
        // disabling by trigger applies to every appended contextual variant.
        g_runtimeHotstringUserEnabled[i] = next_enabled;
    }
    if (first_index < 0) return -2;
    finishRuntimeHotstringSetup();
    return first_index;
}

export fn QMK_SetRuntimeHotstringEnabled(trigger: [*:0]const u16, optionBits: u32, toggle: i32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    var scratch: [hotstrings.MAX_HOTSTRING_TRIGGER_BYTES]u8 = undefined;
    const trigger_len = copyHotstringTriggerUtf16Ascii(trigger, &scratch);
    if (trigger_len == 0) return -1;
    const options = hotstrings.HotstringOptions.fromBits(optionBits);
    return setRuntimeHotstringIdentityEnabled(scratch[0..trigger_len], options, toggle);
}

export fn QMK_SetRuntimeHotstringEnabledEntry(triggerSpec: [*:0]const u16, toggle: i32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    const spec = wideZSpan(triggerSpec);
    const parsed = parseHotstringSpecText16(spec, &[_]u16{}, false);
    var scratch: [hotstrings.MAX_HOTSTRING_TRIGGER_BYTES]u8 = undefined;
    const trigger_len = copyHotstringTriggerText16Ascii(parsed.trigger, &scratch);
    if (trigger_len == 0) return -1;
    const options = hotstrings.HotstringOptions.fromBits(parsed.optionBits);
    return setRuntimeHotstringIdentityEnabled(scratch[0..trigger_len], options, toggle);
}

fn parseToggleText16(text: []const u16) i32 {
    const value = trimSpaces16(text);
    if (equalsAsciiIgnoreCase16(value, "toggle") or equalsAsciiIgnoreCase16(value, "-1")) return -1;
    if (equalsAsciiIgnoreCase16(value, "off") or equalsAsciiIgnoreCase16(value, "0") or equalsAsciiIgnoreCase16(value, "false")) return 0;
    return 1;
}

export fn QMK_SetRuntimeHotstringEnabledToggleEntry(triggerSpec: [*:0]const u16, toggleText: [*:0]const u16) callconv(.c) i32 {
    return QMK_SetRuntimeHotstringEnabledEntry(triggerSpec, parseToggleText16(wideZSpan(toggleText)));
}

fn setupStaticHotstringCallbackEx(trigger: [*:0]const u16, callbackId: i32) i32 {
    return setupStaticHotstringCallbackOptions(trigger, callbackId, (hotstrings.HotstringOptions{}).toBits());
}

fn setupStaticHotstringCallback(trigger: [*:0]const u16, callbackId: i32) void {
    _ = setupStaticHotstringCallbackEx(trigger, callbackId);
}

// Register a modifier double-tap callback for the exact physical side.
fn setupStaticDoubleTapText(key: [*:0]const u16, callbackId: i32) void {
    const vk = getVKFromName(key);
    if (vk == 0) return;
    if (vk >= 0 and vk < VK_COUNT) g_modDtFlat[@intCast(vk)] = callbackId;
    markKeyGateDirty();
    refreshReplayKeyGate();
}
fn setupInternalComboText(pk: [*:0]const u16, sk: [*:0]const u16, modstr: [*:0]const u16, target: [*:0]const u16, is_instant: bool) void {
    const pkVK = getVKFromName(pk);
    const skVK = getVKFromName(sk);
    if (pkVK == 0 or skVK == 0) return;
    const targetVK = getVKFromName(target);
    if (targetVK == 0) return;
    const mask = parseModifierMask(modstr);
    setupInternalComboVK(pkVK, skVK, targetVK, mask, is_instant);
    markKeyGateDirty();
    refreshReplayKeyGate();
}
// 3- or 4-key chord ? single internal remap. Keys are sorted at registration
// so lookup order is always canonical regardless of call order.
fn setupInternalChordText(k1: [*:0]const u16, k2: [*:0]const u16, k3: [*:0]const u16, k4: [*:0]const u16, modstr: [*:0]const u16, target: [*:0]const u16) void {
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
    if (!chordHotPut(.{
        .key = chordKey,
        .targetVK = targetVK,
        .callbackId = 0,
        .modMask = mask,
        .keyCount = @intCast(vkCount),
        .kind = @intFromEnum(ChordHotKind.internal),
    })) return;
    g_hasInternalChords = true;
    g_hasAnyChord = true;
    for (0..vkCount) |ci| if (vks[ci] >= 0 and vks[ci] < VK_COUNT) {
        g_chordParticipantFlat[@intCast(vks[ci])] = true;
    };
    markKeyGateDirty();
    refreshReplayKeyGate();
}
// External chord: queues a PendingCallback (type 5) with the given callbackId so AHK can handle it.
// Pass "" for k4/k5 when registering fewer than 5 keys.
fn setupChordVKs(rawVks: [5]i32, callbackId: i32) void {
    if (rawVks[0] == 0 or rawVks[1] == 0) return;
    var vks: [5]i32 = [_]i32{0} ** 5;
    var vkCount: usize = 0;
    for (rawVks) |vk| {
        if (vk != 0) {
            vks[vkCount] = vk;
            vkCount += 1;
        }
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
    if (!ensureStaticExtChordCacheCapacity(g_extChordCacheLen + 1)) return;
    if (!chordHotPut(.{
        .key = chordKey,
        .targetVK = 0,
        .callbackId = callbackId,
        .modMask = 0,
        .keyCount = @intCast(vkCount),
        .kind = @intFromEnum(ChordHotKind.external),
    })) return;
    g_hasExternalChords = true;
    g_hasAnyChord = true;
    var entry = ExtChordCacheEntry{ .keyCount = @intCast(vkCount) };
    var mask: u16 = 0;
    for (0..vkCount) |ci| {
        entry.vks[ci] = vks[ci];
        if (vks[ci] >= 0 and vks[ci] < VK_COUNT) {
            mask |= @as(u16, @intCast(g_key_virtual_modifier_mask[@intCast(vks[ci])]));
        }
    }
    entry.modMask = mask;
    g_extChordCache[g_extChordCacheLen] = entry;
    g_extChordCacheLen += 1;
    for (0..vkCount) |ci| if (vks[ci] >= 0 and vks[ci] < VK_COUNT) {
        g_chordParticipantFlat[@intCast(vks[ci])] = true;
    };
}
fn appendRuntimeChord(raw_in: [5]i32, row_in: RuntimeChord, context_text: []const u16) bool {
    if (!ensureRuntimeChordCapacity(g_runtimeChordsLen + 1)) return false;
    var raw_vks = raw_in;
    if (raw_vks[0] == 0 or raw_vks[1] == 0) return false;
    var row = row_in;
    if (row.mode > 1) return false;
    if (row.mode == 0 and row.callbackId < 0 and !isCompiledZigCallbackId(row.callbackId)) return false;
    if (row.mode == 1 and row.targetVK == 0) return false;
    if (!ensureRuntimeCallbackSuspendExemptFor(row.callbackId, row.suspendExempt)) return false;
    sortSmall5(&raw_vks, raw_vks.len);
    for (raw_vks) |vk| {
        if (vk == 0) continue;
        row.vks[@intCast(row.keyCount)] = vk;
        row.keyCount += 1;
    }
    if (row.keyCount < 2) return false;
    row.key = @as(u64, @intCast(row.vks[0])) | (@as(u64, @intCast(row.vks[1])) << 16);
    if (row.keyCount >= 3) row.key |= (@as(u64, @intCast(row.vks[2])) << 32);
    if (row.keyCount >= 4) row.key |= (@as(u64, @intCast(row.vks[3])) << 48);
    if (row.keyCount >= 5) row.key ^= @as(u64, @intCast(row.vks[4]));

    var existing_i: usize = 0;
    while (existing_i < g_runtimeChordsLen) : (existing_i += 1) {
        const existing = g_runtimeChords[existing_i];
        if (existing.key != row.key or existing.contextKind != row.contextKind or existing.contextNegated != row.contextNegated) continue;
        if (existing.callbackId != row.callbackId or existing.targetVK != row.targetVK or
            existing.modMask != row.modMask or existing.mode != row.mode or
            existing.suspendExempt != row.suspendExempt) continue;
        if (runtimeContextTextEqual(g_runtimeChordTexts[existing_i][0..@as(usize, @intCast(existing.contextLen))], context_text)) return false;
    }

    if (context_text.len >= RUNTIME_CHORD_CONTEXT_CHARS) return false;
    const text_len = context_text.len;
    row.contextLen = @intCast(text_len);
    const slot = g_runtimeChordsLen;
    @memset(&g_runtimeChordTexts[slot], 0);
    if (text_len != 0) @memcpy(g_runtimeChordTexts[slot][0..text_len], context_text[0..text_len]);
    row.specificityMask = runtimeHotkeySpecificityMask(row.contextKind, g_runtimeChordTexts[slot][0..text_len]);
    g_runtimeChords[slot] = row;
    if (row.specificityMask != 0) {
        for (row.vks[0..@as(usize, @intCast(row.keyCount))]) |vk| {
            if (vk >= 0 and vk < VK_COUNT) g_runtimeChordContextParticipant[@intCast(vk)] = true;
        }
    }
    _ = markRuntimeCallbackSuspendExempt(row.callbackId, row.suspendExempt);
    g_runtimeChordDependencyMask |= row.specificityMask;
    g_runtimeChordsLen += 1;
    return true;
}

fn ensureRuntimeChordCapacity(required: usize) bool {
    if (required <= g_runtimeChordsCap) return true;
    var new_cap: usize = if (g_runtimeChordsCap == 0) RUNTIME_CHORD_INITIAL_CAP else g_runtimeChordsCap * 2;
    while (new_cap < required) : (new_cap *= 2) {}

    const new_chords = gAlloc.alloc(RuntimeChord, new_cap) catch return false;
    const new_texts = gAlloc.alloc(RuntimeChordText, new_cap) catch {
        gAlloc.free(new_chords);
        return false;
    };

    if (g_runtimeChordsLen != 0) {
        @memcpy(new_chords[0..g_runtimeChordsLen], g_runtimeChords[0..g_runtimeChordsLen]);
        @memcpy(new_texts[0..g_runtimeChordsLen], g_runtimeChordTexts[0..g_runtimeChordsLen]);
    }
    if (new_cap > g_runtimeChordsLen) {
        @memset(new_chords[g_runtimeChordsLen..new_cap], RuntimeChord{});
        @memset(new_texts[g_runtimeChordsLen..new_cap], [_]u16{0} ** RUNTIME_CHORD_CONTEXT_CHARS);
    }

    const old_chords = g_runtimeChords;
    const old_texts = g_runtimeChordTexts;
    g_runtimeChords = new_chords;
    g_runtimeChordTexts = new_texts;
    g_runtimeChordsCap = new_cap;
    retireSlice(RuntimeChord, old_chords);
    retireSlice(RuntimeChordText, old_texts);
    return true;
}

export fn QMK_SetupChords(records: [*]const u8, count: u32, contextChars: [*]const u16, contextCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeChordFamily();
    if (!ensureRuntimeChordCapacity(g_runtimeChordsLen + @as(usize, @intCast(count)))) return 0;
    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 48;
        const raw_vks = [_]i32{
            readI32LE(records, off),
            readI32LE(records, off + 4),
            readI32LE(records, off + 8),
            readI32LE(records, off + 12),
            readI32LE(records, off + 16),
        };
        if (raw_vks[0] == 0 or raw_vks[1] == 0) continue;
        const row = RuntimeChord{
            .callbackId = readI32LE(records, off + 20),
            .targetVK = readI32LE(records, off + 24),
            .modMask = readU16LE(records, off + 28),
            .mode = records[off + 30],
            .contextKind = records[off + 31],
            .contextNegated = records[off + 32] != 0,
            .suspendExempt = records[off + 33] != 0,
        };

        const text_offset: usize = @intCast(readU32LE(records, off + 36));
        var text_len: usize = @intCast(readU16LE(records, off + 40));
        if (text_offset > contextCharsLen) continue;
        const remaining: usize = @intCast(contextCharsLen - @as(u32, @intCast(text_offset)));
        if (text_len > remaining) text_len = remaining;
        if (text_len >= RUNTIME_CHORD_CONTEXT_CHARS) continue;
        if (!ensureRuntimeCallbackSuspendExemptFor(row.callbackId, row.suspendExempt)) {
            truncateRuntimeChordsToPublished();
            return 0;
        }
        if (appendRuntimeChord(raw_vks, row, contextChars[text_offset..][0..text_len])) loaded += 1;
    }
    finishRuntimeChordSetup();
    return loaded;
}
/// Higher-level chord entries. AHK sends up to five key strings plus
/// context/mode/mod/target strings and an optional callback id.
/// Record layout (80 bytes): five key string pairs at offsets 0,8,16,24,32;
/// callbackId:i32 at 40; targetOff:u32,targetLen:u16 at 44; mode at 52;
/// mod at 60; suspendExempt:u8 at 66; context at 68.
const InternalSendTarget = struct {
    target_vk: i32,
    mod_mask: u16,
};

fn chordModeRequiresSendDirectSpec(mode_text: []const u16) bool {
    return equalsAsciiIgnoreCase16(trimSpaces16(mode_text), "sendkeydirect");
}

fn comboModeRequiresSendDirectSpec(mode_text: []const u16) bool {
    const mode = trimSpaces16(mode_text);
    return equalsAsciiIgnoreCase16(mode, "sendkeydirect") or equalsAsciiIgnoreCase16(mode, "sendkeydirectinstant");
}

fn parseSendKeyDirectInternalTarget(target_text: []const u16, mod_text: []const u16) ?InternalSendTarget {
    const mod_mask = parseModifierMaskText16(mod_text);
    if (parseSendDirectSpecText16(target_text)) |parsed| {
        return .{ .target_vk = parsed.vk, .mod_mask = mod_mask | parsed.mods };
    }
    return null;
}

fn parseLegacyInternalTarget(target_text: []const u16, mod_text: []const u16) InternalSendTarget {
    return .{ .target_vk = getVKFromText16(target_text), .mod_mask = parseModifierMaskText16(mod_text) };
}

export fn QMK_SetupChordEntries(records: [*]const u8, count: u32, textChars: [*]const u16, textCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeChordFamily();
    if (!ensureRuntimeChordCapacity(g_runtimeChordsLen + @as(usize, @intCast(count)))) return 0;
    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 80;
        var raw_vks = [_]i32{0} ** 5;
        var valid_keys = true;
        var ki: usize = 0;
        while (ki < 5) : (ki += 1) {
            const field = off + ki * 8;
            const key_off: usize = @intCast(readU32LE(records, field));
            var key_len: usize = @intCast(readU16LE(records, field + 4));
            if (key_off > textCharsLen) {
                valid_keys = false;
                break;
            }
            const rem: usize = @intCast(textCharsLen - @as(u32, @intCast(key_off)));
            if (key_len > rem) key_len = rem;
            raw_vks[ki] = if (key_len == 0) 0 else getVKFromText16(textChars[key_off..][0..key_len]);
        }
        if (!valid_keys) continue;
        const callback_id = readI32LE(records, off + 40);
        const target_off: usize = @intCast(readU32LE(records, off + 44));
        var target_len: usize = @intCast(readU16LE(records, off + 48));
        const mode_off: usize = @intCast(readU32LE(records, off + 52));
        var mode_len: usize = @intCast(readU16LE(records, off + 56));
        const mod_off: usize = @intCast(readU32LE(records, off + 60));
        var mod_len: usize = @intCast(readU16LE(records, off + 64));
        const suspend_exempt = records[off + 66] != 0;
        const context_off: usize = @intCast(readU32LE(records, off + 68));
        var context_len: usize = @intCast(readU16LE(records, off + 72));
        if (target_off > textCharsLen or mode_off > textCharsLen or mod_off > textCharsLen or context_off > textCharsLen) continue;
        const target_rem: usize = @intCast(textCharsLen - @as(u32, @intCast(target_off)));
        const mode_rem: usize = @intCast(textCharsLen - @as(u32, @intCast(mode_off)));
        const mod_rem: usize = @intCast(textCharsLen - @as(u32, @intCast(mod_off)));
        const context_rem: usize = @intCast(textCharsLen - @as(u32, @intCast(context_off)));
        if (target_len > target_rem) target_len = target_rem;
        if (mode_len > mode_rem) mode_len = mode_rem;
        if (mod_len > mod_rem) mod_len = mod_rem;
        if (context_len > context_rem) context_len = context_rem;
        const mode_text = textChars[mode_off..][0..mode_len];
        const mod_text = textChars[mod_off..][0..mod_len];
        const mode = parseChordModeText16(mode_text);
        if (mode == 255) continue;
        const parsed_send = if (chordModeRequiresSendDirectSpec(mode_text))
            parseSendKeyDirectInternalTarget(textChars[target_off..][0..target_len], mod_text) orelse continue
        else
            parseLegacyInternalTarget(textChars[target_off..][0..target_len], mod_text);
        const target_vk = if (mode == 1) parsed_send.target_vk else 0;
        const mod_mask = if (mode == 1) parsed_send.mod_mask else parseModifierMaskText16(mod_text);
        const context_parts = runtimeContextPartCount(textChars[context_off..][0..context_len]);
        if (!ensureRuntimeChordCapacity(g_runtimeChordsLen + context_parts) or
            !ensureRuntimeCallbackSuspendExemptFor(callback_id, suspend_exempt))
        {
            truncateRuntimeChordsToPublished();
            return 0;
        }
        var contexts = RuntimeContextListIterator{ .raw = textChars[context_off..][0..context_len] };
        var row_loaded = false;
        while (contexts.next()) |context_text| {
            const context = parseRuntimeContextSpec(context_text);
            if (appendRuntimeChord(raw_vks, .{
                .callbackId = callback_id,
                .targetVK = target_vk,
                .modMask = mod_mask,
                .mode = mode,
                .contextKind = context.kind,
                .contextNegated = context.negated,
                .suspendExempt = suspend_exempt,
            }, context.text)) row_loaded = true;
        }
        if (row_loaded) loaded += 1;
    }
    finishRuntimeChordSetup();
    return loaded;
}

fn chordParseKeysFromDelimitedText(raw: []const u16) [5]i32 {
    var raw_vks = [_]i32{0} ** 5;
    var key_index: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= raw.len and key_index < 5) : (i += 1) {
        if (i == raw.len or raw[i] == 0x001F) {
            const part = trimSpaces16(raw[start..i]);
            if (part.len != 0) {
                raw_vks[key_index] = getVKFromText16(part);
                key_index += 1;
            }
            start = i + 1;
        }
    }
    return raw_vks;
}

fn chordCellIsAction(cell: RuntimeHotkeyCell) bool {
    return cell.tag == HOTKEY_CELL_CALLBACK or cell.tag == HOTKEY_CELL_TEXT;
}

fn chordCellLooksBool(cell: RuntimeHotkeyCell) bool {
    if (runtimeHotkeyCellIsExplicitBool(cell)) return true;
    if (cell.tag != HOTKEY_CELL_TEXT) return false;
    const text = trimSpaces16(cell.text);
    if (text.len == 0) return false;
    if (text.len == 1 and (text[0] == '0' or text[0] == '1')) return true;
    return equalsAsciiIgnoreCase16(text, "true") or
        equalsAsciiIgnoreCase16(text, "false") or
        equalsAsciiIgnoreCase16(text, "yes") or
        equalsAsciiIgnoreCase16(text, "no") or
        equalsAsciiIgnoreCase16(text, "on") or
        equalsAsciiIgnoreCase16(text, "off");
}

fn chordBuildRowFromCells(cells: []const RuntimeHotkeyCell, payload_base: usize) ?struct {
    raw_vks: [5]i32,
    context_text: []const u16,
    callback_id: i32,
    target_vk: i32,
    mod_mask: u16,
    mode: u8,
    suspend_exempt: bool,
} {
    if (cells.len < 2 or cells[0].tag != HOTKEY_CELL_TEXT) return null;
    var raw_vks = [_]i32{0} ** 5;
    var index: usize = 0;
    var context_text: []const u16 = &[_]u16{};
    var mode_text: []const u16 = &[_]u16{};
    var mod_text: []const u16 = &[_]u16{};
    var action_cell: RuntimeHotkeyCell = .{};
    var suspend_exempt = false;
    for (cells) |cell| suspend_exempt = suspend_exempt or ((cell.flags & 1) != 0);

    if (containsChar16(cells[0].text, 0x001F)) {
        raw_vks = chordParseKeysFromDelimitedText(cells[0].text);
        index = 1;
        if (index + 1 < cells.len and cells[index].tag == HOTKEY_CELL_TEXT and chordCellIsAction(cells[index + 1])) {
            context_text = cells[index].text;
            index += 1;
        }
        if (index >= cells.len or !chordCellIsAction(cells[index])) return null;
        action_cell = cells[index];
        index += 1;
    } else if (cells.len >= 7) {
        var key_i: usize = 0;
        while (key_i < 5) : (key_i += 1) {
            if (cells[key_i].tag != HOTKEY_CELL_TEXT) return null;
            raw_vks[key_i] = getVKFromText16(cells[key_i].text);
        }
        if (cells[5].tag != HOTKEY_CELL_TEXT or !chordCellIsAction(cells[6])) return null;
        context_text = cells[5].text;
        action_cell = cells[6];
        index = 7;
    } else {
        var key_i: usize = 0;
        while (index < cells.len and key_i < 5) {
            if (chordCellIsAction(cells[index]) and cells[index].tag != HOTKEY_CELL_TEXT) break;
            if (index + 1 == cells.len) break;
            if (cells[index].tag != HOTKEY_CELL_TEXT) return null;
            raw_vks[key_i] = getVKFromText16(cells[index].text);
            key_i += 1;
            index += 1;
            if (index < cells.len and cells[index].tag == HOTKEY_CELL_CALLBACK) break;
        }
        if (index >= cells.len or !chordCellIsAction(cells[index])) return null;
        action_cell = cells[index];
        index += 1;
    }

    if (index < cells.len and chordCellLooksBool(cells[index]) and index + 1 == cells.len) {
        suspend_exempt = suspend_exempt or runtimeHotkeyBoolCell(cells[index]);
        index += 1;
    }
    if (index < cells.len and cells[index].tag == HOTKEY_CELL_TEXT) {
        mode_text = cells[index].text;
        index += 1;
    }
    if (index < cells.len and cells[index].tag == HOTKEY_CELL_TEXT) {
        mod_text = cells[index].text;
        index += 1;
    }
    if (index < cells.len) suspend_exempt = suspend_exempt or runtimeHotkeyBoolCell(cells[index]);

    const mode = parseChordModeText16(mode_text);
    if (mode == 255) return null;
    const callback_id = switch (action_cell.tag) {
        HOTKEY_CELL_CALLBACK => action_cell.callbackId,
        HOTKEY_CELL_TEXT => if (mode == 1) NATIVE_PAYLOAD_ID_BASE - @as(i32, @intCast(payload_base + action_cell.textOffset)) else -1,
        else => -1,
    };
    const parsed_send = if (chordModeRequiresSendDirectSpec(mode_text))
        parseSendKeyDirectInternalTarget(action_cell.text, mod_text) orelse return null
    else
        parseLegacyInternalTarget(action_cell.text, mod_text);
    const target_vk = if (mode == 1 and action_cell.tag == HOTKEY_CELL_TEXT) parsed_send.target_vk else 0;
    const mod_mask = if (mode == 1 and action_cell.tag == HOTKEY_CELL_TEXT) parsed_send.mod_mask else parseModifierMaskText16(mod_text);
    if (mode == 0 and callback_id < 0) return null;
    if (mode == 1 and target_vk == 0) return null;
    return .{
        .raw_vks = raw_vks,
        .context_text = context_text,
        .callback_id = callback_id,
        .target_vk = target_vk,
        .mod_mask = mod_mask,
        .mode = mode,
        .suspend_exempt = suspend_exempt,
    };
}

/// Typed-cell chord entries. AHK sends row cells; Zig keeps chord-specific row
/// grammar separate from hotkeys/combos while sharing the 16-byte cell envelope.
/// Record layout (132 bytes): cellCount:u8 at 0; eight 16-byte cells at 4.
export fn QMK_SetupChordCellEntries(records: [*]const u8, count: u32, textChars: [*]const u16, textCharsLen: u32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    prepareRuntimeChordFamily();
    if (!ensureRuntimeChordCapacity(g_runtimeChordsLen + @as(usize, @intCast(count)))) return 0;
    const payload_base = if (textCharsLen == 0) g_nativeHotkeyPayloads.len else appendNativeHotkeyPayloads(textChars, textCharsLen);
    if (payload_base == NATIVE_PAYLOAD_APPEND_FAILED) return 0;
    if (textCharsLen != 0 and g_nativeHotkeyPayloads.len != 0) initNativePasteThread();
    var loaded: i32 = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const off = i * 132;
        const raw_cell_count = records[off];
        if (raw_cell_count < 2) continue;
        const cell_count: usize = @min(@as(usize, @intCast(raw_cell_count)), 8);
        var cells = [_]RuntimeHotkeyCell{.{}} ** 8;
        var c: usize = 0;
        var valid = true;
        while (c < cell_count) : (c += 1) {
            cells[c] = readRuntimeHotkeyCell(records, off, c, textChars, textCharsLen) orelse {
                valid = false;
                break;
            };
        }
        if (!valid) continue;
        const parsed = chordBuildRowFromCells(cells[0..cell_count], payload_base) orelse continue;
        const context_parts = runtimeContextPartCount(parsed.context_text);
        if (!ensureRuntimeChordCapacity(g_runtimeChordsLen + context_parts) or
            !ensureRuntimeCallbackSuspendExemptFor(parsed.callback_id, parsed.suspend_exempt))
        {
            truncateRuntimeChordsToPublished();
            return 0;
        }
        var contexts = RuntimeContextListIterator{ .raw = parsed.context_text };
        var row_loaded = false;
        while (contexts.next()) |context_text| {
            const context = parseRuntimeContextSpec(context_text);
            if (appendRuntimeChord(parsed.raw_vks, .{
                .callbackId = parsed.callback_id,
                .targetVK = parsed.target_vk,
                .modMask = parsed.mod_mask,
                .mode = parsed.mode,
                .contextKind = context.kind,
                .contextNegated = context.negated,
                .suspendExempt = parsed.suspend_exempt,
            }, context.text)) row_loaded = true;
        }
        if (row_loaded) loaded += 1;
    }
    finishRuntimeChordSetup();
    return loaded;
}
fn setupChordText(k1: [*:0]const u16, k2: [*:0]const u16, k3: [*:0]const u16, k4: [*:0]const u16, k5: [*:0]const u16, callbackId: i32) void {
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
    if (!ensureStaticExtChordCacheCapacity(g_extChordCacheLen + 1)) return;
    if (!chordHotPut(.{
        .key = chordKey,
        .targetVK = 0,
        .callbackId = callbackId,
        .modMask = 0,
        .keyCount = @intCast(vkCount),
        .kind = @intFromEnum(ChordHotKind.external),
    })) return;
    g_hasExternalChords = true;
    g_hasAnyChord = true;
    // Pre-decode and cache VK array so the prefix check avoids bit-unpacking per keydown.
    var entry = ExtChordCacheEntry{ .keyCount = @intCast(vkCount) };
    var mask: u16 = 0;
    for (0..vkCount) |ci| {
        entry.vks[ci] = vks[ci];
        if (vks[ci] >= 0 and vks[ci] < VK_COUNT) {
            mask |= @as(u16, @intCast(g_key_virtual_modifier_mask[@intCast(vks[ci])]));
        }
    }
    entry.modMask = mask;
    g_extChordCache[g_extChordCacheLen] = entry;
    g_extChordCacheLen += 1;
    for (0..vkCount) |ci| if (vks[ci] >= 0 and vks[ci] < VK_COUNT) {
        g_chordParticipantFlat[@intCast(vks[ci])] = true;
    };
    markKeyGateDirty();
    refreshReplayKeyGate();
}
export fn QMK_RegisterCombo(primary: i32, secondary: i32, combotype: i32) callconv(.c) void {
    if (primary < 0 or primary >= VK_COUNT or secondary < 0 or secondary >= VK_COUNT) return;
    if (combotype == 1) {
        instantComboPrimaryBitSet(primary);
        g_instantComboMatrix[@intCast(primary)][@intCast(secondary)] = true;
    } else {
        comboPrimaryBitSet(primary);
        g_comboMatrix[@intCast(primary)][@intCast(secondary)] = true;
    }
    markKeyGateDirty();
    refreshReplayKeyGate();
}
// ============================================================================
// Section 22 — DLL exports: keystroke processing
// ============================================================================
export fn QMK_KeyDown(key: [*:0]const u16) callconv(.c) void {
    const vk = getVKFromName(key);
    if (vk != 0) {
        beginHotPathActivity();
        defer endHotPathActivity(true);
        if (isModVK(vk)) {
            _ = apply_physical_modifier_event(vk, true);
        } else {
            setPhysicalKeyDownState(vk, true);
        }
        cancelRepeatForDifferentKeyDown(vk);
        bufferKeyDown(vk);
    }
}
export fn QMK_KeyUp(key: [*:0]const u16) callconv(.c) void {
    const vk = getVKFromName(key);
    if (vk != 0) {
        beginHotPathActivity();
        defer endHotPathActivity(false);
        if (isModVK(vk)) {
            _ = apply_physical_modifier_event(vk, false);
        } else {
            setPhysicalKeyDownState(vk, false);
        }
        bufferKeyUp(vk);
    }
}
// Set the AHK thread ID for PostThreadMessage notifications.
// Call this once from AHK after init:
//   DllCall(QMK.Proc("QMK_SetAHKThreadId"), "UInt", DllCall("kernel32\GetCurrentThreadId", "UInt"))
export fn QMK_RegisterDynamicCallbacks(file_mapping_handle: HANDLE, string_buf_out: [*]u8, buf_size: u32, out_count: *u32) callconv(.c) ?*ipc.SharedRingBuffer {
    const view = MapViewOfFile(file_mapping_handle, 0xF001F, 0, 0, 0) orelse return null;
    const ring: *ipc.SharedRingBuffer = @ptrCast(@alignCast(view));

    ring.head = 0;
    @atomicStore(u64, &ring.tail, 0, .release);
    ring.capacity = ipc.RING_CAPACITY;
    g_ipcRing = ring;

    if (buf_size != 0) string_buf_out[0] = 0;
    out_count.* = 0;
    return ring;
}

export fn QMK_GetDynamicCallbackBufferBytes() callconv(.c) u32 {
    return @intCast(PRECOMPILED_CALLBACK_NAME_BYTES + 1);
}

export fn QMK_GetDynamicCallbackName(callback_idx: i32) callconv(.c) [*:0]const u16 {
    _ = callback_idx;
    return @ptrCast(&[_:0]u16{0});
}

// Notify AHK asynchronously via PostThreadMessage.
// Non-blocking — Zig does not wait for AHK to process the message.
// AHK picks it up on its next message pump cycle via OnMessage handlers.
inline fn notifyAHK(hasCbs: bool, hasTimers: bool) void {
    if (hasCbs) flushPendingCallbacksToIpc();
    if (hasTimers) pushIpcControl(ipc.IPC_TIMERS_PENDING);
}

threadlocal var g_qmkThreadPrioritySet: bool = false;

inline fn ensureQmkInputThreadPriority() void {
    if (!g_qmkThreadPrioritySet) {
        _ = SetThreadPriority(GetCurrentThread(), THREAD_PRIORITY_TIME_CRITICAL);
        g_qmkThreadPrioritySet = true;
    }
}
// Combined hot-path entry: processes the event, fast-paths unmodified type-4
// taps directly through Zig without an AHK round-trip. Slow callbacks and
// timers are signalled to AHK via PostThreadMessage — no result struct write,
// no blocking wait, OnKeyDown/OnKeyUp return immediately after one DllCall.
inline fn processKeyEventHot(vk: i32, isDown: i32) void {
    @setEvalBranchQuota(1_000_000);
    if (isDown != 0) {
        const pke8_start = profStartSect();
        cancelRepeatForDifferentKeyDown(vk);
        profSpan(PKE_BASE + 8, pke8_start); // pke8 span: cancelRepeatForDifferentKeyDown
        const pke9_start = profStartSect();
        bufferKeyDown(vk);
        profSpan(PKE_BASE + 9, pke9_start); // pke9 span: bufferKeyDown call
    } else {
        g_directTapCaptureActive = true;
        g_hotstringKeyUpHadDirectTap = false;
        const pke10_start = profStartSect();
        bufferKeyUp(vk);
        profSpan(PKE_BASE + 10, pke10_start); // pke10 span: bufferKeyUp call
        g_directTapCaptureActive = false;
        const key_up_sent_tap = g_hotstringKeyUpHadDirectTap;
        const pke11_start = profStartSect();
        directTapDrain();
        profSpan(PKE_BASE + 11, pke11_start); // pke11 span: directTapDrain
        // Backspace only mutates hotstring history when QMK actually emitted
        // a Backspace tap. Hold/double-tap callbacks consume the key, so
        // applying the matcher undo there desynchronizes text state.
        if (hotstringShouldInspectVK(vk) and (key_up_sent_tap or hotstringIsNavigationVK(vk))) {
            const pke12_start = profStartSect();
            _ = hotstringAfterKeyDown(vk);
            profSpan(PKE_BASE + 12, pke12_start); // pke12 span: hotstringAfterKeyDown
        }
    }

    // Process direct (type-4) callbacks — do NOT include send time in KeyDown stats
    // The repeat worker may append callback-combo repeats concurrently.
    acquirePendingCBLock();
    const cbLen = g_pendingCBsLen;
    var singleDirectCb: PendingCallback = undefined;
    var haveSingleDirectCb = false;
    if (cbLen == 1) {
        const cb = g_pendingCBs[0];
        if (cb.type_ == 4 and cb.modifierMask == 0 and cb.vk != 0) {
            g_pendingCBsLen = 0;
            singleDirectCb = cb;
            haveSingleDirectCb = true;
        }
        releasePendingCBLock();
        if (haveSingleDirectCb) {
            const pke13_start = profStartSect();
            sendKeyDirect(singleDirectCb.vk, 0); // send happens OUTSIDE timing
            profSpan(PKE_BASE + 13, pke13_start); // pke13 span: single direct callback sendKeyDirect
        } else {
            const pke14_start = profStartSect();
            notifyAHK(true, false);
            profSpan(PKE_BASE + 14, pke14_start); // pke14 span: single slow callback notifyAHK
        }
    } else if (cbLen > 1) {
        var slowIdx: usize = 0;
        var i: usize = 0;
        const pke15_start = profStartSect();
        while (i < cbLen) : (i += 1) {
            const cb = g_pendingCBs[i];
            if (cb.type_ == 4 and cb.modifierMask == 0 and cb.vk != 0) {
                sendKeyDirect(cb.vk, 0); // send happens OUTSIDE timing
            } else {
                if (slowIdx != i) g_pendingCBs[slowIdx] = cb;
                slowIdx += 1;
            }
        }
        profSpan(PKE_BASE + 15, pke15_start); // pke15 span: multi-callback drain loop
        g_pendingCBsLen = slowIdx;
        releasePendingCBLock();
        if (slowIdx > 0) {
            const pke16_start = profStartSect();
            notifyAHK(true, false);
            profSpan(PKE_BASE + 16, pke16_start); // pke16 span: multi-callback notifyAHK
        }
    } else {
        releasePendingCBLock();
    }
}

// Returns the HOTKEY_MOD_* bitmask for currently-held modifier keys.
inline fn hotkeyModSlotForVK(vk: i32) i32 {
    return switch (vk) {
        0x11, 0xA2, 0xA3 => 0,
        0x12, 0xA4, 0xA5 => 1,
        0x10, 0xA0, 0xA1 => 2,
        0x5B, 0x5C => 3,
        else => -1,
    };
}

inline fn hotkeyModBitForSlot(slot: usize) u16 {
    return switch (slot) {
        0 => hotkeys.HOTKEY_MOD_CTRL,
        1 => hotkeys.HOTKEY_MOD_ALT,
        2 => hotkeys.HOTKEY_MOD_SHIFT,
        3 => hotkeys.HOTKEY_MOD_WIN,
        else => 0,
    };
}

inline fn physicalModifierLRBitForVK(vk: i32) u8 {
    return switch (vk) {
        0xA2 => 0x01, // LCtrl
        0xA3 => 0x02, // RCtrl
        0xA4 => 0x04, // LAlt
        0xA5 => 0x08, // RAlt
        0xA0 => 0x10, // LShift
        0xA1 => 0x20, // RShift
        0x5B => 0x40, // LWin
        0x5C => 0x80, // RWin
        else => 0,
    };
}

inline fn genericModifierVKForVK(vk: i32) i32 {
    return switch (vk) {
        0xA0, 0xA1 => VK_SHIFT,
        0xA2, 0xA3 => VK_CONTROL,
        0xA4, 0xA5 => VK_MENU,
        0x5B, 0x5C => VK_LWIN,
        else => vk,
    };
}

inline fn physicalModifierTrackingVK(vk: i32) i32 {
    return switch (vk) {
        VK_SHIFT => 0xA0,
        VK_CONTROL => 0xA2,
        VK_MENU => 0xA4,
        else => vk,
    };
}

inline fn queueAnyHotkeyIfMatchedWithGenericModFallback(vk: i32, active_mods: u16, is_down: bool) bool {
    if (queueAnyHotkeyIfMatched(vk, active_mods, is_down)) return true;
    const generic_vk = genericModifierVKForVK(vk);
    if (generic_vk != vk) {
        return queueAnyHotkeyIfMatched(generic_vk, active_mods, is_down);
    }
    return false;
}

fn runtimeModifierOverriddenByRuntime(index: usize) bool {
    if (index >= g_compiledModifiersLen) return false;
    const compiled = g_runtimeModifiers[index];
    var runtime_index = g_compiledModifiersLen;
    while (runtime_index < g_runtimeModifiersLen) : (runtime_index += 1) {
        const runtime = g_runtimeModifiers[runtime_index];
        if (runtime.vk != compiled.vk or
            runtime.contextKind != compiled.contextKind or
            runtime.contextNegated != compiled.contextNegated) continue;
        if (runtimeContextTextEqual(g_runtimeModifierTexts[index][0..@as(usize, @intCast(compiled.contextLen))],
            g_runtimeModifierTexts[runtime_index][0..@as(usize, @intCast(runtime.contextLen))])) return true;
    }
    return false;
}

fn runtimeComboOverriddenByRuntime(row: RuntimeCombo, context_text: []const u16) bool {
    var i: usize = g_compiledCombosLen;
    while (i < g_runtimeCombosLen) : (i += 1) {
        const runtime = g_runtimeCombos[i];
        if (runtime.primaryVK != row.primaryVK or runtime.secondaryVK != row.secondaryVK or
            runtime.mode != row.mode or
            runtime.contextKind != row.contextKind or runtime.contextNegated != row.contextNegated) continue;
        if (runtimeContextTextEqual(g_runtimeComboTexts[i][0..@as(usize, @intCast(runtime.contextLen))], context_text)) return true;
    }
    i = g_compiledInstantCombosLen;
    while (i < g_runtimeInstantCombosLen) : (i += 1) {
        const runtime = g_runtimeInstantCombos[i];
        if (runtime.primaryVK != row.primaryVK or runtime.secondaryVK != row.secondaryVK or
            runtime.mode != row.mode or
            runtime.contextKind != row.contextKind or runtime.contextNegated != row.contextNegated) continue;
        if (runtimeContextTextEqual(g_runtimeInstantComboTexts[i][0..@as(usize, @intCast(runtime.contextLen))], context_text)) return true;
    }
    return false;
}

fn runtimeContextActionOverriddenByRuntime(index: usize) bool {
    if (index >= g_compiledContextActionsLen) return false;
    const compiled = g_runtimeContextActions[index];
    var runtime_index = g_compiledContextActionsLen;
    while (runtime_index < g_runtimeContextActionsLen) : (runtime_index += 1) {
        const runtime = g_runtimeContextActions[runtime_index];
        if (runtime.triggerVK != compiled.triggerVK or
            runtime.actionKind != compiled.actionKind or
            runtime.contextKind != compiled.contextKind or
            runtime.contextNegated != compiled.contextNegated) continue;
        if (runtimeContextActionTextMatches(index, runtimeContextActionText(runtime_index))) return true;
    }
    return false;
}

// Compiled rows occupy the published prefix; runtime setup appends rows after
// that prefix.  Keep both rows in storage, but let a later runtime row own the
// active dispatch identity.  Callback/action payloads are deliberately not
// compared: replacing a compiled callback with a runtime callback is the
// purpose of this overlay.
fn runtimeHotkeyOverriddenByRuntime(index: usize) bool {
    if (index >= g_compiledHotkeysLen) return false;
    const compiled = g_runtimeHotkeys[index];
    var runtime_index = g_compiledHotkeysLen;
    while (runtime_index < g_runtimeHotkeysLen) : (runtime_index += 1) {
        const runtime = g_runtimeHotkeys[runtime_index];
        if (runtime.triggerVK != compiled.triggerVK or
            runtime.modsRequired != compiled.modsRequired or
            runtime.modsForbidden != compiled.modsForbidden or
            runtime.triggerKind != compiled.triggerKind or
            runtime.actionKind != compiled.actionKind or
            runtime.contextKind != compiled.contextKind or
            runtime.contextNegated != compiled.contextNegated or
            runtime.physicalModVK != compiled.physicalModVK or
            runtime.physicalModsRequired != compiled.physicalModsRequired or
            runtime.physicalModsForbidden != compiled.physicalModsForbidden) continue;
        if (runtimeContextTextEqual(g_runtimeHotkeyContexts[index][0..@as(usize, @intCast(compiled.contextLen))],
            g_runtimeHotkeyContexts[runtime_index][0..@as(usize, @intCast(runtime.contextLen))])) return true;
    }
    return false;
}

fn runtimePhysicalModifiersAllow(hk: RuntimeHotkey) bool {
    var required = hk.physicalModsRequired;
    if (required == 0) {
        const physical_mod_vk = hk.physicalModVK;
        if (physical_mod_vk != 0 and !physicalKeyDownVK(physical_mod_vk)) return false;
        required = physicalModifierLRBitForVK(physical_mod_vk);
    }
    const active = g_lr_active_physical_modifiers;
    return (active & required) == required and
        (active & hk.physicalModsForbidden) == 0;
}

// Updates physical modifier-family values selected for output.
inline fn update_physical_modifiers_to_send(vk: i32, is_down: bool, was_down: bool) void {
    if (is_down == was_down) return;
    const lr_bit = physicalModifierLRBitForVK(vk);
    if (lr_bit != 0) {
        if (is_down) {
            g_lr_active_physical_modifiers |= lr_bit;
        } else {
            g_lr_active_physical_modifiers &= ~lr_bit;
        }
    }
    const slot_i = hotkeyModSlotForVK(vk);
    if (slot_i < 0) return;
    const slot: usize = @intCast(slot_i);
    if (is_down) {
        if (g_active_physical_modifier_key_counts_by_category[slot] != std.math.maxInt(u8)) {
            g_active_physical_modifier_key_counts_by_category[slot] += 1;
        }
        g_which_physical_modifiers_to_send |= hotkeyModBitForSlot(slot);
    } else {
        if (g_active_physical_modifier_key_counts_by_category[slot] > 0) {
            g_active_physical_modifier_key_counts_by_category[slot] -= 1;
        }
        if (g_active_physical_modifier_key_counts_by_category[slot] == 0) {
            g_which_physical_modifiers_to_send &= ~hotkeyModBitForSlot(slot);
        }
    }
}

inline fn setPhysicalKeyDownState(vk: i32, is_down: bool) void {
    if (vk < 0 or vk >= VK_COUNT) return;
    const vki: usize = @intCast(vk);
    const was_down = physicalKeyDownAt(vki);
    setPhysicalKeyDownAt(vki, is_down);
    if (is_down and !was_down) {
        g_trackedPhysicalKeysDown +%= 1;
        g_lastPhysicalDownVK = vk;
    } else if (!is_down and was_down) {
        if (g_trackedPhysicalKeysDown > 0) g_trackedPhysicalKeysDown -= 1;
    }
    update_physical_modifiers_to_send(vk, is_down, was_down);
    if (!is_down) clearPhysicalModifierHiddenFromOs(vk);
}

inline fn startModPollThreadForPhysicalModifier() void {
    // Physical modifier truth is event-driven now. Real modifier double-taps
    // are resolved on the actual key-up event, so the old async-state poll
    // helper would only add background wakeups after modifier activity.
}

// Applies one physical modifier transition to tracked physical and Windows-facing state.
inline fn apply_physical_modifier_event(vk: i32, is_down: bool) i32 {
    if (!isModVK(vk)) return vk;
    const tracked_vk = physicalModifierTrackingVK(vk);
    const tracked_valid = tracked_vk >= 0 and tracked_vk < VK_COUNT;
    const was_down = tracked_valid and physicalKeyDownVK(tracked_vk);
    if (is_down) {
        setPhysicalKeyDownState(tracked_vk, true);
        rebuildTrackedPhysicalModifierDerivedState();
        if (tracked_valid and !was_down) {
            g_modPollDownTime[@intCast(tracked_vk)] = getTime();
            startModPollThreadForPhysicalModifier();
        }
    } else {
        if (was_down) recordPhysicalModifierUpForDoubleTap(tracked_vk);
        setPhysicalKeyDownState(tracked_vk, false);
        rebuildTrackedPhysicalModifierDerivedState();
    }
    return tracked_vk;
}

inline fn markPhysicalModifierHiddenFromOs(vk: i32) void {
    const bit = physicalModifierLRBitForVK(vk);
    if (bit == 0) return;
    if ((g_lr_active_physical_modifiers & bit) != 0) {
        markPhysicalModsHiddenFromOs(bit);
    }
}

inline fn clearPhysicalModifierHiddenFromOs(vk: i32) void {
    const bit = physicalModifierLRBitForVK(vk);
    clearPhysicalModsHiddenFromOs(bit);
}

inline fn physicalModifierHiddenFromOs(vk: i32) bool {
    const bit = physicalModifierLRBitForVK(vk);
    return bit != 0 and (hiddenPhysicalModsFromOs() & bit) != 0;
}

inline fn handleForeignPhysicalKeyTransition(vk: i32, is_down: bool) bool {
    _ = vk;
    _ = is_down;
    return false;
}

inline fn flushRuntimePublishAfterKeyEvent(is_down: bool) void {
    if (!is_down and g_trackedPhysicalKeysDown == 0 and @atomicLoad(u32, &g_runtimePublishPendingMask, .acquire) != 0) {
        startRuntimePublishWorkerIfNeeded();
    }
}

// Combines physical and virtual modifier output state before sending.
inline fn compute_modifiers_to_send() u16 {
    // Physical modifiers and QMK virtual/home-row modifiers select the same
    // prebuilt VK/modifier bucket. A modifier state change never rebuilds the
    // runtime hotkey index or runs context matching.
    return g_which_physical_modifiers_to_send | (g_active_virtual_modifiers & 0x000F);
}

inline fn panicExitHotkeyMatches(vk: i32, active_mods: u16, is_down: bool) bool {
    return is_down and
        @atomicLoad(i32, &g_panicExitEnabled, .acquire) != 0 and
        vk == @atomicLoad(i32, &g_panicExitVK, .acquire) and
        (active_mods & @atomicLoad(u16, &g_panicExitModsRequired, .acquire)) == @atomicLoad(u16, &g_panicExitModsRequired, .acquire) and
        (active_mods & @atomicLoad(u16, &g_panicExitModsForbidden, .acquire)) == 0;
}

inline fn handleNativePanicExitIfMatched(vk: i32, active_mods: u16, is_down: bool) void {
    if (!panicExitHotkeyMatches(vk, active_mods, is_down)) return;
    QMK_EmergencyExit();
}

inline fn nativeReloadHotkeyMatches(vk: i32, active_mods: u16, is_down: bool) bool {
    return is_down and
        @atomicLoad(i32, &g_nativeReloadEnabled, .acquire) != 0 and
        vk == @atomicLoad(i32, &g_nativeReloadVK, .acquire) and
        (active_mods & @atomicLoad(u16, &g_nativeReloadModsRequired, .acquire)) == @atomicLoad(u16, &g_nativeReloadModsRequired, .acquire) and
        (active_mods & @atomicLoad(u16, &g_nativeReloadModsForbidden, .acquire)) == 0;
}

inline fn handleNativeReloadIfMatched(vk: i32, active_mods: u16, is_down: bool) void {
    if (!nativeReloadHotkeyMatches(vk, active_mods, is_down)) return;
    QMK_NativeReload();
}

inline fn nativeSuspendHotkeyMatches(vk: i32, active_mods: u16, is_down: bool) bool {
    return is_down and
        @atomicLoad(i32, &g_nativeSuspendEnabled, .acquire) != 0 and
        vk == @atomicLoad(i32, &g_nativeSuspendVK, .acquire) and
        (active_mods & @atomicLoad(u16, &g_nativeSuspendModsRequired, .acquire)) == @atomicLoad(u16, &g_nativeSuspendModsRequired, .acquire) and
        (active_mods & @atomicLoad(u16, &g_nativeSuspendModsForbidden, .acquire)) == 0;
}

inline fn handleNativeSuspendIfMatched(vk: i32, active_mods: u16, is_down: bool) bool {
    const configured_vk = @atomicLoad(i32, &g_nativeSuspendVK, .acquire);
    if (!is_down) {
        if (g_nativeSuspendKeyDown and vk == configured_vk) {
            g_nativeSuspendKeyDown = false;
            return true;
        }
        return false;
    }
    if (g_nativeSuspendKeyDown and vk == configured_vk) return true;
    if (!nativeSuspendHotkeyMatches(vk, active_mods, is_down)) return false;
    g_nativeSuspendKeyDown = true;
    _ = QMK_ToggleRuntimeHotkeysSuspended();
    return true;
}

inline fn physicalMenuModifierIsDown() bool {
    return (g_which_physical_modifiers_to_send & (hotkeys.HOTKEY_MOD_ALT | hotkeys.HOTKEY_MOD_WIN)) != 0;
}

inline fn physicalControlModifierIsDown() bool {
    return (g_which_physical_modifiers_to_send & hotkeys.HOTKEY_MOD_CTRL) != 0;
}

inline fn ringAddInterceptionMenuMaskIfNeeded() void {
    if (!physicalMenuModifierIsDown() or physicalControlModifierIsDown()) return;
    // AutoHotkey's default menu mask is VK_CONTROL with the left-control scan code.
    // VK E8 is useful through SendInput, but it has no Interception scan-code stroke.
    ringAddTapWithInfoTagged(VK_CONTROL, AHK_SENDLEVEL_2, 0);
}

inline fn releasePhysicalModsForSuppressingHotkey() void {
    @setEvalBranchQuota(1_000_000);
    if (g_which_physical_modifiers_to_send == 0) return;
    const visible = snapshotVisiblePhysicalMods();
    if (visible == 0 and !physicalKeyDownVK(0x12) and !physicalKeyDownVK(0x11) and !physicalKeyDownVK(0x10)) return;
    ringReset();
    ringAddInterceptionMenuMaskIfNeeded();
    // Suppressing hotkey neutralization is a persistent hide: release only
    // modifiers Windows currently owns, then mark those LR bits hidden.
    ringAddModifierRelease(visible, AHK_SENDLEVEL_2);
    if (physicalKeyDownVK(0x12)) ringAddKeyWithInfo(0x12, KEYEVENTF_KEYUP, AHK_SENDLEVEL_2); // generic Alt
    if (physicalKeyDownVK(0x11)) ringAddKeyWithInfo(0x11, KEYEVENTF_KEYUP, AHK_SENDLEVEL_2); // generic Ctrl
    if (physicalKeyDownVK(0x10)) ringAddKeyWithInfo(0x10, KEYEVENTF_KEYUP, AHK_SENDLEVEL_2); // generic Shift
    ringSend();
    markPhysicalModsHiddenFromOs(visible);
}

inline fn shouldForwardNativeModifiedStroke(vk: i32, is_down: bool) bool {
    if (vk < 0 or vk >= VK_COUNT) return false;
    const vki: usize = @intCast(vk);
    if (is_down) {
        // AHK-like fallback: when the current key did not match an active
        // hotkey, a real physical modifier chord belongs to Windows. Virtual
        // QMK modifiers still need the buffer path so QMK can synthesize the
        // modifier-wrapped output itself.
        return g_which_physical_modifiers_to_send != 0;
    }
    return g_native_passthrough_to_windows[vki];
}

inline fn recordNativeModifiedStrokeForwarded(vk: i32, is_down: bool) void {
    if (vk < 0 or vk >= VK_COUNT) return;
    const vki: usize = @intCast(vk);
    g_native_passthrough_to_windows[vki] = is_down;
}

inline fn asciiLower16(c: u16) u16 {
    return if (c >= 'A' and c <= 'Z') c + 32 else c;
}

inline fn eqlIgnoreCase16(a: []const u16, b: []const u16) bool {
    if (a.len != b.len) return false;
    for (a, b) |ac, bc| {
        if (asciiLower16(ac) != asciiLower16(bc)) return false;
    }
    return true;
}

inline fn wideSpan(buf: []const u16) []const u16 {
    var len: usize = 0;
    while (len < buf.len and buf[len] != 0) len += 1;
    return buf[0..len];
}

inline fn isSpaceOrTab16(c: u16) bool {
    return c == ' ' or c == '\t';
}

fn trimSpaces16(s: []const u16) []const u16 {
    var start: usize = 0;
    var end: usize = s.len;
    while (start < end and isSpaceOrTab16(s[start])) start += 1;
    while (end > start and isSpaceOrTab16(s[end - 1])) end -= 1;
    return s[start..end];
}

fn startsWithAsciiIgnoreCase16(haystack: []const u16, comptime needle: []const u8) bool {
    if (haystack.len < needle.len) return false;
    inline for (needle, 0..) |nc, i| {
        if (asciiLower16(haystack[i]) != asciiLower16(nc)) return false;
    }
    return true;
}

const CachedTokenKind = enum { class_name, exe };
const CachedTokenHit = struct {
    start: usize,
    value_start: usize,
    kind: CachedTokenKind,
};

fn findNextCachedAhkToken(s: []const u16, start: usize) ?CachedTokenHit {
    var i = start;
    while (i < s.len) : (i += 1) {
        if (i != 0 and !isSpaceOrTab16(s[i - 1])) continue;
        const rest = s[i..];
        if (startsWithAsciiIgnoreCase16(rest, "ahk_class")) {
            return .{ .start = i, .value_start = i + 9, .kind = .class_name };
        }
        if (startsWithAsciiIgnoreCase16(rest, "ahk_exe")) {
            return .{ .start = i, .value_start = i + 7, .kind = .exe };
        }
    }
    return null;
}

fn runtimeAcReset(ac: *RuntimeAcIndex) void {
    if (!ensureRuntimeAcNodeCapacity(ac, 1)) {
        ac.nodeCount = 0;
        ac.edgeCount = 0;
        ac.outputCount = 0;
        ac.overflowed = true;
        return;
    }
    ac.nodeCount = 1;
    ac.edgeCount = 0;
    ac.outputCount = 0;
    ac.overflowed = false;
    @memset(ac.firstEdge, RUNTIME_AC_NONE_U32);
    @memset(ac.failure, 0);
    @memset(ac.outputLink, RUNTIME_AC_NONE_U32);
    @memset(ac.firstOutput, RUNTIME_AC_NONE_U32);
}

inline fn runtimeAcFindEdge(ac: *const RuntimeAcIndex, node: u32, ch: u16) ?u32 {
    if (node >= ac.nodeCount or @as(usize, @intCast(node)) >= ac.firstEdge.len) return null;
    var edge = ac.firstEdge[node];
    while (edge != RUNTIME_AC_NONE_U32) : (edge = ac.nextEdge[edge]) {
        if (@as(usize, @intCast(edge)) >= ac.edgeChar.len) return null;
        if (ac.edgeChar[edge] == ch) return ac.edgeNode[edge];
    }
    return null;
}

fn runtimeAcGetOrAddEdge(ac: *RuntimeAcIndex, node: u32, raw_ch: u16) ?u32 {
    const ch = asciiLower16(raw_ch);
    if (runtimeAcFindEdge(ac, node, ch)) |existing| return existing;
    const required_node = @as(usize, @intCast(ac.nodeCount)) + 1;
    const required_edge = @as(usize, @intCast(ac.edgeCount)) + 1;
    if (!ensureRuntimeAcNodeCapacity(ac, required_node) or !ensureRuntimeAcEdgeCapacity(ac, required_edge)) {
        ac.overflowed = true;
        return null;
    }
    const new_node = ac.nodeCount;
    ac.nodeCount += 1;
    ac.firstEdge[new_node] = RUNTIME_AC_NONE_U32;
    ac.failure[new_node] = 0;
    ac.outputLink[new_node] = RUNTIME_AC_NONE_U32;
    ac.firstOutput[new_node] = RUNTIME_AC_NONE_U32;

    const edge = ac.edgeCount;
    ac.edgeCount += 1;
    ac.edgeChar[edge] = ch;
    ac.edgeNode[edge] = new_node;
    ac.nextEdge[edge] = ac.firstEdge[node];
    ac.firstEdge[node] = edge;
    return new_node;
}

fn runtimeAcAddPattern(ac: *RuntimeAcIndex, pattern: []const u16, hotkey_index: usize) bool {
    if (pattern.len == 0 or hotkey_index > 0xFFFFFFFE) return false;
    if (ac.nodeCount == 0 or ac.firstEdge.len == 0) {
        ac.overflowed = true;
        return false;
    }
    var node: u32 = 0;
    for (pattern) |ch| {
        node = runtimeAcGetOrAddEdge(ac, node, ch) orelse return false;
    }
    if (ac.outputCount >= ac.outputHotkey.len or ac.outputCount > 0xFFFFFFFE) {
        ac.overflowed = true;
        return false;
    }
    const output: usize = @intCast(ac.outputCount);
    ac.outputCount += 1;
    ac.outputHotkey[output] = @intCast(hotkey_index);
    ac.nextOutput[output] = ac.firstOutput[node];
    ac.firstOutput[node] = @intCast(output);
    return true;
}

fn runtimeAcBuildFailures(ac: *RuntimeAcIndex) void {
    if (ac.nodeCount == 0) return;
    if (!ensureRuntimeAcQueueCapacity(@as(usize, @intCast(ac.nodeCount)))) {
        ac.overflowed = true;
        return;
    }
    var head: usize = 0;
    var tail: usize = 0;
    var edge = ac.firstEdge[0];
    while (edge != RUNTIME_AC_NONE_U32) : (edge = ac.nextEdge[edge]) {
        const child = ac.edgeNode[edge];
        ac.failure[child] = 0;
        ac.outputLink[child] = RUNTIME_AC_NONE_U32;
        if (tail >= g_runtimeAcQueue.len) {
            ac.overflowed = true;
            return;
        }
        g_runtimeAcQueue[tail] = child;
        tail += 1;
    }

    while (head < tail) : (head += 1) {
        const node = g_runtimeAcQueue[head];
        edge = ac.firstEdge[node];
        while (edge != RUNTIME_AC_NONE_U32) : (edge = ac.nextEdge[edge]) {
            const ch = ac.edgeChar[edge];
            const child = ac.edgeNode[edge];
            var fail = ac.failure[node];
            while (fail != 0 and runtimeAcFindEdge(ac, fail, ch) == null) {
                fail = ac.failure[fail];
            }
            if (runtimeAcFindEdge(ac, fail, ch)) |next| {
                if (next != child) ac.failure[child] = next;
            } else {
                ac.failure[child] = 0;
            }
            const failure_node = ac.failure[child];
            ac.outputLink[child] = if (ac.firstOutput[failure_node] != RUNTIME_AC_NONE_U32)
                failure_node
            else
                ac.outputLink[failure_node];
            if (tail >= g_runtimeAcQueue.len) {
                ac.overflowed = true;
                return;
            }
            g_runtimeAcQueue[tail] = child;
            tail += 1;
        }
    }
}

inline fn runtimeAcMarkOutputs(ac: *const RuntimeAcIndex, node: u32, matched: []bool) void {
    var output_node = node;
    while (true) {
        var output = ac.firstOutput[output_node];
        while (output != RUNTIME_AC_NONE_U32) : (output = ac.nextOutput[@intCast(output)]) {
            const hotkey_index: usize = @intCast(ac.outputHotkey[@intCast(output)]);
            if (hotkey_index < matched.len) matched[hotkey_index] = true;
        }
        const linked = ac.outputLink[output_node];
        if (linked == RUNTIME_AC_NONE_U32) break;
        output_node = linked;
    }
}

fn runtimeAcScan(ac: *const RuntimeAcIndex, text: []const u16, matched: []bool) void {
    if (ac.nodeCount == 0 or ac.firstEdge.len == 0) return;
    var state: u32 = 0;
    for (text) |raw_ch| {
        const ch = asciiLower16(raw_ch);
        while (state != 0 and runtimeAcFindEdge(ac, state, ch) == null) {
            state = ac.failure[state];
        }
        if (runtimeAcFindEdge(ac, state, ch)) |next| state = next else state = 0;
        runtimeAcMarkOutputs(ac, state, matched);
    }
}

fn rebuildRuntimeContextAutomata() bool {
    if (!ensureRuntimeAcOutputCapacity(&g_runtimeTitleAc, g_runtimeHotkeysLen)) return false;
    if (!ensureRuntimeAcOutputCapacity(&g_runtimeWebsiteAc, g_runtimeHotkeysLen)) return false;
    runtimeAcReset(&g_runtimeTitleAc);
    runtimeAcReset(&g_runtimeWebsiteAc);
    if (g_runtimeTitleAc.overflowed or g_runtimeWebsiteAc.overflowed) return false;
    if (g_runtimeAcFallback.len != 0) @memset(g_runtimeAcFallback, false);

    var i: usize = 0;
    while (i < g_runtimeHotkeysLen) : (i += 1) {
        const hk = g_runtimeHotkeys[i];
        if (hk.specificityMask == 0) continue; // Global rows are permanently active.
        const ctx = runtimeContextText(i);
        const parsed = parseCachedAhkCriterion(ctx);
        var pattern: []const u16 = &.{};
        var added = true;
        if ((hk.specificityMask & RUNTIME_CONTEXT_WEBSITE_BIT) != 0) {
            pattern = if (parsed.title.len != 0) parsed.title else ctx;
            added = runtimeAcAddPattern(&g_runtimeWebsiteAc, pattern, i);
        } else if ((hk.specificityMask & RUNTIME_CONTEXT_TITLE_BIT) != 0) {
            pattern = if (parsed.title.len != 0) parsed.title else ctx;
            added = runtimeAcAddPattern(&g_runtimeTitleAc, pattern, i);
        }
        if (!added) g_runtimeAcFallback[i] = true;
    }
    runtimeAcBuildFailures(&g_runtimeTitleAc);
    runtimeAcBuildFailures(&g_runtimeWebsiteAc);
    return !g_runtimeTitleAc.overflowed and !g_runtimeWebsiteAc.overflowed;
}

fn evaluateRuntimeSubstringContexts() void {
    if (g_runtimeTitleMatched.len != 0) @memset(g_runtimeTitleMatched, false);
    if (g_runtimeWebsiteMatched.len != 0) @memset(g_runtimeWebsiteMatched, false);
    runtimeAcScan(&g_runtimeTitleAc, wideSpan(&g_hotkeyContextState.win_title), g_runtimeTitleMatched);
    runtimeAcScan(&g_runtimeWebsiteAc, wideSpan(&g_hotkeyContextState.url), g_runtimeWebsiteMatched);
}

fn rebuildCompiledContextAutomata() void {
    if (comptime !has_qmk_shortcuts_build) return;
    if (!ensureRuntimeAcOutputCapacity(&g_compiledTitleAc, hotkeys.HOTKEYS.len)) return;
    if (!ensureRuntimeAcOutputCapacity(&g_compiledWebsiteAc, hotkeys.HOTKEYS.len)) return;
    runtimeAcReset(&g_compiledTitleAc);
    runtimeAcReset(&g_compiledWebsiteAc);
    if (g_compiledTitleAc.overflowed or g_compiledWebsiteAc.overflowed) return;
    @memset(&g_compiledAcFallback, false);

    for (hotkeys.HOTKEYS, 0..) |hk, index| {
        if (hk.context_kind == .global) continue;
        var added = true;
        if (hk.context_kind == .website) {
            added = runtimeAcAddPattern(&g_compiledWebsiteAc, hk.win_title, index);
        } else {
            const parsed = g_parsedHotkeyContexts[index];
            if (parsed.title.len != 0) {
                added = runtimeAcAddPattern(&g_compiledTitleAc, parsed.title, index);
            }
        }
        if (!added) g_compiledAcFallback[index] = true;
    }
    runtimeAcBuildFailures(&g_compiledTitleAc);
    runtimeAcBuildFailures(&g_compiledWebsiteAc);
}

fn evaluateCompiledSubstringContexts() void {
    @memset(&g_compiledTitleMatched, false);
    @memset(&g_compiledWebsiteMatched, false);
    runtimeAcScan(&g_compiledTitleAc, wideSpan(&g_hotkeyContextState.win_title), g_compiledTitleMatched[0..]);
    runtimeAcScan(&g_compiledWebsiteAc, wideSpan(&g_hotkeyContextState.url), g_compiledWebsiteMatched[0..]);
}

const CachedAhkCriterion = struct {
    title: []const u16 = &.{},
    class_name: []const u16 = &.{},
    exe: []const u16 = &.{},
};

var g_parsedHotkeyContexts: [hotkeys.HOTKEYS.len]CachedAhkCriterion = [_]CachedAhkCriterion{.{}} ** hotkeys.HOTKEYS.len;
var g_hotkeyContextsParsed: bool = false;
var g_hotkeyContextsAllowed: [hotkeys.HOTKEYS.len]bool = [_]bool{false} ** hotkeys.HOTKEYS.len;

const CompiledHotkeyReadyBank = struct {
    keydown: hotkeys.HotkeyIndex = .{
        .ranges = [_][16]hotkeys.HotkeyRange{[_]hotkeys.HotkeyRange{.{}} ** 16} ** 256,
        .source_indexes = [_]u16{0} ** hotkeys.HOTKEY_SOURCE_INDEX_MAX,
    },
    keyup: hotkeys.HotkeyIndex = .{
        .ranges = [_][16]hotkeys.HotkeyRange{[_]hotkeys.HotkeyRange{.{}} ** 16} ** 256,
        .source_indexes = [_]u16{0} ** hotkeys.HOTKEY_SOURCE_INDEX_MAX,
    },
    active_gate: [256]bool = [_]bool{false} ** 256,
};

var g_compiledHotkeyReadyBanks: [2]CompiledHotkeyReadyBank = .{ .{}, .{} };
var g_activeCompiledHotkeyReadyIndex: u32 = 0;

inline fn runtimeHotkeyModifiersAllow(hk: RuntimeHotkey, active_mods: u16) bool {
    return (active_mods & hk.modsRequired) == hk.modsRequired and
        (active_mods & hk.modsForbidden) == 0;
}

const RUNTIME_HOTKEY_OPTION_SUSPEND_EXEMPT: u32 = 1 << 5;

inline fn runtimeHotkeySuspendExemptFromOptions(option_bits: u32) bool {
    return (option_bits & RUNTIME_HOTKEY_OPTION_SUSPEND_EXEMPT) != 0;
}

fn buildRuntimeGlobalHotkeyIndex(next: u32) bool {
    const global = &g_runtimeGlobalHotkeyIndexes[next];
    if (!ensureRuntimeHotkeyReadyIndexCapacity(global, g_runtimeHotkeysLen * RUNTIME_MOD_BUCKET_COUNT)) return false;
    clearRuntimeHotkeyReadyIndex(global);

    var counts: [VK_COUNT][RUNTIME_MOD_BUCKET_COUNT]u32 = [_][RUNTIME_MOD_BUCKET_COUNT]u32{
        [_]u32{0} ** RUNTIME_MOD_BUCKET_COUNT,
    } ** VK_COUNT;

    var i: usize = 0;
    while (i < g_runtimeHotkeysLen) : (i += 1) {
        const hk = g_runtimeHotkeys[i];
        if (runtimeHotkeyOverriddenByRuntime(i)) continue;
        if (hk.specificityMask != 0) continue;
        if (hk.contextNegated) continue;
        if (hk.triggerVK <= 0 or hk.triggerVK >= VK_COUNT) continue;
        const vk: usize = @intCast(hk.triggerVK);
        global.activeGate[vk] = true;
        var bucket: usize = 0;
        while (bucket < RUNTIME_MOD_BUCKET_COUNT) : (bucket += 1) {
            if (runtimeHotkeyModifiersAllow(hk, @intCast(bucket))) counts[vk][bucket] += 1;
        }
    }

    var next_start: u32 = 0;
    var vk: usize = 0;
    while (vk < VK_COUNT) : (vk += 1) {
        var bucket: usize = 0;
        while (bucket < RUNTIME_MOD_BUCKET_COUNT) : (bucket += 1) {
            global.ranges[vk][bucket] = .{ .start = next_start, .len = counts[vk][bucket] };
            next_start += counts[vk][bucket];
        }
    }

    var cursors: [VK_COUNT][RUNTIME_MOD_BUCKET_COUNT]u32 = [_][RUNTIME_MOD_BUCKET_COUNT]u32{
        [_]u32{0} ** RUNTIME_MOD_BUCKET_COUNT,
    } ** VK_COUNT;
    i = 0;
    while (i < g_runtimeHotkeysLen) : (i += 1) {
        const hk = g_runtimeHotkeys[i];
        if (runtimeHotkeyOverriddenByRuntime(i)) continue;
        if (hk.specificityMask != 0 or hk.contextNegated) continue;
        if (hk.triggerVK <= 0 or hk.triggerVK >= VK_COUNT) continue;
        const hotkey_vk: usize = @intCast(hk.triggerVK);
        var bucket: usize = 0;
        while (bucket < RUNTIME_MOD_BUCKET_COUNT) : (bucket += 1) {
            if (!runtimeHotkeyModifiersAllow(hk, @intCast(bucket))) continue;
            const write_at: usize = @intCast(global.ranges[hotkey_vk][bucket].start + cursors[hotkey_vk][bucket]);
            global.sourceIndexes[write_at] = @intCast(i);
            cursors[hotkey_vk][bucket] += 1;
        }
    }
    return true;
}

fn rebuildActiveRuntimeHotkeyIndex() bool {
    const rebuild_global = g_runtimeHotkeyContextsDirty;
    const next_global: u32 = if (rebuild_global)
        @atomicLoad(u32, &g_activeRuntimeGlobalHotkeyIndex, .acquire) ^ 1
    else
        @atomicLoad(u32, &g_activeRuntimeGlobalHotkeyIndex, .acquire);
    if (g_runtimeHotkeyContextsDirty) {
        if (!rebuildRuntimeContextAutomata()) return false;
        if (!buildRuntimeGlobalHotkeyIndex(next_global)) return false;
    }
    evaluateRuntimeSubstringContexts();
    const current = @atomicLoad(u32, &g_activeRuntimeHotkeyReadyIndex, .acquire);
    const next: u32 = current ^ 1;
    const ready = &g_runtimeHotkeyReadyIndexes[next];
    if (!ensureRuntimeHotkeyReadyIndexCapacity(ready, g_runtimeHotkeysLen * RUNTIME_MOD_BUCKET_COUNT)) return false;
    clearRuntimeHotkeyReadyIndex(ready);

    var counts: [VK_COUNT][RUNTIME_MOD_BUCKET_COUNT]u32 = [_][RUNTIME_MOD_BUCKET_COUNT]u32{
        [_]u32{0} ** RUNTIME_MOD_BUCKET_COUNT,
    } ** VK_COUNT;

    const allowed = gAlloc.alloc(bool, g_runtimeHotkeysLen) catch return false;
    defer gAlloc.free(allowed);
    @memset(allowed, false);
    var i: usize = 0;
    while (i < g_runtimeHotkeysLen) : (i += 1) {
        const hk = g_runtimeHotkeys[i];
        if (runtimeHotkeyOverriddenByRuntime(i)) continue;
        if (hk.specificityMask == 0) continue; // Globals live in the permanent index.
        allowed[i] = runtimeHotkeyContextAllows(i);
        if (!allowed[i]) continue;
        if (hk.triggerVK <= 0 or hk.triggerVK >= VK_COUNT) continue;
        const vk: usize = @intCast(hk.triggerVK);
        ready.activeGate[vk] = true;
        var bucket: usize = 0;
        while (bucket < RUNTIME_MOD_BUCKET_COUNT) : (bucket += 1) {
            if (runtimeHotkeyModifiersAllow(hk, @intCast(bucket))) counts[vk][bucket] += 1;
        }
    }

    var next_start: u32 = 0;
    var vk: usize = 0;
    while (vk < VK_COUNT) : (vk += 1) {
        var bucket: usize = 0;
        while (bucket < RUNTIME_MOD_BUCKET_COUNT) : (bucket += 1) {
            ready.ranges[vk][bucket] = .{ .start = next_start, .len = counts[vk][bucket] };
            next_start += counts[vk][bucket];
        }
    }

    var cursors: [VK_COUNT][RUNTIME_MOD_BUCKET_COUNT]u32 = [_][RUNTIME_MOD_BUCKET_COUNT]u32{
        [_]u32{0} ** RUNTIME_MOD_BUCKET_COUNT,
    } ** VK_COUNT;
    i = 0;
    while (i < g_runtimeHotkeysLen) : (i += 1) {
        if (runtimeHotkeyOverriddenByRuntime(i)) continue;
        if (!allowed[i]) continue;
        const hk = g_runtimeHotkeys[i];
        if (hk.triggerVK <= 0 or hk.triggerVK >= VK_COUNT) continue;
        const hotkey_vk: usize = @intCast(hk.triggerVK);
        var bucket: usize = 0;
        while (bucket < RUNTIME_MOD_BUCKET_COUNT) : (bucket += 1) {
            if (!runtimeHotkeyModifiersAllow(hk, @intCast(bucket))) continue;
            const write_at: usize = @intCast(ready.ranges[hotkey_vk][bucket].start + cursors[hotkey_vk][bucket]);
            ready.sourceIndexes[write_at] = @intCast(i);
            cursors[hotkey_vk][bucket] += 1;
        }
    }

    // Descending context specificity, stable registration order for exact ties.
    vk = 0;
    while (vk < VK_COUNT) : (vk += 1) {
        var bucket: usize = 0;
        while (bucket < RUNTIME_MOD_BUCKET_COUNT) : (bucket += 1) {
            const range = ready.ranges[vk][bucket];
            var offset: u32 = 1;
            while (offset < range.len) : (offset += 1) {
                const absolute: usize = @intCast(range.start + offset);
                const current_index: usize = @intCast(ready.sourceIndexes[absolute]);
                const current_mask = g_runtimeHotkeys[current_index].specificityMask;
                var pos: usize = absolute;
                const range_start: usize = @intCast(range.start);
                while (pos > range_start) {
                    const previous_index: usize = @intCast(ready.sourceIndexes[pos - 1]);
                    if (current_mask <= g_runtimeHotkeys[previous_index].specificityMask) break;
                    ready.sourceIndexes[pos] = @intCast(previous_index);
                    pos -= 1;
                }
                ready.sourceIndexes[pos] = @intCast(current_index);
            }
        }
    }

    @atomicStore(u32, &g_activeRuntimeHotkeyReadyIndex, next, .release);
    if (rebuild_global) @atomicStore(u32, &g_activeRuntimeGlobalHotkeyIndex, next_global, .release);
    g_runtimeHotkeyContextsDirty = false;
    publishCombinedHotkeyGate();
    return true;
}

fn requestRuntimeHotkeyIndexRebuild() void {
    g_runtimeHotkeyContextsDirty = true;
    if (g_bulkSetupDepth == 0) _ = rebuildActiveRuntimeHotkeyIndex();
}

fn rebuildCompiledContextReadyIndex() void {
    if (comptime !has_qmk_shortcuts_build) return;

    const current = @atomicLoad(u32, &g_activeCompiledHotkeyReadyIndex, .acquire);
    const next: u32 = current ^ 1;
    var ready = &g_compiledHotkeyReadyBanks[next];
    ready.* = .{};

    const source_indexes = [_]*const hotkeys.HotkeyIndex{
        &hotkeys.CONTEXT_KEYDOWN_INDEX,
        &hotkeys.CONTEXT_KEYUP_INDEX,
    };
    const destinations = [_]*hotkeys.HotkeyIndex{ &ready.keydown, &ready.keyup };

    for (source_indexes, destinations) |source, destination| {
        var write_at: u16 = 0;
        for (0..256) |vk| {
            for (0..16) |bucket| {
                const source_range = source.ranges[vk][bucket];
                const destination_start = write_at;
                var offset: u16 = 0;
                while (offset < source_range.len) : (offset += 1) {
                    const source_index = source.source_indexes[source_range.start + offset];
                    if (!g_hotkeyContextsAllowed[source_index]) continue;
                    destination.source_indexes[write_at] = source_index;
                    write_at += 1;
                    ready.active_gate[vk] = true;
                }
                destination.ranges[vk][bucket] = .{
                    .start = destination_start,
                    .len = write_at - destination_start,
                };
            }
        }
    }

    @atomicStore(u32, &g_activeCompiledHotkeyReadyIndex, next, .release);
    publishCombinedHotkeyGate();
}

inline fn runtimeContextActionText(index: usize) []const u16 {
    const len: usize = @intCast(g_runtimeContextActions[index].contextLen);
    return g_runtimeContextActionTexts[index][0..len];
}

/// Evaluates one parsed context criterion against the cached window state.
/// Shared by runtime context actions, tap/hold rows, and runtime hotstrings so
/// every runtime context family resolves identically.
fn runtimeContextCriterionAllows(specificity_mask: u8, negated: bool, ctx: []const u16) bool {
    if (specificity_mask == 0) return !negated;
    const parsed = parseCachedAhkCriterion(ctx);
    var matched = true;
    if ((specificity_mask & RUNTIME_CONTEXT_WEBSITE_BIT) != 0) {
        const pattern = if (parsed.title.len != 0) parsed.title else ctx;
        matched = matched and wideContains(&g_hotkeyContextState.url, pattern);
    } else if ((specificity_mask & RUNTIME_CONTEXT_TITLE_BIT) != 0) {
        const pattern = if (parsed.title.len != 0) parsed.title else ctx;
        matched = matched and wideContains(&g_hotkeyContextState.win_title, pattern);
    }
    if ((specificity_mask & RUNTIME_CONTEXT_CLASS_BIT) != 0) {
        const value = if (parsed.class_name.len != 0) parsed.class_name else if (startsWithAsciiIgnoreCase16(ctx, "ahk_class")) trimSpaces16(ctx[9..]) else ctx;
        matched = matched and wideEquals(&g_hotkeyContextState.win_class, value);
    }
    if ((specificity_mask & RUNTIME_CONTEXT_EXE_BIT) != 0) {
        const value = if (parsed.exe.len != 0) parsed.exe else if (startsWithAsciiIgnoreCase16(ctx, "ahk_exe")) trimSpaces16(ctx[7..]) else ctx;
        matched = matched and runtimeExeMatches(&g_hotkeyContextState.win_exe, value);
    }
    if ((specificity_mask & RUNTIME_CONTEXT_BROWSER_BIT) != 0) matched = matched and runtimeHotkeyBrowserContextAllows();
    if ((specificity_mask & RUNTIME_CONTEXT_MENU_BIT) != 0) matched = matched and g_hotkeyContextState.has_context_menu != 0;
    return if (negated) !matched else matched;
}

fn runtimeContextActionAllows(index: usize) bool {
    const action = g_runtimeContextActions[index];
    if (@atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire) != 0 and !action.suspendExempt) return false;
    return runtimeContextCriterionAllows(action.specificityMask, action.contextNegated, runtimeContextActionText(index));
}

inline fn runtimeModifierText(index: usize) []const u16 {
    const len: usize = @intCast(g_runtimeModifiers[index].contextLen);
    return g_runtimeModifierTexts[index][0..len];
}

fn runtimeModifierAllows(index: usize) bool {
    const row = g_runtimeModifiers[index];
    if (@atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire) != 0 and !row.suspendExempt) return false;
    return runtimeContextCriterionAllows(row.specificityMask, row.contextNegated, runtimeModifierText(index));
}

inline fn runtimePassthroughText(index: usize) []const u16 {
    const len: usize = @intCast(g_runtimePassthroughs[index].contextLen);
    return g_runtimePassthroughTexts[index][0..len];
}

fn runtimePassthroughAllows(index: usize) bool {
    const row = g_runtimePassthroughs[index];
    if (@atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire) != 0 and !row.suspendExempt) return false;
    return runtimeContextCriterionAllows(row.specificityMask, row.contextNegated, runtimePassthroughText(index));
}

inline fn activeRuntimePassthroughs() *const RuntimePassthroughActiveBank {
    const idx = @atomicLoad(u32, &g_activeRuntimePassthroughBank, .acquire);
    return &g_runtimePassthroughActiveBanks[idx];
}

inline fn activeRuntimeContextActions() *const RuntimeContextActionActiveBank {
    const idx = @atomicLoad(u32, &g_activeRuntimeContextActionBank, .acquire);
    return &g_runtimeContextActionActiveBanks[idx];
}

inline fn effectiveHoldCallbackId(vk: usize) i32 {
    const runtime_id = activeRuntimeContextActions().hold[vk];
    return if (runtime_id >= 0 or isCompiledZigCallbackId(runtime_id)) runtime_id else g_hcFlat[vk];
}

inline fn effectiveDoubleTapCallbackId(vk: usize) i32 {
    const runtime_id = activeRuntimeContextActions().doubleTap[vk];
    return if (runtime_id >= 0 or isCompiledZigCallbackId(runtime_id)) runtime_id else g_modDtFlat[vk];
}

inline fn effectiveTapHoldTapCallbackId(vk: usize) i32 {
    const bank = activeRuntimeContextActions();
    if (bank.tapHoldTuningSet[vk]) return bank.tapHoldTap[vk];
    return if (bank.tapHoldTap[vk] >= 0 or isCompiledZigCallbackId(bank.tapHoldTap[vk])) bank.tapHoldTap[vk] else g_tapHoldTapCallbackId[vk];
}

inline fn effectiveTapHoldHoldCallbackId(vk: usize) i32 {
    const bank = activeRuntimeContextActions();
    if (bank.tapHoldTuningSet[vk]) return bank.tapHoldHold[vk];
    return if (bank.tapHoldHold[vk] >= 0 or isCompiledZigCallbackId(bank.tapHoldHold[vk])) bank.tapHoldHold[vk] else g_tapHoldHoldCallbackId[vk];
}

inline fn effectiveTapHoldCleanupCallbackId(vk: usize) i32 {
    const bank = activeRuntimeContextActions();
    return if (bank.tapHoldTuningSet[vk]) bank.tapHoldCleanup[vk] else g_tapHoldCleanupCallbackId[vk];
}

inline fn effectiveTapHoldThresholdTicks(vk: usize) i64 {
    const bank = activeRuntimeContextActions();
    return if (bank.tapHoldTuningSet[vk] and bank.tapHoldThreshold[vk] > 0)
        bank.tapHoldThreshold[vk]
    else if (g_tapHoldThreshold[vk] > 0)
        g_tapHoldThreshold[vk]
    else
        msToTicksInt(200);
}

inline fn activeRuntimeModifiers() *const RuntimeModifierActiveBank {
    const idx = @atomicLoad(u32, &g_activeRuntimeModifierBank, .acquire);
    return &g_runtimeModifierActiveBanks[idx];
}

inline fn effectiveModType(vk: usize) i8 {
    const runtime_type = activeRuntimeModifiers().modType[vk];
    return if (runtime_type != MOD_NONE) runtime_type else g_modTypeFlat[vk];
}

fn rebuildActiveRuntimeModifiers() bool {
    const current = @atomicLoad(u32, &g_activeRuntimeModifierBank, .acquire);
    const next: u32 = current ^ 1;
    const bank = &g_runtimeModifierActiveBanks[next];
    bank.* = .{};

    var best_seen: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
    var best_mask: [VK_COUNT]u8 = [_]u8{0} ** VK_COUNT;
    var i: usize = 0;
    while (i < g_runtimeModifiersLen) : (i += 1) {
        if (runtimeModifierOverriddenByRuntime(i)) continue;
        if (!runtimeModifierAllows(i)) continue;
        const row = g_runtimeModifiers[i];
        if (row.vk <= 0 or row.vk >= VK_COUNT) continue;
        const row_vk: usize = @intCast(row.vk);
        // Compiled rows occupy the prefix and runtime rows are appended.  A
        // runtime row with the same key/context identity must replace the
        // compiled row even when its specificity is equal; its modifier type
        // is the runtime takeover payload.
        if (!best_seen[row_vk] or row.specificityMask > best_mask[row_vk] or
            (row.specificityMask == best_mask[row_vk] and i >= g_compiledModifiersLen)) {
            best_seen[row_vk] = true;
            bank.modType[row_vk] = row.modType;
            best_mask[row_vk] = row.specificityMask;
        }
    }
    @atomicStore(u32, &g_activeRuntimeModifierBank, next, .release);
    return true;
}

fn rebuildActiveRuntimeContextActions() bool {
    const current = @atomicLoad(u32, &g_activeRuntimeContextActionBank, .acquire);
    const next: u32 = current ^ 1;
    const bank = &g_runtimeContextActionActiveBanks[next];
    bank.* = .{};
    // These are callback-ID slots, not booleans.  Explicitly restore the
    // runtime sentinel after clearing the bank so an unregistered key can
    // never be mistaken for compiled callback slot 0 during key-gate rebuild.
    @memset(&bank.hold, -1);
    @memset(&bank.doubleTap, -1);
    @memset(&bank.tapHoldTap, -1);
    @memset(&bank.tapHoldHold, -1);
    @memset(&bank.tapHoldCleanup, -1);

    var best_hold_mask: [VK_COUNT]u8 = [_]u8{0} ** VK_COUNT;
    var best_double_mask: [VK_COUNT]u8 = [_]u8{0} ** VK_COUNT;
    var best_th_tap_mask: [VK_COUNT]u8 = [_]u8{0} ** VK_COUNT;
    var best_th_hold_mask: [VK_COUNT]u8 = [_]u8{0} ** VK_COUNT;
    var best_th_tuning_mask: [VK_COUNT]u8 = [_]u8{0} ** VK_COUNT;
    var hold_seen: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
    var double_seen: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
    var th_tap_seen: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
    var th_hold_seen: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
    var th_tuning_seen: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;

    var i: usize = 0;
    while (i < g_runtimeContextActionsLen) : (i += 1) {
        const action = g_runtimeContextActions[i];
        if (runtimeContextActionOverriddenByRuntime(i)) continue;
        if (!runtimeContextActionAllows(i)) continue;
        const vk: usize = @intCast(action.triggerVK);
        switch (action.actionKind) {
            0 => if (!hold_seen[vk] or action.specificityMask > best_hold_mask[vk] or
                (action.specificityMask == best_hold_mask[vk] and i >= g_compiledContextActionsLen)) {
                hold_seen[vk] = true;
                bank.hold[vk] = action.callbackId;
                best_hold_mask[vk] = action.specificityMask;
            },
            1 => if (!double_seen[vk] or action.specificityMask > best_double_mask[vk] or
                (action.specificityMask == best_double_mask[vk] and i >= g_compiledContextActionsLen)) {
                double_seen[vk] = true;
                bank.doubleTap[vk] = action.callbackId;
                best_double_mask[vk] = action.specificityMask;
            },
            2 => if (!th_tap_seen[vk] or action.specificityMask > best_th_tap_mask[vk] or
                (action.specificityMask == best_th_tap_mask[vk] and i >= g_compiledContextActionsLen)) {
                th_tap_seen[vk] = true;
                bank.tapHoldTap[vk] = action.callbackId;
                best_th_tap_mask[vk] = action.specificityMask;
            },
            3 => if (!th_hold_seen[vk] or action.specificityMask > best_th_hold_mask[vk] or
                (action.specificityMask == best_th_hold_mask[vk] and i >= g_compiledContextActionsLen)) {
                th_hold_seen[vk] = true;
                bank.tapHoldHold[vk] = action.callbackId;
                best_th_hold_mask[vk] = action.specificityMask;
            },
            else => if (!th_tuning_seen[vk] or action.specificityMask > best_th_tuning_mask[vk] or
                (action.specificityMask == best_th_tuning_mask[vk] and i >= g_compiledContextActionsLen)) {
                th_tuning_seen[vk] = true;
                bank.tapHoldTap[vk] = action.tapCallbackId;
                bank.tapHoldHold[vk] = action.holdCallbackId;
                bank.tapHoldCleanup[vk] = action.callbackId;
                bank.tapHoldThreshold[vk] = action.thresholdTicks;
                bank.tapHoldTuningSet[vk] = true;
                best_th_tuning_mask[vk] = action.specificityMask;
            },
        }
    }
    @atomicStore(u32, &g_activeRuntimeContextActionBank, next, .release);
    return true;
}

inline fn runtimeComboText(index: usize) []const u16 {
    const len: usize = @intCast(g_runtimeCombos[index].contextLen);
    return g_runtimeComboTexts[index][0..len];
}

inline fn runtimeInstantComboText(index: usize) []const u16 {
    const len: usize = @intCast(g_runtimeInstantCombos[index].contextLen);
    return g_runtimeInstantComboTexts[index][0..len];
}

inline fn runtimeComboAllows(row: RuntimeCombo, ctx: []const u16) bool {
    if (@atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire) != 0 and !row.suspendExempt) return false;
    return runtimeContextCriterionAllows(row.specificityMask, row.contextNegated, ctx);
}

fn clearRuntimeComboBank(bank: *RuntimeComboActiveBank) void {
    bank.* = .{};
}

fn clearActiveRuntimeComboTables() void {
    g_runtimeComboActiveBanks[0] = .{};
    g_runtimeComboActiveBanks[1] = .{};
    @atomicStore(u32, &g_activeRuntimeComboBank, 0, .release);
}

fn applyActiveRuntimeCombo(bank: *RuntimeComboActiveBank, row: RuntimeCombo) void {
    if (row.primaryVK <= 0 or row.primaryVK >= VK_COUNT or row.secondaryVK <= 0 or row.secondaryVK >= VK_COUNT) return;
    const p: usize = @intCast(row.primaryVK);
    const s: usize = @intCast(row.secondaryVK);
    switch (row.mode) {
        1 => {
            bank.instantPrimary[p] = true;
            bank.instantMatrix[p][s] = true;
            bank.instantRemapTarget[p][s] = 0;
            bank.instantRemapMask[p][s] = 0;
            bank.instantCallback[p][s] = row.callbackId;
        },
        2 => {
            if (row.targetVK == 0) return;
            // Compiled native remaps use the same runtime combo bank as
            // SetupCombos, but they do not pass through setupInternalComboVK.
            // Keep the common modifier/send path aware of them as well.
            g_hasInternalCombos = true;
            bank.comboPrimary[p] = true;
            bank.comboMatrix[p][s] = true;
            bank.comboCallback[p][s] = -1;
            bank.comboRemapTarget[p][s] = row.targetVK;
            bank.comboRemapMask[p][s] = row.modMask;
        },
        3 => {
            if (row.targetVK == 0) return;
            g_hasInternalCombos = true;
            bank.instantPrimary[p] = true;
            bank.instantMatrix[p][s] = true;
            bank.instantCallback[p][s] = -1;
            bank.instantRemapTarget[p][s] = row.targetVK;
            bank.instantRemapMask[p][s] = row.modMask;
        },
        else => {
            bank.comboPrimary[p] = true;
            bank.comboMatrix[p][s] = true;
            bank.comboRemapTarget[p][s] = 0;
            bank.comboRemapMask[p][s] = 0;
            bank.comboCallback[p][s] = row.callbackId;
        },
    }
}

fn rebuildActiveRuntimeCombos() bool {
    const current = @atomicLoad(u32, &g_activeRuntimeComboBank, .acquire);
    const next: u32 = current ^ 1;
    const bank = &g_runtimeComboActiveBanks[next];
    clearRuntimeComboBank(bank);

    // Normal, instant, internal, and internal-instant rows compete as one
    // primary+secondary identity. Merge the two append-ordered stores by the
    // registration sequence so an exact context-rank tie naturally keeps the
    // first registration without another comparison field in the winner table.
    const NO_COMBO_SOURCE: u16 = 0xFFFF;
    const INSTANT_SOURCE_BIT: u16 = 0x8000;
    var best_mask: [VK_COUNT][VK_COUNT]u8 = [_][VK_COUNT]u8{[_]u8{0} ** VK_COUNT} ** VK_COUNT;
    var best_source: [VK_COUNT][VK_COUNT]u16 = [_][VK_COUNT]u16{[_]u16{NO_COMBO_SOURCE} ** VK_COUNT} ** VK_COUNT;

    var normal_i: usize = 0;
    var instant_i: usize = 0;
    while (normal_i < g_runtimeCombosLen or instant_i < g_runtimeInstantCombosLen) {
        const take_normal = instant_i >= g_runtimeInstantCombosLen or
            (normal_i < g_runtimeCombosLen and
                g_runtimeCombos[normal_i].registrationOrder < g_runtimeInstantCombos[instant_i].registrationOrder);
        const row = if (take_normal) g_runtimeCombos[normal_i] else g_runtimeInstantCombos[instant_i];
        const row_index = if (take_normal) normal_i else instant_i;
        // Only the compiled preload prefix may be displaced.  A runtime row
        // lives in the suffix being searched by runtimeComboOverriddenByRuntime;
        // asking that helper about the runtime row itself makes it find itself
        // and suppress the overlay (and, consequently, the compiled row too).
        const is_compiled_preload = if (take_normal)
            row_index < g_compiledCombosLen
        else
            row_index < g_compiledInstantCombosLen;
        const allowed = if (take_normal)
            runtimeComboAllows(row, runtimeComboText(row_index))
        else
            runtimeComboAllows(row, runtimeInstantComboText(row_index));
        if (allowed and (!is_compiled_preload or !runtimeComboOverriddenByRuntime(row, if (take_normal)
            runtimeComboText(row_index)
        else
            runtimeInstantComboText(row_index)))) {
            const p: usize = @intCast(row.primaryVK);
            const sec: usize = @intCast(row.secondaryVK);
            if (best_source[p][sec] == NO_COMBO_SOURCE or row.specificityMask > best_mask[p][sec]) {
                best_mask[p][sec] = row.specificityMask;
                best_source[p][sec] = if (take_normal)
                    @intCast(row_index)
                else
                    INSTANT_SOURCE_BIT | @as(u16, @intCast(row_index));
            }
        }
        if (take_normal) normal_i += 1 else instant_i += 1;
    }

    var p: usize = 0;
    while (p < VK_COUNT) : (p += 1) {
        var sec: usize = 0;
        while (sec < VK_COUNT) : (sec += 1) {
            const source = best_source[p][sec];
            if (source == NO_COMBO_SOURCE) continue;
            const is_instant_store = (source & INSTANT_SOURCE_BIT) != 0;
            const source_index: usize = @intCast(source & ~INSTANT_SOURCE_BIT);
            applyActiveRuntimeCombo(bank, if (is_instant_store)
                g_runtimeInstantCombos[source_index]
            else
                g_runtimeCombos[source_index]);
        }
    }

    @atomicStore(u32, &g_activeRuntimeComboBank, next, .release);
    return true;
}

inline fn runtimeChordText(index: usize) []const u16 {
    const len: usize = @intCast(g_runtimeChords[index].contextLen);
    return g_runtimeChordTexts[index][0..len];
}

fn runtimeChordOverriddenByRuntime(index: usize) bool {
    if (index >= g_compiledChordsLen) return false;
    const compiled = g_runtimeChords[index];
    var runtime_index = g_compiledChordsLen;
    while (runtime_index < g_runtimeChordsLen) : (runtime_index += 1) {
        const runtime = g_runtimeChords[runtime_index];
        if (runtime.key != compiled.key or runtime.keyCount != compiled.keyCount or
            runtime.mode != compiled.mode or
            runtime.contextKind != compiled.contextKind or runtime.contextNegated != compiled.contextNegated) continue;
        if (!std.mem.eql(i32, runtime.vks[0..@as(usize, @intCast(runtime.keyCount))],
            compiled.vks[0..@as(usize, @intCast(compiled.keyCount))])) continue;
        if (runtimeContextTextEqual(runtimeChordText(index), runtimeChordText(runtime_index))) return true;
    }
    return false;
}

inline fn runtimeChordAllows(index: usize) bool {
    const row = g_runtimeChords[index];
    if (@atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire) != 0 and !row.suspendExempt) return false;
    return runtimeContextCriterionAllows(row.specificityMask, row.contextNegated, runtimeChordText(index));
}

fn clearRuntimeChordBank(bank: *RuntimeChordActiveBank) void {
    if (bank.hotTable.len != 0) @memset(bank.hotTable, ChordHotEntry{});
    if (bank.extCache.len != 0) @memset(bank.extCache, ExtChordCacheEntry{});
    bank.extCacheLen = 0;
    @memset(&bank.participant, false);
    bank.hasInternal = false;
    bank.hasExternal = false;
    bank.hasAny = false;
}

fn clearActiveRuntimeChordTables() void {
    clearRuntimeChordBank(&g_runtimeChordActiveBanks[0]);
    clearRuntimeChordBank(&g_runtimeChordActiveBanks[1]);
    @atomicStore(u32, &g_activeRuntimeChordBank, 0, .release);
}

fn nextPowerOfTwoAtLeast(value: usize) usize {
    var n: usize = 1;
    while (n < value) : (n *= 2) {}
    return n;
}

fn ensureRuntimeChordActiveBankCapacity(bank: *RuntimeChordActiveBank, chord_count: usize) bool {
    const desired_hot = nextPowerOfTwoAtLeast(@max(STATIC_CHORD_HOT_INITIAL_SLOTS, chord_count * 2));
    if (bank.hotTable.len < desired_hot) {
        const new_hot = gAlloc.alloc(ChordHotEntry, desired_hot) catch return false;
        @memset(new_hot, ChordHotEntry{});
        const old_hot = bank.hotTable;
        bank.hotTable = new_hot;
        retireSlice(ChordHotEntry, old_hot);
    }

    const desired_ext = @max(EXT_CHORD_CACHE_INITIAL_CAP, chord_count);
    if (bank.extCache.len < desired_ext) {
        const new_ext = gAlloc.alloc(ExtChordCacheEntry, desired_ext) catch return false;
        @memset(new_ext, ExtChordCacheEntry{});
        const old_ext = bank.extCache;
        bank.extCache = new_ext;
        retireSlice(ExtChordCacheEntry, old_ext);
    }
    return true;
}

fn runtimeChordCacheExternal(bank: *RuntimeChordActiveBank, row: RuntimeChord) void {
    if (bank.extCacheLen >= bank.extCache.len) return;
    var entry = ExtChordCacheEntry{ .keyCount = row.keyCount };
    var mask: u16 = 0;
    var i: usize = 0;
    while (i < @as(usize, @intCast(row.keyCount)) and i < row.vks.len) : (i += 1) {
        entry.vks[i] = row.vks[i];
        if (row.vks[i] >= 0 and row.vks[i] < VK_COUNT) {
            mask |= @as(u16, @intCast(g_key_virtual_modifier_mask[@intCast(row.vks[i])]));
        }
    }
    entry.modMask = mask;
    bank.extCache[bank.extCacheLen] = entry;
    bank.extCacheLen += 1;
}

fn applyActiveRuntimeChord(bank: *RuntimeChordActiveBank, row: RuntimeChord) void {
    if (row.key == 0 or row.keyCount < 2) return;
    bank.hasAny = true;
    const kind = if (row.mode == 1) ChordHotKind.internal else ChordHotKind.external;
    if (row.mode == 1) {
        if (row.targetVK == 0) return;
        bank.hasInternal = true;
    } else {
        // Complete-compile AHK callbacks use the reserved negative compiled
        // range.  They are still external chord actions and must remain in
        // the active chord cache so the later IPC dispatch can reach AHK.
        if (row.callbackId < 0 and !isCompiledZigCallbackId(row.callbackId)) return;
        bank.hasExternal = true;
        runtimeChordCacheExternal(bank, row);
    }
    _ = chordHotPutInto(bank.hotTable, .{
        .key = row.key,
        .targetVK = row.targetVK,
        .callbackId = row.callbackId,
        .modMask = row.modMask,
        .keyCount = row.keyCount,
        .kind = @intFromEnum(kind),
    });
    var i: usize = 0;
    while (i < @as(usize, @intCast(row.keyCount)) and i < row.vks.len) : (i += 1) {
        const vk = row.vks[i];
        if (vk >= 0 and vk < VK_COUNT) bank.participant[@intCast(vk)] = true;
    }
}

fn rebuildActiveRuntimeChords() bool {
    const scratch_len: usize = if (g_runtimeChordsLen == 0) 1 else g_runtimeChordsLen;
    const best_mask = gAlloc.alloc(u8, scratch_len) catch return false;
    defer gAlloc.free(best_mask);
    const best_index = gAlloc.alloc(usize, scratch_len) catch return false;
    defer gAlloc.free(best_index);
    const identity_key = gAlloc.alloc(u64, scratch_len) catch return false;
    defer gAlloc.free(identity_key);

    @memset(best_mask, 0);
    @memset(best_index, 0);
    @memset(identity_key, 0);

    const current = @atomicLoad(u32, &g_activeRuntimeChordBank, .acquire);
    const next: u32 = current ^ 1;
    const bank = &g_runtimeChordActiveBanks[next];
    if (!ensureRuntimeChordActiveBankCapacity(bank, g_runtimeChordsLen)) return false;
    clearRuntimeChordBank(bank);

    // One winner per canonical chord identity. Rows are append-ordered; strict
    // precedence comparison preserves the first registration on exact ties.
    var identity_len: usize = 0;

    var i: usize = 0;
    while (i < g_runtimeChordsLen) : (i += 1) {
        if (runtimeChordOverriddenByRuntime(i)) continue;
        if (!runtimeChordAllows(i)) continue;
        const row = g_runtimeChords[i];
        var identity: usize = 0;
        while (identity < identity_len and identity_key[identity] != row.key) : (identity += 1) {}
        if (identity == identity_len) {
            identity_key[identity] = row.key;
            best_mask[identity] = row.specificityMask;
            best_index[identity] = i;
            identity_len += 1;
        } else if (row.specificityMask > best_mask[identity] or
            // A runtime row is the authoritative takeover when it has the
            // same canonical chord identity and context as a compiled row.
            // Keep the normal first-registration tie rule for two rows from
            // the same side, but never let the compiled prefix win this
            // exact runtime-overlay tie.
            (row.specificityMask == best_mask[identity] and
                best_index[identity] < g_compiledChordsLen and i >= g_compiledChordsLen)) {
            best_mask[identity] = row.specificityMask;
            best_index[identity] = i;
        }
    }

    i = 0;
    while (i < identity_len) : (i += 1) {
        applyActiveRuntimeChord(bank, g_runtimeChords[best_index[i]]);
    }
    recomputeChordHotSupersetFlags(bank.hotTable);
    @atomicStore(u32, &g_activeRuntimeChordBank, next, .release);
    return true;
}

// Compiled rows are a preload.  A source file may contain the same combo more
// than once; that is harmless for the preload and must not invalidate the
// other compiled families.  Keep runtime setup semantics unchanged.
fn appendPrecompiledCombo(row: RuntimeCombo, context_text: []const u16) bool {
    if (runtimeComboDuplicate(row, context_text)) return true;
    return appendRuntimeCombo(row, context_text);
}

fn rebuildActiveRuntimePassthroughs() bool {
    const current = @atomicLoad(u32, &g_activeRuntimePassthroughBank, .acquire);
    const next: u32 = current ^ 1;
    const bank = &g_runtimePassthroughActiveBanks[next];
    bank.* = .{};
    var best_seen: [VK_COUNT]bool = [_]bool{false} ** VK_COUNT;
    var best_mask: [VK_COUNT]u8 = [_]u8{0} ** VK_COUNT;
    var i: usize = 0;
    while (i < g_runtimePassthroughsLen) : (i += 1) {
        if (runtimePassthroughOverriddenByRuntime(i)) continue;
        if (!runtimePassthroughAllows(i)) continue;
        const row = g_runtimePassthroughs[i];
        if (row.vk <= 0 or row.vk >= VK_COUNT or isModVK(row.vk)) continue;
        const row_vk: usize = @intCast(row.vk);
        if (!best_seen[row_vk] or row.specificityMask > best_mask[row_vk]) {
            best_seen[row_vk] = true;
            bank.enabled[row_vk] = true;
            best_mask[row_vk] = row.specificityMask;
        }
    }
    @atomicStore(u32, &g_activeRuntimePassthroughBank, next, .release);
    return true;
}

fn ensureRuntimePassthroughCapacity(required: usize) bool {
    if (required <= g_runtimePassthroughsCap) return true;
    var new_cap: usize = if (g_runtimePassthroughsCap == 0) RUNTIME_PASSTHROUGH_INITIAL_CAP else g_runtimePassthroughsCap * 2;
    while (new_cap < required) : (new_cap *= 2) {}
    const new_rows = gAlloc.alloc(RuntimePassthrough, new_cap) catch return false;
    const new_texts = gAlloc.alloc(RuntimeContextActionText, new_cap) catch {
        gAlloc.free(new_rows);
        return false;
    };
    if (g_runtimePassthroughsLen != 0) {
        @memcpy(new_rows[0..g_runtimePassthroughsLen], g_runtimePassthroughs[0..g_runtimePassthroughsLen]);
        @memcpy(new_texts[0..g_runtimePassthroughsLen], g_runtimePassthroughTexts[0..g_runtimePassthroughsLen]);
    }
    @memset(new_rows[g_runtimePassthroughsLen..new_cap], RuntimePassthrough{});
    @memset(new_texts[g_runtimePassthroughsLen..new_cap], [_]u16{0} ** RUNTIME_CONTEXT_ACTION_CHARS);
    const old_rows = g_runtimePassthroughs;
    const old_texts = g_runtimePassthroughTexts;
    g_runtimePassthroughs = new_rows;
    g_runtimePassthroughTexts = new_texts;
    g_runtimePassthroughsCap = new_cap;
    retireSlice(RuntimePassthrough, old_rows);
    retireSlice(RuntimeContextActionText, old_texts);
    return true;
}

fn runtimePassthroughOverriddenByRuntime(index: usize) bool {
    if (index >= g_compiledPassthroughsLen) return false;
    const compiled = g_runtimePassthroughs[index];
    var runtime_index = g_compiledPassthroughsLen;
    while (runtime_index < g_runtimePassthroughsLen) : (runtime_index += 1) {
        const runtime = g_runtimePassthroughs[runtime_index];
        if (runtime.vk != compiled.vk or runtime.contextKind != compiled.contextKind or
            runtime.contextNegated != compiled.contextNegated) continue;
        if (runtimeContextTextEqual(g_runtimePassthroughTexts[index][0..@as(usize, @intCast(compiled.contextLen))],
            g_runtimePassthroughTexts[runtime_index][0..@as(usize, @intCast(runtime.contextLen))])) return true;
    }
    return false;
}

fn appendRuntimePassthrough(vk: i32, context_kind: u8, context_negated: bool, context_text: []const u16, suspend_exempt: bool) bool {
    if (vk <= 0 or vk >= VK_COUNT or isModVK(vk)) return false;
    if (context_text.len >= RUNTIME_CONTEXT_ACTION_CHARS) return false;
    if (!ensureRuntimePassthroughCapacity(g_runtimePassthroughsLen + 1)) return false;
    var i: usize = 0;
    while (i < g_runtimePassthroughsLen) : (i += 1) {
        const row = g_runtimePassthroughs[i];
        const len: usize = @intCast(row.contextLen);
        if (row.vk == vk and row.contextKind == context_kind and row.contextNegated == context_negated and
            row.suspendExempt == suspend_exempt and runtimeContextTextEqual(g_runtimePassthroughTexts[i][0..len], context_text)) return true;
    }
    const slot = g_runtimePassthroughsLen;
    @memset(&g_runtimePassthroughTexts[slot], 0);
    if (context_text.len != 0) @memcpy(g_runtimePassthroughTexts[slot][0..context_text.len], context_text);
    g_runtimePassthroughs[slot] = .{
        .vk = vk,
        .contextKind = context_kind,
        .contextNegated = context_negated,
        .contextLen = @intCast(context_text.len),
        .specificityMask = runtimeHotkeySpecificityMask(context_kind, g_runtimePassthroughTexts[slot][0..context_text.len]),
        .suspendExempt = suspend_exempt,
    };
    g_runtimePassthroughsLen += 1;
    return true;
}

inline fn runtimeHotstringContextText(index: usize) []const u16 {
    const len: usize = @intCast(g_hsCtxRows[index].contextLen);
    return g_hsCtxTexts[index][0..len];
}

/// Registration-time index maintenance. The permanent runtime hotstring table
/// is append-only; this list is only a cheap hint for diagnostics/legacy paths.
fn rebuildRuntimeHotstringContextIndex() void {
    g_hsContextBoundLen = 0;
    var h: usize = 0;
    while (h < g_runtimeHotstringLen) : (h += 1) {
        if (g_runtimeHotstringCtxCount[h] == 0) continue;
        if (g_hsContextBoundLen >= g_hsContextBoundIdx.len) break;
        g_hsContextBoundIdx[g_hsContextBoundLen] = @intCast(h);
        g_hsContextBoundLen += 1;
    }
    g_hsContextIndexDirty = false;
}

fn runtimeHotstringBestAllowedMask(h: usize) ?u8 {
    const count: usize = @intCast(g_runtimeHotstringCtxCount[h]);
    if (count == 0) return 0; // global
    const start: usize = @intCast(g_runtimeHotstringCtxStart[h]);
    var seen = false;
    var best: u8 = 0;
    var k: usize = 0;
    while (k < count and start + k < g_hsCtxRowsLen) : (k += 1) {
        const row = g_hsCtxRows[start + k];
        if (!row.allowed) continue;
        if (!seen or row.specificityMask > best) {
            seen = true;
            best = row.specificityMask;
        }
    }
    return if (seen) best else null;
}

fn runtimeHotstringIdentityHash(entry: hotstrings.HotstringEntry) u64 {
    var h: u64 = 1469598103934665603;
    for (entry.trigger) |raw| {
        const b: u8 = if (entry.options.case_sensitive) raw else asciiFoldLower8(raw);
        h ^= b;
        h *%= 1099511628211;
    }
    h ^= if (entry.options.case_sensitive) 0xA5 else 0x5A;
    h *%= 1099511628211;
    h ^= if (entry.options.detect_inside_word) 0xC3 else 0x3C;
    h *%= 1099511628211;
    return if (h == 0) 1 else h;
}

const HOTSTRING_WINNER_INITIAL_SLOTS: usize = 8192;
const RuntimeHotstringWinner = struct { hash: u64 = 0, index: u32 = 0, mask: u8 = 0 };
var g_runtimeHotstringWinnerEmpty: [0]RuntimeHotstringWinner = .{};
var g_runtimeHotstringWinnerScratch: []RuntimeHotstringWinner = g_runtimeHotstringWinnerEmpty[0..];

fn ensureRuntimeHotstringWinnerCapacity(row_count: usize) bool {
    const wanted = nextPowerOfTwoAtLeast(@max(HOTSTRING_WINNER_INITIAL_SLOTS, row_count * 2));
    if (wanted <= g_runtimeHotstringWinnerScratch.len) return true;
    const new_scratch = gAlloc.alloc(RuntimeHotstringWinner, wanted) catch return false;
    @memset(new_scratch, RuntimeHotstringWinner{});
    const old_scratch = g_runtimeHotstringWinnerScratch;
    g_runtimeHotstringWinnerScratch = new_scratch;
    retireSlice(RuntimeHotstringWinner, old_scratch);
    return true;
}

/// Re-evaluate contexts, choose exactly one highest-precedence active variant
/// per hotstring identity, build the inactive entry bank, then atomically publish.
fn rebuildRuntimeHotstringContexts() bool {
    if (g_hsContextIndexDirty) rebuildRuntimeHotstringContextIndex();
    const suspended = @atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire) != 0;

    var i: usize = 0;
    while (i < g_hsCtxRowsLen) : (i += 1) {
        g_hsCtxRows[i].allowed = runtimeContextCriterionAllows(
            g_hsCtxRows[i].specificityMask,
            g_hsCtxRows[i].contextNegated,
            runtimeHotstringContextText(i),
        );
    }

    const current = @atomicLoad(u32, &g_activeRuntimeHotstringBank, .acquire);
    const next: u32 = current ^ 1;
    if (!ensureRuntimeHotstringActiveBankCapacity(next, g_runtimeHotstringLen)) return false;
    if (!ensureRuntimeHotstringWinnerCapacity(g_runtimeHotstringLen)) return false;
    const bank = g_runtimeHotstringActiveBanks[next];
    @memset(g_runtimeHotstringWinnerScratch, RuntimeHotstringWinner{});

    i = 0;
    while (i < g_runtimeHotstringLen) : (i += 1) {
        bank[i] = g_runtimeHotstringEntries[i];
        bank[i].options.enabled = false;
    }

    i = 0;
    while (i < g_runtimeHotstringLen) : (i += 1) {
        if (!g_runtimeHotstringUserEnabled[i]) continue;
        if (runtimeHotstringOverriddenByRuntime(i)) continue;
        if (suspended and !g_runtimeHotstringSuspendExempt[i]) continue;
        const rank = runtimeHotstringBestAllowedMask(i) orelse continue;
        const entry = g_runtimeHotstringEntries[i];
        const hash = runtimeHotstringIdentityHash(entry);
        const mask = g_runtimeHotstringWinnerScratch.len - 1;
        var slot: usize = @intCast(hash & @as(u64, @intCast(mask)));
        var probe: usize = 0;
        while (probe < g_runtimeHotstringWinnerScratch.len) : (probe += 1) {
            const winner = &g_runtimeHotstringWinnerScratch[slot];
            if (winner.hash == 0) {
                winner.* = .{ .hash = hash, .index = @intCast(i), .mask = rank };
                bank[i].options.enabled = true;
                break;
            }
            const existing_index: usize = @intCast(winner.index);
            if (winner.hash == hash and runtimeHotstringIdentityMatches(
                g_runtimeHotstringEntries[existing_index], entry.trigger, entry.options))
            {
                if (rank > winner.mask) {
                    bank[existing_index].options.enabled = false;
                    winner.index = @intCast(i);
                    winner.mask = rank;
                    bank[i].options.enabled = true;
                }
                // Equal rank deliberately leaves the first registration armed.
                break;
            }
            slot = (slot + 1) & mask;
        }
    }

    g_runtimeHotstringActiveLenBanks[next] = g_runtimeHotstringLen;
    @atomicStore(u32, &g_activeRuntimeHotstringBank, next, .release);
    return true;
}

fn runtimeContextRefreshBlockedByUnpublishedSetup(changed_mask: u8) bool {
    if ((g_runtimeHotkeyDependencyMask & changed_mask) != 0 and
        (g_bulkRuntimeHotkeysDirty or g_runtimeHotkeyContextsDirty)) return true;
    if ((g_runtimeContextActionDependencyMask & changed_mask) != 0 and
        g_bulkRuntimeContextActionsDirty) return true;
    if ((g_runtimeModifierDependencyMask & changed_mask) != 0 and
        g_bulkRuntimeModifiersDirty) return true;
    if ((g_runtimePassthroughDependencyMask & changed_mask) != 0 and
        g_bulkRuntimePassthroughsDirty) return true;
    if ((g_runtimeComboDependencyMask & changed_mask) != 0 and
        g_bulkRuntimeCombosDirty) return true;
    if ((g_runtimeChordDependencyMask & changed_mask) != 0 and
        g_bulkRuntimeChordsDirty) return true;
    if ((g_runtimeHotstringDependencyMask & changed_mask) != 0 and
        g_bulkRuntimeHotstringsDirty) return true;
    return false;
}

fn recalculateHotkeyContexts(changed_mask: u8) bool {
    if (changed_mask == 0) return true;
    if (runtimeContextRefreshBlockedByUnpublishedSetup(changed_mask)) return false;

    var rebuild_key_gate = false;
    if ((g_runtimeHotkeyDependencyMask & changed_mask) != 0) {
        if (!rebuildActiveRuntimeHotkeyIndex()) return false;
    }
    if ((g_runtimeContextActionDependencyMask & changed_mask) != 0) {
        if (!rebuildActiveRuntimeContextActions()) return false;
        rebuild_key_gate = true;
    }
    if ((g_runtimeModifierDependencyMask & changed_mask) != 0) {
        if (!rebuildActiveRuntimeModifiers()) return false;
        rebuild_key_gate = true;
    }
    if ((g_runtimePassthroughDependencyMask & changed_mask) != 0) {
        if (!rebuildActiveRuntimePassthroughs()) return false;
        rebuild_key_gate = true;
    }
    if ((g_runtimeComboDependencyMask & changed_mask) != 0) {
        if (!rebuildActiveRuntimeCombos()) return false;
        rebuild_key_gate = true;
    }
    if ((g_runtimeChordDependencyMask & changed_mask) != 0) {
        if (!rebuildActiveRuntimeChords()) return false;
        rebuild_key_gate = true;
    }
    if ((g_runtimeHotstringDependencyMask & changed_mask) != 0) {
        if (!rebuildRuntimeHotstringContexts()) return false;
    }

    // Hotkeys/hotstrings publish their own banks. Rebuild the derived key gate
    // only when a family that changes structural key roles actually changed.
    if (rebuild_key_gate) markKeyGateDirty();
    return true;
}

fn compiledWindowMatchesParsed(parsed: CachedAhkCriterion, entry_index: usize) bool {
    if (parsed.title.len != 0) {
        const title_matches = if (g_compiledAcFallback[entry_index])
            wideContains(&g_hotkeyContextState.win_title, parsed.title)
        else
            g_compiledTitleMatched[entry_index];
        if (!title_matches) return false;
    }
    if (parsed.class_name.len != 0 and !wideEquals(&g_hotkeyContextState.win_class, parsed.class_name)) return false;
    if (parsed.exe.len != 0 and !runtimeExeMatches(&g_hotkeyContextState.win_exe, parsed.exe)) return false;
    return parsed.title.len != 0 or parsed.class_name.len != 0 or parsed.exe.len != 0;
}

fn evalHotkeyContextAllows(hk: hotkeys.CompiledHotkey, entry_index: usize) bool {
    if (hk.context_kind == .global) return true;
    const parsed = g_parsedHotkeyContexts[entry_index];
    return switch (hk.context_kind) {
        .global => true,
        .win_active => compiledWindowMatchesParsed(parsed, entry_index),
        .win_not_active => !compiledWindowMatchesParsed(parsed, entry_index),
        .win_exist => compiledWindowMatchesParsed(parsed, entry_index),
        .win_not_exist => !compiledWindowMatchesParsed(parsed, entry_index),
        .website => if (g_compiledAcFallback[entry_index])
            wideContains(&g_hotkeyContextState.url, hk.win_title)
        else
            g_compiledWebsiteMatched[entry_index],
    };
}

fn initParsedHotkeyContexts() void {
    for (hotkeys.HOTKEYS, 0..) |hk, idx| {
        g_parsedHotkeyContexts[idx] = parseCachedAhkCriterion(hk.win_title);
    }
    g_hotkeyContextsParsed = true;
    rebuildCompiledContextAutomata();
    _ = recalculateHotkeyContexts(RUNTIME_CONTEXT_ALL_BITS);
}

fn parseCachedAhkCriterion(s: []const u16) CachedAhkCriterion {
    var parsed: CachedAhkCriterion = .{};
    const first = findNextCachedAhkToken(s, 0);
    if (first == null) {
        parsed.title = trimSpaces16(s);
        return parsed;
    }

    var hit = first.?;
    parsed.title = trimSpaces16(s[0..hit.start]);
    var pos = hit.value_start;
    var kind = hit.kind;
    while (true) {
        const following = findNextCachedAhkToken(s, pos);
        const end = if (following) |f| f.start else s.len;
        const value = trimSpaces16(s[pos..end]);
        switch (kind) {
            .class_name => parsed.class_name = value,
            .exe => parsed.exe = value,
        }
        if (following) |f| {
            hit = f;
            pos = hit.value_start;
            kind = hit.kind;
        } else {
            break;
        }
    }
    return parsed;
}

// True if the wide buffer contains needle (searches up to first null).
inline fn wideContains(buf: []const u16, needle: []const u16) bool {
    if (needle.len == 0) return true;
    const haystack = wideSpan(buf);
    if (haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (eqlIgnoreCase16(haystack[i .. i + needle.len], needle)) return true;
    }
    return false;
}

inline fn wideEquals(buf: []const u16, needle: []const u16) bool {
    return eqlIgnoreCase16(wideSpan(buf), needle);
}

// Mirrors AHK ahk_exe matching for the cached context state.  If the
// criterion is just a process name (for example "Code.exe"), accept either
// that exact pumped value or the basename of a pumped full executable path.
// If the criterion itself contains a path separator, require the full path.
inline fn runtimeExeMatches(buf: []const u16, criterion: []const u16) bool {
    @setEvalBranchQuota(1_000_000);
    const current = wideSpan(buf);
    if (criterion.len == 0) return true;
    if (eqlIgnoreCase16(current, criterion)) return true;

    var criterion_has_path = false;
    for (criterion) |ch| {
        if (ch == '\\' or ch == '/') {
            criterion_has_path = true;
            break;
        }
    }
    if (criterion_has_path) return false;

    var base_start: usize = 0;
    for (current, 0..) |ch, i| {
        if (ch == '\\' or ch == '/') base_start = i + 1;
    }
    return eqlIgnoreCase16(current[base_start..], criterion);
}

fn cachedWindowMatchesParsed(parsed: CachedAhkCriterion) bool {
    if (parsed.title.len != 0 and !wideContains(&g_hotkeyContextState.win_title, parsed.title)) return false;
    if (parsed.class_name.len != 0 and !wideEquals(&g_hotkeyContextState.win_class, parsed.class_name)) return false;
    if (parsed.exe.len != 0 and !runtimeExeMatches(&g_hotkeyContextState.win_exe, parsed.exe)) return false;
    return parsed.title.len != 0 or parsed.class_name.len != 0 or parsed.exe.len != 0;
}

fn runtimeCompoundContextMatches(ctx: []const u16) bool {
    // AutoHotkey v2 WinTitle semantics: ordinary text before ahk_* selectors is
    // always the window-title criterion. ahk_class/ahk_exe explicitly identify
    // their own criteria; punctuation in the title (including '.') never changes
    // the criterion type. All supplied criteria are ANDed.
    const parsed = parseCachedAhkCriterion(ctx);
    if (parsed.title.len != 0 and !wideContains(&g_hotkeyContextState.win_title, parsed.title)) return false;
    if (parsed.class_name.len != 0 and !wideEquals(&g_hotkeyContextState.win_class, parsed.class_name)) return false;
    if (parsed.exe.len != 0 and !runtimeExeMatches(&g_hotkeyContextState.win_exe, parsed.exe)) return false;
    return parsed.title.len != 0 or parsed.class_name.len != 0 or parsed.exe.len != 0;
}

inline fn runtimeContextText(index: usize) []const u16 {
    const len: usize = @intCast(g_runtimeHotkeys[index].contextLen);
    return g_runtimeHotkeyContexts[index][0..len];
}

inline fn runtimeHotkeyBrowserContextAllows() bool {
    const exe = wideSpan(&g_hotkeyContextState.win_exe);
    return eqlIgnoreCase16(exe, &[_]u16{ 'c', 'h', 'r', 'o', 'm', 'e', '.', 'e', 'x', 'e' }) or
        eqlIgnoreCase16(exe, &[_]u16{ 'm', 's', 'e', 'd', 'g', 'e', '.', 'e', 'x', 'e' }) or
        eqlIgnoreCase16(exe, &[_]u16{ 'f', 'i', 'r', 'e', 'f', 'o', 'x', '.', 'e', 'x', 'e' }) or
        wideSpan(&g_hotkeyContextState.url).len != 0;
}


// Context precedence is lexicographic, highest bit first:
// MENU > WEBSITE > TITLE > CLASS > EXE > BROWSER > GLOBAL.
// Unsigned mask comparison therefore implements the exact hierarchy: a higher
// criterion beats every possible combination of lower criteria.
const RUNTIME_CONTEXT_BROWSER_BIT: u8 = 1 << 0;
const RUNTIME_CONTEXT_EXE_BIT: u8 = 1 << 1;
const RUNTIME_CONTEXT_CLASS_BIT: u8 = 1 << 2;
const RUNTIME_CONTEXT_TITLE_BIT: u8 = 1 << 3;
const RUNTIME_CONTEXT_WEBSITE_BIT: u8 = 1 << 4;
const RUNTIME_CONTEXT_MENU_BIT: u8 = 1 << 5;
const RUNTIME_CONTEXT_MENU_KIND: u8 = 1;
const RUNTIME_CONTEXT_URL_KIND: u8 = 2;
const RUNTIME_CONTEXT_TITLE_KIND: u8 = 3;
const RUNTIME_CONTEXT_CLASS_KIND: u8 = 4;
const RUNTIME_CONTEXT_BROWSER_KIND: u8 = 5;
const RUNTIME_CONTEXT_EXE_KIND: u8 = 6;
const RUNTIME_CONTEXT_GLOBAL_KIND: u8 = 7;
const RUNTIME_CONTEXT_COMPOUND_KIND: u8 = 8;

const RUNTIME_CONTEXT_ALL_BITS: u8 =
    RUNTIME_CONTEXT_MENU_BIT | RUNTIME_CONTEXT_WEBSITE_BIT | RUNTIME_CONTEXT_TITLE_BIT |
    RUNTIME_CONTEXT_CLASS_BIT | RUNTIME_CONTEXT_EXE_BIT | RUNTIME_CONTEXT_BROWSER_BIT;

// Aggregate dependency masks are append-only setup facts. A context update only
// rebuilds a runtime subsystem when a changed context dimension can affect it.
var g_runtimeHotkeyDependencyMask: u8 = 0;
var g_runtimeContextActionDependencyMask: u8 = 0;
var g_runtimeModifierDependencyMask: u8 = 0;
var g_runtimeComboDependencyMask: u8 = 0;
var g_runtimeChordDependencyMask: u8 = 0;
var g_runtimeHotstringDependencyMask: u8 = 0;
var g_runtimePassthroughDependencyMask: u8 = 0;

const RuntimeContextSpec = struct {
    kind: u8 = RUNTIME_CONTEXT_GLOBAL_KIND,
    negated: bool = false,
    text: []const u16 = &[_]u16{},
};

fn containsAsciiIgnoreCase16(haystack: []const u16, comptime needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (haystack.len < needle.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (startsWithAsciiIgnoreCase16(haystack[i..], needle)) return true;
    }
    return false;
}

fn equalsAsciiIgnoreCase16(haystack: []const u16, comptime needle: []const u8) bool {
    if (haystack.len != needle.len) return false;
    inline for (needle, 0..) |nc, i| {
        if (asciiLower16(haystack[i]) != asciiLower16(nc)) return false;
    }
    return true;
}

fn containsChar16(haystack: []const u16, ch: u16) bool {
    for (haystack) |c| {
        if (c == ch) return true;
    }
    return false;
}

fn runtimeContextHasCompoundAhkCriteria(ctx: []const u16) bool {
    const class_pos = findAsciiIgnoreCase16(ctx, "ahk_class");
    const exe_pos = findAsciiIgnoreCase16(ctx, "ahk_exe");
    if (class_pos == null and exe_pos == null) return false;
    const class_count: u8 = if (class_pos != null) 1 else 0;
    const exe_count: u8 = if (exe_pos != null) 1 else 0;
    const token_count: u8 = class_count + exe_count;
    const first_token = if (class_pos) |cp|
        if (exe_pos) |ep| @min(cp, ep) else cp
    else
        exe_pos.?;
    const has_title_prefix = trimSpaces16(ctx[0..first_token]).len != 0;
    return token_count > 1 or has_title_prefix;
}

fn findAsciiIgnoreCase16(haystack: []const u16, comptime needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (haystack.len < needle.len) return null;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (startsWithAsciiIgnoreCase16(haystack[i..], needle)) return i;
    }
    return null;
}

fn parseRuntimeContextSpec(raw_context: []const u16) RuntimeContextSpec {
    var ctx = trimSpaces16(raw_context);
    var negated = false;
    if (ctx.len != 0 and ctx[0] == '!') {
        negated = true;
        ctx = trimSpaces16(ctx[1..]);
    }
    if (ctx.len == 0 or equalsAsciiIgnoreCase16(ctx, "global")) {
        return .{ .kind = RUNTIME_CONTEXT_GLOBAL_KIND, .negated = negated, .text = &[_]u16{} };
    }
    if (equalsAsciiIgnoreCase16(ctx, "#32768") or equalsAsciiIgnoreCase16(ctx, "ahk_class #32768")) {
        return .{ .kind = RUNTIME_CONTEXT_MENU_KIND, .negated = negated, .text = ctx };
    }
    if (runtimeContextHasCompoundAhkCriteria(ctx)) {
        return .{ .kind = RUNTIME_CONTEXT_COMPOUND_KIND, .negated = negated, .text = ctx };
    }
    if (containsAsciiIgnoreCase16(ctx, "ahk_class")) {
        return .{ .kind = RUNTIME_CONTEXT_CLASS_KIND, .negated = negated, .text = ctx };
    }
    if (equalsAsciiIgnoreCase16(ctx, "browser") or equalsAsciiIgnoreCase16(ctx, "browsers")) {
        return .{ .kind = RUNTIME_CONTEXT_BROWSER_KIND, .negated = negated, .text = ctx };
    }
    // AHK-style selectors are authoritative. Do not infer EXE merely because
    // arbitrary context text happens to contain ".exe".
    if (containsAsciiIgnoreCase16(ctx, "ahk_exe")) {
        return .{ .kind = RUNTIME_CONTEXT_EXE_KIND, .negated = negated, .text = ctx };
    }
    // Bare dotted contexts remain QMK's website shorthand only when no AHK
    // selector was present above.
    if (containsChar16(ctx, '.')) {
        return .{ .kind = RUNTIME_CONTEXT_URL_KIND, .negated = negated, .text = ctx };
    }
    return .{ .kind = RUNTIME_CONTEXT_TITLE_KIND, .negated = negated, .text = ctx };
}

const EMPTY_RUNTIME_CONTEXT_TEXT = [_]u16{};

inline fn runtimeContextTextEqual(a: []const u16, b: []const u16) bool {
    const aa = trimSpaces16(a);
    const bb = trimSpaces16(b);
    if (aa.len != bb.len) return false;
    for (aa, bb) |ac, bc| {
        if (asciiLower16(ac) != asciiLower16(bc)) return false;
    }
    return true;
}

const RuntimeContextListIterator = struct {
    raw: []const u16,
    pos: usize = 0,
    emitted_any: bool = false,

    fn next(self: *RuntimeContextListIterator) ?[]const u16 {
        while (self.pos <= self.raw.len) {
            const start = self.pos;
            var end = start;
            while (end < self.raw.len) : (end += 1) {
                if (self.raw[end] == 0x001F) break;
            }
            self.pos = if (end < self.raw.len) end + 1 else self.raw.len + 1;
            const part = trimSpaces16(self.raw[start..end]);
            if (part.len != 0) {
                self.emitted_any = true;
                return part;
            }
        }
        if (!self.emitted_any) {
            self.emitted_any = true;
            return EMPTY_RUNTIME_CONTEXT_TEXT[0..0];
        }
        return null;
    }
};

fn runtimeContextPartCount(raw: []const u16) usize {
    var count: usize = 0;
    var contexts = RuntimeContextListIterator{ .raw = raw };
    while (contexts.next()) |_| count += 1;
    return count;
}

fn runtimeHotstringNonGlobalContextPartCount(raw: []const u16) usize {
    var count: usize = 0;
    var contexts = RuntimeContextListIterator{ .raw = raw };
    while (contexts.next()) |context_text| {
        if (parseRuntimeContextSpec(context_text).kind != RUNTIME_CONTEXT_GLOBAL_KIND) count += 1;
    }
    return count;
}

fn runtimeParsedCriterionCount(parsed: CachedAhkCriterion) u8 {
    var count: u8 = 0;
    if (parsed.title.len != 0) count += 1;
    if (parsed.class_name.len != 0) count += 1;
    if (parsed.exe.len != 0) count += 1;
    return count;
}

fn runtimeHotkeySpecificityMask(context_kind: u8, ctx: []const u16) u8 {
    if (context_kind == 7 or ctx.len == 0) return 0; // global
    if (context_kind == 1) return RUNTIME_CONTEXT_MENU_BIT;
    if (context_kind == 5) return RUNTIME_CONTEXT_BROWSER_BIT;

    const parsed = parseCachedAhkCriterion(ctx);
    var mask: u8 = 0;
    if (parsed.title.len != 0) {
        // In an AHK WinTitle expression, the non-ahk_* prefix is always title
        // text. A standalone QMK website context is identified by context_kind.
        if (context_kind == RUNTIME_CONTEXT_URL_KIND)
            mask |= RUNTIME_CONTEXT_WEBSITE_BIT
        else
            mask |= RUNTIME_CONTEXT_TITLE_BIT;
    }
    if (parsed.class_name.len != 0) {
        if (equalsAsciiIgnoreCase16(parsed.class_name, "#32768"))
            mask |= RUNTIME_CONTEXT_MENU_BIT
        else
            mask |= RUNTIME_CONTEXT_CLASS_BIT;
    }
    if (parsed.exe.len != 0) mask |= RUNTIME_CONTEXT_EXE_BIT;

    // Plain executable forms may have no ahk_exe token.
    if (mask == 0) {
        mask = switch (context_kind) {
            2 => RUNTIME_CONTEXT_WEBSITE_BIT,
            3 => RUNTIME_CONTEXT_TITLE_BIT,
            4 => RUNTIME_CONTEXT_CLASS_BIT,
            5 => RUNTIME_CONTEXT_BROWSER_BIT,
            6 => RUNTIME_CONTEXT_EXE_BIT,
            else => 0,
        };
    }
    return mask;
}

inline fn runtimeHotkeyContextAllows(index: usize) bool {
    const hk = g_runtimeHotkeys[index];
    if (hk.specificityMask == 0) return !hk.contextNegated; // Global: no parsing or matching.

    const ctx = runtimeContextText(index);
    const parsed = parseCachedAhkCriterion(ctx);
    var matched = true;

    if ((hk.specificityMask & RUNTIME_CONTEXT_WEBSITE_BIT) != 0) {
        const pattern = if (parsed.title.len != 0) parsed.title else ctx;
        const website_match = if (g_runtimeAcFallback[index])
            wideContains(&g_hotkeyContextState.url, pattern)
        else
            g_runtimeWebsiteMatched[index];
        matched = matched and website_match;
    } else if ((hk.specificityMask & RUNTIME_CONTEXT_TITLE_BIT) != 0) {
        const pattern = if (parsed.title.len != 0) parsed.title else ctx;
        const title_match = if (g_runtimeAcFallback[index])
            wideContains(&g_hotkeyContextState.win_title, pattern)
        else
            g_runtimeTitleMatched[index];
        matched = matched and title_match;
    }

    if ((hk.specificityMask & RUNTIME_CONTEXT_CLASS_BIT) != 0) {
        const class_value = if (parsed.class_name.len != 0)
            parsed.class_name
        else if (startsWithAsciiIgnoreCase16(ctx, "ahk_class"))
            trimSpaces16(ctx[9..])
        else
            ctx;
        matched = matched and wideEquals(&g_hotkeyContextState.win_class, class_value);
    }

    if ((hk.specificityMask & RUNTIME_CONTEXT_EXE_BIT) != 0) {
        const exe_value = if (parsed.exe.len != 0)
            parsed.exe
        else if (startsWithAsciiIgnoreCase16(ctx, "ahk_exe"))
            trimSpaces16(ctx[7..])
        else
            ctx;
        matched = matched and runtimeExeMatches(&g_hotkeyContextState.win_exe, exe_value);
    }

    if ((hk.specificityMask & RUNTIME_CONTEXT_BROWSER_BIT) != 0) {
        matched = matched and runtimeHotkeyBrowserContextAllows();
    }
    if ((hk.specificityMask & RUNTIME_CONTEXT_MENU_BIT) != 0) {
        matched = matched and g_hotkeyContextState.has_context_menu != 0;
    }

    return if (hk.contextNegated) !matched else matched;
}

// Context check using already-cached g_hotkeyContextState — no window enumeration.
inline fn hotkeyContextAllows(hk: hotkeys.CompiledHotkey, entry_index: usize) bool {
    _ = hk;
    if (!g_hotkeyContextsParsed) {
    }
    return g_hotkeyContextsAllowed[entry_index];
}

inline fn hotkeyModBucket(active_mods: u16) usize {
    return @intCast(active_mods & 0xF);
}

// Compiled and runtime hotkeys share one ready-row matcher. Both builders
// publish context-filtered rows plus permanent global fallback rows; this
// function owns the common hot-path traversal so the two systems cannot drift.
const ReadyHotkeyKind = enum { compiled, runtime };

inline fn matchReadyHotkey(kind: ReadyHotkeyKind, vk: i32, active_mods: u16, is_down: bool) i32 {
    if (vk < 0 or vk >= VK_COUNT) return -1;
    if (comptime !has_qmk_shortcuts_build) {
        if (kind == .compiled) return -1;
    }

    const hotkey_vk: usize = @intCast(vk);
    const bucket = hotkeyModBucket(active_mods);
    const trigger_kind: u8 = if (is_down) 0 else 1;

    // Pass 0 is the context-ready row; pass 1 is the permanent global row.
    var pass: u2 = 0;
    while (pass < 2) : (pass += 1) {
        switch (kind) {
            .compiled => {
                if (hotkey_vk >= 256) return -1;
                const bank_index = @atomicLoad(u32, &g_activeCompiledHotkeyReadyIndex, .acquire);
                const ready_bank = &g_compiledHotkeyReadyBanks[bank_index];
                const index = if (pass == 0)
                    (if (is_down) &ready_bank.keydown else &ready_bank.keyup)
                else
                    (if (is_down) &hotkeys.GLOBAL_KEYDOWN_INDEX else &hotkeys.GLOBAL_KEYUP_INDEX);
                const range = index.ranges[hotkey_vk][bucket];
                var offset: u16 = 0;
                while (offset < range.len) : (offset += 1) {
                    const entry_index: usize = @intCast(index.source_indexes[range.start + offset]);
                    const hk = hotkeys.HOTKEYS[entry_index];
                    if (shouldDeferBufferedOneLetterCompiledHotkey(hk, is_down)) continue;
                    if (hk.physical_mod_vk != 0 and !physicalKeyDownAt(hk.physical_mod_vk)) continue;
                    return @intCast(entry_index);
                }
            },
            .runtime => {
                const bank_index = @atomicLoad(u32, &g_activeRuntimeHotkeyReadyIndex, .acquire);
                const ready = &g_runtimeHotkeyReadyIndexes[bank_index];
                const global_bank = @atomicLoad(u32, &g_activeRuntimeGlobalHotkeyIndex, .acquire);
                const global = &g_runtimeGlobalHotkeyIndexes[global_bank];
                const index = if (pass == 0) ready else global;
                if (pass == 0) {
                    if (!ready.activeGate[hotkey_vk] and !global.activeGate[hotkey_vk]) return -1;
                }
                const range = index.ranges[hotkey_vk][bucket];
                var offset: u32 = 0;
                while (offset < range.len) : (offset += 1) {
                    const source_pos: usize = @intCast(range.start + offset);
                    const entry_index: usize = @intCast(index.sourceIndexes[source_pos]);
                    const hk = g_runtimeHotkeys[entry_index];
                    if (hk.triggerKind != trigger_kind) continue;
                    if (shouldDeferBufferedOneLetterRuntimeHotkey(hk, is_down)) continue;
                    if (shouldDeferRuntimeContextualTapHotkey(hk, is_down)) continue;
                    return @intCast(entry_index);
                }
            },
        }
    }
    return -1;
}

inline fn shouldDeferBufferedOneLetterRuntimeHotkey(hk: RuntimeHotkey, is_down: bool) bool {
    if (!is_down) return false;
    const sequence_active = g_kbLen != 0 or pendingSoloActive() or
        pendingRollActive() or g_pendingChord.active;
    return sequence_active and hk.modsRequired == 0 and hk.modsForbidden == 0 and
        hk.physicalModVK == 0 and hk.physicalModsRequired == 0 and hk.physicalModsForbidden == 0;
}

inline fn shouldDeferBufferedOneLetterCompiledHotkey(hk: hotkeys.CompiledHotkey, is_down: bool) bool {
    if (!is_down) return false;
    const sequence_active = g_kbLen != 0 or pendingSoloActive() or
        pendingRollActive() or g_pendingChord.active;
    return sequence_active and hk.mods_required == 0 and hk.mods_forbidden == 0 and
        hk.physical_mod_vk == 0;
}

inline fn shouldDeferRuntimeContextualTapHotkey(hk: RuntimeHotkey, is_down: bool) bool {
    if (!is_down or hk.actionKind != 1) return false;
    if (hk.modsRequired != 0 or hk.physicalModVK != 0 or hk.physicalModsRequired != 0) return false;
    // This is a solo contextual tap. Hotkey matching runs before the incoming
    // key is inserted, so pending/buffered virtual-mod state means this row
    // would steal a chord, instant combo, or virtual-mod chain.
    return g_kbLen != 0 or
        g_unrelModCount != 0 or
        g_active_virtual_modifier_count != 0 or
        pendingSoloActive() or
        pendingRollActive() or
        g_pendingChord.active;
}

const StructuralHotkeyCandidates = struct {
    count: u32 = 0,
    has_contextual: bool = false,
};

inline fn refreshForegroundContextIfChanged() void {
    if (compiled_shortcuts_test_observability and g_testSuppressForegroundRefresh) return;
    // Menu state is sampled first because a #32768 popup can block the
    // application's normal thread while the low-level input hook continues
    // receiving keys.  The current key must see this state in the same
    // synchronous context-bank rebuild as the foreground window metadata.
    var changed = refreshContextMenuStateForInput();

    const foreground = GetForegroundWindow() orelse {
        if (changed == 0) return;
        if (!recalculateHotkeyContexts(changed)) {
            acquireSetupPublishLock();
            g_pendingContextChangedMask |= changed;
            requestRuntimePublish(RUNTIME_PUBLISH_CONTEXTS);
            releaseSetupPublishLock();
        }
        return;
    };
    // AHK v2 evaluates WinGetTitle/WinGetClass/WinGetProcessName("A") at
    // match time. Titles can change while the HWND stays the same, so this
    // deliberately repolls the foreground window and its metadata on every
    // eligible input event. There
    // is no HWND/PID cache in this path. The affected context banks are rebuilt
    // synchronously before the current key is matched.
    const result = refreshForegroundContextFromHwndMode(foreground, false);
    if (result.ok) changed |= result.changed;
    if (changed == 0) return;

    // This is the input-time path.  Do not hand the new context to the
    // background publisher: the current key must see the rebuilt ready bank.
    if (!recalculateHotkeyContexts(changed)) {
        // Allocation/setup races are exceptional.  Preserve the change for
        // the normal publisher so it can recover after this event.
        acquireSetupPublishLock();
        g_pendingContextChangedMask |= changed;
        requestRuntimePublish(RUNTIME_PUBLISH_CONTEXTS);
        releaseSetupPublishLock();
    }
}

/// Finds hotkeys without consulting the context-ready banks. This is the
/// recovery gate: a stale context publication must not make a real hotkey
/// structurally disappear before the current foreground window is queried.
fn findStructuralHotkeyCandidates(vk: i32, active_mods: u16, is_down: bool) StructuralHotkeyCandidates {
    var result = StructuralHotkeyCandidates{};
    if (vk < 0 or vk >= VK_COUNT) return result;
    const trigger_kind: u8 = if (is_down) 0 else 1;

    var i: usize = 0;
    while (i < g_runtimeHotkeysLen) : (i += 1) {
        const hk = g_runtimeHotkeys[i];
        if (runtimeHotkeyOverriddenByRuntime(i)) continue;
        if (hk.triggerVK != vk or hk.triggerKind != trigger_kind) continue;
        if (runtimeHotkeyModifiersAllow(hk, active_mods) and runtimePhysicalModifiersAllow(hk)) {
            result.count += 1;
            result.has_contextual = result.has_contextual or hk.specificityMask != 0;
        }
    }

    return result;
}

/// Performs the current-window check only after structural hotkey discovery.
/// Context is refreshed synchronously at candidate time; external publishers
/// own website updates.
fn prepareStructuralHotkeyContext(vk: i32, active_mods: u16, is_down: bool) bool {
    const candidates = findStructuralHotkeyCandidates(vk, active_mods, is_down);
    if (candidates.count == 0) return false;
    if (!candidates.has_contextual) return true;

    refreshForegroundContextIfChanged();
    return true;
}

fn prepareStructuralContextAction(vk: i32) void {
    if (vk < 0 or vk >= VK_COUNT or !g_runtimeContextActionGate[@intCast(vk)]) return;
    var i: usize = 0;
    while (i < g_runtimeContextActionsLen) : (i += 1) {
        const action = g_runtimeContextActions[i];
        if (action.triggerVK == vk and action.specificityMask != 0) {
            refreshForegroundContextIfChanged();
            return;
        }
    }
}

/// Chords own their context path. Inspect only registered contextual chord
/// rows which contain the incoming key and one currently held member; this
/// avoids treating a chord continuation as a one-letter hotkey event.
fn prepareStructuralIncomingChordContext(vk: i32) void {
    if (vk < 0 or vk >= VK_COUNT or g_kbLen == 0 or
        !g_runtimeChordContextParticipant[@intCast(vk)]) return;
    var i: usize = 0;
    while (i < g_runtimeChordsLen) : (i += 1) {
        const row = g_runtimeChords[i];
        if (row.specificityMask == 0) continue;
        var contains_incoming = false;
        var contains_held = false;
        for (row.vks[0..@as(usize, @intCast(row.keyCount))]) |member| {
            if (member == vk) contains_incoming = true;
            if (member != vk) {
                if (kbGet(member)) |kd| {
                    if (!kd.isReleased()) contains_held = true;
                }
            }
        }
        if (contains_incoming and contains_held) {
            refreshForegroundContextIfChanged();
            return;
        }
    }
}

fn prepareStructuralComboContext(primary: i32, secondary: i32) void {
    var i: usize = 0;
    while (i < g_runtimeCombosLen) : (i += 1) {
        const row = g_runtimeCombos[i];
        if (row.primaryVK == primary and row.secondaryVK == secondary and row.specificityMask != 0) {
            refreshForegroundContextIfChanged();
            return;
        }
    }
    i = 0;
    while (i < g_runtimeInstantCombosLen) : (i += 1) {
        const row = g_runtimeInstantCombos[i];
        if (row.primaryVK == primary and row.secondaryVK == secondary and row.specificityMask != 0) {
            refreshForegroundContextIfChanged();
            return;
        }
    }
}

fn prepareStructuralChordContext(key: u64) void {
    var i: usize = 0;
    while (i < g_runtimeChordsLen) : (i += 1) {
        const row = g_runtimeChords[i];
        if (row.key == key and row.specificityMask != 0) {
            refreshForegroundContextIfChanged();
            return;
        }
    }
}

fn prepareStructuralHotstringContext() void {
    const history = g_hotstringMatcher.view();
    var i: usize = 0;
    while (i < g_runtimeHotstringLen) : (i += 1) {
        if (g_runtimeHotstringCtxCount[i] == 0) continue;
        const trigger = g_runtimeHotstringEntries[i].trigger;
        if (trigger.len == 0 or trigger.len > history.len) continue;
        const start = history.len - trigger.len;
        var matches = true;
        for (trigger, 0..) |raw, j| {
            const actual = history[start + j];
            if (g_runtimeHotstringEntries[i].options.case_sensitive) {
                if (actual != raw) {
                    matches = false;
                    break;
                }
            } else if (asciiFoldLower8(actual) != asciiFoldLower8(raw)) {
                matches = false;
                break;
            }
        }
        if (matches) {
            refreshForegroundContextIfChanged();
            return;
        }
    }
}

inline fn matchRuntimeHotkeyPass(vk: i32, active_mods: u16, is_down: bool, global_pass: bool) i32 {
    @setEvalBranchQuota(1_000_000);
    if (vk < 0 or vk >= VK_COUNT) return -1;
    const hotkey_vk: usize = @intCast(vk);
    const bucket = hotkeyModBucket(active_mods);
    const trigger_kind: u8 = if (is_down) 0 else 1;
    const bank_index = @atomicLoad(u32, &g_activeRuntimeHotkeyReadyIndex, .acquire);
    const ready = &g_runtimeHotkeyReadyIndexes[bank_index];
    const global_bank = @atomicLoad(u32, &g_activeRuntimeGlobalHotkeyIndex, .acquire);
    const global = &g_runtimeGlobalHotkeyIndexes[global_bank];
    const index = if (global_pass) global else ready;
    const range = index.ranges[hotkey_vk][bucket];
    var offset: u32 = 0;
    while (offset < range.len) : (offset += 1) {
        const source_pos: usize = @intCast(range.start + offset);
        const entry_index: usize = @intCast(index.sourceIndexes[source_pos]);
        const hk = g_runtimeHotkeys[entry_index];
        if (@atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire) != 0 and !hk.suspendExempt) continue;
        if (hk.triggerKind != trigger_kind) continue;
        if (shouldDeferBufferedOneLetterRuntimeHotkey(hk, is_down)) continue;
        if (shouldDeferRuntimeContextualTapHotkey(hk, is_down)) continue;
        if (!runtimePhysicalModifiersAllow(hk)) continue;
        return @intCast(entry_index);
    }
    // Compiled rows are runtime rows. If an index publication handoff leaves
    // this bucket stale, recover from the authoritative row store instead of
    // making a valid callback hotkey disappear.
    var i: usize = 0;
    while (i < g_runtimeHotkeysLen) : (i += 1) {
        const hk = g_runtimeHotkeys[i];
        if (runtimeHotkeyOverriddenByRuntime(i)) continue;
        if (hk.triggerVK != vk or hk.triggerKind != trigger_kind) continue;
        if ((global_pass and hk.specificityMask != 0) or (!global_pass and hk.specificityMask == 0)) continue;
        if (@atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire) != 0 and !hk.suspendExempt) continue;
        if (!runtimeHotkeyModifiersAllow(hk, active_mods) or !runtimePhysicalModifiersAllow(hk)) continue;
        if (!global_pass and !runtimeHotkeyContextAllows(i)) continue;
        if (shouldDeferBufferedOneLetterRuntimeHotkey(hk, is_down)) continue;
        if (shouldDeferRuntimeContextualTapHotkey(hk, is_down)) continue;
        return @intCast(i);
    }
    return -1;
}

inline fn matchRuntimeContextualTapHotkeyPass(vk: i32, active_mods: u16, global_pass: bool) i32 {
    if (vk < 0 or vk >= VK_COUNT) return -1;
    const hotkey_vk: usize = @intCast(vk);
    const bucket = hotkeyModBucket(active_mods);
    const bank_index = @atomicLoad(u32, &g_activeRuntimeHotkeyReadyIndex, .acquire);
    const ready = &g_runtimeHotkeyReadyIndexes[bank_index];
    const global_bank = @atomicLoad(u32, &g_activeRuntimeGlobalHotkeyIndex, .acquire);
    const global = &g_runtimeGlobalHotkeyIndexes[global_bank];
    const index = if (global_pass) global else ready;
    const range = index.ranges[hotkey_vk][bucket];
    var offset: u32 = 0;
    while (offset < range.len) : (offset += 1) {
        const source_pos: usize = @intCast(range.start + offset);
        const entry_index: usize = @intCast(index.sourceIndexes[source_pos]);
        const hk = g_runtimeHotkeys[entry_index];
        if (hk.actionKind != 1 or hk.triggerKind != 0) continue;
        if (@atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire) != 0 and !hk.suspendExempt) continue;
        if (shouldDeferRuntimeContextualTapHotkey(hk, true)) continue;
        if (!runtimePhysicalModifiersAllow(hk)) continue;
        return @intCast(entry_index);
    }
    // The runtime rows are authoritative.  If a publish/index handoff has
    // left this bucket temporarily stale, do not make a valid compiled or
    // runtime tap disappear; recover by checking the same row predicates
    // directly.  The normal indexed path remains the fast path.
    var i: usize = 0;
    while (i < g_runtimeHotkeysLen) : (i += 1) {
        const hk = g_runtimeHotkeys[i];
        if (runtimeHotkeyOverriddenByRuntime(i)) continue;
        if (hk.triggerVK != vk or hk.triggerKind != 0 or hk.actionKind != 1) continue;
        if ((global_pass and hk.specificityMask != 0) or (!global_pass and hk.specificityMask == 0)) continue;
        if (!runtimeHotkeyModifiersAllow(hk, active_mods) or !runtimePhysicalModifiersAllow(hk)) continue;
        if (!global_pass and !runtimeHotkeyContextAllows(i)) continue;
        if (shouldDeferRuntimeContextualTapHotkey(hk, true)) continue;
        return @intCast(i);
    }
    return -1;
}

inline fn dispatchContextualTapAction(callback_id: i32) void {
    if (nativeHotkeyPayloadOffset(callback_id)) |ptr| {
        if (parseSendDirectSpecText16(wideZSpan(ptr))) |parsed| {
            sendDirectSpec(parsed);
        } else {
            // Match the authoritative runtime hotkey path: ordinary native
            // text payloads use the paste worker; only SendKeyDirect-shaped
            // payloads stay on the direct-key path.  Dropping this branch made
            // compiled taps can otherwise silently no-op.
            enqueueNativePaste(9, callback_id);
        }
        return;
    }
    if (callback_id <= NATIVE_PAYLOAD_ID_BASE) {
        _ = @atomicRmw(u32, &g_nativePasteFailed, .Add, 1, .monotonic);
        return;
    }
    queueRuntimeCallback(callback_id, 9);
    notifyAHK(true, false);
}

inline fn contextualTapCallbackIdValid(callback_id: i32) bool {
    // Accept ordinary runtime IDs, native payload IDs, and the separate
    // reserved range used by complete-compile AHK callbacks.
    return callback_id >= 0 or callback_id <= NATIVE_PAYLOAD_ID_BASE or isCompiledZigCallbackId(callback_id);
}

inline fn contextualTapHoldFallbackCallbackId(vk: usize, explicit_hold_callback_id: i32) i32 {
    if (contextualTapCallbackIdValid(explicit_hold_callback_id)) return explicit_hold_callback_id;
    const tap_hold_hold_callback_id = effectiveTapHoldHoldCallbackId(vk);
    if (contextualTapCallbackIdValid(tap_hold_hold_callback_id)) return tap_hold_hold_callback_id;
    return effectiveHoldCallbackId(vk);
}

inline fn armContextualTap(vk: i32, callback_id: i32, hold_callback_id: i32, cleanup_callback_id: i32, threshold_ticks: i64) void {
    if (vk <= 0 or vk >= VK_COUNT) return;
    if (!g_timerInit) initTimer();
    const idx: usize = @intCast(vk);
    if (g_contextualTapArmed[idx]) return;
    g_contextualTapArmed[idx] = true;
    g_contextualTapCallbackId[idx] = callback_id;
    g_contextualTapHoldCallbackId[idx] = hold_callback_id;
    g_contextualTapCleanupCallbackId[idx] = cleanup_callback_id;
    g_contextualTapThreshold[idx] = threshold_ticks;
    g_contextualTapDownTime[idx] = getTime();
}

inline fn resolveContextualTap(vk: i32) void {
    if (vk <= 0 or vk >= VK_COUNT) return;
    const idx: usize = @intCast(vk);
    if (!g_contextualTapArmed[idx]) return;
    if (!g_timerInit) initTimer();
    const callback_id = g_contextualTapCallbackId[idx];
    const hold_callback_id = g_contextualTapHoldCallbackId[idx];
    const cleanup_callback_id = g_contextualTapCleanupCallbackId[idx];
    const threshold_ticks = if (g_contextualTapThreshold[idx] > 0) g_contextualTapThreshold[idx] else g_SingleKeyHoldThreshold;
    const duration = getTime() - g_contextualTapDownTime[idx];
    const interrupted = g_lastPhysicalDownVK != vk;
    const too_long = duration >= threshold_ticks;
    g_contextualTapArmed[idx] = false;
    g_contextualTapCallbackId[idx] = -1;
    g_contextualTapHoldCallbackId[idx] = -1;
    g_contextualTapCleanupCallbackId[idx] = -1;
    g_contextualTapThreshold[idx] = 0;
    g_contextualTapDownTime[idx] = 0;
    if (interrupted) return;
    if (too_long) {
        const effective_hold_callback_id = contextualTapHoldFallbackCallbackId(idx, hold_callback_id);
        if (contextualTapCallbackIdValid(effective_hold_callback_id)) dispatchContextualTapAction(effective_hold_callback_id);
        if (contextualTapCallbackIdValid(cleanup_callback_id)) dispatchContextualTapAction(cleanup_callback_id);
    } else {
        if (contextualTapCallbackIdValid(callback_id)) dispatchContextualTapAction(callback_id);
    }
}

inline fn tryArmRuntimeContextualTapHotkey(vk: i32, active_mods: u16) bool {
    @setEvalBranchQuota(1_000_000);
    if (vk < 0 or vk >= VK_COUNT) return false;
    const vki: usize = @intCast(vk);
    var index = matchRuntimeContextualTapHotkeyPass(vk, active_mods, false);
    if (index < 0) index = matchRuntimeContextualTapHotkeyPass(vk, active_mods, true);
    if (index < 0) return false;
    queueRuntimeHotkeyIndex(index, true);
    const suppress = runtimeHotkeySuppressesOriginal(index);
    if (suppress) releasePhysicalModsForSuppressingHotkey();
    g_hotkey_consumed_down[vki] = suppress;
    return suppress;
}

inline fn queueRuntimeHotkeyIndex(index: i32, is_down: bool) void {
    const hk = g_runtimeHotkeys[@intCast(index)];
    if (hk.actionKind == 1) {
        if (is_down) armContextualTap(hk.triggerVK, hk.callbackId, hk.holdCallbackId, hk.cleanupCallbackId, hk.thresholdTicks);
        return;
    }
    queueRuntimeCallback(hk.callbackId, 9);
    notifyAHK(true, false);
}

inline fn runtimeHotkeySuppressesOriginal(index: i32) bool {
    return g_runtimeHotkeys[@intCast(index)].suppressOriginal;
}

inline fn hotkeyGateContains(vk: i32) bool {
    if (vk < 0 or vk >= 256) return false;
    const u: usize = @intCast(vk);
    // Only the atomically published active gate participates in the hot path.
    // Permanent registration facts stay append-only, but an inactive context
    // must not keep its VK armed.
    const bank = @atomicLoad(u32, &g_activeHotkeyGateBank, .acquire);
    return (g_hotkeyActiveGateBanks[bank][u >> 6] & (@as(u64, 1) << @intCast(u & 63))) != 0;
}

inline fn keyHasRegisteredHotkey(vk: i32) bool {
    if (vk < 0 or vk >= VK_COUNT) return false;
    const idx: usize = @intCast(vk);
    // The permanent runtime gate covers rows registered in any context;
    // the published gate covers currently active compiled/context rows.
    return g_runtimeHotkeyGate[idx] or hotkeyGateContains(vk);
}

/// Cheap registration gate for events that need current window context before
/// matching. Global rows do not cause WinGetTitle/WinGetClass/
/// WinGetProcessName work on every key event.
inline fn keyHasContextSensitiveRegistration(vk: i32) bool {
    if (vk < 0 or vk >= VK_COUNT) return false;
    const idx: usize = @intCast(vk);
    if (g_runtimeContextHotkeyGate[idx] or g_runtimeContextActionGate[idx]) return true;
    return false;
}

inline fn prepareStructuralModifierContext(vk: i32, is_down: bool) void {
    if (!is_down or vk < 0 or vk >= VK_COUNT or
        !g_runtimeContextModifierGate[@intCast(vk)]) return;
    refreshForegroundContextIfChanged();
}

/// Context discovery is allowed for chord keys. Only standalone contextual
/// tap arming below is restricted to the first key in a sequence.
inline fn shouldPrepareStructuralHotkeyContext(vk: i32, is_down: bool) bool {
    return is_down and g_kbLen == 0 and keyHasContextSensitiveRegistration(vk);
}

/// The native contextual tap descriptor is a standalone one-key remap. It
/// must not pre-empt a chord once any other physical key is down, even though
/// the chord itself remains outside this one-letter hotkey gate.  A key can be
/// pending in the solo/roll fast path without being materialized in kb[], so
/// g_kbLen alone is not sufficient here.  Returning false is intentional: the
/// caller then sends this event through processKeyEventHot/bufferKeyDown so the
/// chord engine can consume it as the next member.
inline fn shouldArmRuntimeContextualTapHotkey(vk: i32, is_down: bool) bool {
    return is_down and !keySequenceActive() and keyHasRegisteredHotkey(vk);
}

inline fn keySequenceActive() bool {
    // g_kbLen does not include keys parked in the solo/roll fast path yet.
    return g_kbLen != 0 or pendingSoloActive() or pendingRollActive() or
        g_pendingChord.active;
}

fn publishCombinedHotkeyGate() void {
    const current = @atomicLoad(u32, &g_activeHotkeyGateBank, .acquire);
    const next = current ^ 1;
    var bits = &g_hotkeyActiveGateBanks[next];
    bits.* = [_]u64{0} ** 4;
    const runtime_bank = @atomicLoad(u32, &g_activeRuntimeHotkeyReadyIndex, .acquire);
    const global_bank = @atomicLoad(u32, &g_activeRuntimeGlobalHotkeyIndex, .acquire);
    var vk: usize = 0;
    while (vk < 256) : (vk += 1) {
        const runtime_active = g_runtimeHotkeyReadyIndexes[runtime_bank].activeGate[vk] or
            g_runtimeGlobalHotkeyIndexes[global_bank].activeGate[vk];
        if (runtime_active) bits[vk >> 6] |= @as(u64, 1) << @intCast(vk & 63);
    }
    @atomicStore(u32, &g_activeHotkeyGateBank, next, .release);
}

// Resolution is contextual before global. Matching queues the callback, but
// only suppress-original rows own the physical key's down/up pair.
inline fn queueAnyHotkeyIfMatched(vk: i32, active_mods: u16, is_down: bool) bool {
    @setEvalBranchQuota(1_000_000);
    if (vk < 0 or vk >= VK_COUNT) return false;
    if (shouldPrepareStructuralHotkeyContext(vk, is_down) and
        !prepareStructuralHotkeyContext(vk, active_mods, is_down)) return false;
    const vki: usize = @intCast(vk);
    if (!is_down) {
        resolveContextualTap(vk);
        var matched_up_suppressed = false;
        var index = matchRuntimeHotkeyPass(vk, active_mods, false, false);
        if (index >= 0) {
            queueRuntimeHotkeyIndex(index, false);
            matched_up_suppressed = runtimeHotkeySuppressesOriginal(index);
        }
        if (index < 0) {
            index = matchRuntimeHotkeyPass(vk, active_mods, false, true);
            if (index >= 0) {
                queueRuntimeHotkeyIndex(index, false);
                matched_up_suppressed = runtimeHotkeySuppressesOriginal(index);
            }
        }
        const consumed_down = g_hotkey_consumed_down[vki];
        g_hotkey_consumed_down[vki] = false;
        return matched_up_suppressed or consumed_down;
    }

    var index = matchRuntimeHotkeyPass(vk, active_mods, true, false);
    if (index >= 0) {
        queueRuntimeHotkeyIndex(index, true);
        const suppress = runtimeHotkeySuppressesOriginal(index);
        if (suppress) releasePhysicalModsForSuppressingHotkey();
        g_hotkey_consumed_down[vki] = suppress;
        return suppress;
    }
    index = matchRuntimeHotkeyPass(vk, active_mods, true, true);
    if (index >= 0) {
        queueRuntimeHotkeyIndex(index, true);
                const suppress = runtimeHotkeySuppressesOriginal(index);
        if (suppress) releasePhysicalModsForSuppressingHotkey();
        g_hotkey_consumed_down[vki] = suppress;
        return suppress;
    }
    return false;
}

inline fn queueCompiledHotkeyIfMatched(vk: i32, active_mods: u16, is_down: bool) bool {
    return queueAnyHotkeyIfMatched(vk, active_mods, is_down);
}

inline fn queueCompiledHotkeyIfMatchedSingleModProfiled(vk: i32, active_mods: u16, is_down: bool) bool {
    return queueAnyHotkeyIfMatched(vk, active_mods, is_down);
}

inline fn matchReversePhysicalModHotkey(mod_vk: i32, active_mods: u16) i32 {
    if (comptime !has_qmk_shortcuts_build) {
        return -1;
    }
    if (mod_vk < 0 or mod_vk >= VK_COUNT) return -1;

    var best_index: i32 = -1;
    var best_priority: u8 = 0;
    const index = &hotkeys.KEYDOWN_INDEX;
    const bucket = hotkeyModBucket(active_mods);

    var held_vk: usize = 0;
    while (held_vk < VK_COUNT) : (held_vk += 1) {
        if (held_vk == @as(usize, @intCast(mod_vk))) continue;
        if (!physicalKeyDownAt(held_vk)) continue;
        if (!g_compiledHotkeyGate[held_vk]) continue;

        const range = index.ranges[held_vk][bucket];
        var offset: u16 = 0;
        while (offset < range.len) : (offset += 1) {
            const entry_index: usize = @intCast(index.source_indexes[range.start + offset]);
            const hk = hotkeys.HOTKEYS[entry_index];
            if (hk.physical_mod_vk != @as(u8, @intCast(mod_vk))) continue;
            if ((active_mods & hk.mods_required) != hk.mods_required) continue;
            if ((active_mods & hk.mods_forbidden) != 0) continue;
            if (!hotkeyContextAllows(hk, entry_index)) continue;
            if (best_index == -1 or hk.priority > best_priority) {
                best_index = @intCast(entry_index);
                best_priority = hk.priority;
            }
        }
    }

    return best_index;
}

inline fn queueReversePhysicalModHotkeyIfMatched(mod_vk: i32, active_mods: u16) bool {
    // Compiled rows are inserted into the same runtime hotkey store.  This
    // legacy generated-table path is intentionally disabled so it cannot
    // compete with the runtime matcher.
    _ = mod_vk;
    _ = active_mods;
    return false;
}

inline fn msToTicksInt(ms: i32) i64 {
    return @divTrunc(@as(i64, ms) * g_qpcFreq, 1000);
}

inline fn tapHoldThresholdTicks(vk: i32) i64 {
    const idx: usize = @intCast(vk);
    return if (g_tapHoldThreshold[idx] > 0) g_tapHoldThreshold[idx] else msToTicksInt(200);
}

fn anyOtherPhysicalKeyDown(skip_vk: i32) bool {
    var i: usize = 0;
    while (i < VK_COUNT) : (i += 1) {
        if (@as(i32, @intCast(i)) != skip_vk and physicalKeyDownAt(i)) return true;
    }
    return false;
}

inline fn markGenericTapHoldInterrupted(vk: i32, is_down: bool) void {
    if (!is_down) return;
    var i: usize = 0;
    while (i < VK_COUNT) : (i += 1) {
        if (@as(i32, @intCast(i)) != vk and g_tapHoldArmed[i]) {
            g_tapHoldInterrupted[i] = true;
        }
    }
}

inline fn genericTapHoldConfigured(vk: i32) bool {
    if (vk <= 0 or vk >= VK_COUNT) return false;
    const idx: usize = @intCast(vk);
    // A key armed by an earlier key-down keeps its release routed here even if a
    // context change cleared its callbacks in between, otherwise it stays armed forever.
    return g_tapHoldArmed[idx] or
        contextualTapCallbackIdValid(effectiveTapHoldTapCallbackId(idx)) or
        contextualTapCallbackIdValid(effectiveTapHoldHoldCallbackId(idx));
}

inline fn queueGenericTapHoldCallback(vk: i32, callback_id: i32) void {
    if (!contextualTapCallbackIdValid(callback_id)) return;
    const idx: usize = @intCast(vk);
    if (g_tapHoldCallbackQueued[idx]) return;
    g_tapHoldCallbackQueued[idx] = true;
    dispatchContextualTapAction(callback_id);
}

fn handleGenericTapHold(vk: i32, is_down: bool) bool {
    if (!genericTapHoldConfigured(vk)) return false;
    if (!g_timerInit) initTimer();
    const idx: usize = @intCast(vk);

    if (is_down) {
        // Held keys emit repeated key-down strokes. Re-arming on each repeat would
        // keep resetting the timer, so a hold could never accumulate enough duration.
        if (g_tapHoldArmed[idx]) return true;
        g_tapHoldCallbackQueued[idx] = false;
        g_tapHoldDownTime[idx] = getTime();
        g_tapHoldArmedTapCallbackId[idx] = effectiveTapHoldTapCallbackId(idx);
        g_tapHoldArmedHoldCallbackId[idx] = effectiveTapHoldHoldCallbackId(idx);
        g_tapHoldArmedCleanupCallbackId[idx] = effectiveTapHoldCleanupCallbackId(idx);
        g_tapHoldArmedThreshold[idx] = effectiveTapHoldThresholdTicks(idx);
        g_tapHoldArmed[idx] = true;
        g_tapHoldInterrupted[idx] = compute_modifiers_to_send() != 0 or anyOtherPhysicalKeyDown(vk);
        return true;
    }

    if (!g_tapHoldArmed[idx]) {
        queueGenericTapHoldCallback(vk, g_tapHoldCleanupCallbackId[idx]);
        return true;
    }

    const duration = getTime() - g_tapHoldDownTime[idx];
    const callback_index = if (g_tapHoldInterrupted[idx])
        g_tapHoldArmedCleanupCallbackId[idx]
    else if (duration >= g_tapHoldArmedThreshold[idx])
        g_tapHoldArmedHoldCallbackId[idx]
    else
        g_tapHoldArmedTapCallbackId[idx];

    g_tapHoldArmed[idx] = false;
    g_tapHoldDownTime[idx] = 0;
    g_tapHoldInterrupted[idx] = false;
    g_tapHoldArmedTapCallbackId[idx] = -1;
    g_tapHoldArmedHoldCallbackId[idx] = -1;
    g_tapHoldArmedCleanupCallbackId[idx] = -1;
    g_tapHoldArmedThreshold[idx] = 0;

    queueGenericTapHoldCallback(vk, callback_index);
    return true;
}

fn setupStaticTapHold(vk: i32, tap_callback_id: i32, hold_callback_id: i32, cleanup_callback_id: i32, threshold_ms: i32) i32 {
    if (vk <= 0 or vk >= VK_COUNT) return 0;
    if (tap_callback_id < 0 and hold_callback_id < 0) return 0;
    const idx: usize = @intCast(vk);
    g_tapHoldTapCallbackId[idx] = tap_callback_id;
    g_tapHoldHoldCallbackId[idx] = hold_callback_id;
    g_tapHoldCleanupCallbackId[idx] = cleanup_callback_id;
    g_tapHoldThreshold[idx] = msToTicksInt(@max(50, @min(2000, threshold_ms)));
    g_tapHoldArmed[idx] = false;
    g_tapHoldInterrupted[idx] = false;
    g_tapHoldCallbackQueued[idx] = false;
    g_tapHoldArmedTapCallbackId[idx] = -1;
    g_tapHoldArmedHoldCallbackId[idx] = -1;
    g_tapHoldArmedCleanupCallbackId[idx] = -1;
    g_tapHoldArmedThreshold[idx] = 0;
    return 1;
}

/// Sets the per-key tap/hold threshold and cleanup callback without touching the
/// tap/hold callback ids. Context-aware registrations supply those through
/// QMK_SetupContextActions action kinds 2 and 3, which are re-resolved on
/// every context change.
fn setupStaticTapHoldTuning(vk: i32, cleanup_callback_id: i32, threshold_ms: i32) i32 {
    if (vk <= 0 or vk >= VK_COUNT) return 0;
    const idx: usize = @intCast(vk);
    g_tapHoldCleanupCallbackId[idx] = cleanup_callback_id;
    g_tapHoldThreshold[idx] = msToTicksInt(@max(50, @min(2000, threshold_ms)));
    g_tapHoldArmed[idx] = false;
    g_tapHoldInterrupted[idx] = false;
    g_tapHoldCallbackQueued[idx] = false;
    g_tapHoldArmedTapCallbackId[idx] = -1;
    g_tapHoldArmedHoldCallbackId[idx] = -1;
    g_tapHoldArmedCleanupCallbackId[idx] = -1;
    g_tapHoldArmedThreshold[idx] = 0;
    return 1;
}

// Retained for ABI compatibility with older AHK loaders. Generic tap/hold
// callbacks reset their per-VK queued state when the next press is armed.
export fn QMK_AcknowledgeTapHoldCallback() callconv(.c) void {}

fn cleanupBufferedKeyAfterConsumedKeyUp(vk: i32) void {
    if (vk <= 0 or vk >= VK_COUNT) return;
    const idx = kbFind(vk) orelse return;
    const kd = &g_kbData[idx];
    cancelKeyTimers(vk);
    if (kd.modifierActivated()) {
        const modVK = g_virtual_modifier_output_vk[@intCast(vk)];
        if (modVK != 0) {
            ringReset();
            ringAddKey(modVK, KEYEVENTF_KEYUP);
            ringSend();
        }
    }
    remove_active_virtual_modifier(vk);
    markKeyReleased(vk, kd);
    kd.releaseTime = getTime();
    activePrimaryBitsSync(vk, kd.*);
    if (pendingChordContains(vk)) clearPendingChord();
    _ = kbRemove(vk);
    removeFromKeyOrder(vk);
    rebuildUnreleasedModifierCounters();
}

// A tap/hold participant must remain on the structural buffer path. The
// generic tap/hold fast handler predates combo participation and returns from
// QMK_ProcessKeyEvent before bufferKeyDown can observe the prefix/secondary.
// The structural path still resolves the same tap/hold callbacks on a solo
// release; yielding here only lets combo/chord precedence be decided first.
inline fn genericTapHoldMustYieldToCombo(vk: i32) bool {
    if (vk <= 0 or vk >= VK_COUNT) return false;
    const props = activeContextDerived().gate[@intCast(vk)].props;
    return (props & (KP_CAN_BE_COMBO_PRIMARY |
        KP_CAN_BE_INSTANT_COMBO_PRIMARY |
        KP_CAN_BE_COMBO_SECONDARY |
        KP_CAN_BE_INSTANT_COMBO_SECONDARY)) != 0;
}

export fn QMK_ProcessKeyEvent(vk: i32, isDown: i32) callconv(.c) void {
    ensureQmkInputThreadPriority();

    const is_down = (isDown != 0);
    beginHotPathActivity();
    defer endHotPathActivity(is_down);
    if (isModVK(vk)) {
        const incoming_tracked_vk = physicalModifierTrackingVK(vk);
        const hidden_up = !is_down and physicalModifierHiddenFromOs(incoming_tracked_vk);
        const tracked_vk = apply_physical_modifier_event(vk, is_down);
        if (is_down) cancelRepeatForDifferentKeyDown(tracked_vk);
        if (!is_down) cancelRepeatForRequiredKeyUp(tracked_vk);
        if (is_down) markPhysicalModifierHiddenFromOs(tracked_vk);
        markGenericTapHoldInterrupted(tracked_vk, is_down);
        const modMask = compute_modifiers_to_send();
        handleNativePanicExitIfMatched(tracked_vk, modMask, is_down);
        handleNativeReloadIfMatched(tracked_vk, modMask, is_down);
        if (handleNativeSuspendIfMatched(tracked_vk, modMask, is_down)) return;
        var consumed = false;
        if (@atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire) != 0) {
            consumed = queueAnyHotkeyIfMatchedWithGenericModFallback(tracked_vk, modMask, is_down);
        } else {
            consumed = if (is_down)
                queueReversePhysicalModHotkeyIfMatched(tracked_vk, modMask) or queueAnyHotkeyIfMatchedWithGenericModFallback(tracked_vk, modMask, true)
            else
                queueAnyHotkeyIfMatchedWithGenericModFallback(tracked_vk, modMask, false);
        }
        if (consumed and !is_down) cleanupBufferedKeyAfterConsumedKeyUp(tracked_vk);

        if (is_down) {
            if (consumed or !g_physical_modifier_passthrough) {
                markPhysicalModifierHiddenFromOs(tracked_vk);
            } else {
                clearPhysicalModifierHiddenFromOs(tracked_vk);
            }
        } else if (hidden_up) {
            clearPhysicalModifierHiddenFromOs(tracked_vk);
        }

        if (consumed or hidden_up or !g_physical_modifier_passthrough) {
            return;
        }
        processKeyEventHot(tracked_vk, isDown);
        return;
    }
    prepareStructuralModifierContext(vk, is_down);
    setPhysicalKeyDownState(vk, is_down);
    markGenericTapHoldInterrupted(vk, is_down);
    const qmk_mod_mask = compute_modifiers_to_send();
    handleNativePanicExitIfMatched(vk, qmk_mod_mask, is_down);
    handleNativeReloadIfMatched(vk, qmk_mod_mask, is_down);
    if (handleNativeSuspendIfMatched(vk, qmk_mod_mask, is_down)) return;
    if (@atomicLoad(i32, &g_runtimeHotkeysSuspended, .acquire) != 0) {
        const consumed = queueAnyHotkeyIfMatched(vk, qmk_mod_mask, is_down);
        if (consumed and !is_down) cleanupBufferedKeyAfterConsumedKeyUp(vk);
        return;
    }

    if (tryHandleContextMenuDigit(vk, is_down)) return;

    // A tap/hold press that armed while unmodified owns its eventual key-up even
    // if another modifier is now held. That release must resolve through the
    // tap/hold state machine so an interrupted press cannot leak a tap/hold
    // callback or remain armed after a suppressing chord such as Ctrl+CapsLock.
    const tap_hold_owns_release = !is_down and vk > 0 and vk < VK_COUNT and
        g_tapHoldArmed[@intCast(vk)];
    const contextual_tap_owns_release = !is_down and vk > 0 and vk < VK_COUNT and
        g_contextualTapArmed[@intCast(vk)];
    // Contextual tap-hotkey arming can return before queueAnyHotkeyIfMatched,
    // so perform structural discovery before that early-return path too.
    if (shouldPrepareStructuralHotkeyContext(vk, is_down))
        _ = prepareStructuralHotkeyContext(vk, qmk_mod_mask, is_down);
    prepareStructuralContextAction(vk);
    if (shouldArmRuntimeContextualTapHotkey(vk, is_down) and qmk_mod_mask == 0 and
        tryArmRuntimeContextualTapHotkey(vk, qmk_mod_mask))
    {
        return;
    }
    if (genericTapHoldConfigured(vk) and !genericTapHoldMustYieldToCombo(vk) and !contextual_tap_owns_release and
        (!is_down or !keySequenceActive()) and
        (qmk_mod_mask == 0 or tap_hold_owns_release)) {
        if (handleGenericTapHold(vk, is_down)) return;
    }

    // Four-word active gate avoids all row work for keys with no active hotkey.
    if (queueAnyHotkeyIfMatched(vk, qmk_mod_mask, is_down)) {
        if (is_down) hotstringRecordConsumedKeyDown(vk);
        if (!is_down) cleanupBufferedKeyAfterConsumedKeyUp(vk);
        return;
    }
    processKeyEventHot(vk, isDown);
}

inline fn contextFieldChanged(current: []const u16, incoming: [*:0]const u16) bool {
    return !eqlIgnoreCase16(wideSpan(current), wideZSpan(incoming));
}

inline fn contextMenuChanged(has_context_menu: i32) bool {
    const next: u8 = if (has_context_menu != 0) 1 else 0;
    return g_hotkeyContextState.has_context_menu != next;
}

/// Updates the menu bit and optionally queues it for the background publisher.
/// Input-time callers use queue_publish=false so the current key can rebuild
/// the ready context bank before matching.  A pending external update is
/// consumed in that mode; otherwise an AHK-published menu state could remain
/// invisible to the current key until the publisher wakes up.
fn updateContextMenuStateNative(has_context_menu: i32, queue_publish: bool) u8 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    const changed = contextMenuChanged(has_context_menu);
    const pending = (g_pendingContextChangedMask & RUNTIME_CONTEXT_MENU_BIT) != 0;
    if (changed) {
        g_hotkeyContextState.has_context_menu = if (has_context_menu != 0) 1 else 0;
        _ = @atomicRmw(u32, &g_hotkeyContextState.generation, .Add, 1, .acq_rel);
    }
    if (queue_publish) {
        if (!changed) return 0;
        g_pendingContextChangedMask |= RUNTIME_CONTEXT_MENU_BIT;
        requestRuntimePublish(RUNTIME_PUBLISH_CONTEXTS);
        return RUNTIME_CONTEXT_MENU_BIT;
    }
    if (pending) g_pendingContextChangedMask &= ~RUNTIME_CONTEXT_MENU_BIT;
    return if (changed or pending) RUNTIME_CONTEXT_MENU_BIT else 0;
}

/// Performs a live Win32 lookup. FindWindowW checks the current desktop's
/// top-level windows and returns a handle only while a matching #32768 menu
/// window exists; it does not consult a cached QMK state value.
inline fn refreshContextMenuStateForInput() u8 {
    const has_context_menu = FindWindowW(CONTEXT_MENU_CLASS[0..:0].ptr, null) != null;
    return updateContextMenuStateNative(if (has_context_menu) 1 else 0, false);
}

fn setContextMenuStateNative(has_context_menu: i32) void {
    _ = updateContextMenuStateNative(has_context_menu, true);
}

fn isContextMenuWindow(hwnd: ?HANDLE) bool {
    const h = hwnd orelse return false;
    var class_name: [16]u16 = [_]u16{0} ** 16;
    const len = GetClassNameW(h, &class_name, @intCast(class_name.len));
    if (len != 6) return false;
    return class_name[0] == '#' and class_name[1] == '3' and class_name[2] == '2' and
        class_name[3] == '7' and class_name[4] == '6' and class_name[5] == '8';
}

fn rootWindowFromEventHwnd(hwnd: ?HANDLE) ?HANDLE {
    const raw = hwnd orelse return GetForegroundWindow();
    return GetAncestor(raw, GA_ROOT) orelse raw;
}

/// Website context is owned by the external OnWebsite publisher. Native
/// foreground refreshes never clear or rewrite this field; the publisher
/// explicitly sends the URL or an empty string when it becomes invalid.
export fn QMK_SetWebsiteContext(url: [*:0]const u16) callconv(.c) void {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    var changed: u8 = 0;
    if (contextFieldChanged(&g_hotkeyContextState.url, url)) changed |= RUNTIME_CONTEXT_WEBSITE_BIT | RUNTIME_CONTEXT_BROWSER_BIT;
    copyWideZToSlice(&g_hotkeyContextState.url, url);
    if (changed == 0) return;
    _ = @atomicRmw(u32, &g_hotkeyContextState.generation, .Add, 1, .acq_rel);
    g_pendingContextChangedMask |= changed;
    requestRuntimePublish(RUNTIME_PUBLISH_CONTEXTS);
}

export fn QMK_SetWebsiteContextGuarded(url: [*:0]const u16, expected_exe: [*:0]const u16, expected_class: [*:0]const u16, expected_hwnd: usize, has_context_menu: i32) callconv(.c) i32 {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    if (expected_hwnd != 0) {
        const current_hwnd = rootWindowFromEventHwnd(null) orelse return 0;
        if (expected_hwnd != @intFromPtr(current_hwnd)) return 0;
    }
    if (wideZSpan(expected_exe).len != 0 and contextFieldChanged(&g_hotkeyContextState.win_exe, expected_exe)) return 0;
    if (wideZSpan(expected_class).len != 0 and contextFieldChanged(&g_hotkeyContextState.win_class, expected_class)) return 0;

    var changed: u8 = 0;
    if (contextFieldChanged(&g_hotkeyContextState.url, url)) changed |= RUNTIME_CONTEXT_WEBSITE_BIT | RUNTIME_CONTEXT_BROWSER_BIT;
    if (contextMenuChanged(has_context_menu)) changed |= RUNTIME_CONTEXT_MENU_BIT;
    copyWideZToSlice(&g_hotkeyContextState.url, url);
    g_hotkeyContextState.has_context_menu = if (has_context_menu != 0) 1 else 0;
    if (changed == 0) return 1;
    _ = @atomicRmw(u32, &g_hotkeyContextState.generation, .Add, 1, .acq_rel);
    g_pendingContextChangedMask |= changed;
    requestRuntimePublish(RUNTIME_PUBLISH_CONTEXTS);
    return 1;
}

export fn QMK_SetContextState(title: [*:0]const u16, exe: [*:0]const u16, url: [*:0]const u16) callconv(.c) void {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    var changed: u8 = 0;
    if (contextFieldChanged(&g_hotkeyContextState.win_title, title)) changed |= RUNTIME_CONTEXT_TITLE_BIT;
    if (contextFieldChanged(&g_hotkeyContextState.win_exe, exe)) changed |= RUNTIME_CONTEXT_EXE_BIT | RUNTIME_CONTEXT_BROWSER_BIT;
    if (wideSpan(&g_hotkeyContextState.win_class).len != 0) changed |= RUNTIME_CONTEXT_CLASS_BIT;
    if (contextFieldChanged(&g_hotkeyContextState.url, url)) changed |= RUNTIME_CONTEXT_WEBSITE_BIT | RUNTIME_CONTEXT_BROWSER_BIT;
    copyWideZToSlice(&g_hotkeyContextState.win_title, title);
    copyWideZToSlice(&g_hotkeyContextState.win_exe, exe);
    @memset(&g_hotkeyContextState.win_class, 0);
    copyWideZToSlice(&g_hotkeyContextState.url, url);
    if (changed == 0) return;
    _ = @atomicRmw(u32, &g_hotkeyContextState.generation, .Add, 1, .acq_rel);
    g_pendingContextChangedMask |= changed;
    requestRuntimePublish(RUNTIME_PUBLISH_CONTEXTS);
}

export fn QMK_SetContextStateFull(title: [*:0]const u16, exe: [*:0]const u16, class_name: [*:0]const u16, url: [*:0]const u16) callconv(.c) void {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    var changed: u8 = 0;
    if (contextFieldChanged(&g_hotkeyContextState.win_title, title)) changed |= RUNTIME_CONTEXT_TITLE_BIT;
    if (contextFieldChanged(&g_hotkeyContextState.win_exe, exe)) changed |= RUNTIME_CONTEXT_EXE_BIT | RUNTIME_CONTEXT_BROWSER_BIT;
    if (contextFieldChanged(&g_hotkeyContextState.win_class, class_name)) changed |= RUNTIME_CONTEXT_CLASS_BIT;
    if (contextFieldChanged(&g_hotkeyContextState.url, url)) changed |= RUNTIME_CONTEXT_WEBSITE_BIT | RUNTIME_CONTEXT_BROWSER_BIT;
    copyWideZToSlice(&g_hotkeyContextState.win_title, title);
    copyWideZToSlice(&g_hotkeyContextState.win_exe, exe);
    copyWideZToSlice(&g_hotkeyContextState.win_class, class_name);
    copyWideZToSlice(&g_hotkeyContextState.url, url);
    if (changed == 0) return;
    _ = @atomicRmw(u32, &g_hotkeyContextState.generation, .Add, 1, .acq_rel);
    g_pendingContextChangedMask |= changed;
    requestRuntimePublish(RUNTIME_PUBLISH_CONTEXTS);
}

export fn QMK_SetContextStateFullV2(title: [*:0]const u16, exe: [*:0]const u16, class_name: [*:0]const u16, url: [*:0]const u16, has_context_menu: i32) callconv(.c) void {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    var changed: u8 = 0;
    if (contextFieldChanged(&g_hotkeyContextState.win_title, title)) changed |= RUNTIME_CONTEXT_TITLE_BIT;
    if (contextFieldChanged(&g_hotkeyContextState.win_exe, exe)) changed |= RUNTIME_CONTEXT_EXE_BIT | RUNTIME_CONTEXT_BROWSER_BIT;
    if (contextFieldChanged(&g_hotkeyContextState.win_class, class_name)) changed |= RUNTIME_CONTEXT_CLASS_BIT;
    if (contextFieldChanged(&g_hotkeyContextState.url, url)) changed |= RUNTIME_CONTEXT_WEBSITE_BIT | RUNTIME_CONTEXT_BROWSER_BIT;
    if (contextMenuChanged(has_context_menu)) changed |= RUNTIME_CONTEXT_MENU_BIT;
    copyWideZToSlice(&g_hotkeyContextState.win_title, title);
    copyWideZToSlice(&g_hotkeyContextState.win_exe, exe);
    copyWideZToSlice(&g_hotkeyContextState.win_class, class_name);
    copyWideZToSlice(&g_hotkeyContextState.url, url);
    g_hotkeyContextState.has_context_menu = if (has_context_menu != 0) 1 else 0;
    if (changed == 0) return;
    _ = @atomicRmw(u32, &g_hotkeyContextState.generation, .Add, 1, .acq_rel);
    g_pendingContextChangedMask |= changed;
    requestRuntimePublish(RUNTIME_PUBLISH_CONTEXTS);
}

const PROCESS_QUERY_LIMITED_INFORMATION: DWORD = 0x1000;

const ForegroundContextRefreshResult = struct {
    ok: bool = false,
    changed: u8 = 0,
};

fn refreshForegroundContextFromHwndMode(candidate_hwnd: ?HANDLE, queue_publish: bool) ForegroundContextRefreshResult {
    const hwnd = rootWindowFromEventHwnd(candidate_hwnd) orelse return .{};
    var title: [512:0]u16 = [_:0]u16{0} ** 512;
    var class_name: [256:0]u16 = [_:0]u16{0} ** 256;
    var exe: [256:0]u16 = [_:0]u16{0} ** 256;

    _ = GetWindowTextW(hwnd, &title, @intCast(title.len));
    _ = GetClassNameW(hwnd, &class_name, @intCast(class_name.len));

    var pid: DWORD = 0;
    _ = GetWindowThreadProcessId(hwnd, &pid);
    if (pid != 0) {
        if (OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid)) |proc| {
            var size: DWORD = @intCast(exe.len);
            if (QueryFullProcessImageNameW(proc, 0, &exe, &size) == FALSE) {
                exe[0] = 0;
            } else if (size < exe.len) {
                exe[@intCast(size)] = 0;
            } else {
                exe[exe.len - 1] = 0;
            }
            _ = CloseHandle(proc);
        }
    }

    acquireSetupPublishLock();
    var changed: u8 = 0;
    if (contextFieldChanged(&g_hotkeyContextState.win_title, &title)) changed |= RUNTIME_CONTEXT_TITLE_BIT;
    if (contextFieldChanged(&g_hotkeyContextState.win_exe, &exe)) changed |= RUNTIME_CONTEXT_EXE_BIT | RUNTIME_CONTEXT_BROWSER_BIT;
    if (contextFieldChanged(&g_hotkeyContextState.win_class, &class_name)) changed |= RUNTIME_CONTEXT_CLASS_BIT;
    copyWideZToSlice(&g_hotkeyContextState.win_title, &title);
    copyWideZToSlice(&g_hotkeyContextState.win_exe, &exe);
    copyWideZToSlice(&g_hotkeyContextState.win_class, &class_name);
    if (changed != 0) {
        _ = @atomicRmw(u32, &g_hotkeyContextState.generation, .Add, 1, .acq_rel);
        if (queue_publish) {
            g_pendingContextChangedMask |= changed;
            requestRuntimePublish(RUNTIME_PUBLISH_CONTEXTS);
        }
    }
    releaseSetupPublishLock();
    return .{ .ok = true, .changed = changed };
}

fn refreshForegroundContextFromHwnd(candidate_hwnd: ?HANDLE) i32 {
    const result = refreshForegroundContextFromHwndMode(candidate_hwnd, true);
    return if (result.ok) 1 else 0;
}

export fn QMK_RefreshForegroundContext() callconv(.c) i32 {
    return refreshForegroundContextFromHwnd(null);
}

export fn QMK_RefreshForegroundContextForHwnd(hwnd_value: usize) callconv(.c) i32 {
    const hwnd: ?HANDLE = if (hwnd_value == 0) null else @ptrFromInt(hwnd_value);
    return refreshForegroundContextFromHwnd(hwnd);
}

/// Test-only switch for the guarded Zig suite.  Normal builds cannot alter
/// foreground refresh behavior because this flag is compiled out at use sites.
export fn QMK_TestSetForegroundRefreshSuppressed(enabled: i32) callconv(.c) void {
    if (!compiled_shortcuts_test_observability) return;
    g_testSuppressForegroundRefresh = enabled != 0;
}

export fn QMK_RefreshContextMenuState() callconv(.c) i32 {
    const has_context_menu = FindWindowW(CONTEXT_MENU_CLASS[0..:0].ptr, null) != null;
    setContextMenuStateNative(if (has_context_menu) 1 else 0);
    return if (has_context_menu) 1 else 0;
}

export fn QMK_SetContextMenuState(has_context_menu: i32) callconv(.c) void {
    setContextMenuStateNative(has_context_menu);
}

export fn QMK_SetContextMenuDigitAccessMap(vks: [*]const i32, len: u32) callconv(.c) void {
    const count: usize = @min(@as(usize, @intCast(len)), g_contextMenuDigitAccessVK.len);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const vk = vks[i];
        g_contextMenuDigitAccessVK[i] = if (vk > 0 and vk < VK_COUNT) vk else 0;
    }
    while (i < g_contextMenuDigitAccessVK.len) : (i += 1) {
        g_contextMenuDigitAccessVK[i] = 0;
    }
}

export fn QMK_SetHotstringContextMask(mask: u64) callconv(.c) void {
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    const previous = @atomicLoad(u64, &g_hotstringContextState.active_mask, .acquire);
    if (previous == mask) return;
    g_pendingHotstringContextMask = mask;
    g_pendingHotstringContextMaskValid = true;
    requestRuntimePublish(RUNTIME_PUBLISH_HOTSTRING_CONTEXT_MASK);
}

export fn QMK_GetHotstringContextMask() callconv(.c) u64 {
    return @atomicLoad(u64, &g_hotstringContextState.active_mask, .acquire);
}

noinline fn warmProcessKeyEvent(vk: i32, isDown: i32) void {
    const is_down = isDown != 0;
    setPhysicalKeyDownState(vk, is_down);
    processKeyEventHot(vk, isDown);
}

fn clearWarmHotPathStateOnly() void {
    pendingSoloClear();
    pendingRollClear();
    kbClear();
    ordClear();
    clear_active_virtual_modifiers();
    timerClear();
    kdtClear();
    kutClear();
    pcbClear();
    g_active_physical_and_windows_facing_modifiers = 0;
    g_active_physical_modifiers = 0;
    g_any_physical_modifiers_active = false;
    clearPhysicalKeyDownState();
    @memset(&g_foreignPhysicalKeyDown, false);
    g_foreignPhysicalQuarantineArmed = false;
    g_trackedPhysicalKeysDown = 0;
    g_lastPhysicalDownVK = 0;
    g_which_physical_modifiers_to_send = 0;
    g_lr_active_physical_modifiers = 0;
    @memset(&g_active_physical_modifier_key_counts_by_category, 0);
    @memset(&g_hotkey_consumed_down, false);
    g_lastKeyTime = 0;
    g_typingMode = false;
    g_typingModeUntil = 0;
    g_hotFlags &= ~HF_TYPING;
    g_runtimeFlags = 0;
    g_unreleasedKeyCount = 0;
    g_unreleasedNonModCount = 0;
    g_unrelModCount = 0;
    g_cleanUnrelModCount = 0;
    g_activeModKeyCnt = 0;
    g_modStackDirty = false;
    g_hotstringMatcher.reset();
}

export fn QMK_WarmHotPath() callconv(.c) void {
    initTimer();
    if (g_trackedPhysicalKeysDown != 0 or
        @atomicLoad(i32, &g_hotPathActiveCount, .acquire) != 0 or
        @atomicLoad(u32, &g_runtimePublishPendingMask, .acquire) != 0)
    {
        return;
    }
    const oldSuppress = g_suppressOutputForReplay;
    const oldProfiling = g_profilingEnabled;
    g_suppressOutputForReplay = true;
    g_profilingEnabled = false;

    // Warm the real common event path, not broad cold tables:
    // physical state write, repeat cancel gate, solo tap, rolling overlap,
    // direct tap drain, and a few homerow-ish alpha keys.
    const solo = [_]i32{ 65, 83, 68, 70, 74, 75, 76, 69 };
    var round: u32 = 0;
    while (round < 3) : (round += 1) {
        for (solo) |vk| {
            warmProcessKeyEvent(vk, 1);
            warmProcessKeyEvent(vk, 0);
        }
        warmProcessKeyEvent(65, 1);
        warmProcessKeyEvent(83, 1);
        warmProcessKeyEvent(65, 0);
        warmProcessKeyEvent(83, 0);
        warmProcessKeyEvent(74, 1);
        warmProcessKeyEvent(75, 1);
        warmProcessKeyEvent(74, 0);
        warmProcessKeyEvent(75, 0);
    }

    clearWarmHotPathStateOnly();
    g_suppressOutputForReplay = oldSuppress;
    g_profilingEnabled = oldProfiling;
    QMK_ResetProfilingData();
}
export fn QMK_TimerFired(timerId: [*:0]const u16, timerType: i32, pk: [*:0]const u16, sk: [*:0]const u16, captureTime: f64) callconv(.c) void {
    beginHotPathActivity();
    defer endHotPathActivity(false);
    const tidHash = timerHashZ(timerId);
    cancelTimer(tidHash);
    var pkBuf: [KN_LEN]u16 = [_]u16{0} ** KN_LEN;
    var skBuf: [KN_LEN]u16 = [_]u16{0} ** KN_LEN;
    copyKeyName(&pkBuf, pk);
    copyKeyName(&skBuf, sk);
    clearKeyTimerHash(getVKFromKN(&pkBuf), tidHash);
    clearKeyTimerHash(getVKFromKN(&skBuf), tidHash);
    const captureTimeTicks = @as(i64, @intFromFloat(captureTime * @as(f64, @floatFromInt(g_qpcFreq)) / 1000.0));
    switch (timerType) {
        0 => triggerComboWithQuietCheck(&pkBuf, &skBuf, captureTimeTicks),
        1 => sameModifierGestureWindowTimer(&pkBuf, &skBuf),
        2 => retroTriggerCombo(&pkBuf, &skBuf),
        3 => retroActivateModifier(&pkBuf, &skBuf),
        else => {},
    }
}
// ============================================================================
// Section 23 — DLL exports: query / utility
// ============================================================================
export fn QMK_GetTime() callconv(.c) f64 {
    return @as(f64, @floatFromInt(getTime())) * g_qpcToMs;
}
export fn QMK_GetPendingCallbackCount() callconv(.c) i32 {
    return @intCast(g_pendingCBsLen);
}
export fn QMK_GetPendingCallback(idx: i32, cbId: *i32, k1: [*]u16, k2: [*]u16, cbtype: *i32) callconv(.c) i32 {
    if (idx < 0 or idx >= g_pendingCBsLen) return -1;
    const cb = &g_pendingCBs[@intCast(idx)];
    cbId.* = cb.callbackId;
    @memcpy(k1[0..KN_LEN], cb.key1[0..KN_LEN]);
    @memcpy(k2[0..8], cb.key2[0..8]);
    cbtype.* = cb.type_;
    return 0;
}

export fn QMK_GetHotstringCallbackName(index: i32) callconv(.c) [*:0]const u16 {
    _ = index;
    return @ptrCast(&g_hotstringCallbackNameWide);
}

export fn QMK_GetShortcutCallbackName(callbackType: i32, callbackId: i32) callconv(.c) [*:0]const u16 {
    _ = callbackType;
    _ = callbackId;
    return @ptrCast(&[_:0]u16{0});
}

// Returns the AHK callback_name for a matched compiled hotkey entry.
// callbackId passed from AHK is the HOTKEYS source index stored in PendingCallback.
export fn QMK_GetHotkeyCallbackName(hotkeyIndex: i32) callconv(.c) [*:0]const u16 {
    _ = hotkeyIndex;
    return @ptrCast(&[_:0]u16{0});
}

export fn QMK_GetStaticShortcutContextCount(callbackType: i32) callconv(.c) i32 {
    _ = callbackType;
    return 0;
}

export fn QMK_GetStaticShortcutContextKey(callbackType: i32, index: i32) callconv(.c) [*:0]const u16 {
    _ = callbackType;
    _ = index;
    return @ptrCast(&[_:0]u16{0});
}

export fn QMK_GetStaticShortcutContext(callbackType: i32, index: i32) callconv(.c) [*:0]const u16 {
    _ = callbackType;
    _ = index;
    return @ptrCast(&[_:0]u16{0});
}

export fn QMK_GetStaticShortcutContextCallback(callbackType: i32, index: i32) callconv(.c) [*:0]const u16 {
    _ = callbackType;
    _ = index;
    return @ptrCast(&[_:0]u16{0});
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
    ct.* = @as(f64, @floatFromInt(t.captureTime)) * g_qpcToMs;
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
    return g_active_physical_and_windows_facing_modifiers;
}
export fn QMK_GetActiveModifierCount() callconv(.c) i32 {
    return g_active_virtual_modifier_count;
}
export fn QMK_GetActiveModifierMask() callconv(.c) i32 {
    return @intCast(g_active_virtual_modifiers);
}
export fn QMK_GetPhysicalHiddenModifierMask() callconv(.c) i32 {
    return @intCast(hiddenPhysicalModsFromOs());
}
export fn QMK_GetPendingSoloVK() callconv(.c) i32 {
    return g_pendingSoloVK;
}
export fn QMK_GetRepeatVK() callconv(.c) i32 {
    return repeatVK();
}
export fn QMK_GetRepeatEmitCount() callconv(.c) u64 {
    return @atomicLoad(u64, &g_repeatEmitCount, .monotonic);
}
export fn QMK_CheckHotkey() callconv(.c) bool {
    return g_any_physical_modifiers_active;
}
export fn QMK_IsRepeatActive() callconv(.c) i32 {
    return if (repeatIsActive()) 1 else 0;
}
export fn QMK_IsDirectSendEnabled() callconv(.c) bool {
    return true;
}
export fn QMK_AnyPhysicalModifier() callconv(.c) bool {
    return g_any_physical_modifiers_active;
}
export fn QMK_IsPhysicalKeyDown(vk: i32) callconv(.c) bool {
    if (vk < 0 or vk >= VK_COUNT) return false;
    return physicalKeyDownVK(vk);
}
export fn QMK_GetVKFromNameEntry(keyName: [*:0]const u16) callconv(.c) i32 {
    return getVKFromText16(wideZSpan(keyName));
}
export fn QMK_IsPhysicalKeyDownEntry(keyName: [*:0]const u16) callconv(.c) bool {
    const vk = getVKFromText16(wideZSpan(keyName));
    if (vk < 0 or vk >= VK_COUNT) return false;
    return physicalKeyDownVK(vk);
}
export fn QMK_SetReplaySuppressOutput(enabled: i32) callconv(.c) void {
    g_suppressOutputForReplay = (enabled != 0);
}
export fn QMK_ResetProfilingData() callconv(.c) void {
    g_profiling = .{};
}
export fn QMK_GetFastPathCounters(out: *FastPathCounters) callconv(.c) void {
    out.* = .{
        .kdFastEmpty = 0,
        .kdFastRolling = 0,
        .kdTaplikeEmpty = 0,
        .kdTaplikeRolling = 0,
        .kdSoloUnresolved = 0,
        .kdPostSolo = 0,
        .kdSoloBlockBuffer = 0,
        .kdSoloBlockMods = 0,
        .kdSoloBlockPrimary = 0,
        .kdSoloBlockSpecial = 0,
        .kdSoloBlockRepeat = 0,
        .kdSoloBlockIgnored = 0,
        .kdSoloBlockPhysSys = 0,
        .kdOverlapRoll = 0,
        .kuSkipAll = 0,
        .kuSoloTap = 0,
        .kuHeadOldestTap = 0,
        .kuHeadOldestTailTap = 0,
        .kuPreQueueDrainTap = 0,
        .kuHeadOldestHold = 0,
        .pqFastTap = 0,
        .pqNoUnrelResolve = 0,
        .pqHeadOldestResolve = 0,
        .pqModResolve = 0,
        .pqWaitResolve = 0,
        .pqWaitBreak = 0,
        .pqSlowResolve = 0,
    };
}
export fn QMK_GetTimingSnapshot(out: *TimingSnapshot) callconv(.c) void {
    g_profiling.calculateAllStats();
    out.* = .{
        .keyDownMedian = g_profiling.keyDownStats.median,
        .keyDownAvg = g_profiling.keyDownStats.avg,
        .keyDownP95 = g_profiling.keyDownStats.p95,
        .keyDownCount = g_profiling.keyDownStats.count,
        .keyUpMedian = g_profiling.keyUpStats.median,
        .keyUpAvg = g_profiling.keyUpStats.avg,
        .keyUpP95 = g_profiling.keyUpStats.p95,
        .keyUpCount = g_profiling.keyUpStats.count,
        .directSendMedian = g_profiling.directSendStats.median,
        .directSendAvg = g_profiling.directSendStats.avg,
        .directSendP95 = g_profiling.directSendStats.p95,
        .directSendCount = g_profiling.directSendStats.count,
    };
}
export fn QMK_WriteProfilingReportAscii(out: [*]u8, out_len: usize) callconv(.c) usize {
    if (out_len == 0) return 0;
    g_profiling.calculateAllStats();

    var pos: usize = 0;
    const aStr = struct {
        fn f(b: [*]u8, len: usize, p: *usize, s: []const u8) void {
            for (s) |c| {
                if (p.* + 1 >= len) return;
                b[p.*] = c;
                p.* += 1;
            }
        }
    }.f;
    const aInt = struct {
        fn f(b: [*]u8, len: usize, p: *usize, val: i32) void {
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
                if (p.* + 1 >= len) return;
                b[p.*] = c;
                p.* += 1;
            }
        }
    }.f;
    const aFlt = struct {
        fn f(b: [*]u8, len: usize, p: *usize, val: f64) void {
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
                if (p.* + 1 >= len) return;
                b[p.*] = c;
                p.* += 1;
            }
            if (p.* + 1 < len) {
                b[p.*] = '.';
                p.* += 1;
            }
            var f2: u64 = @intCast(if (frac < 0) -frac else frac);
            var fd: [2]u8 = undefined;
            fd[1] = @intCast('0' + f2 % 10);
            f2 /= 10;
            fd[0] = @intCast('0' + f2 % 10);
            for (fd) |c| {
                if (p.* + 1 >= len) return;
                b[p.*] = c;
                p.* += 1;
            }
        }
    }.f;
    const wStat = struct {
        fn f(b: [*]u8, len: usize, p: *usize, name: []const u8, s: TimingStats) void {
            if (s.count == 0) return;
            aStr(b, len, p, name);
            aStr(b, len, p, ": samples=");
            aInt(b, len, p, s.count);
            aStr(b, len, p, " median=");
            aFlt(b, len, p, s.median);
            aStr(b, len, p, "us avg=");
            aFlt(b, len, p, s.avg);
            aStr(b, len, p, "us p95=");
            aFlt(b, len, p, s.p95);
            aStr(b, len, p, "us\n");
        }
    }.f;

    aStr(out, out_len, &pos, "=== QMK Profiling Snapshot ===\n");
    aStr(out, out_len, &pos, "Configured Capture: ");
    aStr(out, out_len, &pos, configuredInputBackendName());
    aStr(out, out_len, &pos, "\nActive Capture: ");
    aStr(out, out_len, &pos, activeInputBackendName());
    aStr(out, out_len, &pos, "\nConfigured SendMode: ");
    aStr(out, out_len, &pos, configuredSendModeName());
    aStr(out, out_len, &pos, "\n");
    wStat(out, out_len, &pos, "KeyDown", g_profiling.keyDownStats);
    wStat(out, out_len, &pos, "KeyUp", g_profiling.keyUpStats);
    wStat(out, out_len, &pos, "DirectSend", g_profiling.directSendStats);
    out[@min(pos, out_len - 1)] = 0;
    return pos;
}
export fn QMK_PhysModDown(mask: i32) callconv(.c) void {
    beginHotPathActivity();
    defer endHotPathActivity(true);
    if (isModVK(mask)) {
        _ = apply_physical_modifier_event(mask, true);
        return;
    }
    const uMask: u16 = @intCast(@as(u32, @bitCast(mask)) & 0xFFFF);
    const fallback_vks = [_]i32{ 0xA2, 0xA4, 0xA0, 0x5B };
    const fallback_masks = [_]u16{ 0x01, 0x02, 0x04, 0x08 };
    for (fallback_vks, fallback_masks) |vk, bit| {
        if ((uMask & bit) == 0) continue;
        _ = apply_physical_modifier_event(vk, true);
    }
}
export fn QMK_PhysModDownVK(vk: i32) callconv(.c) void {
    beginHotPathActivity();
    defer endHotPathActivity(true);
    _ = apply_physical_modifier_event(vk, true);
}
fn recordPhysicalModifierUpForDoubleTap(vk: i32) void {
    if (vk < 0 or vk >= VK_COUNT) return;
    const idx: usize = @intCast(vk);
    const downTime = g_modPollDownTime[idx];
    if (downTime == 0.0) return;
    const releaseTime = getTime();
    // Runtime context actions are the authoritative overlay for a compiled
    // double-tap row, including the physical-modifier path.
    const cbId = effectiveDoubleTapCallbackId(idx);
    if (cbId != -1) {
        const pressDuration = releaseTime - downTime;
        const priorUp = g_modPollLastUpTime[idx];
        if (pressDuration < g_DoubleTapThreshold and
            priorUp > 0.0 and (downTime - priorUp) < g_DoubleTapThreshold)
        {
            if (cachedNameFromVK(vk)) |nr| {
                queueCallback(cbId, nr, @ptrCast(&[_:0]u16{0}), 6);
                notifyAHK(true, false);
            }
        }
    }
    g_modPollLastUpTime[idx] = releaseTime;
    g_modPollDownTime[idx] = 0.0;
}
export fn QMK_PhysModUp(mask: i32) callconv(.c) void {
    beginHotPathActivity();
    defer endHotPathActivity(false);
    if (isModVK(mask)) {
        _ = apply_physical_modifier_event(mask, false);
        return;
    }
    const raw: u16 = @intCast(@as(u32, @bitCast(mask)) & 0xFFFF);
    const uMask: u16 = raw;
    const fallback_vks = [_]i32{ 0xA2, 0xA4, 0xA0, 0x5B };
    const fallback_masks = [_]u16{ 0x01, 0x02, 0x04, 0x08 };
    for (fallback_vks, fallback_masks) |vk, bit| {
        if ((uMask & bit) == 0) continue;
        _ = apply_physical_modifier_event(vk, false);
    }
}
export fn QMK_PhysModUpVK(vk: i32) callconv(.c) void {
    beginHotPathActivity();
    defer endHotPathActivity(false);
    _ = apply_physical_modifier_event(vk, false);
}
export fn QMK_NoModifiersHeld() callconv(.c) bool {
    if (g_active_virtual_modifier_count > 0 or g_unrelModCount > 0) return false;
    for (0..g_kbLen) |i| {
        const vk = g_kbVK[i];
        const props = if (vk >= 0 and vk < VK_COUNT) activeContextDerived().gate[@intCast(vk)].props else 0;
        if (!g_kbData[i].isReleased() and (props & (KP_CAN_BE_COMBO_PRIMARY | KP_CAN_BE_INSTANT_COMBO_PRIMARY)) != 0)
            return false;
    }
    return true;
}
export fn QMK_HasCombo(primary: i32, secondary: i32) callconv(.c) bool {
    return hasCombo(primary, secondary);
}
export fn QMK_HasInstantCombo(primary: i32, secondary: i32) callconv(.c) bool {
    return hasInstantCombo(primary, secondary);
}
export fn QMK_ProcessCallbacksDirect() callconv(.c) i32 {
    acquirePendingCBLock();
    defer releasePendingCBLock();
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
const SendDirectSpec = struct {
    vk: i32,
    mods: u16,
    repeat_count: u16 = 1,
};

inline fn sendDirectSpec(spec: SendDirectSpec) void {
    var i: u16 = 0;
    while (i < spec.repeat_count) : (i += 1) sendKeyDirect(spec.vk, spec.mods);
}

fn parseSendDirectSpecText16(raw_spec: []const u16) ?SendDirectSpec {
    var text = trimSpaces16(raw_spec);
    if (text.len == 0) return null;
    var mods: u16 = 0;
    while (text.len != 0) {
        switch (text[0]) {
            '^' => mods |= hotkeys.HOTKEY_MOD_CTRL,
            '!' => mods |= hotkeys.HOTKEY_MOD_ALT,
            '+' => mods |= hotkeys.HOTKEY_MOD_SHIFT,
            '#' => mods |= hotkeys.HOTKEY_MOD_WIN,
            else => break,
        }
        text = trimSpaces16(text[1..]);
    }
    if (text.len == 0) return null;

    var key_text: []const u16 = text;
    var repeat_count: u16 = 1;
    if (text[0] == '{') {
        var close: usize = 1;
        while (close < text.len and text[close] != '}') : (close += 1) {}
        if (close >= text.len) return null;
        var end: usize = 1;
        while (end < close and !isSpaceOrTab16(text[end])) : (end += 1) {}
        key_text = text[1..end];
        if (end != close) {
            const count_text = trimSpaces16(text[end..close]);
            if (count_text.len == 0) return null;
            var count: u32 = 0;
            for (count_text) |digit| {
                if (digit < '0' or digit > '9') return null;
                count = count * 10 + @as(u32, digit - '0');
                if (count > 0xFFFF) return null;
            }
            if (count == 0) return null;
            repeat_count = @intCast(count);
        }
        if (trimSpaces16(text[close + 1 ..]).len != 0) return null;
    } else if (text.len == 1) {
        if (text[0] >= 'A' and text[0] <= 'Z') {
            const lower_buf = [_]u16{asciiLower16(text[0])};
            const vk = getVKFromText16(lower_buf[0..]);
            if (vk == 0) return null;
            return .{ .vk = vk, .mods = mods | hotkeys.HOTKEY_MOD_SHIFT };
        }
    }

    const vk = getVKFromText16(key_text);
    if (vk == 0) return null;
    return .{ .vk = vk, .mods = mods, .repeat_count = repeat_count };
}

export fn QMK_SendDirectEntry(sendSpec: [*:0]const u16) callconv(.c) i32 {
    const parsed = parseSendDirectSpecText16(wideZSpan(sendSpec)) orelse return 0;
    sendDirectSpec(parsed);
    return 1;
}

export fn QMK_SendKeyDirectText(keyName: [*:0]const u16, modPrefix: [*:0]const u16) callconv(.c) i32 {
    const vk = getVKFromText16(wideZSpan(keyName));
    if (vk <= 0 or vk >= VK_COUNT) return 0;
    sendKeyDirect(vk, parseModifierMaskText16(wideZSpan(modPrefix)));
    return 1;
}

export fn QMK_SendKeyDirectFromDLL(vk: i32, modifierMask: i32) callconv(.c) void {
    sendKeyDirect(vk, @intCast(@as(u32, @bitCast(modifierMask)) & 0xFFFF));
}
export fn QMK_SendKeyDirectUnmarkedFromDLL(vk: i32, modifierMask: i32) callconv(.c) void {
    // Legacy escape hatch. Interception capture cannot distinguish an
    // unmarked Interception send from physical input, so force the project
    // marker there to avoid recursion/double-fire.
    const info: u64 = if (g_interceptionCaptureReady) AHK_SENDLEVEL_2 else 0;
    sendKeyDirectWithInfo(vk, @intCast(@as(u32, @bitCast(modifierMask)) & 0xFFFF), info);
}
// ============================================================================
// Section 24 — DLL exports: profiling
// ============================================================================
export fn QMK_ToggleProfilingEnabled() callconv(.c) void {
    g_profilingEnabled = !g_profilingEnabled;
    const onMsg = [_:0]u16{ 'P', 'r', 'o', 'f', 'i', 'l', 'i', 'n', 'g', ' ', 'E', 'N', 'A', 'B', 'L', 'E', 'D', 0 };
    const offMsg = [_:0]u16{ 'P', 'r', 'o', 'f', 'i', 'l', 'i', 'n', 'g', ' ', 'D', 'I', 'S', 'A', 'B', 'L', 'E', 'D', 0 };
    const cap = [_:0]u16{ 'Q', 'M', 'K', ' ', 'P', 'r', 'o', 'f', 'i', 'l', 'i', 'n', 'g', 0 };
    showMessageBoxAsync(if (g_profilingEnabled) &onMsg else &offMsg, &cap, MB_OK | MB_ICONINFORMATION | MB_TOPMOST | MB_SETFOREGROUND);
}
export fn QMK_ShowProfilingReport() callconv(.c) void {
    const cap = [_:0]u16{ 'Q', 'M', 'K', ' ', 'P', 'r', 'o', 'f', 'i', 'l', 'i', 'n', 'g', ' ', 'R', 'e', 'p', 'o', 'r', 't', 0 };

    if (!g_profilingEnabled) {
        const dis = [_:0]u16{ 'P', 'r', 'o', 'f', 'i', 'l', 'i', 'n', 'g', ' ', 'i', 's', ' ', 'D', 'I', 'S', 'A', 'B', 'L', 'E', 'D', '.', '\n', '\n', 'U', 's', 'e', ' ', 'Q', 'M', 'K', '_', 'T', 'o', 'g', 'g', 'l', 'e', 'P', 'r', 'o', 'f', 'i', 'l', 'i', 'n', 'g', 'E', 'n', 'a', 'b', 'l', 'e', 'd', '(', ')', ' ', 'f', 'i', 'r', 's', 't', '.', 0 };
        showMessageBoxAsync(&dis, &cap, MB_OK | MB_ICONINFORMATION | MB_TOPMOST | MB_SETFOREGROUND);
        return;
    }
    g_profiling.calculateAllStats();
    var buf8: [16384]u8 = undefined;
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
    aStr(&buf8, &pos, "Configured Capture: ");
    aStr(&buf8, &pos, configuredInputBackendName());
    aStr(&buf8, &pos, "\nActive Capture: ");
    aStr(&buf8, &pos, activeInputBackendName());
    aStr(&buf8, &pos, "\nConfigured SendMode: ");
    aStr(&buf8, &pos, configuredSendModeName());
    aStr(&buf8, &pos, "\n\n");
    wStat(&buf8, &pos, "KeyDown Processing", g_profiling.keyDownStats, aStr, aFlt, aInt);
    wStat(&buf8, &pos, "KeyUp Processing", g_profiling.keyUpStats, aStr, aFlt, aInt);
    wStat(&buf8, &pos, "Direct Send", g_profiling.directSendStats, aStr, aFlt, aInt);
    wStat(&buf8, &pos, "Interception Send", g_profiling.kernelStats, aStr, aFlt, aInt);
    wStat(&buf8, &pos, "DLL SendInput", g_profiling.sendInputStats, aStr, aFlt, aInt);

    const kd = g_profiling.keyDownStats;
    const ds = g_profiling.directSendStats;
    if (kd.count > 0 and ds.count > 0) {
        const ft = TimingStats{ .min = kd.min + ds.min, .median = kd.median + ds.median, .avg = kd.avg + ds.avg, .p95 = kd.p95 + ds.p95, .max = kd.max + ds.max, .count = @min(kd.count, ds.count) };
        wStat(&buf8, &pos, "Total Keystroke Latency", ft, aStr, aFlt, aInt);
    }

    // SendMode status
    aStr(&buf8, &pos, "SendMode Active Path: ");
    if (g_interceptionSendReady) {
        aStr(&buf8, &pos, "Interception driver sends\n");
    } else {
        aStr(&buf8, &pos, "DLL SendInput worker\n");
    }

    // Windows Timer Resolution
    aStr(&buf8, &pos, "\nWindows Timer Resolution: ");
    var curRes: u32 = 0;
    var minRes: u32 = 0;
    var maxRes: u32 = 0;
    const status = NtQueryTimerResolution(&minRes, &maxRes, &curRes);
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
    showMessageBoxAsync(&wide, &cap, MB_OK | MB_ICONINFORMATION | MB_TOPMOST | MB_SETFOREGROUND);
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
    // Count non-empty entries in g_icTable
    var icCount: usize = 0;
    for (g_icTable) |e| if (e.key != 0) {
        icCount += 1;
    };
    var count: usize = icCount;
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
    for (g_icTable) |entry| {
        if (entry.key == 0) continue;
        const ck = entry.key;
        const pkN = cachedNameFromVK(@as(i32, @intCast(ck >> 32))) orelse continue;
        const skN = cachedNameFromVK(@as(i32, @intCast(ck & 0xFFFFFFFF))) orelse continue;
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
    showMessageBoxAsync(&buf, &cap, MB_OK | MB_TOPMOST | MB_SETFOREGROUND);
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
    aStr(&buf8, &pos, "-- Input --\n");
    aStr(&buf8, &pos, "configuredCapture:       ");
    aStr(&buf8, &pos, configuredInputBackendName());
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "activeCapture:           ");
    aStr(&buf8, &pos, activeInputBackendName());
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "configuredSendMode:      ");
    aStr(&buf8, &pos, configuredSendModeName());
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "backendWantsAhkHotkeys:  ");
    aBool(&buf8, &pos, backendWantsAhkHotkeys(), aStr);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "interceptionSendReady:   ");
    aBool(&buf8, &pos, g_interceptionSendReady, aStr);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "interceptionCaptureReady:");
    aBool(&buf8, &pos, g_interceptionCaptureReady, aStr);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "interceptionPollThread:  ");
    aBool(&buf8, &pos, @atomicLoad(i32, &g_pollThreadActive, .acquire) != 0, aStr);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "llHookReady:             ");
    aBool(&buf8, &pos, g_llHookReady, aStr);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "llHookThreadActive:      ");
    aBool(&buf8, &pos, @atomicLoad(i32, &g_llHookThreadActive, .acquire) != 0, aStr);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "llHookThreadId:          ");
    aInt(&buf8, &pos, @intCast(g_llHookThreadId));
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "llHookEventCount:        ");
    aInt(&buf8, &pos, g_llHookEventCount);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "llHookLastVK:            ");
    aInt(&buf8, &pos, g_llHookLastVK);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "llHookLastScan:          ");
    aInt(&buf8, &pos, g_llHookLastScan);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "llHookLastFlags:         ");
    aInt(&buf8, &pos, g_llHookLastFlags);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "llHookLastIsDown:        ");
    aBool(&buf8, &pos, g_llHookLastIsDown != 0, aStr);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "llHookLastConsumed:      ");
    aBool(&buf8, &pos, g_llHookLastConsumed != 0, aStr);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "llHookLastMods:          ");
    aInt(&buf8, &pos, @intCast(g_llHookLastMods));
    aStr(&buf8, &pos, "  (Ctrl=1 Alt=2 Shift=4 Win=8)\n");
    aStr(&buf8, &pos, "currentPhysicalMods:     ");
    aInt(&buf8, &pos, @intCast(compute_modifiers_to_send()));
    aStr(&buf8, &pos, "  (Ctrl=1 Alt=2 Shift=4 Win=8)\n");
    aStr(&buf8, &pos, "physicalLRMods:          ");
    aInt(&buf8, &pos, @intCast(g_lr_active_physical_modifiers));
    aStr(&buf8, &pos, "  (LC=1 RC=2 LA=4 RA=8 LS=16 RS=32 LW=64 RW=128)\n");
    aStr(&buf8, &pos, "ipcControlDropCount:     ");
    aInt(&buf8, &pos, @intCast(@min(g_ipcControlDropCount, @as(u64, 2147483647))));
    aStr(&buf8, &pos, "\n\n");
    aStr(&buf8, &pos, "asyncSendDropCount:      ");
    aInt(&buf8, &pos, @intCast(@min(g_asyncSendDropCount, @as(u64, 2147483647))));
    aStr(&buf8, &pos, "\n\n");

    aStr(&buf8, &pos, "-- Timing --\n");
    aStr(&buf8, &pos, "singleKeyHoldThreshold:  ");
    aFlt(&buf8, &pos, @as(f64, @floatFromInt(g_SingleKeyHoldThreshold)) * g_qpcToMs);
    aStr(&buf8, &pos, " ms\n");
    aStr(&buf8, &pos, "maxHoldThreshold:        ");
    aFlt(&buf8, &pos, @as(f64, @floatFromInt(g_MaxHoldThreshold)) * g_qpcToMs);
    aStr(&buf8, &pos, " ms\n");
    aStr(&buf8, &pos, "quietPeriodDuration:     ");
    aFlt(&buf8, &pos, @as(f64, @floatFromInt(g_QuietPeriodDuration)) * g_qpcToMs);
    aStr(&buf8, &pos, " ms\n");
    aStr(&buf8, &pos, "modifierGestureWindow:   ");
    aFlt(&buf8, &pos, @as(f64, @floatFromInt(g_ModifierGestureWindow)) * g_qpcToMs);
    aStr(&buf8, &pos, " ms\n");
    aStr(&buf8, &pos, "doubleTapThreshold:      ");
    aFlt(&buf8, &pos, @as(f64, @floatFromInt(g_DoubleTapThreshold)) * g_qpcToMs);
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
    aStr(&buf8, &pos, "configuredSendMode:      ");
    aStr(&buf8, &pos, configuredSendModeName());
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "interceptionSendReady:   ");
    aBool(&buf8, &pos, g_interceptionSendReady, aStr);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "interceptionCaptureReady:");
    aBool(&buf8, &pos, g_interceptionCaptureReady, aStr);
    aStr(&buf8, &pos, "\n");

    aStr(&buf8, &pos, "\n-- Runtime State --\n");
    aStr(&buf8, &pos, "activeModCount:          ");
    aInt(&buf8, &pos, g_active_virtual_modifier_count);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "unrelModCount:           ");
    aInt(&buf8, &pos, g_unrelModCount);
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "bufferedKeyCount:        ");
    // Updated: Cast usize to i32 for formatting
    aInt(&buf8, &pos, @intCast(g_kbLen));
    aStr(&buf8, &pos, "\n");
    aStr(&buf8, &pos, "activeTimerCount:        ");
    // Updated: Cast usize to i32 for formatting
    aInt(&buf8, &pos, @intCast(g_timerLen));
    aStr(&buf8, &pos, "\n");

    var wide: [4096:0]u16 = std.mem.zeroes([4096:0]u16);
    for (buf8[0..pos], 0..) |c, i| wide[i] = c;
    showMessageBoxAsync(&wide, &cap, MB_OK | MB_ICONINFORMATION | MB_TOPMOST | MB_SETFOREGROUND);
}
// ============================================================================
// Section 25 — DllMain
// ============================================================================
fn lockDllMemory(hinst: windows.HINSTANCE) void {
    const base = @intFromPtr(hinst);
    if (base == 0) return;
    if (@as(*const u16, @ptrFromInt(base)).* != 0x5A4D) return; // MZ

    // Parse the PE header natively in Zig. MemoryModule should hand us a
    // mapped PE image, but keep this best-effort lock path defensive.
    const e_lfanew = @as(*const i32, @ptrFromInt(base + 0x3C)).*;
    if (e_lfanew <= 0 or e_lfanew > 0x100000) return;
    const nt_headers: usize = base + @as(usize, @intCast(e_lfanew));
    if (@as(*const u32, @ptrFromInt(nt_headers)).* != 0x00004550) return; // PE\0\0

    const sizeOfImage = @as(*const u32, @ptrFromInt(nt_headers + 80)).*;
    if (sizeOfImage > 0 and sizeOfImage <= 0x20000000) {
        // Bump the working set quota
        _ = SetProcessWorkingSetSize(GetCurrentProcess(), 20480000, 40960000);
        // Lock the exact footprint of the DLL
        _ = VirtualLock(hinst, sizeOfImage);
    }
}

fn signalNativeInputShutdownNoWait() void {
    _ = @atomicRmw(i32, &g_interceptionInitGeneration, .Add, 1, .acq_rel);
    _ = @atomicRmw(i32, &g_pollStopGeneration, .Add, 1, .acq_rel);
    g_interceptionCaptureReady = false;
    _ = @atomicRmw(i32, &g_llHookStopGeneration, .Add, 1, .acq_rel);
    const tid = g_llHookThreadId;
    if (tid != 0) {
        _ = PostThreadMessageW(tid, WM_QUIT, 0, 0);
    }
    @atomicStore(i32, &g_async_active, 0, .release);
    if (g_async_event) |ev| _ = SetEvent(ev);
    @atomicStore(i32, &g_nativePasteActive, 0, .release);
    if (g_nativePasteEvent) |ev| _ = SetEvent(ev);
}

export fn QMK_ShutdownNativeInput() callconv(.c) void {
    const mod_poll_stopped = stopModPollThread();
    signalNativeInputShutdownNoWait();
    const ll_hook_stopped = stopLLHookCapture();
    const interception_stopped = stopInterceptionCaptureOnly(false);
    stopAsyncThread();
    const native_paste_stopped = stopNativePasteThread();
    stopRepeatWorker();
    stopSchedThread();
    if (mod_poll_stopped and ll_hook_stopped and interception_stopped and native_paste_stopped)
        freeRetiredAllocationsNow();
}

export fn DllMain(hinst: windows.HINSTANCE, reason: u32, _: ?*anyopaque) callconv(.winapi) BOOL {
    if (reason == 1) { // DLL_PROCESS_ATTACH
        // Lock the DLL in memory and start the high-resolution timer.
        // All other init is deferred to QMK_SetInterceptionCallbacks, which
        // owns the async thread (needed for ringSend warmup) and the
        // g_is_initialized guard that prevents double-init.
        lockDllMemory(hinst);
        initTimer();
    } else if (reason == 0) { // DLL_PROCESS_DETACH
        signalNativeInputShutdownNoWait();
    }
    return TRUE;
}

export fn QMK_ResetForTest() callconv(.c) void {
    initTimer();
    const mod_poll_stopped = stopModPollThread();
    const ll_hook_stopped = stopLLHookCapture();
    const interception_stopped = stopInterceptionCaptureOnly(false);
    stopAsyncThread();
    stopRepeatWorker();
    stopSchedThread();
    const native_paste_stopped = stopNativePasteThread();
    const reset_safe = mod_poll_stopped and ll_hook_stopped and interception_stopped and native_paste_stopped;
    if (!reset_safe) {
        ensureAsyncSendWorker();
        initRepeatWorker();
        initSchedThread();
        return;
    }
    acquireSetupPublishLock();
    defer releaseSetupPublishLock();
    freeRetiredAllocationsNow();
    clearRuntimePublishStateForReset();
    truncateRuntimeHotkeysToPublished();
    truncateRuntimeModifiersToPublished();
    truncateRuntimeContextActionsToPublished();
    truncateRuntimeCombosToPublished();
    truncateRuntimeChordsToPublished();
    truncateRuntimeHotstringsToPublished();
    freeRetiredAllocationsNow();
    clearRuntimePublishStateForReset();
    g_is_initialized = false;
    g_userConfigApplied = false;
    @memset(&g_compiledCallbackBindings, -1);
    kbClear();
    ordClear();
    @memset(&g_kbIdx, -1);
    g_recentKeyUpCount = 0;
    g_activeComboPrimaryCount = 0;
    @memset(&g_comboPrimaryFlat, false);
    @memset(&g_instantComboPrimaryFlat, false);
    @memset(&g_runtimeComboPrimaryFlat, false);
    @memset(&g_runtimeInstantComboPrimaryFlat, false);
    if (g_icTable.len != 0) @memset(g_icTable, IcEntry{});
    if (g_ccTable.len != 0) @memset(g_ccTable, CcEntry{});
    if (g_iccTable.len != 0) @memset(g_iccTable, IccEntry{});
    g_icLen = 0;
    g_ccLen = 0;
    g_iccLen = 0;
    if (g_chordHotTable.len != 0) @memset(g_chordHotTable, ChordHotEntry{});
    g_chordHotLen = 0;
    clearActiveRuntimeChordTables();
    g_runtimeChordsLen = 0;
    for (&g_comboMatrix) |*row| @memset(row, false);
    for (&g_instantComboMatrix) |*row| @memset(row, false);
    clearActiveRuntimeComboTables();
    g_runtimeCombosLen = 0;
    g_runtimeInstantCombosLen = 0;
    g_runtimeComboRegistrationSeq = 0;
    for (&g_pairRelationMask) |*row| @memset(row, 0);
    timerClear();
    ignClear();
    pcbClear();
    if (g_runtimeCallbackSuspendExempt.len != 0) @memset(g_runtimeCallbackSuspendExempt, false);
    if (g_runtimeHotstringSuspendExempt.len != 0) @memset(g_runtimeHotstringSuspendExempt, false);
    if (g_runtimeModifiers.len != 0) @memset(g_runtimeModifiers, RuntimeModifier{});
    if (g_runtimeModifierTexts.len != 0) @memset(g_runtimeModifierTexts, [_]u16{0} ** RUNTIME_CONTEXT_ACTION_CHARS);
    g_runtimeModifiersLen = 0;
    @memset(&g_runtimeModifierTouched, false);
    @memset(&g_runtimeModifierBaseType, MOD_NONE);
    ptmClear();
    kdtClear();
    kutClear();
    clear_active_virtual_modifiers();
    for (&g_keyNames) |*n| @memset(n, 0);
    @memset(&g_vkToRegIdx, -1);
    @memset(&g_scPacked, 0);

    g_keyCount = 0;
    g_active_physical_and_windows_facing_modifiers = 0;
    g_active_physical_modifiers = 0;
    g_any_physical_modifiers_active = false;
    clearPhysicalKeyDownState();
    @memset(&g_foreignPhysicalKeyDown, false);
    g_foreignPhysicalQuarantineArmed = false;
    g_trackedPhysicalKeysDown = 0;
    g_lastPhysicalDownVK = 0;
    g_which_physical_modifiers_to_send = 0;
    g_lr_active_physical_modifiers = 0;
    @memset(&g_active_physical_modifier_key_counts_by_category, 0);
    @memset(&g_hotkey_consumed_down, false);
    @memset(&g_contextualTapArmed, false);
    @memset(&g_contextualTapCallbackId, -1);
    @memset(&g_contextualTapHoldCallbackId, -1);
    @memset(&g_contextualTapCleanupCallbackId, -1);
    @memset(&g_contextualTapThreshold, 0);
    @memset(&g_contextualTapDownTime, 0);
    @memset(&g_native_passthrough_to_windows, false);
    if (mod_poll_stopped) {
        g_modPollActive = 0;
        g_modPollGeneration = 0;
        g_modPollStopGeneration = 0;
    }
    g_lastKeyTime = 0;
    g_typingMode = false;
    g_typingModeUntil = 0;
    g_hotFlags = 0;
    g_runtimeFlags = 0; // FSM-lite
    g_unreleasedKeyCount = 0; // FSM-lite
    g_unreleasedNonModCount = 0; // FSM-lite
    g_activeInstantPrimaryCount = 0; // FSM-lite
    g_activeAnyPrimaryCount = 0; // FSM-lite
    g_unrelModCount = 0;
    g_cleanUnrelModCount = 0;
    g_activeModKeyCnt = 0;
    g_modStackDirty = false;
    g_hasInternalChords = false;
    g_hasExternalChords = false;
    g_hasAnyChord = false;
    g_hasInternalCombos = false;
    g_hotstringMatcher.reset();
    if (g_nativeHotstringPayloads.len != 0) {
        gAlloc.free(g_nativeHotstringPayloads);
        g_nativeHotstringPayloads = &[_]u16{};
    }
    if (g_nativeHotkeyPayloads.len != 0) {
        gAlloc.free(g_nativeHotkeyPayloads);
        g_nativeHotkeyPayloads = &[_]u16{};
    }
    @memset(&g_hcFlat, -1);
    @memset(&g_modDtFlat, -1);
    @memset(&g_holdRegisteredFlat, false);
    @memset(&g_doubleTapRegisteredFlat, false);
    @memset(&g_keyNamePtr, null);
    @memset(&g_keyHoldCallbackId, -1);
    @memset(&g_keyDoubleTapCallbackId, -1);
    if (mod_poll_stopped) {
        g_modPollActive = 0;
        g_modPollGeneration = 0;
        g_modPollStopGeneration = 0;
    }
    if (interception_stopped) {
        g_pollThreadActive = 0;
        g_pollStopGeneration = 0;
        g_interceptionInitActive = 0;
        g_interceptionInitGeneration = 0;
        g_interceptionInitThreadGeneration = 0;
    }
    if (ll_hook_stopped) {
        g_llHookThreadActive = 0;
        g_llHookStopGeneration = 0;
        g_llHookThreadId = 0;
        g_llHookReady = false;
    }
    g_llHookEventCount = 0;
    g_llHookLastVK = 0;
    g_llHookLastScan = 0;
    g_llHookLastFlags = 0;
    g_llHookLastIsDown = 0;
    g_llHookLastConsumed = 0;
    g_llHookLastMods = 0;
    @memset(&g_modPollDownTime, 0);
    @memset(&g_modPollLastUpTime, 0);
    g_extChordCacheLen = 0;
    // Reset name?VK keyed table so re-registration starts clean.
    for (&g_nkvkName) |*s| @memset(s, 0);
    @memset(&g_nkvkVK, 0);
    markKeyGateDirty();
    g_activeComboPrimaryBits = .{ 0, 0, 0, 0 };
    g_activeInstantPrimaryBits = .{ 0, 0, 0, 0 };
    g_activeAnyPrimaryBits = .{ 0, 0, 0, 0 };
    @memset(&g_chordParticipantFlat, false);
    registerDefaultKeys();
    rebuild_runtime_vk_plan();
    g_keyGateDirty = false;
    armForeignPhysicalKeyQuarantine();
    warmHotTables();
    ensureAsyncSendWorker();
    initRepeatWorker();
    initSchedThread();
    _ = recalculateHotkeyContexts(RUNTIME_CONTEXT_ALL_BITS);
}
export fn QMK_ResetForReplayBench() callconv(.c) void {
    initTimer();
    QMK_ResetForTest();
    @atomicStore(u64, &g_repeatEmitCount, 0, .monotonic);
    applyPrecompiledShortcuts();
    rebuild_runtime_vk_plan();
    g_keyGateDirty = false;
    warmHotTables();
    g_profilingEnabled = true;
    QMK_ResetProfilingData();
}

export fn QMK_GetBuildFlagsForArcBench() callconv(.c) u32 {
    var flags: u32 = 0;
    if (comptime microbenchdebug) flags |= 1 << 0;
    if (comptime compile_with_profiling) flags |= 1 << 1;
    if (comptime compile_with_pgo) flags |= 1 << 2;
    if (comptime has_qmk_shortcuts_build) flags |= 1 << 3;
    if (comptime has_qmk_hotstrings_build) flags |= 1 << 6;
    if (comptime has_compiled_user_shortcuts_build) flags |= 1 << 7;
    if (g_profilingEnabled) flags |= 1 << 4;
    if (g_suppressOutputForReplay) flags |= 1 << 5;
    return flags;
}

export fn QMK_GetBuildFeatureFlags() callconv(.c) u32 {
    return QMK_GetBuildFlagsForArcBench();
}

/// Diagnostic identity for the compiled user-shortcut bridge.
/// This is intentionally independent of the test-observability build flag so
/// AHK can verify which shortcut table was compiled into the loaded DLL.
export fn QMK_GetCompiledAhkCallbackCount() callconv(.c) u32 {
    if (comptime has_compiled_user_shortcuts_build and
        @hasDecl(compiled_user_shortcuts, "Compiled_Callbacks") and
        @hasDecl(compiled_user_shortcuts.Compiled_Callbacks, "ahk"))
        return @intCast(compiled_user_shortcuts.Compiled_Callbacks.ahk.len);
    return 0;
}

export fn QMK_DebugKeyNameCaseFoldOK() callconv(.c) i32 {
    return 1;
}

// ============================================================================
// Section 25 — PGO profile export
// ============================================================================
export fn QMK_WriteLLVMProfileTo(path: [*:0]const u8) callconv(.c) i32 {
    if (comptime !compile_with_profiling) return -1;

    const INVALID_HANDLE_VALUE = std.math.maxInt(usize);
    const heap = GetProcessHeap();
    const mem = HeapAlloc(heap, 0, 1048576) orelse return -3;
    defer _ = HeapFree(heap, 0, mem);

    const buf: [*]u8 = @ptrCast(mem);
    const write_profile_result = __llvm_profile_write_buffer(buf);
    if (write_profile_result != 0) return write_profile_result;

    const h = CreateFileA(path, GENERIC_WRITE, 0, null, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, null);
    if (@intFromPtr(h) == INVALID_HANDLE_VALUE) return -4;
    defer _ = CloseHandle(h);

    var written: DWORD = 0;
    if (WriteFile(h, buf, 1048576, &written, null) == 0) return -5;
    if (written == 0) return -6;

    return 0;
}
export fn QMK_SetClipboardOwnerHwnd(hwnd_value: usize) callconv(.c) i32 {
    if (hwnd_value == 0) return 0;
    g_clipboardOwnerHwnd = @ptrFromInt(hwnd_value);
    return if (ensureClipboardMutex()) 1 else 0;
}

fn sendInputUnicodeText(text: []const u16) bool {
    var batch: [128]InputSlot = undefined;
    var pos: usize = 0;
    while (pos < text.len) {
        const count = @min(text.len - pos, 64);
        for (0..count) |i| {
            batch[i * 2] = .{ .wVk = 0, .wScan = text[pos + i], .dwFlags = KEYEVENTF_UNICODE, .dwExtraInfo = AHK_SENDLEVEL_2 };
            batch[i * 2 + 1] = .{ .wVk = 0, .wScan = text[pos + i], .dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP, .dwExtraInfo = AHK_SENDLEVEL_2 };
        }
        const input_count: u32 = @intCast(count * 2);
        if (SendInput(input_count, @ptrCast(&batch[0]), INPUT_STRUCT_SIZE) != input_count)
            return false;
        pos += count;
    }
    return true;
}

fn sendEventText(text: []const u16) bool {
    for (text) |ch| {
        const vk: u16 = if (ch == '\n' or ch == '\r') VK_RETURN else if (ch == '\t') 0x09 else blk: {
            const scanBits = VkKeyScanW(ch);
            if (scanBits == -1) return false;
            break :blk @intCast(@as(u16, @bitCast(scanBits)) & 0xFF);
        };
        const scanBits: u16 = if (ch == '\n' or ch == '\r' or ch == '\t') 0 else @as(u16, @bitCast(VkKeyScanW(ch)));
        const shift_state: u8 = @intCast((scanBits >> 8) & 0xFF);
        const scan: u8 = @intCast(MapVirtualKeyW(vk, MAPVK_VK_TO_VSC) & 0xFF);
        const extra: usize = AHK_SENDLEVEL_2;
        if ((shift_state & 1) != 0) keybd_event(@intCast(VK_SHIFT), @intCast(MapVirtualKeyW(VK_SHIFT, MAPVK_VK_TO_VSC)), 0, extra);
        if ((shift_state & 2) != 0) keybd_event(@intCast(VK_CONTROL), @intCast(MapVirtualKeyW(VK_CONTROL, MAPVK_VK_TO_VSC)), 0, extra);
        if ((shift_state & 4) != 0) keybd_event(@intCast(VK_MENU), @intCast(MapVirtualKeyW(VK_MENU, MAPVK_VK_TO_VSC)), 0, extra);
        keybd_event(@intCast(vk), scan, 0, extra);
        keybd_event(@intCast(vk), scan, KEYEVENTF_KEYUP, extra);
        if ((shift_state & 4) != 0) keybd_event(@intCast(VK_MENU), @intCast(MapVirtualKeyW(VK_MENU, MAPVK_VK_TO_VSC)), KEYEVENTF_KEYUP, extra);
        if ((shift_state & 2) != 0) keybd_event(@intCast(VK_CONTROL), @intCast(MapVirtualKeyW(VK_CONTROL, MAPVK_VK_TO_VSC)), KEYEVENTF_KEYUP, extra);
        if ((shift_state & 1) != 0) keybd_event(@intCast(VK_SHIFT), @intCast(MapVirtualKeyW(VK_SHIFT, MAPVK_VK_TO_VSC)), KEYEVENTF_KEYUP, extra);
    }
    return true;
}

fn sendInterceptionText(text: []const u16) bool {
    if (!g_interceptionSendReady) return false;
    for (text) |ch| {
        if (ch == '\r') continue;
        const effective: u16 = if (ch == '\n') VK_RETURN else if (ch == '\t') 0x09 else ch;
        const scanBits = VkKeyScanW(effective);
        if (scanBits == -1) return false;
        const bits: u16 = @bitCast(scanBits);
        const vk: i32 = @intCast(bits & 0xFF);
        const state: u8 = @intCast((bits >> 8) & 0xFF);
        const mods: u16 = (if ((state & 1) != 0) hotkeys.HOTKEY_MOD_SHIFT else 0)
            | (if ((state & 2) != 0) hotkeys.HOTKEY_MOD_CTRL else 0)
            | (if ((state & 4) != 0) hotkeys.HOTKEY_MOD_ALT else 0);
        sendKeyDirect(vk, mods);
    }
    return true;
}

export fn QMK_SetPasteMode(mode: i32) callconv(.c) i32 {
    if (mode < 0 or mode > 4) return 0;
    g_pasteMode = mode;
    return 1;
}

export fn QMK_Paste(text: [*:0]const u16) callconv(.c) i32 {
    const text_len = std.mem.len(text);
    const text_slice = text[0..text_len];
    if (g_pasteMode == 1) return if (sendInterceptionText(text_slice)) 1 else 0;
    if (g_pasteMode == 3) return if (sendInputUnicodeText(text_slice)) 1 else 0;
    if (g_pasteMode == 4) return if (sendEventText(text_slice)) 1 else 0;
    if (g_pasteMode == 0 and !g_interceptionSendReady) return 0;
    if (!lockClipboardState()) return 0;
    defer unlockClipboardState();
    if (!openClipboardWithRetry()) return 0;

    backupClipboardAllOpen();
    _ = CloseClipboard();

    if (!putWideOnClipboard(text_slice)) return 0;

    const generation = @atomicRmw(u32, &g_hotstringClipboardRestoreGeneration, .Add, 1, .acq_rel) + 1;
    if (CreateThread(null, 0, restoreClipboardThreadProc, @ptrFromInt(@as(usize, generation)), 0, null)) |h| {
        _ = CloseHandle(h);
    }

    const held_mod_mask = snapshotVisiblePhysicalMods();
    ringReset();
    if (held_mod_mask != 0) ringAddModifierRelease(held_mod_mask, AHK_SENDLEVEL_2);
    if (physicalKeyDownVK(0x12)) ringAddKeyWithInfo(0x12, KEYEVENTF_KEYUP, AHK_SENDLEVEL_2); // generic Alt
    if (physicalKeyDownVK(0x11)) ringAddKeyWithInfo(0x11, KEYEVENTF_KEYUP, AHK_SENDLEVEL_2); // generic Ctrl
    if (physicalKeyDownVK(0x10)) ringAddKeyWithInfo(0x10, KEYEVENTF_KEYUP, AHK_SENDLEVEL_2); // generic Shift
    ringAddKeyWithInfo(VK_CONTROL, 0, AHK_SENDLEVEL_2);
    ringAddTapWithInfoTagged(0x56, AHK_SENDLEVEL_2, 0);
    ringAddKeyWithInfo(VK_CONTROL, KEYEVENTF_KEYUP, AHK_SENDLEVEL_2);
    if (held_mod_mask != 0) ringAddModifierRestore(held_mod_mask, AHK_SENDLEVEL_2);
    if (g_pasteMode == 0) ringSend() else ringSendAtomic();

    return 1;
}

