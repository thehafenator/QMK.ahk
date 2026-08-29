# QMK.ahk

**QMK-style keyboard features for AutoHotkey v2 on Windows — without needing a programmable keyboard.**

QMK.ahk lets you build firmware-style keyboard behavior in AutoHotkey: home-row modifiers, layers, combos, chords, tap/hold actions, hotkeys, hotstrings, and context-aware shortcuts. Your mappings stay easy to write in AHK, while timing-sensitive keyboard processing runs in a native Zig core.

Use it to turn an ordinary Windows keyboard into a deeply programmable keyboard without flashing firmware or moving your automation logic out of AutoHotkey.

---

## What is QMK.ahk?

Projects such as QMK and ZMK provide powerful keyboard features at the firmware level, but normally require compatible hardware and firmware configuration.

QMK.ahk brings many of the same ideas to **any Windows keyboard** while keeping configuration in **AutoHotkey v2**.

For example, you can:

- tap `A` normally, but hold it to use it as `Ctrl`
- hold `C` and use the right side of the keyboard as a numpad
- press `J` + `K` together for `Escape`
- give a key separate tap, hold, double-tap, and repeated-tap behavior
- create 2-key combos and 3–5 key chords
- make shortcuts behave differently in specific apps, windows, or websites
- keep complex actions as normal AutoHotkey callbacks
- keep simple key sends entirely in the native fast path

QMK.ahk is designed to coexist with the rest of your AutoHotkey setup rather than replace it.

---

## Features

| Feature | What it does |
|---|---|
| **Modifiers** | Turn ordinary keys into `Ctrl`, `Shift`, `Alt`, or `Win` while held |
| **Combos** | Trigger an action from two overlapping keys |
| **Chords** | Trigger actions from 3-, 4-, or 5-key combinations |
| **Taps & Holds** | Give one key different behavior when tapped or held |
| **Double Taps** | Assign actions to rapid repeated presses |
| **Hotkeys** | Register QMK-managed hotkeys with AHK-style callbacks or native actions |
| **Hotstrings** | Expand typed abbreviations through the QMK runtime |
| **Contexts** | Scope mappings to global, executable, window class, title, browser, or website contexts |
| **Rollover / buffering** | Preserve physical press order during overlapping key presses |
| **Quiet period** | Distinguish intentional combos from normal fast typing |
| **Native sends** | Keep simple key-output actions inside the Zig runtime |
| **AHK callbacks** | Call your existing AutoHotkey functions for complex actions |
| **Multiple backends** | Use Interception, a low-level Windows hook, or AutoHotkey-based capture/send paths |
| **Runtime configuration** | Add and change mappings in AHK without recompiling the Zig core |

---

## Quick example

```ahk
#Requires AutoHotkey v2.0

; Home-row modifiers
QMK.SetupModifiers([
    ["a", "Ctrl"],
    ["s", "Shift"],
    ["d", "Win"],
    ["f", "Alt"],
])

; Two-key combos
QMK.SetupCombos([
    ["j", "k", "global", QMK.SendKeyDirect("{Escape}"), "instant"],
    ["a", ";", "global", QMK.SendKeyDirect("{Backspace}"), "instant"],
])

; Context-aware hold action
QMK.SetupHolds([
    ["k", ["youtube.com"], (*) => Send("{Space}")],
])

; Hotstring
QMK.SetupHotstrings([
    [":*:email", "global", "user@example.com"],
])
```

The mappings are defined in AutoHotkey. QMK.ahk passes them into the native runtime at startup and handles keyboard events from there.

---

## Installation

### Requirements

- **Windows**
- **AutoHotkey v2**
- The QMK.ahk project files / release

**Interception is optional.** You can try QMK.ahk without installing a keyboard driver by using the built-in non-Interception input/output paths.

### Basic setup

1. Download or clone QMK.ahk.
2. Make sure AutoHotkey v2 is installed.
3. Include/load QMK.ahk from your script.
4. Add your `QMK.Setup...()` definitions.
5. Run the script.
6. Open **QMK Settings** to choose or adjust the input and send backends if needed.

For driver setup, backend selection, verification, troubleshooting, and native-core compilation, see **[Installation Guide](docs/INSTALL.md)**.

---

## API overview

QMK.ahk intentionally keeps the public setup API small. Most configuration is done through these calls:

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
```

### Actions

A mapping can either:

- execute an **AutoHotkey callback**, or
- use a native QMK action such as `QMK.SendKeyDirect(...)` when only keyboard output is needed.

```ahk
; Native key send
["j", "k", "global", QMK.SendKeyDirect("{Escape}"), "instant"]

; AutoHotkey callback
["h", ["global"], (*) => MyWindowManager.SnapLeft()]
```

### Contexts

The same API can be scoped to where a shortcut should work:

```ahk
"global"
"ahk_exe Code.exe"
"ahk_class Chrome_WidgetWin_1"
"ahk_class Chrome_WidgetWin_1 ahk_exe msedge.exe"
"docs.google.com"
```

The full syntax, parameter shapes, context rules, timing behavior, and examples are covered in the **[Tutorial](docs/TUTORIAL.md)**.

---

## Example uses

### Home-row modifiers

Keep your fingers on the home row while using normal modifier shortcuts:

```ahk
QMK.SetupModifiers([
    ["a", "Ctrl"],
    ["s", "Shift"],
    ["d", "Win"],
    ["f", "Alt"],
])
```

Tap the keys normally to type `a`, `s`, `d`, and `f`; hold them as part of another shortcut to use their modifier behavior.

### Layers without a dedicated layer key

A regular key can effectively become a layer key through combos. For example, holding `C` with nearby keys can create a numpad, while another key can become a navigation or media layer.

### Context-aware automation

The same physical shortcut can have application-specific behavior with a global fallback, so you do not need to maintain separate hotkey systems for every program.

---

## How it works

QMK.ahk uses AutoHotkey as the configuration and automation layer and a native Zig DLL as the timing-sensitive keyboard engine.

```text
Your AutoHotkey script
        │
        │ QMK.Setup...()
        ▼
     QMK.ahk
        │
        │ runtime configuration
        ▼
   QMKCore (Zig)
        │
        ├─ key state / timing
        ├─ buffering / rollover
        ├─ modifiers
        ├─ combos / chords
        ├─ taps / holds
        ├─ hotkeys / hotstrings
        └─ context matching
        │
        ▼
 native key action or AHK callback
```

User mappings are runtime data. **You do not need to rebuild the Zig core when you add or change shortcuts.**

---

## Performance

The native core exists to keep the event path lightweight and predictable even with large shortcut configurations.

Current development measurements reported by the project are approximately:

| Build | Median processing latency |
|---|---:|
| PGO-optimized native core | ~2 µs |
| Standard Zig build | ~10 µs |

Runtime shortcut configuration is batched during startup; current development measurements are roughly **~10 ms** for setup.

These are development measurements rather than guaranteed results for every machine or configuration.

---

## Input and output options

QMK.ahk is not tied to one capture method. The current project supports input/output paths including:

- **Interception** — optional low-level keyboard capture/send path
- **Windows low-level hook** — driver-free capture path
- **AutoHotkey hotkeys** — AHK-based capture option
- **SendInput** — driver-free output option

The settings interface can be used to select the appropriate backend for your system.

---

## Documentation

### [Installation Guide](docs/INSTALL.md)
Install QMK.ahk, choose an input/output backend, verify the setup, troubleshoot common problems, and optionally build QMKCore yourself.

### [Tutorial](docs/TUTORIAL.md)
Learn the API progressively: modifiers, contexts, combos, timing, chords, taps/holds, hotstrings, hotkeys, settings, and advanced configuration.

### `lib/ReadMe_Tutorial.ahk`
A copy/pasteable AutoHotkey reference containing practical examples of the public API.

---

## QMK.ahk vs. keyboard firmware

QMK.ahk is inspired by the flexibility of QMK/ZMK-style keyboard configuration, but it runs on Windows rather than inside your keyboard.

That has a few useful consequences:

- no special programmable keyboard is required
- no firmware flashing is required
- configuration can be reloaded quickly
- mappings can directly call AutoHotkey functions and Windows automation
- shortcuts can react to the active application, window, or website

Firmware still has advantages when you need behavior that is completely independent of Windows or AutoHotkey. QMK.ahk is aimed at users who want firmware-like keyboard behavior **plus** desktop-aware automation.

---

## Notes

- Normal AutoHotkey hotkeys and hotstrings can coexist with QMK.ahk mappings.
- Keyboard hardware rollover limitations can prevent some large physical chords from being detected.
- Interception is optional; users who do not want a driver can use the available driver-free paths.
- Most users never need to compile the Zig core themselves.

---

## Project history

QMK.ahk began as a pure AutoHotkey implementation of QMK-like keyboard behavior. As the project grew, the timing-sensitive runtime was moved into Zig while keeping the user-facing configuration and callbacks in AutoHotkey.

The current design focuses on a small AHK API, runtime-configured shortcuts, low-latency native processing, and compatibility with existing AutoHotkey automation.
