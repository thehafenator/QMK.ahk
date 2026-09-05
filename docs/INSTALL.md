# Installing QMK.ahk

This guide is intentionally ordered from the simplest setup to the more advanced options.

## Requirements

For the normal prebuilt path, the project documentation establishes these core requirements:

- **Windows**
- **AutoHotkey v2**
- The QMK.ahk project files / release

You do **not** need to install Zig, LLVM, or MSVC just to define and use shortcuts. Those are only needed if you want to rebuild the native core yourself.

## 1. Get the project

Download or clone the QMK.ahk repository and keep its included files together.

The current project embeds the native QMKCore machine code for easier distribution. User shortcuts remain in AutoHotkey and are registered with the native core at runtime.

The AutoHotkey library entry point is the repository-root file `QMKInterception.ahk`. Include that file from your own script, then add your own `QMK.Setup...()` definitions.

## 2. Start with the no-driver path

QMK.ahk can be tried without installing Interception.

Open **QMK Settings** from the tray menu (or call `QMKUserConfig.ShowGui()`) and choose an input/output combination that does not depend on Interception.

### Input backend choices

| Setting | Meaning |
|---|---|
| `auto` | Chooses the fastest available supported backend. |
| `interception` | Uses the Interception kernel driver. |
| `llhook` | Uses the low-level hook in the native Zig DLL. |
| `ahk_hotkeys` | Uses AutoHotkey hotkeys for capture. |

For a first test, **`llhook`** is the simplest native path when available. `ahk_hotkeys` is another no-driver option.

### Send mode choices

| Setting | Meaning |
|---|---|
| `auto` | Uses Interception sending when available, otherwise falls back. |
| `interception` | Sends through Interception. |
| `sendinput` | Sends through Windows SendInput. |

For a no-driver test, use **`sendinput`** or leave the setting on `auto` if the project correctly falls back on your machine.

## 3. Add safety shortcuts first

While configuring keyboard hooks, keep a reliable exit/reload path available.

```ahk
QMK.SetupHotkeys([
    ["*#Escape", "global", "panicExit", true],
    ["*^+r", "global", "nativeReload", true],
    ["^!s", "global", QMK.SuspendExempt((*) => QMK.Suspend())],
    ["F1", "global", (*) => QMKUserConfig.ShowGui()],
])
```

These examples provide:

- native emergency exit
- native reload
- suspend/resume
- a shortcut to QMK Settings

The `true` flag on the native safety rows makes them suspend-exempt.

## 4. Verify the basic engine

Start with one small mapping rather than importing a full configuration.

```ahk
QMK.SetupModifiers([
    ["a", "Ctrl"],
])
```

Expected behavior:

- Tap `A` normally → `a`
- Hold `A` while pressing another key → `A` can act as virtual Ctrl

Then test a direct combo:

```ahk
QMK.SetupCombos([
    ["a", ";", "global", QMK.SendKeyDirect("{Backspace}"), "instant"],
])
```

If both work, move on to the [Tutorial](TUTORIAL.md).

## 5. Configure timing

Open **QMK Settings** from the tray menu. Settings are stored in `QMKconfig.ini` according to the current tutorial.

The main timing settings are:

| Setting | Purpose |
|---|---|
| `singleKeyHoldThreshold` | How long a key must be held for single-key hold behavior. |
| `maxHoldThreshold` | Long-hold threshold. |
| `maxThresholdSuppress` | Controls long-hold suppression behavior. |
| `quietPeriodDuration` | Protects ordinary typing from accidental combos/chords. |
| `modifierGestureWindow` | Timing window for modifier chaining/gestures. |
| `doubleTapThreshold` | Time allowed between taps for double-tap behavior. |
| `repeatInitialDelay` | Delay before repeated-tap repetition starts. |
| `repeatInterval` | Interval between repeated events. |

The tutorial uses **150 ms** as the default quiet-period example.

## Installing Interception (optional)

QMK.ahk does **not** require Interception. You can use the Zig low-level hook (`llhook`) for capture and `SendInput` for output without installing a keyboard driver.

If you want the Interception capture/send path, install the official driver from the [Interception repository](https://github.com/oblitum/Interception). QMK.ahk does not need AutoHotInterception's AHK wrapper or sample files; this release already contains its own QMK runtime and native import files.

### Driver installation

1. Download the latest release from the official [Interception releases](https://github.com/oblitum/Interception/releases) page.
2. Before extracting a downloaded archive, open its **Properties** and select **Unblock** if Windows shows that option. This prevents Windows attachment blocking from stopping the installer or DLLs later.
3. Extract the archive to a temporary location.
4. Open **Command Prompt as administrator** and change to the extracted `command line installer` directory.
5. Run the installer without arguments first. It displays the installation usage:

   ```text
   install-interception.exe
   ```

6. Run the install command it specifies:

   ```text
   install-interception.exe /install
   ```

Do not launch `install-interception.exe` by double-clicking it. Restart Windows only if the installer or Windows requests it.

After installation, open **QMK Settings** and select the desired backends:

- **Input Backend: `auto`** — prefer Interception when available and fall back when it is not.
- **Input Backend: `interception`** — require Interception for capture.
- **Send Mode: `auto`** — prefer Interception sending and fall back to `SendInput`.
- **Send Mode: `interception`** — require Interception for sending.

Start with `auto` unless you specifically need to require the driver. If the driver is not installed or is unavailable, use `llhook` plus `sendinput` for a driver-free configuration.

### Interception driver fix

The [Interception driver fix](https://github.com/hygorostrowskij/interception-driver-fix) is a separate project; it is not included in QMK.ahk and does not include the driver. Its documentation describes it as a companion fix for devices that become unresponsive after hot-plugging or waking from sleep. It is also relevant to the classic Interception device-ID exhaustion problem, where keyboard IDs can pass 10 or mouse IDs can pass 20.

Install the driver first, then follow the fix project's own [release and installation instructions](https://github.com/hygorostrowskij/interception-driver-fix/releases). Do not copy its installer or service files into the QMK.ahk release.

If you use AutoHotInterception's optional monitor tools for troubleshooting, tick one device at a time. Those tools are not required by QMK.ahk, and the device IDs may change after unplug/replug or hibernate/resume.

### Safety warning

Interception operates below normal Windows input handling. A blocked key can affect system-level shortcuts, so keep a second keyboard or other recovery method available, preserve a reliable QMK exit/reload shortcut, and know how to disable the script in Safe Mode before enabling blocking behavior.

The upstream [AutoHotInterception README](https://github.com/evilC/AutoHotInterception/blob/master/README.md) provides additional driver warnings and troubleshooting context. It is a separate AHK wrapper project, not a dependency of this QMK.ahk release.

## Website-specific contexts

Website contexts such as:

```ahk
"docs.google.com"
```

use the project's website-awareness integration. The tutorial references `OnWebsite.ahk` for this functionality.

Application contexts such as `ahk_exe` and `ahk_class` do not require website matching.

## Direct sends vs AutoHotkey callbacks

Prefer the native send path when the action is only a key send:

```ahk
["a", "h", "global", QMK.SendKeyDirect("^{Left}")]
```

Use an AutoHotkey callback for application logic:

```ahk
["CapsLock", "e", "global", (*) => ActivateExampleApp()]
```

A callback makes a round trip to AutoHotkey. That is normally fine, but `QMK.SendKeyDirect()` avoids the AHK callback round trip for simple sends.

## Troubleshooting

### QMK Settings is not visible

The current tutorial says the tray menu should contain **QMK Settings** unless the script uses `#NoTrayIcon` or the menu lines have been removed.

You can also expose it with:

```ahk
F1::QMKUserConfig.ShowGui()
```

or with the QMK hotkey example shown above.

### A combo fires while typing

Increase `quietPeriodDuration` in QMK Settings. Also check whether the row is marked `"instant"`, because instant combos intentionally bypass normal quiet-period protection.

### A combo feels hard to trigger

The quiet period may be too high for your typing style. The engine also supports retroactive timing, so test the behavior before reducing the value aggressively.

### Modifier combinations trigger unexpectedly

The tutorial recommends considering a smaller `modifierGestureWindow` if accidental modifier chaining occurs.

### A 3-, 4-, or 5-key chord never registers

Test the physical key combination independently. Some keyboards cannot report particular simultaneous key combinations because of hardware rollover / matrix limitations. Software cannot recover a key event the keyboard never reports.

### AutoHotkey callbacks feel slower than direct sends

For simple key output, replace:

```ahk
(*) => QMK.SendKeyDirect("1")
```

with:

```ahk
QMK.SendKeyDirect("1")
```

so the send stays in the native QMK path.

### A normal AutoHotkey hotkey/hotstring still exists

That is allowed. QMK mappings and ordinary AutoHotkey hotkeys/hotstrings can coexist.

## Building the native core (advanced)

You only need this section if you want to rebuild QMKCore for your machine, change native Zig code, or regenerate the embedded machine code.

For the straightforward click-by-click workflow, see **[QMK Compiler GUI](COMPILER_GUI.md)**. The short version is: open **QMK Settings** → **Compile** → **Open PGO Compiler**, then choose **Zig Build** for the normal build or **Full PGO Build** for the optional PGO path.

### Option A: standard Zig build

The current tutorial specifies:

- AutoHotkey v2
- **Zig 0.16**

In the compiler window, open **Compiler Settings** → **Zig Build Settings**, confirm the required paths and Zig 0.16, save, and click **Zig Build**.

The compiler writes the rebuilt native core back into the project's embedded QMK variables according to the tutorial.

### Option B: full PGO build

The PGO path requires a Windows build environment with:

- MSVC build tools
- Clang / LLVM

In the compiler window, open **Compiler Settings** → **PGO Settings**, resolve every missing dependency, save, and click **Full PGO Build**.

The reference file reports approximately ~2 µs median key latency for its PGO development build versus ~10 µs for its standard Zig build. Treat these as project development measurements rather than guaranteed machine-independent results.

## Next

Continue with **[Tutorial: QMK.ahk User API](TUTORIAL.md)** for the actual shortcut syntax.
