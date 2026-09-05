# QMKInterception.ahk
**Breaking Changes as of 9/5/2026**
- This project began as a pure AutoHotkey implementation of QMK-like keyboard behavior. It has been updated for better speed and reliability. Please see the legacy branch, or see the tutorial for syntax changes.

**What is QMKInterception.ahk?**

This project aims to let you build your own custom-shortcuts beyond what AutoHotkey alone is typically capable of. This allows firmware-style keyboard behavior in AutoHotkey: home-row modifiers, layers, combos, chords, tap/hold actions, hotkeys, hotstrings, and context-aware shortcuts. Your mappings stay easy to write in AHK, while timing-sensitive keyboard processing runs in a native Zig core.

Projects such as QMK and ZMK provide powerful keyboard features at the firmware level, but normally require compatible hardware and firmware configuration.

QMKInterception.ahk brings many of the same ideas to **any Windows keyboard** while keeping configuration in **AutoHotkey v2**.

QMKInterception.ahk brings many of the same ideas to **any Windows keyboard** while keeping configuration in **AutoHotkey v2**.

For example, you can:

- tap `A` normally, but hold it to use it as `Ctrl`
- hold `C` and use the right side of the keyboard as a numpad
- press `J` + `K` together for `Escape`
- give a key separate action for a quick tap, a hold, and double-tap
- create any 2-key shorcut through combos and 3–5 key chords
- make shortcuts behave differently in specific apps, windows, or websites
- keep complex actions as normal AutoHotkey callbacks
- keep simple key sends entirely in the native fast path through the Dll.

QMKInterception.ahk is designed to run a layer beneath your existing AutoHotkey setup rather than replace it.

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

; Hold U and send Win+Up to maximize the active window
QMK.SetupHolds([
    ["u", ["global"], (*) => Send("#{Up}")],
])

; Explicit .email hotstring (no wildcard trigger)
QMK.SetupHotstrings([
    [":X:.email", "global", "demo@example.com"],
])
```

The mappings are defined in AutoHotkey. QMK.ahk passes them into the native runtime at startup and handles keyboard events from there. For more complete patterns and API shapes, continue to the [full tutorial](docs/TUTORIAL.md).

---

## Installation

### Requirements

- **Windows**
- **AutoHotkey v2**
- The QMK.ahk project files / release

**Interception is optional.** You can try QMK.ahk without installing a keyboard driver by using the built-in non-Interception input/output paths.

### Where to start

1. Read the **[Installation Guide](docs/INSTALL.md)** for the first setup and backend choice.
2. Use the **[Tutorial](docs/TUTORIAL.md)** for the full API and backend behavior.
3. Use the **[GUI Compiler Guide](docs/COMPILER_GUI.md)** only if you need to rebuild the native core.
4. Open **[Quick_Demo.ahk](Quick_Demo.ahk)** for a runnable sanitized example.

### Basic setup

1. Download or clone QMK.ahk.
2. Make sure AutoHotkey v2 is installed.
3. Include/load `QMKInterception.ahk` from your script.
4. Add your `QMK.Setup...()` definitions.
5. Run the script.
6. Open **QMK Settings** to choose or adjust the input and send backends if needed.

For driver setup, backend selection, verification, and troubleshooting, see the **[Installation Guide](docs/INSTALL.md)**. For the click-by-click native rebuild flow, see the **[GUI Compiler Guide](docs/COMPILER_GUI.md)**.

### Optional Interception driver

The Interception driver is only needed when you choose the `interception` capture or send path. Download the driver from the [official Interception repository](https://github.com/oblitum/Interception), extract it, and run its command-line installer from an **Administrator Command Prompt**. Do not double-click the installer:

```text
install-interception.exe
install-interception.exe /install
```

If Windows marks the downloaded archive or DLLs as blocked, use the file's **Properties → Unblock** option before extracting or running it. For the driver's reconnect/frozen-device issue, see the separate [Interception driver fix](https://github.com/hygorostrowskij/interception-driver-fix). The complete procedure and safety warnings are in the **[Installation Guide](docs/INSTALL.md)**.

---

## API overview

QMK.ahk intentionally keeps the public setup API small (see the tutorial for concrete examples). Most configuration is done through these calls:

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
- use a native QMK action such as `QMK.SendKeyDirect(...)` to send a keystroke through the dll, which is faster than a round-trip back to AutoHotkey. 

```ahk
; Native key send with a 2-key combo
QMK.SetupCombos([
["j", "k", "global", QMK.SendKeyDirect("{Escape}"), "instant"],
)]

; AutoHotkey callback with a Setup Hold
QMK.SetupHolds([
["h", ["global"], (*) => MyWindowManager.SnapLeft()]
)]
```

### Contexts

These strings help determine what contexts (which program needs to be active) for a given context to run. More on this here: (**[Tutorial](docs/TUTORIAL.md)**.:

```ahk
"global"
"ahk_exe Code.exe"
"ahk_class Chrome_WidgetWin_1"
"ahk_class Chrome_WidgetWin_1 ahk_exe msedge.exe"
"docs.google.com"
```
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

QMKInterception.ahk uses a native Zig DLL and either a low-level keyboardhook to add extra layers of shortcuts underneath your existing AutoHotkey setup. When AutoHotkey Runs, your shortcuts are passed into the dll, then keystrokes are interpretted by the dll before 

```text
Your AutoHotkey script
        │
        │ QMK.Setup...()
        ▼
     QMKInterception.ahk
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

User mappings are runtime data, and much like AutoHotkey itself, the runtime shape makes it easy to edit your shortcuts without needing to compile to native code. If you notice startup lag, however, you can transpile your shortcuts to native Zig and and AutoHotkey callback table. 

---

## Performance

I built this to be as fast and memory safe as possible. Sometimes I am amazed at how fast native code executes. 

Current development measurements reported by the project are approximately:

| Build | Median processing latency |
|---|---:|
| PGO-optimized native core | ~2 µs |
| Standard Zig build | ~10 µs |

After initial runtime initialization, current development measurements are roughly **1~10 us** for key delay - roughly 7-8 thousand times faster than a 60 Hz screen takes to update one frame.

---

## Input and output options

For those that may not be able to install the interception driver (which requires administrator priveleges), a low-level hook in the native code also exists. The current project supports input/output paths including:

- **Interception** — optional low-level keyboard capture/send path
- **Windows low-level hook** — driver-free capture path
- **AutoHotkey hotkeys** — AHK-based capture option
- **SendInput** — driver-free output option

The settings interface can be used to select the appropriate backend for your system.

---

## Documentation

### [Installation Guide](docs/INSTALL.md)
Install QMKInterception.ahk, include into your script, choose an input/output backend, verify the setup, troubleshoot common problems, and optionally build QMKCore yourself.

### [Tutorial](docs/TUTORIAL.md)
Learn the API progressively: modifiers, contexts, combos, timing, chords, taps/holds, hotstrings, hotkeys, settings, and advanced configuration.

### [GUI Compiler Guide](docs/COMPILER_GUI.md)
Rebuild the native core from QMK Settings, choose the standard Zig build or optional Full PGO Build, and understand which outputs stay local.

The copy/pasteable examples are in the sanitized [Tutorial](docs/TUTORIAL.md) and [quick demo](Quick_Demo.ahk). They use generic contexts and callbacks rather than a user's personal shortcut files.

---

## Benefits of QMKInterception.ahk vs. keyboard firmware

QMKInterception.ahk is inspired by the flexibility of QMK/ZMK-style keyboard configuration, but instead of compiling on the firmware level, it is emulated at a sofware level.

This means:

- no special programmable keyboard is required
- no firmware flashing is required
- configuration can be changed reloaded quickly
- mappings can directly call AutoHotkey functions. 
- Shortcuts can react to the active application, window, or website


--

## Notes

- Normal AutoHotkey hotkeys and hotstrings can coexist with QMK.ahk mappings.
- Keyboard hardware rollover limitations can prevent some large physical chords from being detected.
- Interception is optional; users who do not want a driver can use the available driver-free paths.
- Most users never need to compile the Zig core themselves.

---

## Project history

QMK.ahk began as a pure AutoHotkey implementation of QMK-like keyboard behavior. As the project grew, the timing-sensitive runtime was moved into Zig while keeping the user-facing configuration and callbacks in AutoHotkey.

The current design focuses on a small AHK API, runtime-configured shortcuts, low-latency native processing, and compatibility with existing AutoHotkey automation.
