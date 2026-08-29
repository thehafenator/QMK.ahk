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

    Win+Escape       = Exit
    Ctrl+Shift+R     = Reload
    Ctrl+Alt+S       = Suspend / Resume
    F1               = QMK Settings
*/

; ============================================================================
; GLOBAL DEMO STATE
; ============================================================================

global DemoGui := 0
global DemoProgress := 0
global DemoTitle := 0
global DemoBody := 0
global DemoTry := 0
global DemoCode := 0
global DemoBack := 0
global DemoNext := 0

global DemoLesson := 0
global DemoLoaded := Map()

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
    . "The demo also shows the functions used to recreate these in your own shortcuts."
    . "your own shortcuts.`n`n"
    . "Click OK to begin. When you have finished, see the 'Tutorial.ahk' file for more in-depth examples and explanations",
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
    global DemoCode
    global DemoBack
    global DemoNext
    DemoGui := Gui("+Resize +AlwaysOnTop", "QMK.ahk — Interactive Demo & Tutorial")
    DemoGui.SetFont("s10", "Segoe UI")

    DemoProgress := DemoGui.AddText("xm ym w780 h24", "")
    DemoProgress.SetFont("s9 c666666", "Segoe UI")

    DemoTitle := DemoGui.AddText("xm y+8 w780 h42", "")
    DemoTitle.SetFont("s18 bold", "Segoe UI")

    DemoBody := DemoGui.AddText("xm y+10 w780 h90", "")

    DemoTry := DemoGui.AddText("xm y+10 w780 h100", "")
    DemoTry.SetFont("s10 bold", "Segoe UI")

    DemoGui.AddText("xm y+10 w780 h24", "What this looks like in your own QMK setup:")

    DemoCode := DemoGui.AddEdit("xm y+6 w780 h220 ReadOnly -Wrap +HScroll", "")
    DemoCode.SetFont("s9", "Consolas")

    DemoBack := DemoGui.AddButton("xm y+14 w100 h32", "Previous")
    DemoBack.OnEvent("Click", DemoPrevious)

    DemoNext := DemoGui.AddButton("x+8 yp w100 h32 Default", "Next")
    DemoNext.OnEvent("Click", DemoNextPage)

    settingsButton := DemoGui.AddButton("x+20 yp w120 h32", "QMK Settings")
    settingsButton.OnEvent("Click", DemoOpenSettings)

    tutorialButton := DemoGui.AddButton("x+8 yp w145 h32", "Open Full Tutorial")
    tutorialButton.OnEvent("Click", DemoOpenTutorial)

    exitButton := DemoGui.AddButton("x+8 yp w90 h32", "Exit")
    exitButton.OnEvent("Click", DemoExit)

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

    if (DemoLesson < 12)
        ShowLesson(DemoLesson + 1)
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
    global DemoProgress
    global DemoBack
    global DemoNext

    DemoLesson := number

    if !DemoLoaded.Has(number) {
        ActivateLesson(number)
        DemoLoaded[number] := true
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

    DemoProgress.Text := "Lesson " number " of 12"

    DemoBack.Enabled := number > 1

    if (number = 12) {
        DemoNext.Text := "Finished"
        DemoNext.Enabled := false
    } else {
        DemoNext.Text := "Next"
        DemoNext.Enabled := true
    }
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

SetLesson(title, body, tryText, codeText) {
    global DemoTitle
    global DemoBody
    global DemoTry
    global DemoCode

    DemoTitle.Text := title
    DemoBody.Text := body
    DemoTry.Text := tryText
    DemoCode.Value := codeText
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
        "1. Start with safety controls`n`n",
        "Before experimenting with keyboard behavior, it is useful to have "
        . "an immediate exit, reload, suspend, and Settings shortcut available.",
        "TRY IT:`n"
        . "F1 = QMK Settings`n"
        . "Ctrl+Alt+S = Suspend / Resume`n"
        . "Ctrl+Shift+R = Reload`n"
        . "Win+Escape = Exit",
        CodeLines(
            "QMK.SetupHotkeys([",
            "    [" "*#Escape" ", " "global" ", " "panicExit" ", true],",
            "    [" "*^+r" ", " "global" ", " "nativeReload" ", true],",
            "    [" "^!s" ", " "global" ", QMK.SuspendExempt((*) => QMK.Suspend())],",
            "    [" "F1" ", " "global" ", (*) => QMKUserConfig.ShowGui()],",
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
        "TRY IT:`n"
        . "Click the QMK Settings button below and look around. "
        . "You do not need to change anything.",
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
        "12. Now make it yours",
        "The setup families you just tried are the building blocks. "
        . "The real power comes from combining them with ordinary AutoHotkey "
        . "functions and any other libraries you already use.",
        "YOU'RE READY TO BUILD YOUR OWN:`n"
        . "Click Open Full Tutorial and use it as a reference while writing "
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
            "; Because callbacks are normal AutoHotkey functions,",
            "; QMK can also integrate with optional libraries:",
            "",
            "; (*) => media.volume.up()",
            "; (*) => mm.SnapLeft()",
            "; (*) => mouse.move(" "h" ")",
            "; (*) => OpenGmail()"
        )
    )
}

; ============================================================================
; CUMULATIVE DEMO SETUP
; ============================================================================

SetupDemoSafety() {
    QMK.SetupHotkeys([
        ["*#Escape", "global", "panicExit", true],
        ["*^+r", "global", "nativeReload", true],
        ["^!s", "global", QMK.SuspendExempt((*) => QMK.Suspend())],
        ["F1", "global", (*) => QMKUserConfig.ShowGui()],
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
    tutorialPath := A_ScriptDir "\docs\TUTORIAL.md"

    if FileExist(tutorialPath) {
        Run(tutorialPath)
        return
    }

    MsgBox(
        "Could not find the tutorial at:`n`n"
        . tutorialPath
        . "`n`nOpen docs\TUTORIAL.md from the QMK repository.",
        "QMK.ahk Tutorial"
    )
}