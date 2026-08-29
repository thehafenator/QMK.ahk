#Requires AutoHotkey v2.0
#SingleInstance Force
#Include QMKInterception.ahk

#Include lib\Example Dependencies\UIA\Lib\UIA.ahk
#Include lib\Example Dependencies\UIA\Lib\UIA_Browser.ahk
#Include lib\Example Dependencies\Monitor Manager.ahk
#Include lib\Example Dependencies\OnWebsite.ahk
#Include lib\Example Dependencies\mouse.ahk
#Include lib\Example Dependencies\scroll.ahk
#Include lib\Example Dependencies\TabActivator.ahk

/*
    ============================================================================
    QMK.ahk — INTERACTIVE DEMO & TUTORIAL
    Version: DEMO-2.0-PLAIN-FUNCTIONS
    ============================================================================

    This demo follows the general order of ReadMe_Tutorial.ahk.

    HOW IT WORKS

    - Each page is a normal Lesson1(), Lesson2(), etc. function.
    - When the user reaches a lesson for the first time, that lesson's setup
      function is called.
    - Setup is cumulative.
    - Nothing is cleared when moving forward.
    - Previous only changes the information displayed in the GUI.
    - The code shown in the GUI is representative of what the user would put
      in their own QMK configuration.

    Ctrl+Alt+S       = Suspend / Resume
    Ctrl+Shift+R     = Reload
    Win+Escape       = Exit
*/

; ============================================================================
; GLOBAL DEMO STATE
; ============================================================================

global DemoGui := 0
global DemoProgress := 0
global DemoTitle := 0
global DemoBody := 0
global DemoTry := 0
global DemoStatus := 0
global DemoCode := 0
global DemoPlayground := 0
global DemoSettingsButton := 0
global DemoBack := 0
global DemoNext := 0

global DemoLesson := 0
global DemoLoaded := Map()
global DemoPlaygroundSaved := Map()

; ============================================================================
; INTRO
; ============================================================================

introResult := MsgBox(
    "Welcome to the QMK.ahk interactive demo.`n`n"
    . "This is meant to give you an idea of what QMK.ahk can do and let you "
    . "try the main shortcut families yourself.`n`n"
    . "The examples are intentionally basic. Each time you click Next, the "
    . "next example is added to the running QMK configuration, so you can test it out yourself. Earlier "
    . "examples stay active.`n`n"
    . "You can try the examples anywhere that makes sense: a text editor, "
    . "browser text box, document, or another application you already use.`n`n"
    . "The demo also shows the functions used to recreate these in your own shortcuts.`n`n"
    . "Click OK to begin. When you finish, you can open lib\ReadMe_Tutorial.ahk "
    . "for the full tutorial and more in-depth examples.",
    "QMK.ahk — Interactive Demo",
    "OKCancel Iconi"
)

if (introResult = "Cancel")
    ExitApp()

BuildDemoGui()
ShowLesson(1)

; ============================================================================
; GUI
; ============================================================================

BuildDemoGui() {
    global DemoGui
    global DemoProgress
    global DemoTitle
    global DemoBody
    global DemoTry
    global DemoStatus
    global DemoCode
    global DemoPlayground
    global DemoSettingsButton
    global DemoBack
    global DemoNext

    DemoGui := Gui("+Resize +AlwaysOnTop", "QMK.ahk — Interactive Demo & Tutorial")
    DemoGui.SetFont("s10", "Segoe UI")

    DemoProgress := DemoGui.AddText("x10 y10 w780 h22", "")
    DemoProgress.SetFont("s9 c666666", "Segoe UI")

    DemoStatus := DemoGui.AddText("x10 y34 w780 h22", "")
    DemoStatus.SetFont("s9 bold", "Segoe UI")

    DemoTitle := DemoGui.AddText("x10 y60 w780 h40", "")
    DemoTitle.SetFont("s18 bold", "Segoe UI")

    DemoBody := DemoGui.AddText("x10 y104 w780 h70", "")

    DemoGui.AddGroupBox("x10 y180 w780 h108", "Try it")
    DemoTry := DemoGui.AddText("x24 y204 w752 h70", "")
    DemoTry.SetFont("s10 bold", "Segoe UI")

    DemoGui.AddText("x10 y300 w380 h24", "What this looks like in your QMK setup:")
    DemoGui.AddText("x410 y300 w380 h24", "Try it here:")

    DemoCode := DemoGui.AddEdit("x10 y326 w380 h214 ReadOnly -Wrap +HScroll", "")
    DemoCode.SetFont("s9", "Consolas")

    DemoPlayground := DemoGui.AddEdit("x410 y326 w380 h214", "")
    DemoPlayground.SetFont("s10", "Consolas")

    exitButton := DemoGui.AddButton("x10 y570 w90 h32", "Exit")
    exitButton.OnEvent("Click", DemoExit)

    DemoSettingsButton := DemoGui.AddButton("x108 y570 w120 h32", "QMK Settings")
    DemoSettingsButton.OnEvent("Click", DemoOpenSettings)
    DemoSettingsButton.Visible := false

    DemoBack := DemoGui.AddButton("x600 y570 w100 h32", "Previous")
    DemoBack.OnEvent("Click", DemoPrevious)

    DemoNext := DemoGui.AddButton("x708 y570 w100 h32 Default", "Next")
    DemoNext.OnEvent("Click", DemoNextPage)

    DemoGui.OnEvent("Close", DemoExit)
    DemoGui.OnEvent("Escape", DemoExit)

    DemoGui.Show("w820 h620")
}

DemoPrevious(*) {
    global DemoLesson

    if (DemoLesson > 1)
        ShowLesson(DemoLesson - 1)
}

DemoNextPage(*) {
    global DemoLesson

    if (DemoLesson < 12) {
        ShowLesson(DemoLesson + 1)
        return
    }

    OpenFullTutorial()
}

DemoOpenSettings(*) {
    QMKUserConfig.ShowGui()
}

DemoOpenTutorial(*) {
    OpenFullTutorial()
}

DemoExit(*) {
    ExitApp()
}

; ============================================================================
; LESSON NAVIGATION
; ============================================================================

ShowLesson(number) {
    global DemoLesson
    global DemoLoaded
    global DemoPlaygroundSaved
    global DemoPlayground
    global DemoProgress
    global DemoStatus
    global DemoSettingsButton
    global DemoBack
    global DemoNext

    if (DemoLesson > 0 && DemoLesson != number)
        DemoPlaygroundSaved[DemoLesson] := DemoPlayground.Value

    DemoLesson := number
    newlyActivated := false

    if !DemoLoaded.Has(number) {
        ActivateLesson(number)
        DemoLoaded[number] := true
        newlyActivated := true
    }

    switch number {
        case 1:
            Lesson1()
        case 2:
            Lesson2()
        case 3:
            Lesson3()
        case 4:
            Lesson4()
        case 5:
            Lesson5()
        case 6:
            Lesson6()
        case 7:
            Lesson7()
        case 8:
            Lesson8()
        case 9:
            Lesson9()
        case 10:
            Lesson10()
        case 11:
            Lesson11()
        case 12:
            Lesson12()
    }

    DemoProgress.Text := (number = 12) ? "Demo complete" : "Lesson " number " of 12"
    DemoStatus.Text := newlyActivated ? DemoActivationText(number) : ""
    DemoBack.Enabled := number > 1
    DemoSettingsButton.Visible := (number = 12)

    if (number = 12) {
        DemoNext.Text := "Open Full Tutorial"
        DemoNext.Enabled := true
    } else {
        DemoNext.Text := "Next"
        DemoNext.Enabled := true
    }
}

DemoActivationText(number) {
    switch number {
        case 1:
            return "✓ Safety shortcuts are now active"
        case 2:
            return "✓ Home-row modifiers are now active"
        case 3:
            return "✓ Context-specific modifier examples are now active"
        case 4:
            return "✓ Combos are now active"
        case 6:
            return "✓ Chords are now active"
        case 7:
            return "✓ Holds, taps, and double taps are now active"
        case 8:
            return "✓ Hotstrings are now active"
        case 9:
            return "✓ Hotkeys are now active"
    }

    return ""
}

ActivateLesson(number) {
    switch number {
        case 1:
            SetupDemoSafety()

        case 2:
            SetupDemoModifiers()

        case 3:
            SetupDemoContexts()

        case 4:
            SetupDemoCombos()

        case 6:
            SetupDemoChords()

        case 7:
            SetupDemoTapHoldFamily()

        case 8:
            SetupDemoHotstrings()

        case 9:
            SetupDemoHotkeys()
    }
}

; ============================================================================
; DISPLAY HELPERS
; ============================================================================

SetLesson(title, body, tryText, codeText, playgroundText := "") {
    global DemoLesson
    global DemoPlaygroundSaved
    global DemoTitle
    global DemoBody
    global DemoTry
    global DemoCode
    global DemoPlayground

    DemoTitle.Text := title
    DemoBody.Text := body
    DemoTry.Text := tryText
    DemoCode.Value := codeText

    if DemoPlaygroundSaved.Has(DemoLesson) {
        DemoPlayground.Value := DemoPlaygroundSaved[DemoLesson]
        return
    }

    if (playgroundText = "")
        playgroundText := DemoPlaygroundText(title)

    DemoPlayground.Value := playgroundText
}

DemoPlaygroundText(title) {
    switch title {
        case "1. Start with safety controls":
            return "This box is yours to type in.`r`n`r`nThe safety shortcuts are active while you work through the demo."

        case "2. Home-row modifiers":
            return "Type normally here.`r`n`r`nThen try:`r`nHold A + T`r`nHold L + s`r`nStack A + S + another key"

        case "3. Context-aware shortcuts":
            return "Contexts make the same physical key behave differently depending on the active app, title, class, browser, or website.`r`n`r`nYou can keep typing here while reading the example on the left."

        case "4. Two-key combos":
            return "Move around inside this sentence using A+H and A+L.`r`n`r`nDelete some of these words with A+;.`r`n`r`nTry C+J, C+K, and C+L here: 123456789"

        case "5. Quiet period and rollover":
            return "Type quickly and naturally here.`r`n`r`nThe goal is for normal overlapping typing to still feel normal, while deliberate QMK combos continue to work."

        case "6. Three-, four-, and five-key chords":
            return "Select words in this sentence using A+S+H and A+S+L.`r`n`r`nChords let larger groups of keys become their own shortcuts."

        case "7. Holds, taps, tap-holds, and double taps":
            return "Try the lesson shortcuts, then type here normally.`r`n`r`nHold F2`r`nTap F3`r`nDouble-tap F4"

        case "8. Hotstrings":
            return "Type this below:`r`n`r`nqmkdemo`r`n`r`nThen try:`r`naddr"

        case "9. Hotkeys":
            return "Move the caret around this text using Alt+H/J/K/L.`r`n`r`nYou can keep typing here to give yourself more text to navigate."

        case "10. User Settings":
            return "QMK Settings controls the runtime backends and timing values.`r`n`r`nA Settings button will appear on the final page so you can explore it after the demo."

        case "11. Compiling your own QMKCore":
            return "Shortcut changes do not require recompiling QMKCore.`r`n`r`nThe compiler is an advanced option for rebuilding the native core itself."

        case "12. Demo complete":
            return "Everything you enabled during the demo is still active.`r`n`r`nTry anything again here, then open the full tutorial when you are ready to build your own shortcuts."
    }

    return "Try the current lesson here."
}

CodeLines(lines*) {
    output := ""

    for index, line in lines {
        if (index > 1)
            output .= "`r`n"

        output .= line
    }

    return output
}

; ============================================================================
; LESSON 1 — SAFETY
; ============================================================================

Lesson1() {
    SetLesson(
        "1. Start with safety controls",
        "Before experimenting with keyboard behavior, it is useful to have "
        . "an immediate exit, reload, suspend, and Settings shortcut available.",
        "TRY IT:`n"
        . "Ctrl+Alt+S = Suspend / Resume`n"
        . "Ctrl+Shift+R = Reload`n"
        . "Win+Escape = Exit",
        CodeLines(
            "QMK.SetupHotkeys([",
            "    [" "^!s" ", " "global" ", QMK.SuspendExempt((*) => QMK.Suspend())],",
            "    [" "*^+r" ", " "global" ", " "nativeReload" ", true],",
            "    [" "*#Escape" ", " "global" ", " "panicExit" ", true],",
            "])"
        )
    )
}

; ============================================================================
; LESSON 2 — MODIFIERS
; ============================================================================

Lesson2() {
    SetLesson(
        "2. Home-row modifiers",
        "A normal letter can behave like Ctrl, Shift, Win, or Alt while held. "
        . "Tapping the key still types the normal character. Multiple modifiers "
        . "can also be held together.",
        "TRY IT somewhere you can type:`n"
        . "Tap A = a`n"
        . "Hold A + T = Ctrl+T`n"
        . "Hold L + S = Shift+S`n"
        . "Try stacking several home-row modifiers together.",
        CodeLines(
            "QMK.SetupModifiers([",
            "    [" "a" ", " "Ctrl" "],",
            "    [" "s" ", " "Shift" "],",
            "    [" "d" ", " "Win" "],",
            "    [" "f" ", " "Alt" "],",
            "    [" "j" ", " "Alt" "],",
            "    [" "k" ", " "Win" "],",
            "    [" "l" ", " "Shift" "],",
            "    [" ";" ", " "Ctrl" "],",
            "])"
        )
    )
}

; ============================================================================
; LESSON 3 — CONTEXTS
; ============================================================================

Lesson3() {
    SetLesson(
        "3. Context-aware shortcuts",
        "QMK mappings can be limited to an executable, window class, title, "
        . "website, browser, or global context. This works similarly to "
        . "AutoHotkey #HotIf, but the context is supplied directly in the setup row.",
        "THIS ONE IS MOSTLY CONCEPTUAL:`n"
        . "The example gives CapsLock different behavior in different programs. "
        . "If you use one of those applications, you can try it there.",
        CodeLines(
            "QMK.SetupModifiers([",
            "    [" "CapsLock" ", " "Ctrl" ",",
            "        " "ahk_exe Code.exe, ahk_class Chrome_WidgetWin_1 ahk_exe msedge.exe" "],",
            "",
            "    [" "CapsLock" ", " "Escape" ",",
            "        " "ahk_class Chrome_WidgetWin_1 ahk_exe chrome.exe" "],",
            "])"
        )
    )
}

; ============================================================================
; LESSON 4 — COMBOS
; ============================================================================

Lesson4() {
    SetLesson(
        "4. Two-key combos",
        "`nCombos let two overlapping keys trigger their own action. "
        . "A combo can send keys directly through QMK or call a normal "
        . "AutoHotkey function.",
        "TRY IT somewhere you can edit text:`n"
        . "A + H = Ctrl+Left`n"
        . "A + L = Ctrl+Right`n"
        . "A + `; = Backspace`n"
        . "C + J/K/L = 4 / 5 / 6",
        CodeLines(
            "QMK.SetupCombos([",
            "    [" "a" ", " "h" ", " "global" ", QMK.SendKeyDirect(" "^{Left}" ")],",
            "    [" "a" ", " "l" ", " "global" ", QMK.SendKeyDirect(" "^{Right}" ")],",
            "    [" "a" ", " ";" ", " "global" ", QMK.SendKeyDirect(" "{Backspace}" "), " "instant" "],",
            "",
            "    [" "c" ", " "j" ", " "global" ", QMK.SendKeyDirect(" "4" ")],",
            "    [" "c" ", " "k" ", " "global" ", QMK.SendKeyDirect(" "5" ")],",
            "    [" "c" ", " "l" ", " "global" ", QMK.SendKeyDirect(" "6" ")],",
            "",
            "    [" "CapsLock" ", " "t" ", " "global" ", (*) => MyAhkFunction()],",
            "])"
        )
    )
}

; ============================================================================
; LESSON 5 — QUIET PERIOD
; ============================================================================

Lesson5() {
    SetLesson(
        "5. Quiet period and rollover",
        "Normal fast typing often contains overlapping key presses. QMK keeps "
        . "the physical press order and uses a quiet period to help distinguish "
        . "normal typing from intentional combinations.",
        "TRY IT:`n"
        . "Type quickly and normally for a few seconds. Then deliberately "
        . "activate one of the combos from the previous page.",
        CodeLines(
            "; Example timing setting:",
            "",
            "quietPeriodDuration = 150 ms",
            "",
            "; Normal combo:",
            "[" "a" ", " "h" ", " "global" ", QMK.SendKeyDirect(" "^{Left}" ")]",
            "",
            "; Instant combo bypasses the quiet period:",
            "[" "a" ", " ";" ", " "global" ", QMK.SendKeyDirect(" "{Backspace}" "), " "instant" "]"
        )
    )
}

; ============================================================================
; LESSON 6 — CHORDS
; ============================================================================

Lesson6() {
    SetLesson(
        "6. Three-, four-, and five-key chords",
        "Chords extend the combo idea to larger groups of keys. "
        . "They are useful when you want actions that are increasingly unlikely "
        . "to happen accidentally during normal typing.",
        "TRY IT in editable text:`n"
        . "A + S + H = Ctrl+Shift+Left`n"
        . "A + S + L = Ctrl+Shift+Right",
        CodeLines(
            "QMK.SetupChords([",
            "    [" "a" ", " "s" ", " "h" ", " "global" ", QMK.SendKeyDirect(" "^+{Left}" ")],",
            "    [" "a" ", " "s" ", " "l" ", " "global" ", QMK.SendKeyDirect(" "^+{Right}" ")],",
            "",
            ; "    ; Four-key example:",
            ; "    ; [""a"", ""s"", ""d"", ""h"", ""global"", (*) => SomeFunction()],",
            ; "",
            ; "    ; Five-key example:",
            ; "    ; [""a"", ""s"", ""d"", ""f"", ""o"", ""global"", (*) => AnotherFunction()],",
            "])"
        )
    )
}

; ============================================================================
; LESSON 7 — HOLDS / TAPS / DOUBLE TAPS
; ============================================================================

Lesson7() {
    SetLesson(
        "7. Holds, taps, tap-holds, and double taps",
        "A single physical key can perform different actions depending on "
        . "whether it is tapped, held, or pressed repeatedly.",
        "TRY IT:`n"
        . "Hold F2 = show a tooltip`n"
        . "Tap F3 = type [QMK tap]`n"
        . "Double-tap F4 = show a tooltip",
        CodeLines(
            "QMK.SetupHolds([",
            "    [" "F2" ", [" "global" "], (*) => ShowHoldDemo()],",
            "])",
            "",
            "QMK.SetupTaps([",
            "    [" "F3" ", " "global" ", QMK.SendKeyDirect(" "[QMK tap]" ")],",
            "])",
            "",
            "QMK.SetupDoubleTaps([",
            "    [" "F4" ", " "global" ", (*) => ShowDoubleTapDemo()],",
            "])"
        )
    )
}

; ============================================================================
; LESSON 8 — HOTSTRINGS
; ============================================================================

Lesson8() {
    SetLesson(
        "8. Hotstrings",
        "QMK can also handle AutoHotkey-style hotstrings. The replacement "
        . "can be direct text or an AutoHotkey callback.",
        "TRY IT somewhere you can type:`n"
        . "Type qmkdemo`n"
        . "It should immediately expand to: QMK.ahk is working!",
        CodeLines(
            "QMK.SetupHotstrings([",
            "    [" ":*:qmkdemo" ", " "global" ", " "QMK.ahk is working!" "],",
            "    [" ":*:addr" ", " "global" ", " "123 Example Street" "],",
            "",
            "    `; Callback example:",
            ; "     [":*:sig", "global", (*) => PasteMySignature()],",
            ; "    [" ":*:sig" ", " "global" ", (*) => PasteMySignature()],

            "])"
        )
    )
}

; ============================================================================
; LESSON 9 — HOTKEYS
; ============================================================================

Lesson9() {
    SetLesson(
        "9. Hotkeys",
        "QMK-managed hotkeys use familiar AutoHotkey-style hotkey syntax. "
        . "Simple actions can stay inside the native QMK send path, while "
        . "other hotkeys can call AutoHotkey functions.",
        "TRY IT:`n"
        . "Alt+H = Left`n"
        . "Alt+J = Down`n"
        . "Alt+K = Up`n"
        . "Alt+L = Right",
        CodeLines(
            "QMK.SetupHotkeys([",
            "    [" "!h" ", " "global" ", QMK.SendKeyDirect(" "{Left}" ")],",
            "    [" "!j" ", " "global" ", QMK.SendKeyDirect(" "{Down}" ")],",
            "    [" "!k" ", " "global" ", QMK.SendKeyDirect(" "{Up}" ")],",
            "    [" "!l" ", " "global" ", QMK.SendKeyDirect(" "{Right}" ")],",
            "])"
        )
    )
}

; ============================================================================
; LESSON 10 — SETTINGS
; ============================================================================

Lesson10() {
    SetLesson(
        "10. User Settings",
        "QMKconfig.ini stores user settings and QMK Settings provides a GUI "
        . "for changing them. This includes the input backend, output mode, "
        . "timing values, repeat behavior, and other runtime options.",
        "FOR NOW:`n"
        . "This page explains the main settings. A QMK Settings button will appear "
        . "on the final page so you can explore them after finishing the demo.",
        CodeLines(
            "Input backend:",
            "    auto",
            "    interception",
            "    llhook",
            "    ahk_hotkeys",
            "",
            "Send mode:",
            "    auto",
            "    interception",
            "    sendinput",
            "",
            "Timing settings include:",
            "    singleKeyHoldThreshold",
            "    quietPeriodDuration",
            "    modifierGestureWindow",
            "    doubleTapThreshold",
            "    repeatInitialDelay",
            "    repeatInterval"
        )
    )
}

; ============================================================================
; LESSON 11 — COMPILER
; ============================================================================

Lesson11() {
    SetLesson(
        "11. Compiling your own QMKCore",
        "You do not need to compile QMKCore just to create or change shortcuts. "
        . "Your shortcuts are runtime configuration. The compiler is for users "
        . "who want to rebuild the native core itself.",
        "NOTHING IS COMPILED BY THIS DEMO.`n"
        . "If you want to build QMKCore yourself, use QMKCompiler.ahk.",
        CodeLines(
            "; Normal shortcut changes:",
            ";     Edit your QMK.Setup... calls",
            ";     Reload",
            ";     No Zig compilation required",
            "",
            "; Native build:",
            ";     Open QMKCompiler.ahk",
            ";     Choose the build type",
            ";     Verify tool paths",
            ";     Compile"
        )
    )
}

; ============================================================================
; LESSON 12 — OPTIONAL INTEGRATIONS / NEXT STEP
; ============================================================================

Lesson12() {
    SetLesson(
        "12. Demo complete",
        "You have now tried the main QMK shortcut families. Everything you added "
        . "during the demo is still active, and the same QMK.Setup... calls can be "
        . "used in your own configuration.",
        "READY TO MAKE IT YOURS:`n"
        . "Use the playground for one last test, open QMK Settings if you want to "
        . "see the runtime options, then click Open Full Tutorial to start building "
        . "your own shortcuts.",
        CodeLines(
            "QMK.SetupModifiers([...])",
            "QMK.SetupCombos([...])",
            "QMK.SetupChords([...])",
            "QMK.SetupHolds([...])",
            "QMK.SetupTaps([...])",
            "QMK.SetupDoubleTaps([...])",
            "QMK.SetupHotstrings([...])",
            "QMK.SetupHotkeys([...])",
            "",
            "Next: lib\ReadMe_Tutorial.ahk"
        )
    )
}

; ============================================================================
; CUMULATIVE DEMO SETUP
; ============================================================================

SetupDemoSafety() {
    QMK.SetupHotkeys([
        ["^!s", "global", QMK.SuspendExempt((*) => QMK.Suspend())],
        ["*^+r", "global", "nativeReload", true],
        ["*#Escape", "global", "panicExit", true],
    ])
}

SetupDemoModifiers() {
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
}

SetupDemoContexts() {
    QMK.SetupModifiers([
        [
            "CapsLock",
            "Ctrl",
            "ahk_exe Code.exe, ahk_class Chrome_WidgetWin_1 ahk_exe msedge.exe"
        ],
        [
            "CapsLock",
            "Escape",
            "ahk_class Chrome_WidgetWin_1 ahk_exe chrome.exe"
        ],
    ])
}

SetupDemoCombos() {
    QMK.SetupCombos([
        ["a", "h", "global", QMK.SendKeyDirect("^{Left}")],
        ["a", "l", "global", QMK.SendKeyDirect("^{Right}")],
        [
            "a",
            ";",
            "global",
            QMK.SendKeyDirect("{Backspace}"),
            "instant"
        ],
        ["c", "j", "global", QMK.SendKeyDirect("4")],
        ["c", "k", "global", QMK.SendKeyDirect("5")],
        ["c", "l", "global", QMK.SendKeyDirect("6")],
        ["CapsLock", "t", "global", (*) => DemoCallback()],
    ])
}

SetupDemoChords() {
    QMK.SetupChords([
        [
            "a",
            "s",
            "h",
            "global",
            QMK.SendKeyDirect("^+{Left}")
        ],
        [
            "a",
            "s",
            "l",
            "global",
            QMK.SendKeyDirect("^+{Right}")
        ],
    ])
}

SetupDemoTapHoldFamily() {
    QMK.SetupHolds([
        [
            "F2",
            ["global"],
            (*) => ShowHoldDemo()
        ],
    ])

    QMK.SetupTaps([
        [
            "F3",
            "global",
            QMK.SendKeyDirect("[QMK tap]")
        ],
    ])

    QMK.SetupDoubleTaps([
        [
            "F4",
            "global",
            (*) => ShowDoubleTapDemo()
        ],
    ])
}

SetupDemoHotstrings() {
    QMK.SetupHotstrings([
        [
            ":*:qmkdemo",
            "global",
            "QMK.ahk is working!"
        ],
        [
            ":*:addr",
            "global",
            "123 Example Street"
        ],
    ])
}

SetupDemoHotkeys() {
    QMK.SetupHotkeys([
        [
            "!h",
            "global",
            QMK.SendKeyDirect("{Left}")
        ],
        [
            "!j",
            "global",
            QMK.SendKeyDirect("{Down}")
        ],
        [
            "!k",
            "global",
            QMK.SendKeyDirect("{Up}")
        ],
        [
            "!l",
            "global",
            QMK.SendKeyDirect("{Right}")
        ],
    ])
}

; ============================================================================
; CALLBACK EXAMPLES
; ============================================================================

DemoCallback() {
    ToolTip("This QMK combo called a normal AutoHotkey function.")

    SetTimer(
        (*) => ToolTip(),
        -1800
    )
}

ShowHoldDemo() {
    ToolTip("F2 hold action fired.")

    SetTimer(
        (*) => ToolTip(),
        -1800
    )
}

ShowDoubleTapDemo() {
    ToolTip("F4 double-tap action fired.")

    SetTimer(
        (*) => ToolTip(),
        -1800
    )
}

; ============================================================================
; DOCUMENTATION
; ============================================================================

OpenFullTutorial() {
    tutorialPath := A_ScriptDir "\lib\ReadMe_Tutorial.ahk"

    if FileExist(tutorialPath) {
        Run(tutorialPath)
        return
    }

    MsgBox(
        "Could not find the tutorial at:`n`n"
        . tutorialPath
        . "`n`nExpected file: lib\ReadMe_Tutorial.ahk",
        "QMK.ahk Tutorial"
    )
}