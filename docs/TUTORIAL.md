# QMK.ahk Tutorial

This tutorial is the sanitized reference for the public API. The examples are intentionally small so you can copy individual patterns into your own shortcut file.

Callback names in these examples—such as `ActivateExampleApp()`, `ShowExampleMedia()`, and `MoveExampleWindow()`—are generic placeholders. Replace them with functions from your own AutoHotkey setup.

Before using these snippets, include the repository-root `QMKInterception.ahk` file from your own AutoHotkey script.

## Optional Interception driver setup

The tutorial works with the driver-free `llhook` and `sendinput` paths. If you choose an `interception` backend, install the driver from the [official Interception releases](https://github.com/oblitum/Interception/releases) page:

1. Unblock the downloaded archive in **Properties** if Windows offers that option.
2. Open **Command Prompt as administrator** in the extracted `command line installer` directory.
3. Run `install-interception.exe`, then run `install-interception.exe /install` as instructed by the installer.
4. Select `auto` or `interception` in **QMK Settings**.

For devices that freeze after reconnecting or waking from sleep, consult the separate [Interception driver fix](https://github.com/hygorostrowskij/interception-driver-fix). It is installed separately and is not part of this QMK.ahk package. Read the [full installation and safety guide](INSTALL.md) before enabling driver-backed blocking.

## Before you start: add safety controls

The reference file recommends these four shortcuts first:

```ahk
QMK.SetupHotkeys([
    ["*#Escape", "global", "panicExit", true],
    ["*^+r", "global", "nativeReload", true],
    ["^!s", "global", QMK.SuspendExempt((*) => QMK.Suspend())],
    ["F1", "global", (*) => QMKUserConfig.ShowGui()],
])
```

They give you emergency exit, reload, suspend/resume, and a shortcut to QMK Settings. Keeping exit/reload suspend-exempt is useful if an AutoHotkey routine becomes unresponsive.

---

# 1. Modifiers

Virtual modifiers—often called **home-row modifiers**—let an ordinary key behave like Ctrl, Shift, Alt, or Win while held.

```ahk
QMK.SetupModifiers([
    ["a", "Ctrl"],
    ["s", "Shift"],
    ["d", "Win"],
    ["f", "Alt"],
    ["j", "Alt"],
    ["k", "Win"],
    ["l", "Shift"],
    [";", "Ctrl"],
])
```

With the first row, `a+t` can behave like Ctrl+T while a normal tap still types `a`.

Modifiers can also chain. For example, if `A` is Ctrl and `S` is Shift, holding both while pressing another key can produce Ctrl+Shift+that key.

### Shape

```ahk
[key, modifierName]
[key, modifierName, context]
[key, modifierName, context, suspendExempt]
```

| Parameter | Meaning |
|---|---|
| `key` | Physical key that becomes a virtual modifier. |
| `modifierName` | Common values: `Ctrl`, `Shift`, `Alt`, `Win`. |
| `context` | Optional scope. `global` is implied by default. |
| `suspendExempt` | Optional boolean. `true` keeps the modifier active while QMK is suspended. |

For startup efficiency and readability, group related mappings into one `QMK.SetupModifiers()` call rather than registering them one at a time.

---

# 2. Contexts

QMK mappings can be scoped in a way similar to AutoHotkey `#HotIf` conditions.

```ahk
QMK.SetupModifiers([
    ["CapsLock", "Ctrl", "ahk_exe Code.exe, ahk_class Chrome_WidgetWin_1 ahk_exe msedge.exe"],
    ["CapsLock", "Escape", "ahk_class Chrome_WidgetWin_1 ahk_exe chrome.exe"],
])
```

The tutorial's examples show:

- `global`
- `ahk_exe ...`
- `ahk_class ...`
- combined `ahk_class ... ahk_exe ...`
- website strings such as `docs.google.com`

When class and executable are placed together without a comma between them, both conditions must be true. A comma separates alternative contexts in the reference syntax.

The reference file gives this general priority:

1. `ahk_class #32768` — Win32 menus
2. Website-specific context
3. Specific `ahk_class`
4. Specific `ahk_exe`
5. `global`

Modifiers, combos, chords, holds, tap-holds, double taps, hotkeys, and hotstrings can all be context-scoped.

---

# 3. Two-key combos

Combos map two physical keys to a dedicated action.

```ahk
QMK.SetupCombos([
    ["a", "h", "global", QMK.SendKeyDirect("^{Left}")],
    ["a", "l", "global", QMK.SendKeyDirect("^{Right}")],
    ["a", ";", "global", QMK.SendKeyDirect("{Backspace}"), "instant"],
    ["CapsLock", "e", "global", (*) => ActivateExampleApp()],
    ["v", "k", "global", (*) => ShowExampleMedia(), "instant"],
])
```

A combo overrides the ordinary virtual-modifier interpretation for that exact pair. This lets `A` behave like Ctrl generally while reserving `a+h` for Ctrl+Left, for example.

### Native send vs callback

For a simple key send, keep the action in the native path:

```ahk
["c", "n", "global", QMK.SendKeyDirect("1")]
```

You can technically wrap the same call in a callback:

```ahk
["c", "n", "global", (*) => QMK.SendKeyDirect("1")]
```

but that adds a DLL → AutoHotkey → DLL round trip. Use a callback when you actually need AutoHotkey logic:

```ahk
["CapsLock", "e", "global", (*) => ActivateExampleApp()]
```

For multi-step actions, a named function is often clearer:

```ahk
TestFunction() {
    SendEvent("This is a test")
    Sleep(200)
    ToolTip("We sent it")
    SetTimer(() => ToolTip(), -2000)
}

QMK.SetupCombos([
    ["a", "k", "global", (*) => TestFunction()],
])
```

### Shape

```ahk
[key1, key2, context, action]
[key1, key2, context, action, "instant"]
```

`"instant"` fires as soon as the pair is recognized. Without it, the combo participates in the normal quiet-period / rollover timing.

---

# 4. Quiet period and rollover

Fast typing often includes overlapping key presses. QMK uses a configurable **quiet period** to prevent ordinary overlap from becoming an accidental combo or chord.

The current reference file uses **150 ms** as the default example.

Two important cases can still trigger inside that general model:

- a row explicitly marked `"instant"`
- retroactive recognition when the timing conditions become satisfied after a fast overlap

This retroactive behavior is intended to preserve both normal rolling typing and intentional combos. QMKCore also tracks key-down order and preserves FIFO order when keys are eventually sent to the operating system.

If accidental triggers occur:

- increase `quietPeriodDuration`
- avoid `"instant"` on pairs that occur during normal typing
- consider decreasing `modifierGestureWindow` if virtual modifiers chain too easily

---

# 5. Three-, four-, and five-key chords

Chords extend the same idea to 3–5 physical keys.

```ahk
QMK.SetupChords([
    ["a", "s", "j", "global", QMK.SendKeyDirect("+{Down}")],
    ["a", "s", "k", "global", QMK.SendKeyDirect("+{Up}")],
    ["a", "s", "d", "h", "global", (*) => MoveExampleWindow("left")],
    ["a", "s", "d", "l", "global", (*) => MoveExampleWindow("right")],
    ["a", "s", "d", "f", "o", "global", (*) => ActivateExampleApp()],
])
```

### Shape

```ahk
[key1, key2, key3, context, action]
[key1, key2, key3, context, action, "instant"]
[key1, key2, key3, key4, context, action]
[key1, key2, key3, key4, key5, context, action]
```

Use `QMK.SendKeyDirect()` for native key output or a callback for AutoHotkey work.

### Hardware limitation

Some keyboards cannot report certain simultaneous 3–5 key combinations. If one exact chord never works, test the physical keys independently with a keyboard tester. A hardware rollover limitation cannot be fixed in software.

---

# 6. Holds, taps, tap-holds, and double taps

Single keys can trigger actions based on how they are pressed.

## Holds

```ahk
QMK.SetupHolds([
    ["e", ["global"], (*) => ActivateExampleApp()],
    ["h", ["global"], (*) => MoveExampleWindow("left")],
    ["j", ["global"], (*) => MoveExampleWindow("down-left")],
    ["k", ["global"], (*) => MoveExampleWindow("up-right")],
    ["l", ["global"], (*) => MoveExampleWindow("right")],
])
```

A practical pattern is to dedicate memorable global hold keys to frequently used applications or window actions.

## Taps and tap-holds

```ahk
QMK.SetupTaps([
    ["h", "Example Editor", QMK.SendKeyDirect("1")],
    ["j", "Example Editor", QMK.SendKeyDirect("2")],
    ["k", "Example Editor", QMK.SendKeyDirect("4")],
    ["l", "Example Editor", QMK.SendKeyDirect("{Enter}")],
])
```

Supported shapes described in the reference file include:

```ahk
QMK.SetupTaps([
    [key, context, QMK.SendKeyDirect(tapAction)],
    [key, context, QMK.SendKeyDirect(tapAction), holdCallback],
    [key, context, QMK.SendKeyDirect(tapAction), holdCallback, thresholdMs],
])

QMK.SetupTap({
    key: key,
    context: context,
    tap: QMK.SendKeyDirect(tapAction)
})
```

A quick release takes the tap path; holding beyond the configured threshold takes the hold path when one is defined.

## Double taps

```ahk
QMK.SetupDoubleTaps([
    ["LCtrl", "example.com", (*) => ActivateExampleApp()],
])
```

Shape:

```ahk
[key, context, action]
[key, context, action, suspendExempt]
```

The double-tap window is controlled by `doubleTapThreshold`.

## Repeated taps

The current design also allows repeated-tap behavior for keys without a dedicated double-tap mapping: double-tap and hold a repeatable key such as Backspace to repeat it. Timing is controlled by `repeatInitialDelay` and `repeatInterval`.

---

# 7. Hotstrings

QMK can register AutoHotkey-style hotstring triggers in the native engine.

```ahk
QMK.SetupHotstrings([
    [":*:addr", "global", "123 Example Street"],
    [":*:email", "global", "user@example.com"],
    [":*:sig", "ahk_exe ExampleApp.exe", (*) => InsertExampleSignature()],
])
```

### Shape

```ahk
[hotstringSpec, context, replacement]
[hotstringSpec, context, callback]
```

| Parameter | Meaning |
|---|---|
| `hotstringSpec` | AutoHotkey-style trigger, such as `:*:email`. |
| `context` | `global`, one context, or context alternatives. |
| `replacement` | Text to emit. |
| `callback` | AutoHotkey function called when the hotstring fires. |

Ordinary AutoHotkey hotstrings can coexist with QMK hotstrings. The native path is mainly useful when you want some high-volume text rules filtered and dispatched outside AutoHotkey's single-threaded hotkey/hotstring processing.

---

# 8. Hotkeys

QMK hotkeys use familiar AutoHotkey-style hotkey text.

```ahk
QMK.SetupHotkeys([
    ["!h", "global", QMK.SendKeyDirect("{Left}")],
    ["!j", "global", QMK.SendKeyDirect("{Down}")],
    ["!k", "global", QMK.SendKeyDirect("{Up}")],
    ["!l", "global", QMK.SendKeyDirect("{Right}")],
])
```

### Shape

```ahk
[hotkeySpec, context, action]
[hotkeySpec, context, action, suspendExempt]
```

`action` can be:

- `QMK.SendKeyDirect("...")`
- a supported native action string such as `"panicExit"`
- an AutoHotkey callback

Ordinary AutoHotkey hotkeys can remain in the same script if you prefer.

---

# 9. User settings

The reference file says user settings are stored in **`QMKconfig.ini`** and edited through the tray menu's **QMK Settings** GUI.

Useful settings include:

### General

- `applyUserConfig` — whether saved settings are pushed into the running QMK core.

### Input backend

- `auto`
- `interception`
- `llhook`
- `ahk_hotkeys`

The reference file describes Interception as the fastest capture path, `llhook` as a fast no-driver native option, and AutoHotkey hotkeys as the most AHK-dependent capture path.

If you want to use Interception, install it from the same repositories linked by the QMK Settings GUI:

- **Interception — official repository:** https://github.com/oblitum/Interception
- **Interception driver fix:** https://github.com/hygorostrowskij/interception-driver-fix

The driver fix is intended for systems that encounter Interception's **10-keyboard / 10-mouse device limit**, particularly with reconnecting Bluetooth devices.

See [INSTALL.md](INSTALL.md) for the fuller installation notes and backend recommendations.

### Send mode

- `auto`
- `interception`
- `sendinput`

### Timing

- `singleKeyHoldThreshold`
- `maxHoldThreshold`
- `maxThresholdSuppress`
- `quietPeriodDuration`
- `modifierGestureWindow`
- `doubleTapThreshold`
- `repeatInitialDelay`
- `repeatInterval`

If the tray menu is unavailable, call:

```ahk
QMKUserConfig.ShowGui()
```

from your own hotkey.

---

# 10. Group your setup calls

The current implementation is designed to batch runtime configuration efficiently. Prefer grouped setup calls:

```ahk
QMK.SetupModifiers([
    ["a", "Ctrl"],
    ["s", "Shift"],
    ["d", "Win"],
    ["f", "Alt"],
])
```

over many one-row calls when practical. This is both easier to read and faster to initialize.

---

# 11. Compiling your own core

You do not need to rebuild Zig just to add or change shortcuts. User mappings are runtime configuration.

Compile QMKCore only when you want to:

- rebuild the native core for your machine
- update the bundled native library
- change/test native Zig code

The current reference file describes two paths.

## Standard Zig build

Requires:

- AutoHotkey v2
- Zig 0.16

Use **Zig Settings** / **Zig Build** in the included QMK compiler, satisfy the dependency checks, then compile.

## Full PGO build

Requires a Windows build environment with:

- MSVC build tools
- Clang / LLVM

Use **PGO Settings** / **Full PGO Build**, satisfy the dependency checks, then compile.

The compiler is described as rebuilding the core and embedding the resulting native code into `QMKVariables.ahk` in the project's `lib` folder.

The current tutorial reports development measurements of roughly **~2 µs median key latency** for its PGO build and **~10 µs** for the standard Zig build.

---

# API quick reference

```ahk
QMK.SetupModifiers([...])
QMK.SetupCombos([...])
QMK.SetupChords([...])
QMK.SetupHolds([...])
QMK.SetupTaps([...])
QMK.SetupTap({...})
QMK.SetupDoubleTaps([...])
QMK.SetupHotstrings([...])
QMK.SetupHotkeys([...])

QMK.SendKeyDirect("...")
QMK.Suspend()
QMK.SuspendExempt(callback)
QMKUserConfig.ShowGui()
```

For a runnable-style collection of examples, see **`Quick_Demo.ahk`**.
