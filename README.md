# QMK.ahk - Keyboard Layers and Home Row Modifiers in AutoHotkey v2

---
## TLDR:
QMK is a powerful open-source firmware for mechanical keyboards, enabling custom key mappings, layers, and shortcuts for enhanced productivity and ergonomics. This AutoHotkey v2 script, split into `QMKClass.ahk` (core logic) and `QMK.ahk` for user-defined shortcuts  brings QMK-like functionality to any keyboard on Windows. It supports **homerow modifiers** (e.g., using `a` as Ctrl), **hold actions** (e.g., hold `h` to snap a window left), **combos** (e.g., `a` + `h` for an actions), and **instant combos** for quick triggers. Benefits include streamlined workflows, reduced finger movement, and highly customizable shortcuts, making it ideal for power users, programmers, and anyone seeking a more efficient keyboard experience.
Similar to my `MouseGestures.ahk` and `8BitDo.ahk` scripts, it uses **context-aware mappings** with global fallbacks, so you only define common actions once. With `OnWebsite.ahk` and Descolada's UIA library, you can create **website-specific** hold shortcuts as well. If enough interest, I may expand that context specificity to combos as well.

## Examples:
- Custom layer/combos - Holding the 'v' key - and pressing either h, j, k, l for media controls, or 'c' and keys on the right of the keyboard for a numpad without moving your hands. Any key can become it's own 'modifier' of sorts.
- Hold-Actions - Holding 'c' alone past threshold to trigger an action like launch/hide a program. Can be context sensitive.
- Homerow mods - 'a' can be mapped to control, 's' to Shift, and'd' to Win when held down, normally, 'a', 's', 'd' - pressed with k will send Control+Shift+Win+k.

## Benefits/key keatures inlude:
- Ability to try QMK/ZMK-like functionatlity without the need to flash firmware. Edits can be made quickly and reloaded.
- Simpler Syntax, plugs directly into your existing Autohotkey functions
- Buffering and Rollover Support - keys are buffered with a 'First-in-first-out' approach. Even if you release your keys in a slightly different order, they are processed by the oldest in the queue.
- Home row modifiers - supports 'stacking' - if 'a' is control, and 's' is shift, you can press 'asl' and have it send the keys ^+l. One benefit is reduced movement of fingers from the homerow, potentially reducing wrist pain.
- SetupCombo and Setupinstantcombo - any two keys can trigger an action. The former allows rollover support.
- Very accurate timing from query performance counter - to the microsecond, even if on heavy load or on battery saver.
- Light. Tested on a 10+ year-old laptop with no noticeable delay/lag.
-  QMK.ahk does not affect the functionality of normal hotkeys/hotstrings from firing.

## Basic timing logic:
  - Keys that are pressed separately go through very little processing, sent nearly insantly through the buffer
  - When 2 or more keys overlap
        - Normal typing - All released withing threshold (200ms) => sent as taps in order they were typed 
        - 'Quick' - retroactive and proactive
                - Either 200ms after the first key was pressed down (retroactive), or if the second key pressed up before then (proactive) >> action occurs
        - Held - if held past threshold, modifiers, combos, etc. Fires with little to no delay
------

## Quick Example

In `QMK.ahk`, define user shortcuts: (this file has user configurations and the #includes for the QMKClass.ahk and other dependencies

``
    QMK.SetupModifier("a", "Ctrl")  ; 'a' acts as Ctrl when held
    QMK.SetupHold("h", ["global"], (*) => mm.SnapLeft("A"))  ; Hold h to snap left
    QMK.SetupCombo("a", "h", (*) => mm.SnapLeft("A"))  ; a+h snaps window left
    QMK.SetupInstantCombo("a", ";", (*) => SendEvent("{Backspace}"))  ; a+; instantly sends Backspace
    QMK.SetupHold("k", ["youtube.com"], (*) => Send("{Space}"))  ; Hold k on YouTube to play/pause. 
``

---

## Getting Started

Download the source code on Github, unzip it, and open `QMK.ahk` in an editor to view or modify user-defined shortcuts. I have a few suggestions to get you started, but feel free to edit as you'd like! The core logic resides in `QMKClass.ahk` File. Dependencies are included in the same folder, so double-clicking `QMK.ahk` should run it.

---

**Required Files:**
``
    #Requires AutoHotkey v2.0
    #Include QMK ; Core class for shortcut logic
    #Include QMKConfig.ahk  ; User-defined shortcuts
``

**Recommended Dependencies (optional, can be deleted if not needed):**
``
    #Include OnWebsite.ahk  ; URL caching for website-specific shortcuts
    #Include UIA\Lib\UIA.ahk  ; Browser automation
    #Include UIA\Lib\UIA_Browser.ahk  ; Browser-specific automation
    #Include MonitorManager.ahk  ; Window snapping and monitor management
    #Include scroll.ahk  ; Smooth Scrolling
    #Include mouse.ahk  ; Move the mouse using a layer
    #Include TabActivator.ahk  ; Activate a specific tab in Edge. If already on tab, cycle through to next instance. Updates in background.
``

---

## Sample Default Mappings

These mappings in `QMK.ahk` mirror my `MouseGestures.ahk` for consistency, focusing on window management, navigation, and productivity. Customize them in `QMK.ahk` or add your own. Commented-out sections are included for inspiration and can be enabled if the referenced scripts are available.

**Modifiers:**

    QMK.SetupModifier("a", "Ctrl")
    QMK.SetupModifier("s", "Shift")
    QMK.SetupModifier("d", "Win")
    QMK.SetupModifier("f", "Alt")
    QMK.SetupModifier("j", "Alt")
    QMK.SetupModifier("k", "Win")
    QMK.SetupModifier("l", "Shift")
    QMK.SetupModifier(";", "Ctrl")

**Window Management (a layer + arrow keys/other, with MonitorManager):**

    QMK.SetupCombo("a", "h", (*) => mm.SnapLeft("A"))  ; Snap left
    QMK.SetupCombo("a", "l", (*) => mm.SnapRight("A"))  ; Snap right
    QMK.SetupCombo("a", "j", (*) => mm.GestureDL())  ; Restore/minimize
    QMK.SetupCombo("a", "k", (*) => mm.GestureUR())  ; Maximize/fullscreen
    QMK.SetupCombo("a", "g", (*) => Send("!{Tab}"))  ; Switch apps
    QMK.SetupInstantCombo("a", ";", (*) => SendEvent("{Backspace}"))  ; Backspace
    QMK.SetupInstantCombo("a", "'", (*) => SendEvent("^{Backspace}"))  ; Delete word backward
    QMK.SetupInstantCombo(";", "a", (*) => SendEvent("^{a}"))  ; Select all

**Additional Window Management (move to next screen):**

    QMK.SetupCombo("x", "h", (*) => mm.ThrowLeft("A"))  ; Throw left
    QMK.SetupCombo("x", "l", (*) => mm.ThrowRight("A"))  ; Throw right
    QMK.SetupCombo("m", "h", (*) => mm.ThrowLeft("A"))  ; Throw left
    QMK.SetupCombo("m", "l", (*) => mm.ThrowRight("A"))  ; Throw right

**Numpad Layer (c for Calculator):**

    QMK.SetupCombo("c", "n", (*) => SendEvent("1"))
    QMK.SetupCombo("c", "m", (*) => SendEvent("1"))
    QMK.SetupCombo("c", ",", (*) => SendEvent("2"))
    QMK.SetupCombo("c", ".", (*) => SendEvent("3"))
    QMK.SetupCombo("c", "j", (*) => SendEvent("4"))
    QMK.SetupCombo("c", "k", (*) => SendEvent("5"))
    QMK.SetupCombo("c", "l", (*) => SendEvent("6"))
    QMK.SetupCombo("c", "u", (*) => SendEvent("7"))
    QMK.SetupCombo("c", "i", (*) => SendEvent("8"))
    QMK.SetupCombo("c", "o", (*) => SendEvent("9"))
    QMK.SetupCombo("c", "Space", (*) => SendEvent("0"))
    QMK.SetupCombo("c", ";", (*) => SendEvent("{Backspace}"))
    QMK.SetupCombo("c", "'", (*) => SendEvent("^{Backspace}"))
    QMK.SetupCombo("c", "[", (*) => SendEvent("."))
    QMK.SetupCombo("c", "Enter", (*) => mouse.click("c"))

**Mouse Control (d layer):**

    QMK.SetupCombo("d", "l", (*) => SetTimer(mouse.move, -1))  ; Move right
    QMK.SetupCombo("d", "i", (*) => SetTimer(() => Scroll.up(), -1))  ; Scroll up
    QMK.SetupCombo("d", "j", (*) => SetTimer(mouse.move, -1))  ; Move down
    QMK.SetupCombo("d", "k", (*) => SetTimer(mouse.move, -1))  ; Move up
    QMK.SetupCombo("d", "f", (*) => SendEvent("+#{s}"))  ; Snipping tool
    QMK.SetupCombo("d", "h", (*) => SetTimer(mouse.move, -1))  ; Move left
    QMK.SetupCombo("d", "u", (*) => Send("{Browser_Back}"))  ; Browser back
    QMK.SetupCombo("d", "p", (*) => Send("{Browser_Forward}"))  ; Browser forward
    QMK.SetupCombo("d", ",", (*) => SetTimer(() => Scroll.Down(), -1))  ; Scroll down
    QMK.SetupCombo("d", "Enter", (*) => SetTimer(() => mouse.click("d"), -1))  ; Click

**Editing (f layer for cursor movement):**

    QMK.SetupCombo("f", "h", (*) => SendEvent("^{Left}"))  ; Move left word
    QMK.SetupCombo("f", "k", (*) => SendEvent("{Up}"))  ; Move up
    QMK.SetupCombo("f", "j", (*) => SendEvent("{Down}"))  ; Move down
    QMK.SetupCombo("f", "l", (*) => SendEvent("^{Right}"))  ; Move right word
    QMK.SetupInstantCombo("f", ";", (*) => SendEvent("{Backspace}"))  ; Backspace
    QMK.SetupInstantCombo("f", "'", (*) => SendEvent("{Delete}"))  ; Delete

**Larger Movements (g layer for Go):**

    QMK.SetupInstantCombo("g", ";", (*) => SendEvent("^{Backspace}"))  ; Delete word backward
    QMK.SetupInstantCombo("g", "'", (*) => SendEvent("^{Delete}"))  ; Delete word forward
    QMK.SetupCombo("g", "j", (*) => Send("{Down}"))  ; Move down
    QMK.SetupCombo("g", "k", (*) => Send("{Up}"))  ; Move up
    QMK.SetupCombo("g", "h", (*) => Send("{Home}"))  ; Move to line start
    QMK.SetupCombo("g", "l", (*) => Send("{End}"))  ; Move to line end
    QMK.SetupCombo("g", "u", (*) => Send("^{Home}"))  ; Move to document start
    QMK.SetupCombo("g", "n", (*) => Send("^{End}"))  ; Move to document end

**Escape Combo:**

    QMK.SetupInstantCombo("j", "k", (*) => Send("{Escape}"))
    QMK.SetupInstantCombo("k", "j", (*) => Send("{Escape}"))

**Program Layer (p layer, commented out for inspiration):**

    ; QMK.SetupCombo("p", "a", (*) => anki.activate(true))
    ; QMK.SetupCombo("p", "z", (*) => zen.activate(true))
    ; QMK.SetupCombo("p", "s", (*) => spotify.activate(true))
    ; QMK.SetupCombo("p", "m", (*) => messenger.activate(true))
    ; QMK.SetupCombo("p", "w", (*) => word.activate())
    ; QMK.SetupCombo("p", "d", (*) => runchecklist())
    ; QMK.SetupCombo("p", "o", (*) => Onenote.activate(true))
    ; QMK.SetupCombo("p", "u", (*) => outlookdesktop.activate(true))

**Shift Layer (s layer for Shift-modified keys):**

    QMK.SetupInstantCombo("s", ";", (*) => SendEvent("{:}"))  ; Send colon
    QMK.SetupInstantCombo("s", "'", (*) => SendEvent("{`"}"))  ; Send quote

**Space Combos (commented out to avoid typing issues):**

    ; QMK.SetupCombo("a", "Space", (*) => SendEvent("a "))
    ; QMK.SetupCombo("s", "Space", (*) => SendEvent("s "))
    ; QMK.SetupCombo("d", "Space", (*) => SendEvent("d "))
    ; QMK.SetupCombo("f", "Space", (*) => SendEvent("f "))

**Volume Layer (v layer, commented out for inspiration):**

    ; QMK.SetupCombo("v", "j", (*) => media.volume.down())
    ; QMK.SetupCombo("v", "k", (*) => media.volume.up())
    ; QMK.SetupCombo("v", "m", (*) => media.volume.mute())
    ; QMK.SetupCombo("v", "l", (*) => media.next())
    ; QMK.SetupCombo("v", "h", (*) => media.previous())
    ; QMK.SetupCombo("v", "p", (*) => media.toggleplaypause())

**Website Layer (w layer, commented out for inspiration, requires UIA):**

    ; QMK.SetupCombo("w", "c", (*) => chatgpt.screenshot())
    ; QMK.SetupCombo("w", "d", (*) => globals.activaterun("Google Docs", "https://docs.google.com/"))
    ; QMK.SetupCombo("w", "g", (*) => globals.activaterun("Gmail", "https://mail.google.com"))
    ; QMK.SetupCombo("w", "j", (*) => globals.activaterun("ChatGPT", "https://chatgpt.com/?temporary-chat=true&model=gpt-5-instant"))
    ; QMK.SetupCombo("w", "k", (*) => globals.activaterun("Claude", "https://claude.ai/new"))
    ; QMK.SetupCombo("w", "n", (*) => globals.activaterun("NotebookLM", "https://notebooklm.google.com/"))
    ; QMK.SetupCombo("w", "r", (*) => globals.activaterun("Grok", "https://grok.com"))
    ; QMK.SetupCombo("w", "p", (*) => globals.activaterun("Spotify for Creators", "https://creators.spotify.com/pod/show/7lNvdBsvWKhblGyVn80JTo/episodes?pageSize=30"))
    ; QMK.SetupCombo("w", "y", (*) => globals.activaterun("Youtube", "https://www.youtube.com"))

**Spotify Playlist (dot layer, commented out for inspiration):**

    ; QMK.SetupCombo(".", "l", (*) => Spotify.PlayPlaylist("Liked Songs"))

**Holds (hjkl for window management, global):**

    QMK.SetupHold("h", ["global"], (*) => mm.SnapLeft("A"))  ; Snap left
    QMK.SetupHold("j", ["global"], (*) => mm.GestureDL())  ; Restore/minimize
    QMK.SetupHold("k", ["global"], (*) => mm.GestureUR())  ; Maximize/fullscreen
    QMK.SetupHold("l", ["global"], (*) => mm.SnapRight("A"))  ; Snap right
    QMK.SetupHold("u", ["global"], (*) => mm.GestureUL())  ; Close window
    QMK.SetupHold("o", ["global"], (*) => mm.GestureUR())  ; Maximize/fullscreen
    QMK.SetupHold("n", ["global"], (*) => mm.GestureDL())  ; Restore/minimize
    QMK.SetupHold("m", ["global"], (*) => mm.GestureDL())  ; Restore/minimize
    QMK.SetupHold(".", ["global"], (*) => mm.GestureDR())  ; Minimize

**Program-Specific Holds (commented out for inspiration):**

    ; QMK.SetupHold("k", ["ahk_exe ONENOTE.EXE"], (*) => onenote.GestureUR())
    ; QMK.SetupHold("j", ["ahk_exe ONENOTE.EXE"], (*) => onenote.GestureDL())
    ; QMK.SetupHold("j", ["ahk_exe anki.exe"], (*) => anki.GestureDL())
    ; QMK.SetupHold("k", ["ahk_exe anki.exe"], (*) => anki.GestureUR())

**Program Activation Holds (commented out for inspiration):**

    ; QMK.SetupHold("a", ["global"], (*) => anki.activate(true))
    ; QMK.SetupHold("c", ["global"], (*) => globals.activaterun("Google Calendar", "https://calendar.google.com/calendar/u/0/r"))
    ; QMK.SetupHold("d", ["global"], (*) => runchecklist())
    ; QMK.SetupHold("e", ["global"], (*) => edge.activate(true))
    ; QMK.SetupHold("f", ["global"], (*) => globals.activaterun("ChatGPT", "https://chatgpt.com/?temporary-chat=true&model=gpt-4o"))
    ; QMK.SetupHold("g", ["global"], (*) => globals.activaterun("Gmail", "https://mail.google.com/mail/u/0/#inbox"))
    ; QMK.SetupHold("p", ["global"], (*) => phonelink.activate(true))
    ; QMK.SetupHold("q", ["global"], (*) => (globals.quitminimize(), Activatelast()))
    ; QMK.SetupHold("r", ["global"], (*) => Send("^{home}"))
    ; QMK.SetupHold("s", ["global"], (*) => spotify.activate(true))
    ; QMK.SetupHold("t", ["global"], (*) => Run(lib "\Simple Timer.ahk"))
    ; QMK.SetupHold("v", ["global"], (*) => vscode.activate(true))
    ; QMK.SetupHold("w", ["global"], (*) => Send("^{w}"))
    ; QMK.SetupHold("x", ["global"], (*) => SecondaryMenus())
    ; QMK.SetupHold("y", ["global"], (*) => globals.activaterun("Youtube", "https://www.youtube.com"))
    ; QMK.SetupHold("Tab", ["global"], (*) => Send("!{Tab}"))
    ; QMK.SetupHold("[", ["global"], (*) => MenuMap["programs"].Show())
    ; QMK.SetupHold(";", ["global"], (*) => MenuMap["Spotify"].Show())

**Win32 Context Menus Holds:**

    QMK.SetupHold("l", ["ahk_class #32768"], (*) => (ToolTip(">>>> Moved Right!"), Send("^#{Right}"), SetTimer((*) => ToolTip(), -1000)))  ; Move to right desktop
    QMK.SetupHold("h", ["ahk_class #32768"], (*) => (ToolTip("<<<< Moved Left!"), Send("^#{Left}"), SetTimer((*) => ToolTip(), -1000)))  ; Move to left desktop
    QMK.SetupHold("k", ["ahk_class #32768"], (*) => (ToolTip("New Desktop!"), SetTimer(() => ToolTip(), -1000), Send("^#d")))  ; New desktop
    QMK.SetupHold("j", ["ahk_class #32768"], (*) => (ToolTip("Closed Desktop!"), SetTimer((*) => ToolTip(), -1000), Send("^#{F4}")))  ; Close desktop

**Timer Combos (commented out for inspiration):**

    ; QMK.SetupCombo("1", "m", (*) => (Run(lib "\Simple Timer.ahk 1"), SetTimer((*) => ToolTip(), -1000), ToolTip("1 minute timer started!")))
    ; QMK.SetupCombo("2", "m", (*) => (Run(lib "\Simple Timer.ahk 2"), SetTimer((*) => ToolTip(), -1000), ToolTip("2 minute timer started!")))
    ; QMK.SetupCombo("3", "m", (*) => (Run(lib "\Simple Timer.ahk 3"), SetTimer((*) => ToolTip(), -1000), ToolTip("3 minute timer started!")))
    ; QMK.SetupCombo("4", "m", (*) => (Run(lib "\Simple Timer.ahk 4"), SetTimer((*) => ToolTip(), -1000), ToolTip("4 minute timer started!")))
    ; QMK.SetupCombo("5", "m", (*) => (Run(lib "\Simple Timer.ahk 5"), SetTimer((*) => ToolTip(), -1000), ToolTip("5 minute timer started!")))
    ; QMK.SetupCombo("6", "m", (*) => (Run(lib "\Simple Timer.ahk 6"), SetTimer((*) => ToolTip(), -1000), ToolTip("6 minute timer started!")))
    ; QMK.SetupCombo("7", "m", (*) => (Run(lib "\Simple Timer.ahk 7"), SetTimer((*) => ToolTip(), -1000), ToolTip("7 minute timer started!")))
    ; QMK.SetupCombo("8", "m", (*) => (Run(lib "\Simple Timer.ahk 8"), SetTimer((*) => ToolTip(), -1000), ToolTip("8 minute timer started!")))
    ; QMK.SetupCombo("9", "m", (*) => (Run(lib "\Simple Timer.ahk 9"), SetTimer((*) => ToolTip(), -1000), ToolTip("9 minute timer started!")))
    ; QMK.SetupCombo("1", "0", (*) => (Run(lib "\Simple Timer.ahk 10"), SetTimer((*) => ToolTip(), -1000), ToolTip("10 minute timer started!")))
    ; and so on

**Virtual Key Remappings (only when physical Ctrl is not pressed):**

    ; #HotIf !GetKeyState('LControl', 'p')
    ; ^#h::ToolTip("<<<< Moved Left!"), Send("^#{Left}"), SetTimer(() => ToolTip(), -500)
    ; ^#l::ToolTip(">>>> Moved Right!"), Send("^#{Right}"), SetTimer(() => ToolTip(), -500)
    ; ^+l::^+Right
    ; ^+h::^+Left
    ; ^+k::+Up
    ; ^+j::+Down
    ; ^+c::^c
    ; #HotIf

---

## Context Priority Order

The `QMK` class in `QMKClass.ahk` checks contexts for holds in this order, triggering the first match:

1. Win32 Context Menus (`ahk_class #32768`)
2. Website-specific (URL matching, requires `OnWebsite.ahk`)
3. Window title matches
4. Window class matches
5. Browser fallback (`browser` or `browsers`)
6. Window executable matches
7. Global mappings (last resort)

Combos and instant combos are primarily global, with limited context sensitivity (e.g., Win32 context menus).

---

## Best Practices/Integration

- **Order Matters**: For holds, list more specific contexts first (e.g., `studio.youtube.com` before `youtube.com`):

        QMK.SetupHold("k", ["studio.youtube.com"], (*) => MsgBox("YouTube Studio"))
        QMK.SetupHold("k", ["youtube.com"], (*) => Send("{Space}"))

- **Integrates With**:
  - `MouseGestures.ahk`: Mouse-based gestures.
  - `8BitDo.ahk`: Controller-based shortcuts.
  - `Macropad.ahk`: Custom macro pad support.
  - All use `OnWebsite.ahk` for URL-sensitive hold actions. Consolidate into one script to reduce URL queries.

- **Typing Compatibility**: The script prioritizes normal typing during rapid key presses (within `comboQuietPeriod`). Use instant combos for critical shortcuts to avoid delays.

- **Combos vs. Holds**: Combos override modifier behavior when defined. Holds support full context sensitivity, while combos are mostly global.

---

## Advanced Configuration

Customize settings in the `QMK` class within `QMKClass.ahk`:

    static userconfig := {
        timingMode: "accurate",  ; "accurate" (microsecond timing) or "fast" (A_TickCount, less reliable)
        holdThreshold: 150,  ; ms to trigger hold actions (150-200ms recommended)
        maxBufferSize: 50,  ; Max keys in buffer (default 50)
        comboQuietPeriod: 150,  ; ms to prioritize typing over combos
        modifierThreshold: 200,  ; ms for stacking modifiers
        maxHoldTime: 1000,  ; ms before suppressing long-held keys
        maxholdsupresseskeys: true  ; Suppress keys held past maxHoldTime
    }

**Fallback Behaviors**:
- **Short Tap**: Sends the key as-is (e.g., tap `a` sends `a`).
- **Long Hold**: Triggers hold action if defined, else sends key.
- **Combos**: Trigger after `comboQuietPeriod` or immediately for instant combos.
- **Modifiers**: Activate after `holdThreshold` or when paired with another key.

Customize behaviors in `BufferKeyUp` or `ProcessQueue` methods in `QMKClass.ahk`.

---

## Troubleshooting

**Combo/Hold Not Firing:**
- Check for more specific context overriding global hold mappings.
- Ensure key is registered in `allKeys` in `QMKClass.ahk`.
- Verify `holdThreshold` or `comboQuietPeriod` isn’t too long.
- Check for physical modifier interference (e.g., holding Ctrl).

**Typing Issues:**
- Increase `comboQuietPeriod` in `QMKClass.ahk` for faster typing.
- Use instant combos for critical shortcuts.
- Comment out space combos in `QMK.ahk` if modifiers + space misfire:

        ; QMK.SetupCombo("a", "Space", (*) => SendEvent("a "))

**Buffer Stuck:**
- Press a traditional modifier (e.g., Ctrl, Alt) to clear the buffer.
- Call `QMK.EmergencyReset()` from `QMKClass.ahk` to reset all state.

**Performance Issues:**
- Enable `ProcessSetPriority("High")` in `QMK.ahk` for better responsiveness.
- Adjust `timingMode` to `"fast"` in `QMKClass.ahk` for older hardware, though less reliable.

---

## Performance Optimizations

For older hardware, uncomment these settings in `QMK.ahk`:

    ProcessSetPriority("High")  ; Prioritize script execution
    SetKeyDelay(-1, 0)
    SetDefaultMouseSpeed(0)
    SetMouseDelay(0)
    SetControlDelay(-1)
    SetWinDelay(-1)
    A_HotkeyInterval := 2000
    A_MaxHotkeysPerInterval := 200
