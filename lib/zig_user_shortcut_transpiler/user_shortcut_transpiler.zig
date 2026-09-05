const std = @import("std");

const SourceSpec = struct {
    name: []const u8,
    family: []const u8,
    is_collection: bool,
    is_control: bool,
};

const Row = struct {
    source_index: usize,
    row_index: usize,
    source_order: usize,
    family: []const u8,
    source_path: []const u8,
    source_text: []const u8,
    classification: []const u8,
    source_hash: u64,
    callback_slots: [3]i32,
    owned_source: ?[]u8,
    chord_normalized: bool,
};

const Source = struct {
    path: []const u8,
    bytes: []u8,
};

const specs = [_]SourceSpec{
    .{ .name = "QMK.SetupPanicExitHotkey(", .family = "NativeControls", .is_collection = false, .is_control = true },
    .{ .name = "QMK.SetupNativeReloadHotkey(", .family = "NativeControls", .is_collection = false, .is_control = true },
    .{ .name = "QMK.SetupHotkey(", .family = "Hotkeys", .is_collection = false, .is_control = false },
    .{ .name = "QMK.SetupHotkeys(", .family = "Hotkeys", .is_collection = true, .is_control = false },
    .{ .name = "QMK.SetupModifier(", .family = "Modifiers", .is_collection = false, .is_control = false },
    .{ .name = "QMK.SetupModifiers(", .family = "Modifiers", .is_collection = true, .is_control = false },
    .{ .name = "QMK.SetupPassthrough(", .family = "Passthroughs", .is_collection = false, .is_control = false },
    .{ .name = "QMK.SetupPassthroughs(", .family = "Passthroughs", .is_collection = true, .is_control = false },
    .{ .name = "QMK.SetupCombo(", .family = "Combos", .is_collection = false, .is_control = false },
    .{ .name = "QMK.SetupCombos(", .family = "Combos", .is_collection = true, .is_control = false },
    .{ .name = "QMK.SetupChord(", .family = "Chords", .is_collection = false, .is_control = false },
    .{ .name = "QMK.SetupChords(", .family = "Chords", .is_collection = true, .is_control = false },
    .{ .name = "QMK.SetupHold(", .family = "Holds", .is_collection = false, .is_control = false },
    .{ .name = "QMK.SetupHolds(", .family = "Holds", .is_collection = true, .is_control = false },
    .{ .name = "QMK.SetupDoubleTap(", .family = "DoubleTaps", .is_collection = false, .is_control = false },
    .{ .name = "QMK.SetupDoubleTaps(", .family = "DoubleTaps", .is_collection = true, .is_control = false },
    .{ .name = "QMK.SetupTap(", .family = "Taps", .is_collection = false, .is_control = false },
    .{ .name = "QMK.SetupTaps(", .family = "Taps", .is_collection = true, .is_control = false },
    .{ .name = "QMK.SetupTapHolds(", .family = "TapHolds", .is_collection = true, .is_control = false },
    .{ .name = "QMK.SetupHotstring(", .family = "Hotstrings", .is_collection = false, .is_control = false },
    .{ .name = "QMK.SetupHotstrings(", .family = "Hotstrings", .is_collection = true, .is_control = false },
};

fn isIdentChar(b: u8) bool {
    return (b >= 'a' and b <= 'z') or (b >= 'A' and b <= 'Z') or
        (b >= '0' and b <= '9') or b == '_';
}

fn fnv1a64(bytes: []const u8) u64 {
    var h: u64 = 0xcbf29ce484222325;
    for (bytes) |b| {
        h ^= b;
        h *%= 0x100000001b3;
    }
    return h;
}

fn skipQuoted(bytes: []const u8, start: usize) ?usize {
    var i = start + 1;
    while (i < bytes.len) : (i += 1) {
        if (bytes[i] == '`') {
            if (i + 1 < bytes.len) i += 1;
            continue;
        }
        if (bytes[i] == '"') {
            if (i + 1 < bytes.len and bytes[i + 1] == '"') {
                i += 1;
                continue;
            }
            return i + 1;
        }
    }
    return null;
}

fn findBalanced(bytes: []const u8, open_index: usize, open: u8, close: u8) ?usize {
    var depth: usize = 0;
    var i = open_index;
    while (i < bytes.len) : (i += 1) {
        if (bytes[i] == '"') {
            i = skipQuoted(bytes, i) orelse return null;
            if (i == 0) return null;
            i -= 1;
            continue;
        }
        if (bytes[i] == ';') {
            while (i < bytes.len and bytes[i] != '\n') : (i += 1) {}
            continue;
        }
        if (bytes[i] == open) depth += 1;
        if (bytes[i] == close) {
            if (depth == 0) return null;
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return null;
}

fn trim(bytes: []const u8) []const u8 {
    return std.mem.trim(u8, bytes, " \t\r\n");
}

fn splitTopLevel(gpa: std.mem.Allocator, bytes: []const u8) !std.ArrayList([]const u8) {
    var result = std.ArrayList([]const u8).empty;
    var parens: usize = 0;
    var brackets: usize = 0;
    var braces: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        if (bytes[i] == '"') {
            i = skipQuoted(bytes, i) orelse return error.UnterminatedString;
            if (i == 0) return error.UnterminatedString;
            i -= 1;
            continue;
        }
        if (bytes[i] == ';') {
            if (parens == 0 and brackets == 0 and braces == 0) {
                const comment_start = start;
                const before_comment = trim(bytes[comment_start..i]);
                if (before_comment.len > 0) try result.append(gpa, before_comment);
                while (i < bytes.len and bytes[i] != '\n') : (i += 1) {}
                start = if (i < bytes.len) i + 1 else bytes.len;
                continue;
            }
            while (i < bytes.len and bytes[i] != '\n') : (i += 1) {}
            continue;
        }
        switch (bytes[i]) {
            '(' => parens += 1,
            ')' => {
                if (parens > 0) parens -= 1;
            },
            '[' => brackets += 1,
            ']' => {
                if (brackets > 0) brackets -= 1;
            },
            '{' => braces += 1,
            '}' => {
                if (braces > 0) braces -= 1;
            },
            ',' => if (parens == 0 and brackets == 0 and braces == 0) {
                try result.append(gpa, trim(bytes[start..i]));
                start = i + 1;
            },
            else => {},
        }
    }
    const last = trim(bytes[start..]);
    if (last.len > 0) try result.append(gpa, last);
    return result;
}

fn indexOfIgnoreCase(bytes: []const u8, needle: []const u8) ?usize {
    if (needle.len == 0) return 0;
    if (needle.len > bytes.len) return null;
    var start: usize = 0;
    while (start + needle.len <= bytes.len) : (start += 1) {
        if (std.ascii.eqlIgnoreCase(bytes[start .. start + needle.len], needle)) return start;
    }
    return null;
}

fn containsAny(bytes: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| if (indexOfIgnoreCase(bytes, needle) != null) return true;
    return false;
}

fn findCallOpenIgnoreCase(bytes: []const u8, function_name: []const u8) ?usize {
    if (function_name.len == 0 or function_name.len > bytes.len) return null;
    var start: usize = 0;
    while (start + function_name.len <= bytes.len) : (start += 1) {
        if (!std.ascii.eqlIgnoreCase(bytes[start .. start + function_name.len], function_name)) continue;
        var open = start + function_name.len;
        while (open < bytes.len and (bytes[open] == ' ' or bytes[open] == '\t' or bytes[open] == '\r' or bytes[open] == '\n')) : (open += 1) {}
        if (open < bytes.len and bytes[open] == '(') return open;
    }
    return null;
}

fn containsCallIgnoreCase(bytes: []const u8, function_name: []const u8) bool {
    return findCallOpenIgnoreCase(bytes, function_name) != null;
}

fn isIdentifierStart(byte: u8) bool {
    return (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or byte == '_';
}

fn isIdentifierByte(byte: u8) bool {
    return isIdentifierStart(byte) or (byte >= '0' and byte <= '9');
}

fn isDottedReference(value: []const u8) bool {
    const t = trim(value);
    if (t.len == 0 or isQuotedElement(t)) return false;
    var position: usize = 0;
    var segments: usize = 0;
    while (position < t.len) {
        if (!isIdentifierStart(t[position])) return false;
        position += 1;
        while (position < t.len and isIdentifierByte(t[position])) : (position += 1) {}
        segments += 1;
        if (position == t.len) break;
        if (t[position] != '.') return false;
        position += 1;
        if (position == t.len) return false;
    }
    return segments >= 2;
}

fn rowHasDottedCallbackReference(gpa: std.mem.Allocator, family: []const u8, row: []const u8) bool {
    var args = splitTopLevel(gpa, if (trim(row).len >= 2 and trim(row)[0] == '[' and trim(row)[trim(row).len - 1] == ']') trim(row)[1 .. trim(row).len - 1] else row) catch return false;
    defer args.deinit(gpa);
    var first_action: usize = if (std.mem.eql(u8, family, "TapHolds")) 3 else 2;
    if (std.mem.eql(u8, family, "Hotkeys") or std.mem.eql(u8, family, "Taps") or
        std.mem.eql(u8, family, "Holds") or std.mem.eql(u8, family, "DoubleTaps") or
        std.mem.eql(u8, family, "Hotstrings")) {
        // Public wrappers accept global shorthand [key, action, ...] as well
        // as contextual [key, context, action, ...].
        first_action = if (args.items.len >= 3 and isChordContextOrNonKey(args.items[1])) 2 else 1;
    }
    if (args.items.len <= first_action) return false;
    for (args.items[first_action..]) |argument| if (isDottedReference(argument)) return true;
    return false;
}

fn isQuotedElement(bytes: []const u8) bool {
    const t = trim(bytes);
    return t.len >= 2 and t[0] == '"' and t[t.len - 1] == '"';
}

fn isObjectLiteral(bytes: []const u8) bool {
    const t = trim(bytes);
    return t.len >= 2 and t[0] == '{' and t[t.len - 1] == '}';
}

fn objectField(gpa: std.mem.Allocator, object: []const u8, wanted: []const u8) ?[]const u8 {
    const t = trim(object);
    if (!isObjectLiteral(t)) return null;
    var fields = splitTopLevel(gpa, t[1 .. t.len - 1]) catch return null;
    defer fields.deinit(gpa);
    for (fields.items) |field| {
        const colon = std.mem.indexOfScalar(u8, field, ':') orelse continue;
        const name = trim(field[0..colon]);
        if (std.ascii.eqlIgnoreCase(name, wanted)) return trim(field[colon + 1 ..]);
    }
    return null;
}

fn objectFieldAny(gpa: std.mem.Allocator, object: []const u8, names: []const []const u8) ?[]const u8 {
    for (names) |name| if (objectField(gpa, object, name)) |value| return value;
    return null;
}

fn objectContext(gpa: std.mem.Allocator, object: []const u8) []const u8 {
    return objectFieldAny(gpa, object, &[_][]const u8{ "context", "contexts" }) orelse "\"global\"";
}

fn objectAction(gpa: std.mem.Allocator, family: []const u8, object: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, family, "Taps"))
        return objectFieldAny(gpa, object, &[_][]const u8{ "tapAction", "tap", "action" });
    if (std.mem.eql(u8, family, "Hotstrings"))
        // Mirror QMK.SetupHotstringsCompat: callback wins, then text, then
        // replacement. Keep `action` as a legacy alias for captured rows.
        return objectFieldAny(gpa, object, &[_][]const u8{ "callback", "text", "replacement", "action" });
    return objectFieldAny(gpa, object, &[_][]const u8{ "callback", "action", "target" });
}

fn normalizeChordArraySource(gpa: std.mem.Allocator, family: []const u8, source_text: []const u8) !?[]u8 {
    if (!std.mem.eql(u8, family, "Chords")) return null;
    var args = splitTopLevel(gpa, source_text) catch return null;
    defer args.deinit(gpa);
    if (args.items.len < 2) return null;
    const keys = trim(args.items[0]);
    if (keys.len < 2 or keys[0] != '[' or keys[keys.len - 1] != ']') return null;
    var key_items = splitTopLevel(gpa, keys[1 .. keys.len - 1]) catch return null;
    defer key_items.deinit(gpa);
    if (key_items.items.len < 2 or key_items.items.len > 5) return null;

    // SetupChord(keys, context?, callback?, suspendExempt?) is a singular
    // convenience wrapper.  Flatten its key array and make its implicit mode
    // and modifier fields explicit for the same chord tail parser used by
    // SetupChords rows.
    const context: []const u8 = if (args.items.len >= 3) args.items[1] else "\"global\"";
    const action: []const u8 = if (args.items.len >= 3) args.items[2] else args.items[1];
    const suspend_expr: []const u8 = if (args.items.len >= 4) args.items[3] else "false";
    const mode: []const u8 = if (containsCallIgnoreCase(action, "QMK.SendKeyDirect") or containsCallIgnoreCase(action, "QMK.SendDirect")) "\"sendkeydirect\"" else "\"callback\"";
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(gpa);
    try out.append(gpa, '[');
    for (key_items.items, 0..) |key, index| {
        if (index != 0) try out.appendSlice(gpa, ", ");
        try out.appendSlice(gpa, key);
    }
    try out.appendSlice(gpa, ", ");
    try out.appendSlice(gpa, context);
    try out.appendSlice(gpa, ", ");
    try out.appendSlice(gpa, action);
    try out.appendSlice(gpa, ", ");
    try out.appendSlice(gpa, mode);
    try out.appendSlice(gpa, ", \"\", ");
    try out.appendSlice(gpa, suspend_expr);
    try out.append(gpa, ']');
    return try out.toOwnedSlice(gpa);
}

fn normalizeObjectSource(gpa: std.mem.Allocator, family: []const u8, object: []const u8) !?[]u8 {
    if (!isObjectLiteral(object)) return null;
    if (std.mem.eql(u8, family, "Combos")) {
        const primary = objectField(gpa, object, "primary") orelse return null;
        const secondary = objectField(gpa, object, "secondary") orelse return null;
        const context = objectContext(gpa, object);
        const action = objectAction(gpa, family, object) orelse return null;
        const mode = objectFieldAny(gpa, object, &[_][]const u8{ "mode", "type" }) orelse "\"normal\"";
        const mods = objectFieldAny(gpa, object, &[_][]const u8{ "mods", "mod" }) orelse "\"\"";
        const suspend_expr = objectField(gpa, object, "suspendExempt") orelse "false";
        return try std.fmt.allocPrint(gpa, "[{s}, {s}, {s}, {s}, {s}, {s}, {s}]", .{ primary, secondary, context, action, mode, mods, suspend_expr });
    }
    if (std.mem.eql(u8, family, "Chords")) {
        const keys = objectField(gpa, object, "keys") orelse return null;
        const key_text = trim(keys);
        if (key_text.len < 2 or key_text[0] != '[' or key_text[key_text.len - 1] != ']') return null;
        var key_items = splitTopLevel(gpa, key_text[1 .. key_text.len - 1]) catch return null;
        defer key_items.deinit(gpa);
        if (key_items.items.len < 2 or key_items.items.len > 5) return null;
        const context = objectContext(gpa, object);
        const action = objectAction(gpa, family, object) orelse return null;
        const mode = objectFieldAny(gpa, object, &[_][]const u8{ "mode", "type" }) orelse "\"callback\"";
        const mods = objectFieldAny(gpa, object, &[_][]const u8{ "mods", "mod" }) orelse "\"\"";
        const suspend_expr = objectField(gpa, object, "suspendExempt") orelse "false";
        var out = std.ArrayList(u8).empty;
        errdefer out.deinit(gpa);
        try out.append(gpa, '[');
        for (key_items.items, 0..) |item, index| {
            if (index != 0) try out.appendSlice(gpa, ", ");
            try out.appendSlice(gpa, trim(item));
        }
        try out.appendSlice(gpa, ", ");
        try out.appendSlice(gpa, context);
        try out.appendSlice(gpa, ", ");
        try out.appendSlice(gpa, action);
        const suffix = try std.fmt.allocPrint(gpa, ", {s}, {s}, {s}]", .{ mode, mods, suspend_expr });
        defer gpa.free(suffix);
        try out.appendSlice(gpa, suffix);
        return try out.toOwnedSlice(gpa);
    }
    const key = if (std.mem.eql(u8, family, "Hotstrings"))
        (objectField(gpa, object, "trigger") orelse return null)
    else
        (objectField(gpa, object, "key") orelse objectField(gpa, object, "spec") orelse return null);
    const context = objectContext(gpa, object);
    const suspend_expr = objectField(gpa, object, "suspendExempt") orelse "false";
    var text: []u8 = undefined;
    if (std.mem.eql(u8, family, "Hotkeys")) {
        const action = objectAction(gpa, family, object) orelse return null;
        text = try std.fmt.allocPrint(gpa, "[{s}, {s}, {s}, {s}]", .{ key, context, action, suspend_expr });
    } else if (std.mem.eql(u8, family, "Taps")) {
        const action = objectAction(gpa, family, object) orelse return null;
        const hold = objectFieldAny(gpa, object, &[_][]const u8{ "holdCallback", "hold" }) orelse "\"\"";
        const threshold = objectFieldAny(gpa, object, &[_][]const u8{ "thresholdMs", "threshold" }) orelse "0";
        const cleanup = objectFieldAny(gpa, object, &[_][]const u8{ "cleanupCallback", "cleanup" }) orelse "\"\"";
        text = try std.fmt.allocPrint(gpa, "[{s}, {s}, {s}, {s}, {s}, {s}, {s}]", .{ key, context, action, hold, threshold, cleanup, suspend_expr });
    } else if (std.mem.eql(u8, family, "TapHolds")) {
        const tap = objectFieldAny(gpa, object, &[_][]const u8{ "tapCallback", "tap" }) orelse "\"\"";
        const hold = objectFieldAny(gpa, object, &[_][]const u8{ "holdCallback", "hold" }) orelse "\"\"";
        const threshold = objectFieldAny(gpa, object, &[_][]const u8{ "thresholdMs", "threshold" }) orelse "200";
        const cleanup = objectFieldAny(gpa, object, &[_][]const u8{ "cleanupCallback", "cleanup" }) orelse "\"\"";
        // QMK.SetupTapHoldsCompat consumes the canonical array shape
        // [key, context, threshold, tap, hold, cleanup, suspend].
        text = try std.fmt.allocPrint(gpa, "[{s}, {s}, {s}, {s}, {s}, {s}, {s}]", .{ key, context, threshold, tap, hold, cleanup, suspend_expr });
    } else if (std.mem.eql(u8, family, "Holds") or std.mem.eql(u8, family, "DoubleTaps")) {
        const action = objectAction(gpa, family, object) orelse return null;
        text = try std.fmt.allocPrint(gpa, "[{s}, {s}, {s}, {s}]", .{ key, context, action, suspend_expr });
    } else if (std.mem.eql(u8, family, "Modifiers")) {
        const modifier = objectFieldAny(gpa, object, &[_][]const u8{ "modifier", "mod", "modType" }) orelse return null;
        text = try std.fmt.allocPrint(gpa, "[{s}, {s}, {s}, {s}]", .{ key, modifier, context, suspend_expr });
    } else if (std.mem.eql(u8, family, "Passthroughs")) {
        text = try std.fmt.allocPrint(gpa, "[{s}, {s}, {s}]", .{ key, context, suspend_expr });
    } else if (std.mem.eql(u8, family, "Hotstrings")) {
        const action = objectAction(gpa, family, object) orelse return null;
        text = try std.fmt.allocPrint(gpa, "[{s}, {s}, {s}, {s}]", .{ key, context, action, suspend_expr });
    } else {
        return null;
    }
    return text;
}

fn isLiteralTapDescriptor(bytes: []const u8) bool {
    const t = trim(bytes);
    const prefix = "QMK.Tap";
    if (t.len <= prefix.len or !std.ascii.eqlIgnoreCase(t[0..prefix.len], prefix)) return false;
    var open: usize = prefix.len;
    while (open < t.len and (t[open] == ' ' or t[open] == '\t')) : (open += 1) {}
    if (open >= t.len or t[open] != '(') return false;
    const close = findBalanced(t, open, '(', ')') orelse return false;
    if (trim(t[close + 1 ..]).len != 0) return false;
    return isQuotedElement(t[open + 1 .. close]);
}

fn isLiteralCall(bytes: []const u8, function_name: []const u8) bool {
    const t = trim(bytes);
    const open = findCallOpenIgnoreCase(t, function_name) orelse return false;
    const close = findBalanced(t, open, '(', ')') orelse return false;
    if (trim(t[close + 1 ..]).len != 0) return false;
    return isQuotedElement(t[open + 1 .. close]);
}

fn isPureDirectArrow(bytes: []const u8) bool {
    const arrow = std.mem.indexOf(u8, bytes, "=>") orelse return false;
    var body = trim(bytes[arrow + 2 ..]);
    // Collection rows retain their outer closing bracket while scanning.
    if (body.len > 0 and body[body.len - 1] == ']') body = trim(body[0 .. body.len - 1]);
    const names = [_][]const u8{ "QMK.SendKeyDirect", "QMK.SendDirect" };
    for (names) |name| {
        if (!std.ascii.startsWithIgnoreCase(body, name)) continue;
        var open = name.len;
        while (open < body.len and (body[open] == ' ' or body[open] == '\t')) : (open += 1) {}
        if (open >= body.len or body[open] != '(') continue;
        const close = findBalanced(body, open, '(', ')') orelse continue;
        if (trim(body[close + 1 ..]).len == 0) return true;
    }
    return false;
}

fn classifyRow(family: []const u8, row: []const u8) []const u8 {
    if (std.mem.eql(u8, family, "NativeControls")) return "native_control";
    if (std.mem.eql(u8, family, "Hotkeys") and containsAny(row, &[_][]const u8{ "panicExit", "nativeReload" })) return "native_control";
    if (isObjectLiteral(row)) {
        if (std.mem.eql(u8, family, "Modifiers") or std.mem.eql(u8, family, "Passthroughs")) return "native_candidate";
        const action = objectAction(std.heap.page_allocator, family, row) orelse return "unknown";
        if (std.mem.eql(u8, family, "Taps") and isLiteralTapDescriptor(action)) return "tap_descriptor";
        if (std.mem.eql(u8, family, "Hotstrings") and isQuotedElement(action)) return "native_literal";
        if (isCallbackExpression(action)) return "callback";
        if (containsCallIgnoreCase(action, "QMK.SendKeyDirect") or containsCallIgnoreCase(action, "QMK.SendDirect")) return "native";
        if (isQuotedElement(action)) return "native_literal";
        return "callback";
    }
    // A hotstring replacement is a literal payload even when its text
    // contains callback-looking characters such as `() => ...`.
    if (std.mem.eql(u8, family, "Hotstrings")) {
        const row_trimmed = trim(row);
        const row_body = if (row_trimmed.len >= 2 and row_trimmed[0] == '[' and row_trimmed[row_trimmed.len - 1] == ']') row_trimmed[1 .. row_trimmed.len - 1] else row_trimmed;
        if (splitTopLevel(std.heap.page_allocator, row_body)) |elements_value| {
            var elements = elements_value;
            defer elements.deinit(std.heap.page_allocator);
            if (elements.items.len >= 2) {
                const action_index: usize = if (elements.items.len >= 3 and parseLiteralBool(elements.items[2]) == null) 2 else 1;
                if (action_index < elements.items.len and isQuotedElement(elements.items[action_index])) return "native_literal";
            }
        } else |_| {}
    }
    // An arrow expression is an AHK callback even when its body consists of a
    // direct-send call.  Native payload lowering is reserved for literal
    // action expressions; otherwise callback-backed taps/hotkeys lose their
    // callback slot and silently become the wrong action kind.
    if (containsAny(row, &[_][]const u8{ "=>", "(*)" })) return "callback";
    if (rowHasDottedCallbackReference(std.heap.page_allocator, family, row)) return "callback";
    if (containsCallIgnoreCase(row, "Func") or containsCallIgnoreCase(row, "QMK.SuspendExempt")) return "callback";
    if ((std.mem.eql(u8, family, "Holds") or std.mem.eql(u8, family, "DoubleTaps")) and
        (containsCallIgnoreCase(row, "QMK.SendKeyDirect") or containsCallIgnoreCase(row, "QMK.SendDirect") or containsCallIgnoreCase(row, "QMK.Tap"))) return "callback";
    if (containsCallIgnoreCase(row, "QMK.Tap")) {
        const row_trimmed = trim(row);
        const row_body = if (row_trimmed.len >= 2 and row_trimmed[0] == '[' and row_trimmed[row_trimmed.len - 1] == ']') row_trimmed[1 .. row_trimmed.len - 1] else row_trimmed;
        if (splitTopLevel(std.heap.page_allocator, row_body)) |elements_value| {
            var elements = elements_value;
            defer elements.deinit(std.heap.page_allocator);
            if ((std.mem.eql(u8, family, "Hotkeys") or std.mem.eql(u8, family, "Taps")) and elements.items.len >= 3 and isLiteralTapDescriptor(elements.items[2])) return "tap_descriptor";
        } else |_| {}
        return "callback";
    }
    // A non-arrow direct-send expression is the legacy native form used by
    // setup rows such as ["F24", "global", SendEvent("!{Tab}")].  Do not
    // classify arrow bodies this way: the callback check above deliberately
    // preserves those for the AHK callback bridge.
    if (std.mem.eql(u8, family, "Hotkeys") or std.mem.eql(u8, family, "Taps")) {
        const row_trimmed = trim(row);
        const row_body = if (row_trimmed.len >= 2 and row_trimmed[0] == '[' and row_trimmed[row_trimmed.len - 1] == ']') row_trimmed[1 .. row_trimmed.len - 1] else row_trimmed;
        if (splitTopLevel(std.heap.page_allocator, row_body)) |elements_value| {
            var elements = elements_value;
            defer elements.deinit(std.heap.page_allocator);
            const action_index: usize = if (elements.items.len >= 3 and isChordContextOrNonKey(elements.items[1])) 2 else 1;
            if (action_index < elements.items.len) {
                const action = elements.items[action_index];
                const names = [_][]const u8{ "SendEvent", "SendInput", "Send" };
                for (names) |name| if (isLiteralCall(action, name)) return "native";
            }
        } else |_| {}
    }
    if (containsCallIgnoreCase(row, "QMK.SendKeyDirect") or containsCallIgnoreCase(row, "QMK.SendDirect")) return "native";

    const row_trimmed = trim(row);
    const row_body = if (row_trimmed.len >= 2 and row_trimmed[0] == '[' and row_trimmed[row_trimmed.len - 1] == ']') row_trimmed[1 .. row_trimmed.len - 1] else row_trimmed;
    if (splitTopLevel(std.heap.page_allocator, row_body)) |elements_value| {
        var elements = elements_value;
        defer elements.deinit(std.heap.page_allocator);
        if (elements.items.len >= 3 and isQuotedElement(elements.items[2])) return "native_literal";
        if (std.mem.eql(u8, family, "Hotstrings") and elements.items.len >= 3) return "callback";
    } else |_| {}

    if (std.mem.eql(u8, family, "Modifiers") or std.mem.eql(u8, family, "Passthroughs")) return "native_candidate";
    return "unknown";
}

fn appendRow(gpa: std.mem.Allocator, rows: *std.ArrayList(Row), source_index: usize, source_path: []const u8, family: []const u8, row_index: usize, source_text: []const u8) !void {
    const object_normalized = try normalizeObjectSource(gpa, family, source_text);
    const chord_normalized = if (object_normalized == null) try normalizeChordArraySource(gpa, family, source_text) else null;
    const normalized = object_normalized orelse chord_normalized;
    const captured = normalized orelse source_text;
    try rows.append(gpa, .{
        .source_index = source_index,
        .row_index = row_index,
        .source_order = rows.items.len,
        .family = family,
        .source_path = source_path,
        .source_text = captured,
        .classification = classifyRow(family, captured),
        .source_hash = fnv1a64(captured),
        .callback_slots = .{ -1, -1, -1 },
        .owned_source = normalized,
        .chord_normalized = std.mem.eql(u8, family, "Chords") and normalized != null,
    });
}

fn scanSource(gpa: std.mem.Allocator, source: Source, source_index: usize, rows: *std.ArrayList(Row)) !void {
    var i: usize = 0;
    while (i < source.bytes.len) {
        if (source.bytes[i] == '"') {
            i = skipQuoted(source.bytes, i) orelse return error.UnterminatedString;
            continue;
        }
        if (source.bytes[i] == ';') {
            while (i < source.bytes.len and source.bytes[i] != '\n') : (i += 1) {}
            continue;
        }

        var found: ?SourceSpec = null;
        var setup_prefix_len: usize = 0;
        for (specs) |spec| {
            const name_len = spec.name.len - 1; // the final byte is '('
            if (i + name_len > source.bytes.len or !std.ascii.eqlIgnoreCase(source.bytes[i .. i + name_len], spec.name[0..name_len])) continue;
            if (i != 0 and isIdentChar(source.bytes[i - 1])) continue;
            var open_candidate = i + name_len;
            while (open_candidate < source.bytes.len and (source.bytes[open_candidate] == ' ' or source.bytes[open_candidate] == '\t' or source.bytes[open_candidate] == '\r' or source.bytes[open_candidate] == '\n')) : (open_candidate += 1) {}
            if (open_candidate < source.bytes.len and source.bytes[open_candidate] == '(') {
                found = spec;
                setup_prefix_len = open_candidate - i + 1;
                break;
            }
        }
        const spec = found orelse {
            i += 1;
            continue;
        };

        const open_index = i + setup_prefix_len - 1;
        const close_index = findBalanced(source.bytes, open_index, '(', ')') orelse return error.UnbalancedSetupCall;
        const call_text = trim(source.bytes[i .. close_index + 1]);
        const args = source.bytes[open_index + 1 .. close_index];

        // QMKShortcutCollector.CaptureCallRows starts each setup call at
        // rowIndex=0. Preserve that per-call index; source_order below is the
        // global ordering used for deterministic output and callback slots.
        var row_index: usize = 0;
        if (spec.is_control) {
            // Native controls need the wrapper name retained so the emitter
            // can distinguish panic-exit from native-reload.
            try appendRow(gpa, rows, source_index, source.path, spec.family, row_index, call_text);
        } else if (!spec.is_collection) {
            // Singular public wrappers have the same row grammar as a plural
            // collection entry.  Store only their arguments so every family
            // reaches the same normalization/lowering path.
            try appendRow(gpa, rows, source_index, source.path, spec.family, row_index, args);
        } else {
            const outer = trim(args);
            if (outer.len < 2 or outer[0] != '[') return error.CollectionMustBeArray;
            const outer_close = findBalanced(outer, 0, '[', ']') orelse return error.UnbalancedCollection;
            if (trim(outer[outer_close + 1 ..]).len != 0) return error.TrailingCollectionText;
            var entries = try splitTopLevel(gpa, outer[1..outer_close]);
            defer entries.deinit(gpa);
            for (entries.items) |entry| {
                const clean = trim(entry);
                if (clean.len == 0) continue;
                try appendRow(gpa, rows, source_index, source.path, spec.family, row_index, clean);
                row_index += 1;
            }
            // An empty collection is a valid no-op in the AHK wrapper. Do not
            // manufacture an unknown sentinel row: complete-compiled mode
            // should accept the no-op while still rejecting malformed rows.
        }
        i = close_index + 1;
    }
}

fn rowArgumentText(row: []const u8) []const u8 {
    const t = trim(row);
    if (!std.mem.startsWith(u8, t, "QMK.")) return t;
    const open = std.mem.indexOfScalar(u8, t, '(') orelse return t;
    const close = findBalanced(t, open, '(', ')') orelse return t;
    return t[open + 1 .. close];
}

fn appendLine(gpa: std.mem.Allocator, out: *std.ArrayList(u8), comptime format: []const u8, args: anytype) !void {
    const line = try std.fmt.allocPrint(gpa, format, args);
    defer gpa.free(line);
    try out.appendSlice(gpa, line);
}

fn sourceSetHash(sources: []const Source) u64 {
    var hash: u64 = 0xcbf29ce484222325;
    for (sources, 0..) |source, index| {
        hash ^= fnv1a64(source.path) +% @as(u64, @intCast(index));
        hash *%= 0x100000001b3;
        hash ^= fnv1a64(source.bytes);
        hash *%= 0x100000001b3;
    }
    return hash;
}

// Match QMKCompiler.ComputeShortcutBuildId(): FNV-1a over each selected path,
// a newline, and the UTF-8-decoded source characters, reduced to u32.
fn ahkBuildIdHash(sources: []const Source) u32 {
    var hash: u32 = 2166136261;
    for (sources) |source| {
        for (source.path) |byte| hash = (hash ^ @as(u32, byte)) *% 16777619;
        hash = (hash ^ 10) *% 16777619;
        var iterator = std.unicode.Utf8Iterator{ .bytes = source.bytes, .i = 0 };
        while (iterator.nextCodepoint()) |codepoint| {
            hash = (hash ^ @as(u32, @intCast(codepoint))) *% 16777619;
        }
    }
    return hash;
}

fn emitManifest(init: std.process.Init, gpa: std.mem.Allocator, sources: []const Source, rows: []const Row, output_dir: std.Io.Dir) !void {
    var out = std.ArrayList(u8).empty;
    defer out.deinit(gpa);
    try out.appendSlice(gpa,
        \\# Zig user-shortcut transpiler complete-compiled manifest
        \\# Source capture is source-only; typed emission is deterministic and does not execute AHK inputs.
        \\mode=complete_compiled
    );
    try out.append(gpa, '\n');
    try appendLine(gpa, &out, "source_count={d}\n", .{sources.len});
    try appendLine(gpa, &out, "row_count={d}\n", .{rows.len});

    for (sources, 0..) |source, index| {
        try appendLine(gpa, &out, "SOURCE {d}|{s}|bytes={d}|hash={x}\n", .{ index, source.path, source.bytes.len, fnv1a64(source.bytes) });
    }
    try appendLine(gpa, &out, "source_set_hash={x}\n", .{sourceSetHash(sources)});

    var counts = std.StringHashMap(usize).init(gpa);
    defer counts.deinit();
    for (rows) |row| {
        const current = counts.get(row.family) orelse 0;
        try counts.put(row.family, current + 1);
    }
    var emitted_families = std.StringHashMap(void).init(gpa);
    defer emitted_families.deinit();
    for (specs) |spec| {
        if (counts.get(spec.family)) |count| {
            if (!emitted_families.contains(spec.family)) {
                try appendLine(gpa, &out, "FAMILY {s}={d}\n", .{ spec.family, count });
                try emitted_families.put(spec.family, {});
            }
        }
    }
    try appendLine(gpa, &out, "ROWS_BEGIN\n", .{});
    for (rows) |row| {
    try appendLine(gpa, &out, "ROW {d}|{d}|order={d}|{s}|{s}|{s}|len={d}|hash={x}\n", .{
            row.source_index,
            row.row_index,
            row.source_order,
            row.family,
            row.classification,
            row.source_path,
            row.source_text.len,
            row.source_hash,
        });
    }
    try appendLine(gpa, &out, "ROWS_END\n", .{});

    try output_dir.writeFile(init.io, .{
        .sub_path = "manifest.txt",
        .data = out.items,
    });
}

fn quotedText(value: []const u8) []const u8 {
    const t = trim(value);
    if (t.len >= 2 and t[0] == '"' and t[t.len - 1] == '"') {
        const body = t[1 .. t.len - 1];
        if (std.mem.eql(u8, body, "``")) return "`";
        return body;
    }
    return t;
}

fn emitByteSlice(gpa: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try out.appendSlice(gpa, "&.{ ");
    for (value, 0..) |byte, index| {
        if (index != 0) try out.appendSlice(gpa, ", ");
        try appendLine(gpa, out, "{d}", .{@as(u16, byte)});
    }
    if (value.len != 0) try out.appendSlice(gpa, ", ");
    try out.appendSlice(gpa, "0 }");
}

fn emitU8(gpa: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try out.appendSlice(gpa, "&.{ ");
    for (value, 0..) |byte, index| {
        if (index != 0) try out.appendSlice(gpa, ", ");
        try appendLine(gpa, out, "{d}", .{@as(u16, byte)});
    }
    try out.appendSlice(gpa, " }");
}

fn emitKey(gpa: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try out.appendSlice(gpa, "u(\"");
    for (value) |byte| switch (byte) {
        '\\' => try out.appendSlice(gpa, "\\\\"),
        '"' => try out.appendSlice(gpa, "\\\""),
        '\n' => try out.appendSlice(gpa, "\\n"),
        '\r' => try out.appendSlice(gpa, "\\r"),
        '\t' => try out.appendSlice(gpa, "\\t"),
        else => try out.append(gpa, byte),
    };
    try out.appendSlice(gpa, "\")");
}

fn emitU16(gpa: std.mem.Allocator, out: *std.ArrayList(u8), value: []const u8) !void {
    try emitByteSlice(gpa, out, value);
}

fn emitContext(gpa: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    try out.appendSlice(gpa, ".{ .kind = .global, .negated = false, .text = &.{}, .specificity_mask = 0 }");
}

fn splitRowArgs(gpa: std.mem.Allocator, value: []const u8) !std.ArrayList([]const u8) {
    const t = trim(value);
    if (t.len >= 2 and t[0] == '[' and t[t.len - 1] == ']') return splitTopLevel(gpa, t[1 .. t.len - 1]);
    if (std.mem.indexOfScalar(u8, t, '(')) |open| {
        const close = findBalanced(t, open, '(', ')') orelse return error.UnbalancedRow;
        if (trim(t[close + 1 ..]).len == 0) return splitTopLevel(gpa, t[open + 1 .. close]);
    }
    return splitTopLevel(gpa, t);
}

fn parseLiteralString(gpa: std.mem.Allocator, value: []const u8) ![]u8 {
    const t = trim(value);
    if (t.len < 2 or t[0] != '"' or t[t.len - 1] != '"') return error.ExpectedLiteralString;
    var result = std.ArrayList(u8).empty;
    errdefer result.deinit(gpa);
    var i: usize = 1;
    while (i + 1 < t.len) : (i += 1) {
        if (t[i] == '"' and i + 1 < t.len - 1 and t[i + 1] == '"') {
            try result.append(gpa, '"');
            i += 1;
        } else if (t[i] == '`' and i + 1 < t.len - 1) {
            i += 1;
            try result.append(gpa, switch (t[i]) {
                'n' => '\n', 'r' => '\r', 't' => '\t', 'b' => '\x08',
                'v' => '\x0b', 'a' => '\x07', 'f' => '\x0c',
                else => t[i],
            });
        } else {
            try result.append(gpa, t[i]);
        }
    }
    return result.toOwnedSlice(gpa);
}

fn parseLiteralBool(value: []const u8) ?bool {
    const t = trim(value);
    // Match QMKInterception.RawValueLooksBool, including the textual forms
    // accepted by the AHK wrappers for optional exemption cells.
    if (std.ascii.eqlIgnoreCase(t, "true") or std.mem.eql(u8, t, "1") or
        std.ascii.eqlIgnoreCase(t, "yes") or std.ascii.eqlIgnoreCase(t, "on")) return true;
    if (std.ascii.eqlIgnoreCase(t, "false") or std.mem.eql(u8, t, "0") or
        std.ascii.eqlIgnoreCase(t, "no") or std.ascii.eqlIgnoreCase(t, "off")) return false;
    return null;
}

fn parseLiteralInt(value: []const u8) ?i64 {
    return std.fmt.parseInt(i64, trim(value), 10) catch null;
}

const ContextParts = struct {
    kind: []const u8,
    negated: bool,
    text: []u8,
};

fn parseContext(gpa: std.mem.Allocator, expression: []const u8) !ContextParts {
    var value = trim(expression);
    var nested: ?std.ArrayList([]const u8) = null;
    defer if (nested) |*items| items.deinit(gpa);
    var raw: []u8 = undefined;
    if (value.len >= 2 and value[0] == '[' and value[value.len - 1] == ']') {
        const items = try splitTopLevel(gpa, value[1 .. value.len - 1]);
        if (items.items.len == 0) return error.CompoundContext;
        var joined = std.ArrayList(u8).empty;
        defer joined.deinit(gpa);
        for (items.items, 0..) |item, index| {
            const item_raw = try parseLiteralString(gpa, item);
            defer gpa.free(item_raw);
            if (index != 0) try joined.append(gpa, 0x1F);
            try joined.appendSlice(gpa, trim(item_raw));
        }
        raw = try joined.toOwnedSlice(gpa);
        nested = items;
    } else {
        raw = try parseLiteralString(gpa, value);
        // QMK.SplitContextList() treats a scalar context containing commas as
        // an OR-list.  Encode that same list separator used by the runtime so
        // each Explorer selector is parsed independently after preload.
        if (std.mem.indexOfScalar(u8, raw, ',') != null) {
            var joined = std.ArrayList(u8).empty;
            defer joined.deinit(gpa);
            var emitted: usize = 0;
            var comma_items = std.mem.splitScalar(u8, raw, ',');
            while (comma_items.next()) |item| {
                const clean = trim(item);
                if (clean.len == 0) continue;
                if (emitted != 0) try joined.append(gpa, 0x1F);
                try joined.appendSlice(gpa, clean);
                emitted += 1;
            }
            if (emitted == 0) try joined.appendSlice(gpa, "global");
            const split_raw = try joined.toOwnedSlice(gpa);
            gpa.free(raw);
            raw = split_raw;
        }
    }
    errdefer gpa.free(raw);
    const trimmed_initial = try gpa.dupe(u8, trim(raw));
    gpa.free(raw);
    raw = trimmed_initial;
    var negated = false;
    // With multiple contexts, keep each entry's leading `!` in the encoded
    // text.  QMKCore parses each U+001F-delimited entry separately, matching
    // QMK.ContextPredicateMatches() for arrays and comma-separated strings.
    if (raw.len > 0 and raw[0] == '!' and std.mem.indexOfScalar(u8, raw, 0x1F) == null) {
        negated = true;
        const without = try gpa.dupe(u8, trim(raw[1..]));
        gpa.free(raw);
        raw = without;
    }
    const normalized = try gpa.alloc(u8, raw.len);
    for (raw, 0..) |byte, index| normalized[index] = std.ascii.toLower(byte);
    defer gpa.free(normalized);
    var kind: []const u8 = "title";
    if (raw.len == 0 or std.mem.eql(u8, normalized, "global")) {
        kind = "global";
        if (raw.len != 0) {
            gpa.free(raw);
            raw = try gpa.alloc(u8, 0);
        }
    } else if (std.mem.eql(u8, normalized, "#32768") or std.mem.eql(u8, normalized, "ahk_class #32768")) {
        kind = "menu";
    } else if (contextHasCompoundAhkCriteria(normalized, raw)) {
        kind = "compound";
    } else if (std.mem.indexOf(u8, normalized, "ahk_class") != null) {
        kind = "class";
    } else if (std.mem.eql(u8, normalized, "browser") or std.mem.eql(u8, normalized, "browsers")) {
        kind = "browser";
    } else if (std.mem.indexOf(u8, normalized, "ahk_exe") != null) {
        kind = "exe";
    } else if (std.mem.indexOfScalar(u8, raw, '.') != null) {
        kind = "website";
    }
    return .{ .kind = kind, .negated = negated, .text = raw };
}

fn contextHasCompoundAhkCriteria(normalized: []const u8, raw: []const u8) bool {
    const class_pos = std.mem.indexOf(u8, normalized, "ahk_class");
    const exe_pos = std.mem.indexOf(u8, normalized, "ahk_exe");
    if (class_pos == null and exe_pos == null) return false;
    const token_count: u8 = (if (class_pos != null) @as(u8, 1) else 0) + (if (exe_pos != null) @as(u8, 1) else 0);
    const first_pos = if (class_pos) |cp| if (exe_pos) |ep| @min(cp, ep) else cp else exe_pos.?;
    return token_count > 1 or trim(raw[0..first_pos]).len != 0;
}

fn emitContextParts(gpa: std.mem.Allocator, out: *std.ArrayList(u8), context: ContextParts) !void {
    try appendLine(gpa, out, ".{{ .kind = .{s}, .negated = {s}, .text = ", .{ context.kind, if (context.negated) "true" else "false" });
    // Context text is a counted runtime slice, not a zero-terminated string.
    // Payload/replacement strings still use emitU16(), which intentionally
    // emits a terminator.
    try emitU8(gpa, out, context.text);
    try out.appendSlice(gpa, ", .specificity_mask = 0 }");
}

fn modifierMask(value: []const u8) u16 {
    var result: u16 = 0;
    for (value) |byte| result |= switch (byte) { '^' => 1, '!' => 2, '+' => 4, '#' => 8, else => 0 };
    return result;
}

fn isLiteralMode(value: []const u8) bool {
    const t = trim(value);
    if (!isQuotedElement(t)) return false;
    const body = quotedText(t);
    return std.ascii.eqlIgnoreCase(body, "callback") or std.ascii.eqlIgnoreCase(body, "internal") or
        std.ascii.eqlIgnoreCase(body, "sendkeydirect") or std.ascii.eqlIgnoreCase(body, "sendkeydirectinstant") or
        std.ascii.eqlIgnoreCase(body, "instant") or std.ascii.eqlIgnoreCase(body, "internalinstant") or
        std.ascii.eqlIgnoreCase(body, "instantinternal") or std.ascii.eqlIgnoreCase(body, "callbackinstant");
}

fn knownKeySpelling(value: []const u8) bool {
    const t = trim(value);
    if (t.len == 1) return true;
    const names = [_][]const u8{ "Escape", "Esc", "Tab", "Enter", "Return", "Backspace", "Space", "CapsLock", "AppsKey", "Shift", "Control", "Ctrl", "PgUp", "PageUp", "PgDn", "PageDown", "PrintScreen", "PrintScr", "MButton", "XButton1", "XButton2", "ScrollLock", "NumLock", "Insert", "Delete", "Home", "End", "Left", "Up", "Right", "Down", "LControl", "LCtrl", "RControl", "RCtrl", "LShift", "RShift", "LAlt", "RAlt", "LWin", "RWin" };
    for (names) |name| if (std.ascii.eqlIgnoreCase(t, name)) return true;
    if (t.len >= 2 and (t[0] == 'F' or t[0] == 'f')) return parseLiteralInt(t[1..]) != null;
    return false;
}

fn isLiteralModifierMask(value: []const u8) bool {
    if (!isQuotedElement(value)) return false;
    const text = quotedText(value);
    // The AHK object/normalized forms use an empty modifier string when no
    // extra modifier mask is requested.  It is still an explicit optional tail
    // field and must be consumed by chordTail rather than mistaken for the
    // action or context.
    if (text.len == 0) return true;
    for (text) |byte| if (byte != '^' and byte != '!' and byte != '+' and byte != '#') return false;
    return true;
}

fn isChordContextOrNonKey(value: []const u8) bool {
    const t = trim(value);
    if (t.len >= 2 and t[0] == '[' and t[t.len - 1] == ']') return true;
    if (!isQuotedElement(t)) return false;
    const text = quotedText(t);
    if (text.len == 0 or !knownKeySpelling(text)) return true;
    return false;
}

fn comboModeName(classification: []const u8, args: []const []const u8) []const u8 {
    var mode: []const u8 = "";
    // Contextual rows place mode after [primary, secondary, context, action];
    // global shorthand places it after [primary, secondary, action].
    const has_context = args.len >= 4 and isChordContextOrNonKey(args[2]);
    const mode_index: usize = if (has_context) 4 else 3;
    if (args.len > mode_index and isQuotedElement(args[mode_index])) mode = quotedText(args[mode_index]);
    const instant = std.ascii.eqlIgnoreCase(mode, "instant") or std.ascii.eqlIgnoreCase(mode, "instant_callback") or std.ascii.eqlIgnoreCase(mode, "callbackinstant") or std.ascii.eqlIgnoreCase(mode, "sendkeydirectinstant") or std.ascii.eqlIgnoreCase(mode, "internalinstant") or std.ascii.eqlIgnoreCase(mode, "instantinternal");
    if (std.mem.eql(u8, classification, "callback")) return if (instant) "instant_callback" else "normal_callback";
    return if (instant) "internal_instant_remap" else "internal_remap";
}

const TargetParts = struct { key: []const u8, mod_mask: u16 };

fn parseSendTarget(payload: []const u8, extra_mods: u16) !TargetParts {
    var i: usize = 0;
    var mods = extra_mods;
    while (i < payload.len) {
        const bit: u16 = switch (payload[i]) { '^' => 1, '!' => 2, '+' => 4, '#' => 8, else => 0 };
        if (bit == 0) break;
        mods |= bit;
        i += 1;
    }
    var key = trim(payload[i..]);
    if (key.len >= 2 and key[0] == '{' and key[key.len - 1] == '}') key = trim(key[1 .. key.len - 1]);
    if (key.len == 0 or std.mem.indexOfScalar(u8, key, '{') != null or std.mem.indexOfScalar(u8, key, '}') != null) return error.UnsupportedTarget;
    return .{ .key = key, .mod_mask = mods };
}

const ChordTail = struct { action_index: usize, context_index: ?usize, mod_mask: u16, suspend_exempt: bool };

fn chordTail(args: []const []const u8, normalized: bool) !ChordTail {
    if (args.len < 3) return error.UnsupportedChord;
    var action_index = args.len - 1;
    var suspend_exempt = false;
    if (parseLiteralBool(args[action_index])) |value| {
        suspend_exempt = value;
        if (action_index == 0) return error.UnsupportedChord;
        action_index -= 1;
    }
    var mod_mask: u16 = 0;
    if (action_index > 0 and isLiteralModifierMask(args[action_index])) {
        mod_mask = modifierMask(quotedText(args[action_index]));
        action_index -= 1;
    }
    if (action_index > 0 and isLiteralMode(args[action_index])) action_index -= 1;
    var context_index: ?usize = null;
    if (normalized) {
        // Normalized chord rows always have the authoritative shape:
        // [key..., context, action, mode, mods, suspend].  Once the tail is
        // removed, context is therefore the element immediately before the
        // action for every 2/3/4/5-key chord.  Do not infer it from whether
        // the cell happens to look like a key.
        if (action_index == 0) return error.UnsupportedChord;
        context_index = action_index - 1;
    } else if (action_index > 3 and isChordContextOrNonKey(args[action_index - 1])) {
        context_index = action_index - 1;
    }
    return .{ .action_index = action_index, .context_index = context_index, .mod_mask = mod_mask, .suspend_exempt = suspend_exempt };
}

const HotstringOptionsParts = struct {
    case_sensitive: bool = false,
    conform_to_case: bool = false,
    backspace: bool = true,
    omit_end_char: bool = false,
    require_end_char: bool = true,
    inside_word: bool = false,
    reset: bool = false,
    execute: bool = false,
    suspend_exempt: bool = false,
    send_raw: bool = false,
};

fn parseHotstringOptions(value: []const u8) HotstringOptionsParts {
    var result = HotstringOptionsParts{};
    var i: usize = 0;
    while (i < value.len) : (i += 1) {
        const upper = std.ascii.toUpper(value[i]);
        const next = if (i + 1 < value.len) value[i + 1] else 0;
        switch (upper) {
            'X' => result.execute = true,
            'Z' => result.reset = true,
            '?' => { result.inside_word = next != '0'; if (next == '0') i += 1; },
            'O' => { result.omit_end_char = next != '0'; if (next == '0') i += 1; },
            'B' => { result.backspace = next != '0'; if (next == '0') i += 1; },
            '*' => { result.require_end_char = next == '0'; if (next == '0') i += 1; },
            'C' => { if (next == '0') result.conform_to_case = true else result.case_sensitive = next != '1'; if (next == '0' or next == '1') i += 1; },
            'S' => { if (next != 'I' and next != 'E' and next != 'P') { result.suspend_exempt = next != '0'; if (next == '0') i += 1; } },
            'R', 'T' => result.send_raw = true,
            else => {},
        }
    }
    return result;
}

fn emitHotstringOptions(gpa: std.mem.Allocator, out: *std.ArrayList(u8), options: HotstringOptionsParts) !void {
    try appendLine(gpa, out, ".{{ .case_sensitive = {s}, .conform_to_case = {s}, .backspace = {s}, .omit_end_char = {s}, .require_end_char = {s}, .inside_word = {s}, .reset = {s}, .execute = {s}, .suspend_exempt = {s}, .enabled = true, .send_raw = {s} }}", .{
        if (options.case_sensitive) "true" else "false", if (options.conform_to_case) "true" else "false", if (options.backspace) "true" else "false", if (options.omit_end_char) "true" else "false", if (options.require_end_char) "true" else "false", if (options.inside_word) "true" else "false", if (options.reset) "true" else "false", if (options.execute) "true" else "false", if (options.suspend_exempt) "true" else "false", if (options.send_raw) "true" else "false",
    });
}

fn isCallbackExpression(value: []const u8) bool {
    return isDottedReference(value) or containsAny(value, &[_][]const u8{ "=>", "(*)" }) or
        containsCallIgnoreCase(value, "Func") or containsCallIgnoreCase(value, "QMK.SuspendExempt") or
        containsCallIgnoreCase(value, "QMK.Tap") or containsCallIgnoreCase(value, "QMK.SendKeyDirect") or
        containsCallIgnoreCase(value, "QMK.SendDirect");
}

// Return the source expression used by one callback-bearing role.  The
// expression itself remains a slice of the captured source; only the small
// argument-vector bookkeeping is temporary.  Keeping the raw expression as
// the key matches the existing AHK compiler's callback deduplication rule.
fn callbackExpressionForPart(row: Row, part: u8) ?[]const u8 {
    if (isObjectLiteral(row.source_text)) {
        var value: ?[]const u8 = null;
        if (std.mem.eql(u8, row.family, "Taps")) {
            value = switch (part) {
                0 => objectAction(std.heap.page_allocator, row.family, row.source_text),
                1 => objectFieldAny(std.heap.page_allocator, row.source_text, &[_][]const u8{ "holdCallback", "hold" }),
                2 => objectFieldAny(std.heap.page_allocator, row.source_text, &[_][]const u8{ "cleanupCallback", "cleanup" }),
                else => null,
            };
        } else if (std.mem.eql(u8, row.family, "Holds") or std.mem.eql(u8, row.family, "DoubleTaps") or
            std.mem.eql(u8, row.family, "Hotstrings") or std.mem.eql(u8, row.family, "Combos") or
            std.mem.eql(u8, row.family, "Chords")) {
            value = objectAction(std.heap.page_allocator, row.family, row.source_text);
        }
        if (value) |expression| {
            const candidate = trim(expression);
            return if (isCallbackExpression(candidate)) candidate else null;
        }
        return null;
    }

    var args = splitRowArgs(std.heap.page_allocator, row.source_text) catch return null;
    defer args.deinit(std.heap.page_allocator);

    if (std.mem.eql(u8, row.family, "TapHolds")) {
        const index: usize = switch (part) { 0 => 3, 1 => 4, 2 => 5, else => return null };
        if (index >= args.items.len) return null;
        const value = trim(args.items[index]);
        return if (isCallbackExpression(value)) value else null;
    }
    if (std.mem.eql(u8, row.family, "Taps")) {
        const layout = tapLayout(args.items) catch return null;
        const index: usize = switch (part) {
            0 => layout.action_index,
            1 => layout.hold_index orelse return null,
            2 => layout.cleanup_index orelse return null,
            else => return null,
        };
        if (index >= args.items.len) return null;
        const value = trim(args.items[index]);
        return if (isCallbackExpression(value)) value else null;
    }
    if (std.mem.eql(u8, row.family, "Holds") or std.mem.eql(u8, row.family, "DoubleTaps")) {
        if (args.items.len < 2) return null;
        const has_context = args.items.len >= 3 and parseLiteralBool(args.items[2]) == null;
        const action_index: usize = if (has_context) 2 else 1;
        if (action_index >= args.items.len) return null;
        const value = trim(args.items[action_index]);
        return if (isCallbackExpression(value)) value else null;
    }
    if (std.mem.eql(u8, row.family, "Chords")) {
        for (args.items, 0..) |value, index| {
            if (index < 2) continue;
            const candidate = trim(value);
            if (isCallbackExpression(candidate)) return candidate;
        }
        return null;
    }
    if (std.mem.eql(u8, row.family, "Combos")) {
        // Combo syntax is either [primary, secondary, action, ...] or
        // [primary, secondary, context, action, ...].  The old extractor
        // always used element 3, so contextual AHK combo callbacks were
        // emitted with wrapper functions but no callback ID in the Zig row.
        // Do not infer the action position from row length: a combo may omit
        // context, and its optional mode follows the action.  The callback
        // expression is the first callback-bearing argument after the keys.
        for (args.items[2..]) |value| {
            const candidate = trim(value);
            if (isCallbackExpression(candidate)) return candidate;
        }
        return null;
    }
    if (std.mem.eql(u8, row.family, "Hotkeys")) {
        // Hotkeys accept both the collection form and the singular wrapper:
        // [spec, action], [spec, action, suspend_exempt],
        // [spec, context, action], and [spec, context, action, suspend_exempt].
        if (args.items.len < 2) return null;
        const has_context = args.items.len >= 3 and parseLiteralBool(args.items[2]) == null;
        const action_index: usize = if (has_context) 2 else 1;
        if (action_index >= args.items.len) return null;
        const value = trim(args.items[action_index]);
        return if (isCallbackExpression(value)) value else null;
    }
    if (std.mem.eql(u8, row.family, "Hotstrings")) {
        if (args.items.len < 2) return null;
        const has_context = args.items.len >= 3 and parseLiteralBool(args.items[2]) == null;
        const action_index: usize = if (has_context) 2 else 1;
        if (action_index >= args.items.len) return null;
        const value = trim(args.items[action_index]);
        return if (!isQuotedElement(value)) value else null;
    }
    if (args.items.len < 3) return null;
    const value = trim(args.items[2]);
    return if (isCallbackExpression(value) or std.mem.eql(u8, row.family, "Hotstrings")) value else null;
}

fn callbackPartCount(row: Row) u8 {
    if (std.mem.eql(u8, row.family, "TapHolds")) {
        var args = splitRowArgs(std.heap.page_allocator, row.source_text) catch return 0;
        defer args.deinit(std.heap.page_allocator);
        return if (args.items.len >= 6) 3 else 2;
    }
    if (std.mem.eql(u8, row.family, "Taps")) return 3;
    return 1;
}

fn assignCallbackSlots(gpa: std.mem.Allocator, rows: []Row) !void {
    var callback_slots = std.StringHashMap(i32).init(gpa);
    defer callback_slots.deinit();
    var next_slot: i32 = 0;
    for (rows) |*row| {
        if (!std.mem.eql(u8, row.classification, "callback")) continue;
        const part_count = callbackPartCount(row.*);
        for (0..part_count) |part| {
            const expression = callbackExpressionForPart(row.*, @intCast(part)) orelse continue;
            const slot = callback_slots.get(expression) orelse blk: {
                const fresh = next_slot;
                next_slot += 1;
                try callback_slots.put(expression, fresh);
                break :blk fresh;
            };
            row.callback_slots[part] = slot;
        }
    }
}

fn callbackSlotForPart(row: Row, part: u8) i32 {
    if (part >= row.callback_slots.len) return -1;
    return row.callback_slots[part];
}

fn callbackSlot(row: Row) i32 {
    return callbackSlotForPart(row, 0);
}

const CallbackWrapperParts = struct { params: []const u8, body: []const u8, is_reference: bool = false };

fn appendAhkBody(gpa: std.mem.Allocator, out: *std.ArrayList(u8), body: []const u8) !void {
    // SendDirect was the legacy spelling; emit the live QMK API directly so
    // generated callbacks never require a post-generation compatibility pass.
    var remaining = body;
    while (std.mem.indexOf(u8, remaining, "QMK.SendDirect(") ) |index| {
        try out.appendSlice(gpa, remaining[0..index]);
        try out.appendSlice(gpa, "QMK.SendKeyDirect(");
        remaining = remaining[index + "QMK.SendDirect(".len ..];
    }
    try out.appendSlice(gpa, remaining);
}

fn unwrapSuspendExempt(value: []const u8) []const u8 {
    const text = trim(value);
    const prefix = "QMK.SuspendExempt";
    if (!std.ascii.startsWithIgnoreCase(text, prefix)) return text;
    var open = prefix.len;
    while (open < text.len and (text[open] == ' ' or text[open] == '\t')) : (open += 1) {}
    if (open >= text.len or text[open] != '(') return text;
    const close = findBalanced(text, open, '(', ')') orelse return text;
    if (trim(text[close + 1 ..]).len != 0) return text;
    return trim(text[open + 1 .. close]);
}

fn callbackWrapperParts(expression: []const u8) ?CallbackWrapperParts {
    const text = unwrapSuspendExempt(expression);
    const arrow = std.mem.indexOf(u8, text, "=>") orelse {
        if (text.len > 0 and (std.mem.indexOfScalar(u8, text, '.') != null or (std.ascii.startsWithIgnoreCase(text, "QMK.Tap") and containsCallIgnoreCase(text, "QMK.Tap")))) return .{ .params = "*", .body = text, .is_reference = std.mem.indexOfScalar(u8, text, '.') != null };
        return null;
    };
    const before = trim(text[0..arrow]);
    if (before.len == 0 or before[before.len - 1] != ')') return null;
    var depth: usize = 0;
    var position: usize = before.len;
    while (position > 0) {
        position -= 1;
        switch (before[position]) {
            ')' => depth += 1,
            '(' => {
                if (depth == 0) return null;
                depth -= 1;
                if (depth == 0) return .{ .params = trim(before[position + 1 .. before.len - 1]), .body = trim(text[arrow + 2 ..]) };
            },
            else => {},
        }
    }
    return null;
}

fn appendCallbackName(gpa: std.mem.Allocator, out: *std.ArrayList(u8), slot: i32) !void {
    try out.appendSlice(gpa, "QMKCB_");
    const number: usize = @intCast(slot + 1);
    if (number < 10) try out.append(gpa, '0');
    if (number < 100) try out.append(gpa, '0');
    if (number < 1000) try out.append(gpa, '0');
    try appendLine(gpa, out, "{d}", .{number});
}

fn appendSourceCallbackName(gpa: std.mem.Allocator, out: *std.ArrayList(u8), source_index: usize, slot: i32) !void {
    var name: [32]u8 = undefined;
    const text = try std.fmt.bufPrint(&name, "QMKCB_S{d:0>3}_{d:0>4}", .{ source_index + 1, @as(usize, @intCast(slot + 1)) });
    try out.appendSlice(gpa, text);
}

const HotkeyParts = struct {
    key: []const u8,
    mods_required: u16,
    mods_forbidden: u16,
    trigger_kind: u8,
    suppress_original: bool,
    physical_mod_vk: u8,
    physical_mods_required: u8,
    physical_mods_forbidden: u8,
};

fn isHotkeyModifier(byte: u8) bool {
    return byte == '^' or byte == '!' or byte == '+' or byte == '#';
}

fn modifierVk(name: []const u8) u8 {
    // AHK custom hotkeys allow any valid key before '&', not only the four
    // OS modifier families.  This lookup is also used for ordinary key
    // spellings when calculating collapsed/physical masks.
    if (name.len == 1) {
        const c = std.ascii.toUpper(name[0]);
        if ((c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9')) return c;
    }
    const names = [_]struct { text: []const u8, vk: u8 }{
        .{ .text = "LControl", .vk = 0xA2 }, .{ .text = "LCtrl", .vk = 0xA2 },
        .{ .text = "RControl", .vk = 0xA3 }, .{ .text = "RCtrl", .vk = 0xA3 },
        .{ .text = "LShift", .vk = 0xA0 }, .{ .text = "RShift", .vk = 0xA1 },
        .{ .text = "LAlt", .vk = 0xA4 }, .{ .text = "RAlt", .vk = 0xA5 },
        .{ .text = "LWin", .vk = 0x5B }, .{ .text = "RWin", .vk = 0x5C },
        .{ .text = "Control", .vk = 0x11 }, .{ .text = "Ctrl", .vk = 0x11 },
        .{ .text = "Shift", .vk = 0x10 }, .{ .text = "Alt", .vk = 0x12 },
        .{ .text = "Win", .vk = 0x5B }, .{ .text = "CapsLock", .vk = 0x14 },
        .{ .text = "Capslock", .vk = 0x14 }, .{ .text = "Tab", .vk = 0x09 },
        .{ .text = "Enter", .vk = 0x0D }, .{ .text = "Return", .vk = 0x0D },
        .{ .text = "Escape", .vk = 0x1B }, .{ .text = "Esc", .vk = 0x1B },
        .{ .text = "Space", .vk = 0x20 }, .{ .text = "Backspace", .vk = 0x08 },
        .{ .text = "AppsKey", .vk = 0x5D }, .{ .text = "ScrollLock", .vk = 0x91 },
        .{ .text = "NumLock", .vk = 0x90 }, .{ .text = "Insert", .vk = 0x2D },
        .{ .text = "Delete", .vk = 0x2E }, .{ .text = "Home", .vk = 0x24 },
        .{ .text = "End", .vk = 0x23 }, .{ .text = "Left", .vk = 0x25 },
        .{ .text = "Up", .vk = 0x26 }, .{ .text = "Right", .vk = 0x27 },
        .{ .text = "Down", .vk = 0x28 }, .{ .text = "PgUp", .vk = 0x21 },
        .{ .text = "PageUp", .vk = 0x21 }, .{ .text = "PgDn", .vk = 0x22 },
        .{ .text = "PageDown", .vk = 0x22 }, .{ .text = "PrintScreen", .vk = 0x2C },
        .{ .text = "PrintScr", .vk = 0x2C }, .{ .text = "MButton", .vk = 0x04 },
        .{ .text = "XButton1", .vk = 0x05 }, .{ .text = "XButton2", .vk = 0x06 },
        .{ .text = "LButton", .vk = 0x01 }, .{ .text = "RButton", .vk = 0x02 },
    };
    for (names) |entry| if (std.ascii.eqlIgnoreCase(name, entry.text)) return entry.vk;
    if (name.len >= 2 and (name[0] == 'F' or name[0] == 'f')) {
        if (parseLiteralInt(name[1..])) |n| if (n >= 1 and n <= 24) return @intCast(0x6F + n);
    }
    return switch (name.len == 1) {
        true => switch (name[0]) {
            ';' => 0xBA, '=' => 0xBB, ',' => 0xBC, '-' => 0xBD,
            '.' => 0xBE, '/' => 0xBF, '`' => 0xC0, '[' => 0xDB,
            '\\' => 0xDC, ']' => 0xDD, '\'' => 0xDE,
            else => 0,
        },
        false => 0,
    };
}

fn collapsedModifierBit(vk: u8) u16 {
    return switch (vk) {
        0x10, 0xA0, 0xA1 => 0x04,
        0x11, 0xA2, 0xA3 => 0x01,
        0x12, 0xA4, 0xA5 => 0x02,
        0x5B, 0x5C => 0x08,
        else => 0,
    };
}

fn physicalModifierBits(vk: u8) u8 {
    // Must match QMKCore.physicalModifierLRBitForVK exactly.
    return switch (vk) {
        0xA2 => 0x01, 0xA3 => 0x02, 0xA4 => 0x04, 0xA5 => 0x08,
        0xA0 => 0x10, 0xA1 => 0x20, 0x5B => 0x40, 0x5C => 0x80,
        else => 0,
    };
}

fn parseHotkeySpec(spec_value: []const u8) HotkeyParts {
    const original = trim(spec_value);
    var text = original;
    var suppress = true;
    var allow_extra = false;
    var physical_vk: u8 = 0;
    var physical_required: u8 = 0;
    var mods: u16 = 0;
    if (std.mem.indexOf(u8, text, " & ")) |composite| {
        var prefix = trim(text[0..composite]);
        text = trim(text[composite + 3 ..]);
        if (prefix.len > 0 and prefix[0] == '~') { suppress = false; prefix = trim(prefix[1..]); }
        if (prefix.len > 0 and prefix[0] == '*') { allow_extra = true; prefix = trim(prefix[1..]); }
        physical_vk = modifierVk(prefix);
        if (physical_vk != 0) {
            physical_required = physicalModifierBits(physical_vk);
            mods |= collapsedModifierBit(physical_vk);
        }
        if (text.len > 0 and text[0] == '~') { suppress = false; text = trim(text[1..]); }
    } else {
        while (text.len > 0 and (text[0] == '~' or text[0] == '*' or text[0] == '$')) : (text = trim(text[1..])) {
            if (text[0] == '~') suppress = false;
            if (text[0] == '*') allow_extra = true;
        }
        var side: u8 = 0;
        if (text.len > 0 and (text[0] == '<' or text[0] == '>')) {
            side = text[0];
            text = trim(text[1..]);
        }
        if (side != 0 and text.len > 0 and isHotkeyModifier(text[0])) {
            physical_vk = switch (text[0]) {
                '!' => if (side == '<') 0xA4 else 0xA5,
                '^' => if (side == '<') 0xA2 else 0xA3,
                '+' => if (side == '<') 0xA0 else 0xA1,
                '#' => if (side == '<') 0x5B else 0x5C,
                else => 0,
            };
            physical_required = physicalModifierBits(physical_vk);
        }
        while (text.len > 0 and isHotkeyModifier(text[0])) : (text = trim(text[1..])) {
            mods |= switch (text[0]) { '^' => 1, '!' => 2, '+' => 4, '#' => 8, else => 0 };
        }
    }
    var trigger_kind: u8 = 0;
    if (text.len >= 3 and std.ascii.eqlIgnoreCase(text[text.len - 3 ..], " up")) {
        trigger_kind = 1;
        text = trim(text[0 .. text.len - 3]);
    }
    // AHK represents one literal backtick inside a quoted string as two
    // backticks.  The source reader intentionally preserves bytes, so decode
    // this key spelling at the semantic boundary before feeding QMKCore.
    const key = if (std.mem.eql(u8, text, "``")) "`" else text;
    const key_vk = modifierVk(key);
    mods |= collapsedModifierBit(key_vk);
    const forbidden: u16 = if (allow_extra) 0 else 0x0F & ~(mods);
    // Ordinary AHK modifier hotkeys use the collapsed modifier mask above;
    // they do not forbid the corresponding physical left/right keys.  Keep
    // the strict physical exclusion only for rows that explicitly name a
    // physical modifier (composite or side-specific syntax).
    const physical_forbidden: u8 = if (allow_extra or physical_vk == 0)
        0
    else
        0xFF & ~(physical_required | physicalModifierBits(key_vk));
    return .{ .key = key, .mods_required = mods, .mods_forbidden = forbidden, .trigger_kind = trigger_kind,
        .suppress_original = suppress, .physical_mod_vk = physical_vk, .physical_mods_required = physical_required,
        .physical_mods_forbidden = physical_forbidden };
}

const ActionPayload = struct { payload: []u8, action_kind: u8 };

const TapLayout = struct {
    context_index: ?usize,
    action_index: usize,
    hold_index: ?usize,
    threshold_index: ?usize,
    cleanup_index: ?usize,
    suspend_index: ?usize,
};

fn tapLayout(args: []const []const u8) !TapLayout {
    if (args.len < 2) return error.UnsupportedTap;
    const has_context = args.len >= 3 and isChordContextOrNonKey(args[1]);
    const action_index: usize = if (has_context) 2 else 1;
    var layout = TapLayout{
        .context_index = if (has_context) 1 else null,
        .action_index = action_index,
        .hold_index = null,
        .threshold_index = null,
        .cleanup_index = null,
        .suspend_index = null,
    };
    var next = action_index + 1;
    // The short optional form ends with the exemption boolean. A longer form
    // follows the AHK signature: hold callback, threshold, cleanup, exemption.
    if (next < args.len and parseLiteralBool(args[next]) != null and next + 1 == args.len) {
        layout.suspend_index = next;
        return layout;
    }
    if (next < args.len) {
        layout.hold_index = next;
        next += 1;
    }
    if (next < args.len) {
        layout.threshold_index = next;
        next += 1;
    }
    if (next < args.len) {
        layout.cleanup_index = next;
        next += 1;
    }
    if (next < args.len) layout.suspend_index = next;
    return layout;
}

fn actionPayload(gpa: std.mem.Allocator, action: []const u8) !?ActionPayload {
    // AHK combo/chord object rows may use a plain literal target.  Treat it
    // like the native text carried by a SendKeyDirect descriptor.
    if (isQuotedElement(action)) {
        const payload = try parseLiteralString(gpa, action);
        return .{ .payload = payload, .action_kind = 0 };
    }
    // Keep the established qualified-call path intact for QMK helpers.  The
    // bare AHK send functions below are a separate legacy native form.
    const qmk_names = [_][]const u8{ "SendKeyDirect", "SendDirect", "QMK.Tap" };
    for (qmk_names, 0..) |name, index| {
        if (findCallOpenIgnoreCase(action, name)) |open| {
            const close = findBalanced(action, open, '(', ')') orelse return null;
            const arg = trim(action[open + 1 .. close]);
            if (!isQuotedElement(arg)) return null;
            const payload = try parseLiteralString(gpa, arg);
            return .{ .payload = payload, .action_kind = if (index == 2) 1 else 0 };
        }
    }
    const direct_names = [_][]const u8{ "SendEvent", "SendInput", "Send" };
    for (direct_names) |name| {
        if (!isLiteralCall(action, name)) continue;
        const t = trim(action);
        const open = findCallOpenIgnoreCase(t, name) orelse return null;
        const close = findBalanced(t, open, '(', ')') orelse return null;
        const payload = try parseLiteralString(gpa, trim(t[open + 1 .. close]));
        return .{ .payload = payload, .action_kind = 1 };
    }
    return null;
}

fn emitTypedArtifacts(init: std.process.Init, gpa: std.mem.Allocator, sources: []const Source, rows: []Row, output_dir: std.Io.Dir) !void {
    try assignCallbackSlots(gpa, rows);
    var out = std.ArrayList(u8).empty;
    defer out.deinit(gpa);
    try out.appendSlice(gpa,
        \\//! Generated by the Zig user-shortcut transpiler.
        \\//! Complete-compiled mode: no QMK.Setup* calls are retained.
        \\pub fn u(comptime text: []const u8) []const u8 { return text; }
        \\pub const ContextKind = enum(u8) { global, menu, website, title, class, exe, browser, compound };
        \\pub const Context = struct { kind: ContextKind = .global, negated: bool = false, text: []const u16 = &.{}, specificity_mask: u8 = 0 };
        \\pub const NativeControlKind = enum { panic_exit, native_reload };
        \\pub const HotstringAction = enum { paste_withbackup, interception_text, ahk_callback };
        \\pub const HotstringOptions = packed struct(u16) { case_sensitive: bool = false, conform_to_case: bool = false, backspace: bool = true, omit_end_char: bool = false, require_end_char: bool = true, inside_word: bool = false, reset: bool = false, execute: bool = false, suspend_exempt: bool = false, enabled: bool = true, send_raw: bool = false, send_mode: u3 = 0, reserved: u2 = 0 };
        \\pub const Compiled_Native_Control_Row = struct { trigger: []const u8, mods_required: u16, mods_forbidden: u16, kind: NativeControlKind, enabled: bool };
        \\
    );
    const build_id = try std.fmt.allocPrint(gpa, "{X:0>8}", .{ahkBuildIdHash(sources)});
    defer gpa.free(build_id);
    try appendLine(gpa, &out, "pub const compiled_build_id = \"{s}\";\n", .{build_id});
    try appendLine(gpa, &out, "pub const compiled_source_count: usize = {d};\npub const compiled_row_count: usize = {d};\n\n", .{ sources.len, rows.len });

    try out.appendSlice(gpa, "pub const Compiled_Native_Controls = struct { pub const panic_exit = [_]Compiled_Native_Control_Row{\n");
    for (rows) |row| if (std.mem.eql(u8, row.classification, "native_control")) {
        var args = try splitRowArgs(gpa, rowArgumentText(row.source_text)); defer args.deinit(gpa);
        if (args.items.len < 1) return error.UnsupportedNativeControl;
        const spec = try parseLiteralString(gpa, args.items[0]); defer gpa.free(spec);
        const parts = parseHotkeySpec(spec);
        const control_text = if (args.items.len >= 3) quotedText(args.items[2]) else row.source_text;
        const is_panic = containsAny(control_text, &[_][]const u8{"panicExit"}) or containsAny(row.source_text, &[_][]const u8{"panicExit"});
        if (is_panic) {
            try out.appendSlice(gpa, "    .{ .trigger = "); try emitKey(gpa, &out, parts.key);
            try appendLine(gpa, &out, ", .mods_required = {d}, .mods_forbidden = {d}, .kind = .panic_exit, .enabled = true }},\n", .{parts.mods_required, parts.mods_forbidden});
        }
    };
    try out.appendSlice(gpa, "}; pub const native_reload = [_]Compiled_Native_Control_Row{\n");
    for (rows) |row| if (std.mem.eql(u8, row.classification, "native_control")) {
        var args = try splitRowArgs(gpa, rowArgumentText(row.source_text)); defer args.deinit(gpa);
        if (args.items.len < 1) return error.UnsupportedNativeControl;
        const spec = try parseLiteralString(gpa, args.items[0]); defer gpa.free(spec);
        const parts = parseHotkeySpec(spec);
        const control_text = if (args.items.len >= 3) quotedText(args.items[2]) else row.source_text;
        const is_reload = containsAny(control_text, &[_][]const u8{"nativeReload"}) or containsAny(row.source_text, &[_][]const u8{"nativeReload"});
        if (is_reload) {
            try out.appendSlice(gpa, "    .{ .trigger = "); try emitKey(gpa, &out, parts.key);
            try appendLine(gpa, &out, ", .mods_required = {d}, .mods_forbidden = {d}, .kind = .native_reload, .enabled = true }},\n", .{parts.mods_required, parts.mods_forbidden});
        }
    };
    try out.appendSlice(gpa, "}; };\n\n");

    try out.appendSlice(gpa, "pub const Compiled_Modifiers = struct { pub const Row = struct { key: []const u8, mod_type: i8, context: Context, suspend_exempt: bool }; pub const rows = [_]Row{\n");
    for (rows) |row| if (std.mem.eql(u8, row.family, "Modifiers")) {
        var args = try splitRowArgs(gpa, row.source_text); defer args.deinit(gpa);
        if (args.items.len < 2) return error.UnsupportedModifier;
        const key = try parseLiteralString(gpa, args.items[0]); defer gpa.free(key);
        const mod = try parseLiteralString(gpa, args.items[1]); defer gpa.free(mod);
        const mod_type: i8 = if (std.ascii.eqlIgnoreCase(mod, "Ctrl") or std.ascii.eqlIgnoreCase(mod, "Control")) 0 else if (std.ascii.eqlIgnoreCase(mod, "Alt")) 1 else if (std.ascii.eqlIgnoreCase(mod, "Shift")) 2 else if (std.ascii.eqlIgnoreCase(mod, "Win") or std.ascii.eqlIgnoreCase(mod, "Windows")) 3 else return error.UnsupportedModifier;
        const context_expr = if (args.items.len >= 3) args.items[2] else "\"global\"";
        const context = try parseContext(gpa, context_expr); defer gpa.free(context.text);
        const suspend_exempt = if (args.items.len >= 4) (parseLiteralBool(args.items[3]) orelse return error.UnsupportedModifier) else false;
        try out.appendSlice(gpa, "    .{ .key = "); try emitKey(gpa, &out, key);
        try appendLine(gpa, &out, ", .mod_type = {d}, .context = ", .{mod_type}); try emitContextParts(gpa, &out, context); try appendLine(gpa, &out, ", .suspend_exempt = {s} }},\n", .{if (suspend_exempt) "true" else "false"});
    };
    try out.appendSlice(gpa, "}; };\n\n");

    try out.appendSlice(gpa, "pub const Compiled_Passthroughs = struct { pub const Row = struct { key: []const u8, context: Context, suspend_exempt: bool }; pub const rows = [_]Row{\n");
    for (rows) |row| if (std.mem.eql(u8, row.family, "Passthroughs")) {
        var args = try splitRowArgs(gpa, row.source_text); defer args.deinit(gpa);
        if (args.items.len < 1) return error.UnsupportedPassthrough;
        const key = try parseLiteralString(gpa, args.items[0]); defer gpa.free(key);
        const context_expr = if (args.items.len >= 2) args.items[1] else "\"global\"";
        const context = try parseContext(gpa, context_expr); defer gpa.free(context.text);
        const suspend_exempt = if (args.items.len >= 3) (parseLiteralBool(args.items[2]) orelse return error.UnsupportedPassthrough) else false;
        try out.appendSlice(gpa, "    .{ .key = "); try emitKey(gpa, &out, key); try out.appendSlice(gpa, ", .context = "); try emitContextParts(gpa, &out, context); try appendLine(gpa, &out, ", .suspend_exempt = {s} }},\n", .{if (suspend_exempt) "true" else "false"});
    };
    try out.appendSlice(gpa, "}; };\n\n");

    try out.appendSlice(gpa, "pub const Compiled_Hotkeys = struct { pub const Row = struct { trigger: []const u8, mods_required: u16, mods_forbidden: u16, callback_id: i32, hold_callback_id: i32, cleanup_callback_id: i32, threshold_ticks: i64, trigger_kind: u8, action_kind: u8, suppress_original: bool, context: Context, physical_mod_vk: u8, physical_mods_required: u8, physical_mods_forbidden: u8, suspend_exempt: bool, callback: u8, native_payload: []const u16 = &.{} }; pub const rows = [_]Row{\n");
    for (rows) |row| if (std.mem.eql(u8, row.family, "Hotkeys")) {
        if (std.mem.eql(u8, row.classification, "native_control")) continue;
        var args = try splitRowArgs(gpa, row.source_text); defer args.deinit(gpa);
        if (args.items.len < 2) return error.UnsupportedHotkey;
        const spec = try parseLiteralString(gpa, args.items[0]); defer gpa.free(spec);
        const parts = parseHotkeySpec(spec);
        // Normalize both public shapes before emission:
        //   [spec, action]
        //   [spec, action, suspend_exempt]
        //   [spec, context, action]
        //   [spec, context, action, suspend_exempt]
        const has_context = args.items.len >= 3 and parseLiteralBool(args.items[2]) == null;
        const action_index: usize = if (has_context) 2 else 1;
        const context_expr = if (has_context) args.items[1] else "\"global\"";
        const context = try parseContext(gpa, context_expr); defer gpa.free(context.text);
        const suspend_index: usize = if (has_context and args.items.len >= 4) 3 else if (!has_context and args.items.len >= 3) 2 else 0;
        const action_text = args.items[action_index];
        const action_is_arrow = containsAny(action_text, &[_][]const u8{ "=>", "(*)" });
        const native_payload = if (action_is_arrow) null else try actionPayload(gpa, action_text);
        const suspend_exempt = (suspend_index != 0 and (parseLiteralBool(args.items[suspend_index]) orelse return error.UnsupportedHotkey)) or containsAny(action_text, &[_][]const u8{"QMK.SuspendExempt"});
            try out.appendSlice(gpa, "    .{ .trigger = "); try emitKey(gpa, &out, parts.key);
        try appendLine(gpa, &out, ", .mods_required = {d}, .mods_forbidden = {d}, .callback_id = ", .{ parts.mods_required, parts.mods_forbidden });
        if (!action_is_arrow and (std.mem.eql(u8, row.classification, "native") or std.mem.eql(u8, row.classification, "tap_descriptor") or native_payload != null)) {
            const payload = native_payload orelse {
                std.debug.print("unsupported hotkey action family={s} class={s} row={s} action={s}\\n", .{ row.family, row.classification, row.source_text, action_text });
                return error.UnsupportedHotkey;
            };
            defer gpa.free(payload.payload);
            try out.appendSlice(gpa, "-1, .hold_callback_id = -1, .cleanup_callback_id = -1, .threshold_ticks = 0, .trigger_kind = ");
            try appendLine(gpa, &out, "{d}, .action_kind = {d}, .suppress_original = ", .{ parts.trigger_kind, payload.action_kind });
            try out.appendSlice(gpa, if (parts.suppress_original) "true" else "false");
            try out.appendSlice(gpa, ", .context = "); try emitContextParts(gpa, &out, context);
            try appendLine(gpa, &out, ", .physical_mod_vk = {d}, .physical_mods_required = {d}, .physical_mods_forbidden = {d}, .suspend_exempt = {s}, .callback = 0, .native_payload = ", .{ parts.physical_mod_vk, parts.physical_mods_required, parts.physical_mods_forbidden, if (suspend_exempt) "true" else "false" });
            try emitU16(gpa, &out, payload.payload);
        } else {
            try appendLine(gpa, &out, "{d}, .hold_callback_id = -1, .cleanup_callback_id = -1, .threshold_ticks = 0, .trigger_kind = {d}, .action_kind = 0, .suppress_original = ", .{callbackSlot(row), parts.trigger_kind});
            try out.appendSlice(gpa, if (parts.suppress_original) "true" else "false");
            try out.appendSlice(gpa, ", .context = "); try emitContextParts(gpa, &out, context);
            try appendLine(gpa, &out, ", .physical_mod_vk = {d}, .physical_mods_required = {d}, .physical_mods_forbidden = {d}, .suspend_exempt = {s}, .callback = 0, .native_payload = &.{{ 0 }}", .{ parts.physical_mod_vk, parts.physical_mods_required, parts.physical_mods_forbidden, if (suspend_exempt) "true" else "false" });
        }
        try out.appendSlice(gpa, " },\n");
    };
    try out.appendSlice(gpa, "}; };\n\n");

    try out.appendSlice(gpa, "pub const Compiled_Holds = struct { pub const Row = struct { key: []const u8, callback_id: i32, context: Context, suspend_exempt: bool }; pub const rows = [_]Row{\n");
    for (rows) |row| if (std.mem.eql(u8, row.family, "Holds")) {
        var args = try splitRowArgs(gpa, row.source_text); defer args.deinit(gpa);
        if (args.items.len < 2) return error.UnsupportedHold;
        const key = try parseLiteralString(gpa, args.items[0]); defer gpa.free(key);
        const has_context = args.items.len >= 3 and parseLiteralBool(args.items[2]) == null;
        const context_expr = if (has_context) args.items[1] else "\"global\"";
        const context = try parseContext(gpa, context_expr); defer gpa.free(context.text);
        const suspend_index: usize = if (has_context and args.items.len >= 4) 3 else if (!has_context and args.items.len >= 3) 2 else 0;
        const suspend_exempt = if (suspend_index != 0) (parseLiteralBool(args.items[suspend_index]) orelse return error.UnsupportedHold) else false;
        if (callbackSlot(row) < 0) return error.UnsupportedHold;
        try out.appendSlice(gpa, "    .{ .key = "); try emitKey(gpa, &out, key); try appendLine(gpa, &out, ", .callback_id = {d}, .context = ", .{callbackSlot(row)}); try emitContextParts(gpa, &out, context); try appendLine(gpa, &out, ", .suspend_exempt = {s} }},\n", .{if (suspend_exempt) "true" else "false"});
    };
    try out.appendSlice(gpa, "}; };\n\n");
    try out.appendSlice(gpa, "pub const Compiled_Double_Taps = struct { pub const Row = struct { key: []const u8, callback_id: i32, context: Context, suspend_exempt: bool }; pub const rows = [_]Row{\n");
    for (rows) |row| if (std.mem.eql(u8, row.family, "DoubleTaps")) {
        var args = try splitRowArgs(gpa, row.source_text); defer args.deinit(gpa);
        if (args.items.len < 2) return error.UnsupportedDoubleTap;
        const key = try parseLiteralString(gpa, args.items[0]); defer gpa.free(key);
        const has_context = args.items.len >= 3 and parseLiteralBool(args.items[2]) == null;
        const context_expr = if (has_context) args.items[1] else "\"global\"";
        const context = try parseContext(gpa, context_expr); defer gpa.free(context.text);
        const suspend_index: usize = if (has_context and args.items.len >= 4) 3 else if (!has_context and args.items.len >= 3) 2 else 0;
        const suspend_exempt = if (suspend_index != 0) (parseLiteralBool(args.items[suspend_index]) orelse return error.UnsupportedDoubleTap) else false;
        if (callbackSlot(row) < 0) return error.UnsupportedDoubleTap;
        try out.appendSlice(gpa, "    .{ .key = "); try emitKey(gpa, &out, key); try appendLine(gpa, &out, ", .callback_id = {d}, .context = ", .{callbackSlot(row)}); try emitContextParts(gpa, &out, context); try appendLine(gpa, &out, ", .suspend_exempt = {s} }},\n", .{if (suspend_exempt) "true" else "false"});
    };
    try out.appendSlice(gpa, "}; };\n\n");
    try out.appendSlice(gpa, "pub const Compiled_Taps = struct { pub const Row = Compiled_Hotkeys.Row; pub const rows = [_]Row{\n");
    for (rows) |row| if (std.mem.eql(u8, row.family, "Taps")) {
        var args = try splitRowArgs(gpa, row.source_text); defer args.deinit(gpa);
        if (args.items.len < 2) return error.UnsupportedTap;
        const key = try parseLiteralString(gpa, args.items[0]); defer gpa.free(key);
        const parts = parseHotkeySpec(key);
        const layout = try tapLayout(args.items);
        const context_expr = if (layout.context_index) |index| args.items[index] else "\"global\"";
        const context = try parseContext(gpa, context_expr); defer gpa.free(context.text);
        const tap_callback = callbackSlotForPart(row, 0);
        const hold_callback = callbackSlotForPart(row, 1);
        const cleanup_callback = callbackSlotForPart(row, 2);
        const action = if (tap_callback >= 0) null else (try actionPayload(gpa, args.items[layout.action_index])) orelse return error.UnsupportedTap;
        defer if (action) |payload| gpa.free(payload.payload);
        const threshold = if (layout.threshold_index) |index| (parseLiteralInt(args.items[index]) orelse return error.UnsupportedTap) else 0;
        const suspend_exempt = if (layout.suspend_index) |index| (parseLiteralBool(args.items[index]) orelse return error.UnsupportedTap) else false;
        try out.appendSlice(gpa, "    .{ .trigger = "); try emitKey(gpa, &out, parts.key); try appendLine(gpa, &out, ", .mods_required = {d}, .mods_forbidden = {d}, .callback_id = {d}, .hold_callback_id = {d}, .cleanup_callback_id = {d}, .threshold_ticks = {d}, .trigger_kind = {d}, .action_kind = 1, .suppress_original = {s}, .context = ", .{ parts.mods_required, parts.mods_forbidden, tap_callback, hold_callback, cleanup_callback, threshold, parts.trigger_kind, if (parts.suppress_original) "true" else "false" }); try emitContextParts(gpa, &out, context); try appendLine(gpa, &out, ", .physical_mod_vk = {d}, .physical_mods_required = {d}, .physical_mods_forbidden = {d}, .suspend_exempt = {s}, .callback = 0, .native_payload = ", .{ parts.physical_mod_vk, parts.physical_mods_required, parts.physical_mods_forbidden, if (suspend_exempt) "true" else "false" });
        if (action) |payload| try emitU16(gpa, &out, payload.payload) else try out.appendSlice(gpa, "&.{ 0 }");
        try out.appendSlice(gpa, " },\n");
    };
    try out.appendSlice(gpa, "}; };\n\n");
    try out.appendSlice(gpa, "pub const Compiled_Tap_Holds = struct { pub const Row = struct { key: []const u8, tap_callback_id: i32, hold_callback_id: i32, cleanup_callback_id: i32, threshold_ticks: i64, context: Context, suspend_exempt: bool }; pub const rows = [_]Row{\n");
    for (rows) |row| if (std.mem.eql(u8, row.family, "TapHolds")) {
        var args = try splitRowArgs(gpa, row.source_text); defer args.deinit(gpa);
        if (args.items.len < 5) return error.UnsupportedTapHold;
        const key = try parseLiteralString(gpa, args.items[0]); defer gpa.free(key);
        const context = try parseContext(gpa, args.items[1]); defer gpa.free(context.text);
        const threshold = parseLiteralInt(args.items[2]) orelse return error.UnsupportedTapHold;
        const suspend_index: usize = if (args.items.len >= 7) 6 else 0;
        const suspend_exempt = if (suspend_index != 0) (parseLiteralBool(args.items[suspend_index]) orelse return error.UnsupportedTapHold) else false;
        try out.appendSlice(gpa, "    .{ .key = "); try emitKey(gpa, &out, key); try appendLine(gpa, &out, ", .tap_callback_id = {d}, .hold_callback_id = {d}, .cleanup_callback_id = {d}, .threshold_ticks = {d}, .context = ", .{callbackSlotForPart(row, 0), callbackSlotForPart(row, 1), if (args.items.len >= 6) callbackSlotForPart(row, 2) else @as(i32, -1), threshold}); try emitContextParts(gpa, &out, context); try appendLine(gpa, &out, ", .suspend_exempt = {s} }},\n", .{if (suspend_exempt) "true" else "false"});
    };
    try out.appendSlice(gpa, "}; };\n\n");
    try out.appendSlice(gpa, "pub const ComboMode = enum(u8) { normal_callback, instant_callback, internal_remap, internal_instant_remap }; pub const Compiled_Combos = struct { pub const Row = struct { primary: []const u8, secondary: []const u8, callback_id: i32, target: []const u8, mod_mask: u16, mode: ComboMode, context: Context, suspend_exempt: bool, registration_order: u32 }; ");
    const combo_modes = [_][]const u8{ "normal_callback", "instant_callback", "internal_remap", "internal_instant_remap" };
    for (combo_modes) |wanted_mode| {
        try appendLine(gpa, &out, "pub const {s} = [_]Row{{\n", .{wanted_mode});
        for (rows) |row| if (std.mem.eql(u8, row.family, "Combos")) {
            var args = try splitRowArgs(gpa, row.source_text); defer args.deinit(gpa);
            if (args.items.len < 3) return error.UnsupportedCombo;
            const actual_mode = comboModeName(row.classification, args.items);
            if (!std.mem.eql(u8, actual_mode, wanted_mode)) continue;
            const primary = try parseLiteralString(gpa, args.items[0]); defer gpa.free(primary);
            const secondary = try parseLiteralString(gpa, args.items[1]); defer gpa.free(secondary);
            const has_context = args.items.len >= 4 and isChordContextOrNonKey(args.items[2]);
            const context_expr = if (has_context) args.items[2] else "\"global\"";
            const context = try parseContext(gpa, context_expr); defer gpa.free(context.text);
            const mod_text = if (args.items.len >= 6 and isQuotedElement(args.items[5])) quotedText(args.items[5]) else "";
            const explicit_mods = modifierMask(mod_text);
            const suspend_exempt = if (args.items.len >= 7) (parseLiteralBool(args.items[6]) orelse return error.UnsupportedCombo) else false;
            try out.appendSlice(gpa, "    .{ .primary = "); try emitKey(gpa, &out, primary); try out.appendSlice(gpa, ", .secondary = "); try emitKey(gpa, &out, secondary);
            if (std.mem.eql(u8, row.classification, "callback")) {
                try appendLine(gpa, &out, ", .callback_id = {d}, .target = u(\"\"), .mod_mask = {d}, .mode = .{s}, .context = ", .{callbackSlot(row), explicit_mods, wanted_mode});
            } else {
                const action_index: usize = if (has_context) 3 else 2;
                const payload = (try actionPayload(gpa, args.items[action_index])) orelse return error.UnsupportedCombo;
                defer gpa.free(payload.payload);
                const target = try parseSendTarget(payload.payload, explicit_mods);
                try appendLine(gpa, &out, ", .callback_id = -1, .target = ", .{}); try emitKey(gpa, &out, target.key);
                try appendLine(gpa, &out, ", .mod_mask = {d}, .mode = .{s}, .context = ", .{target.mod_mask, wanted_mode});
            }
             try emitContextParts(gpa, &out, context); try appendLine(gpa, &out, ", .suspend_exempt = {s}, .registration_order = {d} }},\n", .{if (suspend_exempt) "true" else "false", row.source_order});
        };
        try out.appendSlice(gpa, "}; ");
    }
    try out.appendSlice(gpa, "};\n\n");
    try out.appendSlice(gpa, "pub const Compiled_Chords = struct { pub const Row = struct { keys: [5][]const u8, key_count: u8, callback_id: i32, target: []const u8, mod_mask: u16, context: Context, suspend_exempt: bool }; pub const external_callback = [_]Row{\n");
    for (rows) |row| if (std.mem.eql(u8, row.family, "Chords")) {
        var args = try splitRowArgs(gpa, row.source_text); defer args.deinit(gpa);
        const tail = try chordTail(args.items, row.chord_normalized);
        if (!std.mem.eql(u8, row.classification, "callback")) continue;
        try out.appendSlice(gpa, "    .{ .keys = .{ ");
        var key_index: usize = 0; var emitted: usize = 0;
        while (key_index < tail.action_index and emitted < 5) : (key_index += 1) {
            if (tail.context_index) |context_index| if (key_index >= context_index) break;
            const key = try parseLiteralString(gpa, args.items[key_index]); defer gpa.free(key);
            if (key.len == 0) continue;
            if (emitted != 0) try out.appendSlice(gpa, ", "); try emitKey(gpa, &out, key); emitted += 1;
        }
        const key_count = emitted;
        while (emitted < 5) : (emitted += 1) { if (emitted != 0) try out.appendSlice(gpa, ", "); try out.appendSlice(gpa, "u(\"\")"); }
        try appendLine(gpa, &out, " }}, .key_count = {d}, .callback_id = {d}, .target = u(\"\"), .mod_mask = {d}, .context = ", .{key_count, callbackSlot(row), tail.mod_mask});
        const context = try parseContext(gpa, if (tail.context_index) |index| args.items[index] else "\"global\""); defer gpa.free(context.text);
        try emitContextParts(gpa, &out, context); try appendLine(gpa, &out, ", .suspend_exempt = {s} }},\n", .{if (tail.suspend_exempt) "true" else "false"});
    };
    try out.appendSlice(gpa, "};\n");
    try out.appendSlice(gpa, "pub const internal_remap = [_]Row{\n");
    for (rows) |row| if (std.mem.eql(u8, row.family, "Chords")) {
        var args = try splitRowArgs(gpa, row.source_text); defer args.deinit(gpa);
        const tail = try chordTail(args.items, row.chord_normalized);
        if (!std.mem.eql(u8, row.classification, "native")) continue;
        try out.appendSlice(gpa, "    .{ .keys = .{ ");
        var key_index: usize = 0; var emitted: usize = 0;
        while (key_index < tail.action_index and emitted < 5) : (key_index += 1) {
            if (tail.context_index) |context_index| if (key_index >= context_index) break;
            const key = try parseLiteralString(gpa, args.items[key_index]); defer gpa.free(key);
            if (key.len == 0) continue;
            if (emitted != 0) try out.appendSlice(gpa, ", "); try emitKey(gpa, &out, key); emitted += 1;
        }
        const key_count = emitted;
        while (emitted < 5) : (emitted += 1) { if (emitted != 0) try out.appendSlice(gpa, ", "); try out.appendSlice(gpa, "u(\"\")"); }
        const payload = (try actionPayload(gpa, args.items[tail.action_index])) orelse return error.UnsupportedChord; defer gpa.free(payload.payload);
        const target = try parseSendTarget(payload.payload, tail.mod_mask);
        try out.appendSlice(gpa, " }, .key_count = "); try appendLine(gpa, &out, "{d}, .callback_id = -1, .target = ", .{key_count}); try emitKey(gpa, &out, target.key); try appendLine(gpa, &out, ", .mod_mask = {d}, .context = ", .{target.mod_mask});
        const context = try parseContext(gpa, if (tail.context_index) |index| args.items[index] else "\"global\""); defer gpa.free(context.text);
        try emitContextParts(gpa, &out, context); try appendLine(gpa, &out, ", .suspend_exempt = {s} }},\n", .{if (tail.suspend_exempt) "true" else "false"});
    };
    try out.appendSlice(gpa, "}; };\n\n");
    try out.appendSlice(gpa, "pub const Compiled_Hotstrings = struct { pub const Row = struct { trigger: []const u8, replacement: []const u16, callback_id: i32, action: HotstringAction, options: HotstringOptions, context: Context, source_order: u32 }; pub const rows = [_]Row{\n");
    for (rows) |row| if (std.mem.eql(u8, row.family, "Hotstrings")) {
        var args = try splitRowArgs(gpa, row.source_text); defer args.deinit(gpa);
        if (args.items.len < 2) return error.UnsupportedHotstring;
        const trigger_storage = try parseLiteralString(gpa, args.items[0]); defer gpa.free(trigger_storage);
        var trigger = trigger_storage;
        var option_text: []const u8 = "";
        if (trigger.len > 0 and trigger[0] == ':') {
            const close = std.mem.indexOfScalarPos(u8, trigger, 1, ':') orelse return error.UnsupportedHotstring;
            option_text = trigger[1..close];
            trigger = trigger[close + 1..];
        }
        if (trigger.len == 0) return error.UnsupportedHotstring;
        const has_context = args.items.len >= 3 and parseLiteralBool(args.items[2]) == null;
        const action_index: usize = if (has_context) 2 else 1;
        const context_expr = if (has_context) args.items[1] else "\"global\"";
        const context = try parseContext(gpa, context_expr); defer gpa.free(context.text);
        var options = parseHotstringOptions(option_text);
        const callback = !isQuotedElement(args.items[action_index]);
        const suspend_index: usize = if (has_context and args.items.len >= 4) 3 else if (!has_context and args.items.len >= 3) 2 else 0;
        if (suspend_index != 0) options.suspend_exempt = options.suspend_exempt or (parseLiteralBool(args.items[suspend_index]) orelse return error.UnsupportedHotstring);
        try out.appendSlice(gpa, "    .{ .trigger = "); try emitU8(gpa, &out, trigger); try out.appendSlice(gpa, ", .replacement = ");
        if (callback) try out.appendSlice(gpa, "&.{ 0 }") else { const replacement = try parseLiteralString(gpa, args.items[action_index]); defer gpa.free(replacement); try emitU16(gpa, &out, replacement); }
        try appendLine(gpa, &out, ", .callback_id = {d}, .action = .{s}, .options = ", .{if (callback) callbackSlot(row) else @as(i32, -1), if (callback) "ahk_callback" else "paste_withbackup"});
         try emitHotstringOptions(gpa, &out, options); try out.appendSlice(gpa, ", .context = "); try emitContextParts(gpa, &out, context); try appendLine(gpa, &out, ", .source_order = {d} }},\n", .{row.source_order});
    };
    try out.appendSlice(gpa, "}; };\n\n");
    try out.appendSlice(gpa, "pub const AhkCallback = struct { bridge_id: i32, name: []const u8 };\npub const CallbackKind = enum { ahk };\npub const CallbackDescriptor = struct { slot: u32, kind: CallbackKind, ahk: AhkCallback };\npub const Compiled_Callbacks = struct { pub const native = [_]CallbackDescriptor{}; pub const zig = [_]CallbackDescriptor{}; pub const ahk = [_]CallbackDescriptor{\n");
    var descriptor_seen = std.AutoHashMap(i32, void).init(gpa);
    defer descriptor_seen.deinit();
    for (rows) |row| if (std.mem.eql(u8, row.classification, "callback")) {
        const part_count = callbackPartCount(row);
        for (0..part_count) |part| {
            if (callbackExpressionForPart(row, @intCast(part)) == null) continue;
            const slot = callbackSlotForPart(row, @intCast(part));
            if (slot < 0 or descriptor_seen.contains(slot)) continue;
            try descriptor_seen.put(slot, {});
            try out.appendSlice(gpa, "    .{ .slot = ");
            try appendLine(gpa, &out, "{d}", .{slot});
            try out.appendSlice(gpa, ", .kind = .ahk, .ahk = .{ .bridge_id = ");
            try appendLine(gpa, &out, "{d}", .{slot});
            try out.appendSlice(gpa, ", .name = \"");
            try appendCallbackName(gpa, &out, slot);
            try out.appendSlice(gpa, "\" } },\n");
        }
    };
    try out.appendSlice(gpa, "}; };\npub const Compiled_Source_Order = [_]u32{");
    for (rows, 0..) |row, index| {
        if (index != 0) try out.appendSlice(gpa, ", ");
        try appendLine(gpa, &out, "{d}", .{row.source_order});
    }
    try out.appendSlice(gpa, "};\n");
    try output_dir.writeFile(init.io, .{ .sub_path = "generated_user_shortcuts.zig", .data = out.items });
    var ahk = std.ArrayList(u8).empty;
    defer ahk.deinit(gpa);
    try ahk.appendSlice(gpa, "#Requires AutoHotkey v2.0\n; Generated callback bridge for the Zig transpiler.\n");
    try ahk.appendSlice(gpa, "; Complete-compiled mode callback map.\n");
    var ahk_seen = std.AutoHashMap(i32, void).init(gpa);
    defer ahk_seen.deinit();
    for (rows) |row| if (std.mem.eql(u8, row.classification, "callback")) {
        const part_count = callbackPartCount(row);
        for (0..part_count) |part| {
            const expression = callbackExpressionForPart(row, @intCast(part)) orelse continue;
            const slot = callbackSlotForPart(row, @intCast(part));
            if (slot < 0 or ahk_seen.contains(slot)) continue;
            const wrapper = callbackWrapperParts(expression) orelse continue;
            try ahk_seen.put(slot, {});
            try ahk.appendSlice(gpa, "\n");
             try appendCallbackName(gpa, &ahk, slot);
            try ahk.appendSlice(gpa, "(");
            try ahk.appendSlice(gpa, wrapper.params);
            try ahk.appendSlice(gpa, ")\n{\n    return ");
            try appendAhkBody(gpa, &ahk, wrapper.body);
            if (wrapper.is_reference) try ahk.appendSlice(gpa, "()");
            try ahk.appendSlice(gpa, "\n}\n");
        }
    };
    try ahk.appendSlice(gpa, "\nQMKCompiledCallbackMap := Map(\n");
    var map_seen = std.AutoHashMap(i32, void).init(gpa);
    defer map_seen.deinit();
    var map_count: usize = 0;
    for (rows) |row| if (std.mem.eql(u8, row.classification, "callback")) {
        const part_count = callbackPartCount(row);
        for (0..part_count) |part| {
            if (callbackExpressionForPart(row, @intCast(part)) == null) continue;
            const slot = callbackSlotForPart(row, @intCast(part));
            if (slot < 0 or map_seen.contains(slot)) continue;
            try map_seen.put(slot, {});
            if (map_count != 0) try ahk.appendSlice(gpa, ",\n");
            try ahk.appendSlice(gpa, "    (QMK.COMPILED_CALLBACK_ID_BASE - ");
            try appendLine(gpa, &ahk, "{d}", .{slot});
            try ahk.appendSlice(gpa, "), ");
             try appendCallbackName(gpa, &ahk, slot);
            map_count += 1;
        }
    };
    try ahk.appendSlice(gpa, "\n)\nQMK.InstallCompiledCallbackMap(QMKCompiledCallbackMap)\n");
    try output_dir.writeFile(init.io, .{ .sub_path = "user_callbacks.ahk", .data = ahk.items });
    for (sources, 0..) |_, source_index| {
        try emitSourceCallbackFile(init, gpa, rows, source_index, output_dir);
    }
}

fn emitSourceCallbackFile(init: std.process.Init, gpa: std.mem.Allocator, rows: []const Row, source_index: usize, output_dir: std.Io.Dir) !void {
    var ahk = std.ArrayList(u8).empty;
    defer ahk.deinit(gpa);
    try ahk.appendSlice(gpa, "#Requires AutoHotkey v2.0\n; Generated callback bridge for one Zig source file.\n");
    try ahk.appendSlice(gpa, "; This map is a source-specific slice of the global callback-slot space.\n");
    var seen = std.AutoHashMap(i32, void).init(gpa);
    defer seen.deinit();
    for (rows) |row| if (row.source_index == source_index and std.mem.eql(u8, row.classification, "callback")) {
        const part_count = callbackPartCount(row);
        for (0..part_count) |part| {
            const expression = callbackExpressionForPart(row, @intCast(part)) orelse continue;
            const slot = callbackSlotForPart(row, @intCast(part));
            if (slot < 0 or seen.contains(slot)) continue;
            const wrapper = callbackWrapperParts(expression) orelse continue;
            try seen.put(slot, {});
            try ahk.appendSlice(gpa, "\n");
             try appendSourceCallbackName(gpa, &ahk, source_index, slot);
            try ahk.appendSlice(gpa, "(");
            try ahk.appendSlice(gpa, wrapper.params);
            try ahk.appendSlice(gpa, ")\n{\n    return ");
            try appendAhkBody(gpa, &ahk, wrapper.body);
            if (wrapper.is_reference) try ahk.appendSlice(gpa, "()");
            try ahk.appendSlice(gpa, "\n}\n");
        }
    };
    var map_name: [64]u8 = undefined;
    const map_name_text = try std.fmt.bufPrint(&map_name, "QMKCompiledCallbackMap_{d:0>3}", .{source_index + 1});
    try ahk.appendSlice(gpa, "\n");
    try ahk.appendSlice(gpa, map_name_text);
    try ahk.appendSlice(gpa, " := Map(\n");
    var map_count: usize = 0;
    seen.clearRetainingCapacity();
    for (rows) |row| if (row.source_index == source_index and std.mem.eql(u8, row.classification, "callback")) {
        const part_count = callbackPartCount(row);
        for (0..part_count) |part| {
            if (callbackExpressionForPart(row, @intCast(part)) == null) continue;
            const slot = callbackSlotForPart(row, @intCast(part));
            if (slot < 0 or seen.contains(slot)) continue;
            try seen.put(slot, {});
            if (map_count != 0) try ahk.appendSlice(gpa, ",\n");
            try ahk.appendSlice(gpa, "    (QMK.COMPILED_CALLBACK_ID_BASE - ");
            try appendLine(gpa, &ahk, "{d}", .{slot});
            try ahk.appendSlice(gpa, "), ");
             try appendSourceCallbackName(gpa, &ahk, source_index, slot);
            map_count += 1;
        }
    };
    try ahk.appendSlice(gpa, "\n)\nQMK.InstallCompiledCallbackMap(");
    try ahk.appendSlice(gpa, map_name_text);
    try ahk.appendSlice(gpa, ")\n");
    var file_name: [64]u8 = undefined;
    const file_name_text = try std.fmt.bufPrint(&file_name, "user_callbacks_{d:0>3}.ahk", .{source_index + 1});
    try output_dir.writeFile(init.io, .{ .sub_path = file_name_text, .data = ahk.items });
}

fn readSourceFile(init: std.process.Init, gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    const limit = std.Io.Limit.limited(64 * 1024 * 1024);
    if (std.fs.path.isAbsolute(path)) {
        const parent = std.fs.path.dirname(path) orelse return error.InvalidSourcePath;
        var dir = try std.Io.Dir.openDirAbsolute(init.io, parent, .{});
        defer dir.close(init.io);
        return dir.readFileAlloc(init.io, std.fs.path.basename(path), gpa, limit);
    }
    return std.Io.Dir.cwd().readFileAlloc(init.io, path, gpa, limit);
}

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var fixture_mode = false;
    var emit_mode = false;
    var diagnose_mode = false;
    var explicit_sources = false;
    var output_path: []const u8 = "candidate_data\\zig_user_shortcut_transpiler\\out";
    var source_paths = std.ArrayList([]const u8).empty;
    defer source_paths.deinit(gpa);
    var arg_index: usize = 1;
    while (arg_index < args.len) : (arg_index += 1) {
        const arg = args[arg_index];
        if (std.mem.eql(u8, arg, "--fixture")) {
            fixture_mode = true;
        } else if (std.mem.eql(u8, arg, "--emit")) {
            emit_mode = true;
        } else if (std.mem.eql(u8, arg, "--diagnose")) {
            diagnose_mode = true;
        } else if (std.mem.eql(u8, arg, "--source")) {
            if (arg_index + 1 >= args.len) return error.MissingSourceArgument;
            explicit_sources = true;
            arg_index += 1;
            try source_paths.append(gpa, args[arg_index]);
        } else if (std.mem.eql(u8, arg, "--output-dir")) {
            if (arg_index + 1 >= args.len) return error.MissingOutputArgument;
            arg_index += 1;
            output_path = args[arg_index];
        } else {
            return error.UnknownArgument;
        }
    }
    if (!explicit_sources) {
        if (fixture_mode) {
            try source_paths.append(gpa, "candidate_data\\zig_user_shortcut_transpiler\\fixtures\\full_native_smoke.ahk");
        } else {
            try source_paths.appendSlice(gpa, &[_][]const u8{
                "production_code\\QMKHotkeys.ahk", "production_code\\QMK Shortcuts.ahk", "production_code\\Hotstrings.ahk", "production_code\\8BitDo_QMK.ahk",
            });
        }
    }

    try std.Io.Dir.cwd().createDirPath(init.io, output_path);
    var output_dir = if (std.fs.path.isAbsolute(output_path))
        try std.Io.Dir.openDirAbsolute(init.io, output_path, .{})
    else
        try std.Io.Dir.cwd().openDir(init.io, output_path, .{});
    defer output_dir.close(init.io);

    var sources = std.ArrayList(Source).empty;
    defer {
        for (sources.items) |source| gpa.free(source.bytes);
        sources.deinit(gpa);
    }
    for (source_paths.items) |path| {
        const bytes = try readSourceFile(init, gpa, path);
        try sources.append(gpa, .{ .path = path, .bytes = bytes });
    }

    var rows = std.ArrayList(Row).empty;
    defer {
        for (rows.items) |row| if (row.owned_source) |owned| gpa.free(owned);
        rows.deinit(gpa);
    }
    for (sources.items, 0..) |source, source_index| try scanSource(gpa, source, source_index, &rows);

    var unknown_count: usize = 0;
    for (rows.items) |row| {
        if (!std.mem.eql(u8, row.classification, "unknown")) continue;
        if (diagnose_mode and unknown_count < 80) std.debug.print("UNKNOWN {s}|{d}|{s}\n", .{ row.family, row.row_index, row.source_text });
        unknown_count += 1;
    }
    if (diagnose_mode) {
        std.debug.print("unknown_count={d}\n", .{unknown_count});
    }
    try emitManifest(init, gpa, sources.items, rows.items, output_dir);
    if (emit_mode and unknown_count != 0) return error.UnsupportedRows;
    if (emit_mode) {
        try emitTypedArtifacts(init, gpa, sources.items, rows.items, output_dir);
        std.debug.print("checkpoint 2 emitted typed artifact with {d} rows\n", .{rows.items.len});
    } else {
        std.debug.print("checkpoint 1 captured {d} rows from {d} sources\n", .{ rows.items.len, sources.items.len });
    }
}

test "normalized singular chords preserve three-versus-four key arity" {
    const cases = [_]struct { source: []const u8, key_count: usize }{
        .{ .source = "[\"a\", \"s\", \"d\"], \"global\", (*) => ToolTip(\"three\")", .key_count = 3 },
        .{ .source = "[\"a\", \"s\", \"d\", \"f\"], \"global\", (*) => ToolTip(\"four\")", .key_count = 4 },
    };
    for (cases) |case| {
        const normalized = (try normalizeChordArraySource(std.testing.allocator, "Chords", case.source)) orelse return error.TestUnexpectedResult;
        defer std.testing.allocator.free(normalized);
        var args = try splitRowArgs(std.testing.allocator, normalized);
        defer args.deinit(std.testing.allocator);
        const tail = try chordTail(args.items, true);
        try std.testing.expect(tail.context_index != null);
        try std.testing.expectEqual(case.key_count, tail.context_index.?);
    }

    const raw_cases = [_]struct { source: []const u8, key_count: usize }{
        .{ .source = "[\"a\", \"s\", \"d\", \"global\", (*) => ToolTip(\"three\")]", .key_count = 3 },
        .{ .source = "[\"a\", \"s\", \"d\", \"f\", \"global\", (*) => ToolTip(\"four\")]", .key_count = 4 },
    };
    for (raw_cases) |case| {
        var args = try splitRowArgs(std.testing.allocator, case.source);
        defer args.deinit(std.testing.allocator);
        const tail = try chordTail(args.items, false);
        try std.testing.expect(tail.context_index != null);
        try std.testing.expectEqual(case.key_count, tail.context_index.?);
    }
}
