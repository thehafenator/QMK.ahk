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
    Version: DEMO-2.1-INTERACTIVE
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

    DemoGui.AddText("x10 y188 w380 h24", "What this looks like in your QMK setup:")
    DemoGui.AddText("x410 y188 w380 h24 Right", "Try it")

    DemoCode := DemoGui.AddEdit("x10 y214 w380 h326 ReadOnly -Wrap +HScroll", "")
    DemoCode.SetFont("s9", "Consolas")

    DemoTry := DemoGui.AddText("x410 y214 w380 h92", "")
    DemoTry.SetFont("s10 bold", "Segoe UI")

    DemoPlayground := DemoGui.AddEdit("x410 y312 w380 h228", "")
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

    if (DemoLesson < 11) {
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
    }

    DemoProgress.Text := (number = 11) ? "Demo complete" : "Lesson " number " of 11"
    DemoStatus.Text := newlyActivated ? DemoActivationText(number) : ""
    DemoBack.Enabled := number > 1
    DemoSettingsButton.Visible := (number >= 10)

    if (number = 11) {
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
            return "✓ Combos and the C numpad layer are now active"
        case 6:
            return "✓ Chords are now active"
        case 7:
            return "✓ Hold and tap examples are now active"
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
            return "This box is yours to type in.`r`n`r`nThe safety shortcuts stay available while you work through the demo."

        case "2. Home-row modifiers":
            return "Type normally here first.`r`n`r`nThen try A+F in a program where Ctrl+F opens Find.`r`nTry A+S+F for Ctrl+Shift+F.`r`n`r`nTap the modifier letters normally too."

        case "3. Context-aware shortcuts":
            return "Contexts let the same physical key behave differently depending on the active app, title, class, browser, or website.`r`n`r`nThis page is mainly showing the setup shape."

        case "4. Two-key combos":
            return "Move around this sentence with A+H and A+L.`r`n`r`nDelete a character with A+;.`r`n`r`nC-layer numpad:`r`nU I O = 7 8 9`r`nJ K L = 4 5 6`r`nN , . = 1 2 3`r`nSpace = 0"

        case "5. Quiet period and rollover":
            return "nation`r`n`r`nTry typing the word nation while deliberately overlapping your presses: press the next key before releasing the previous one, and occasionally release them out of order.`r`n`r`nKeep each key under about one second. QMK should preserve the original press order."

        case "6. Three-, four-, and five-key chords":
            return "Select words in this sentence using A+S+H and A+S+L.`r`n`r`nThese are three-key chords. The same API also supports four- and five-key chords."

        case "7. Holds and taps":
            return "Tap Q normally, then hold Q long enough to trigger the hold action.`r`n`r`nTap X to see a simple tap remap.`r`n`r`nThis page intentionally skips double-taps in the quick demo."

        case "8. Hotstrings":
            return "Type either of these and finish with Space:`r`n`r`nqmkdemo `r`naddr `r`n`r`nThe ending Space triggers the hotstring."

        case "9. Hotkeys":
            return "Move the caret around this text using Alt+H/J/K/L.`r`n`r`nYou can type more text here and keep navigating it."

        case "10. User Settings":
            return "Click QMK Settings below to inspect the input backend, send mode, timing, rollover, and repeat settings.`r`n`r`nYou do not need to change anything for the demo."

        case "11. Demo complete":
            return "Everything you enabled during the demo is still active.`r`n`r`nTry anything again here, explore QMK Settings if you want, then open the full ReadMe_Tutorial.ahk when you are ready to build your own setup."
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
        . "an immediate suspend, reload, and exit shortcut available.",
        "TRY IT:`n"
        . "Ctrl+Alt+S = Suspend / Resume`n"
        . "Ctrl+Shift+R = Reload`n"
        . "Win+Escape = Exit",
        CodeLines(
            "QMK.SetupHotkeys([",
            "    [""^!s"", ""global"", QMK.SuspendExempt((*) => QMK.Suspend())],",
            "    [""*^+r"", ""global"", ""nativeReload"", true],",
            "    [""*#Escape"", ""global"", ""panicExit"", true],",
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
        "Normal letters can behave like Ctrl, Shift, Win, or Alt while held, "
        . "while still typing normally when tapped. Modifiers can also stack.",
        "TRY IT:`n"
        . "Tap A normally = a`n"
        . "A + F = Ctrl+F`n"
        . "A + S + F = Ctrl+Shift+F`n"
        . "J / K / L / ; mirror Alt / Win / Shift / Ctrl on the right hand.",
        CodeLines(
            "QMK.SetupModifiers([",
            "    [""a"", ""Ctrl""],",
            "    [""s"", ""Shift""],",
            "    [""d"", ""Win""],",
            "    [""f"", ""Alt""],",
            "    [""j"", ""Alt""],",
            "    [""k"", ""Win""],",
            "    [""l"", ""Shift""],",
            "    ["";"", ""Ctrl""],",
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
        . "website, browser, or global context, similar to AutoHotkey #HotIf.",
        "CONCEPTUAL EXAMPLE:`n"
        . "The same CapsLock key can have different behavior depending on which application is active.",
        CodeLines(
            "QMK.SetupModifiers([",
            "    [""CapsLock"", ""Ctrl"",",
            "        ""ahk_exe Code.exe, ahk_class Chrome_WidgetWin_1 ahk_exe msedge.exe""],",
            "",
            "    [""CapsLock"", ""Escape"",",
            "        ""ahk_class Chrome_WidgetWin_1 ahk_exe chrome.exe""],",
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
        "Combos let two overlapping keys trigger their own action. They can also "
        . "turn a normal key into a layer key, such as C becoming a numpad layer.",
        "TRY IT:`n"
        . "A + H/L = Ctrl+Left / Ctrl+Right`n"
        . "A + ; = Backspace`n"
        . "Hold C with UIO / JKL / N,. for a numpad",
        CodeLines(
            "QMK.SetupCombos([",
            "    [""a"", ""h"", ""global"", QMK.SendKeyDirect(""^{Left}"")],",
            "    [""a"", ""l"", ""global"", QMK.SendKeyDirect(""^{Right}"")],",
            "    [""a"", "";"", ""global"", QMK.SendKeyDirect(""{Backspace}""), ""instant""],",
            "",
            "    [""c"", ""n"", ""global"", QMK.SendKeyDirect(""1"")],",
            "    [""c"", "","", ""global"", QMK.SendKeyDirect(""2"")],",
            "    [""c"", ""."", ""global"", QMK.SendKeyDirect(""3"")],",
            "    [""c"", ""j"", ""global"", QMK.SendKeyDirect(""4"")],",
            "    [""c"", ""k"", ""global"", QMK.SendKeyDirect(""5"")],",
            "    [""c"", ""l"", ""global"", QMK.SendKeyDirect(""6"")],",
            "    [""c"", ""u"", ""global"", QMK.SendKeyDirect(""7"")],",
            "    [""c"", ""i"", ""global"", QMK.SendKeyDirect(""8"")],",
            "    [""c"", ""o"", ""global"", QMK.SendKeyDirect(""9"")],",
            "    [""c"", ""Space"", ""global"", QMK.SendKeyDirect(""0"")],",
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
        "QMK keeps keys in physical press order even when normal fast typing causes "
        . "presses and releases to overlap. The quiet period helps separate typing from deliberate combos.",
        "TRY IT:`n"
        . "Type nation while intentionally overlapping the keys.`n"
        . "Press the next key before releasing the previous one, and release a few out of order.`n"
        . "Keep each key held under about one second.",
        CodeLines(
            "; QMK Settings -> Timing",
            "quietPeriodDuration = 150 ms",
            "",
            "; Normal combos respect rollover / quiet-period behavior:",
            "[""a"", ""h"", ""global"", QMK.SendKeyDirect(""^{Left}"")]",
            "",
            "; Instant combos fire as soon as recognized:",
            "[""a"", "";"", ""global"", QMK.SendKeyDirect(""{Backspace}""), ""instant""]"
        )
    )
}

; ============================================================================
; LESSON 6 — CHORDS
; ============================================================================

Lesson6() {
    SetLesson(
        "6. Three-, four-, and five-key chords",
        "Chords extend the combo idea to larger groups of keys. Three-key chords are "
        . "useful for frequent commands; the same API also supports four- and five-key groups.",
        "TRY IT:`n"
        . "A + S + H = Ctrl+Shift+Left`n"
        . "A + S + L = Ctrl+Shift+Right",
        CodeLines(
            "QMK.SetupChords([",
            "    [""a"", ""s"", ""h"", ""global"", QMK.SendKeyDirect(""^+{Left}"")],",
            "    [""a"", ""s"", ""l"", ""global"", QMK.SendKeyDirect(""^+{Right}"")],",
            "",
            "    ; Four-key shape:",
            "    ; [""a"", ""s"", ""d"", ""h"", ""global"", (*) => SomeFunction()],",
            "",
            "    ; Five-key shape:",
            "    ; [""a"", ""s"", ""d"", ""f"", ""o"", ""global"", (*) => AnotherFunction()],",
            "])"
        )
    )
}

; ============================================================================
; LESSON 7 — HOLDS / TAPS / DOUBLE TAPS
; ============================================================================

Lesson7() {
    SetLesson(
        "7. Holds and taps",
        "A single physical key can take a different path depending on how it is used. "
        . "This quick demo uses a normal hold and a simple tap remap, and leaves double-taps for the full tutorial.",
        "TRY IT:`n"
        . "Tap Q normally, then hold Q = tooltip`n"
        . "Tap X = [QMK tap]",
        CodeLines(
            "QMK.SetupHolds([",
            "    [""q"", [""global""], (*) => ShowHoldDemo()],",
            "])",
            "",
            "QMK.SetupTaps([",
            "    [""x"", ""global"", QMK.SendKeyDirect(""[QMK tap]"")],",
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
        "QMK can handle AutoHotkey-style hotstrings. In this demo the trigger waits "
        . "for an ending character, so type the abbreviation and then press Space.",
        "TRY IT:`n"
        . "Type qmkdemo + Space`n"
        . "Type addr + Space",
        CodeLines(
            "QMK.SetupHotstrings([",
            "    [""::qmkdemo"", ""global"", ""QMK.ahk is working!""],",
            "    [""::addr"", ""global"", ""123 Example Street""],",
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
        . "Simple key sends can stay inside the native QMK path.",
        "TRY IT:`n"
        . "Alt+H = Left`n"
        . "Alt+J = Down`n"
        . "Alt+K = Up`n"
        . "Alt+L = Right",
        CodeLines(
            "QMK.SetupHotkeys([",
            "    [""!h"", ""global"", QMK.SendKeyDirect(""{Left}"")],",
            "    [""!j"", ""global"", QMK.SendKeyDirect(""{Down}"")],",
            "    [""!k"", ""global"", QMK.SendKeyDirect(""{Up}"")],",
            "    [""!l"", ""global"", QMK.SendKeyDirect(""{Right}"")],",
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
        "QMKconfig.ini stores user settings and QMK Settings provides a GUI for "
        . "changing the input backend, send mode, timing, repeat behavior, and other runtime options.",
        "TRY IT:`n"
        . "Click the QMK Settings button below and look around. You do not need to change anything.",
        CodeLines(
            "Input backend:",
            "    auto | interception | llhook | ahk_hotkeys",
            "",
            "Send mode:",
            "    auto | interception | sendinput",
            "",
            "Timing:",
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
        "11. Demo complete",
        "You have now tried the main QMK shortcut families. Everything added during "
        . "the demo is still active, and these same QMK.Setup... calls are what you use in your own configuration.",
        "READY TO MAKE IT YOURS:`n"
        . "Try anything again, open QMK Settings if you want, then click Open Full Tutorial.",
        CodeLines(
            "QMK.SetupModifiers([...])",
            "QMK.SetupCombos([...])",
            "QMK.SetupChords([...])",
            "QMK.SetupHolds([...])",
            "QMK.SetupTaps([...])",
            "QMK.SetupHotstrings([...])",
            "QMK.SetupHotkeys([...])",
            "",
            "Next: lib\\ReadMe_Tutorial.ahk"
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
        ["a", ";", "global", QMK.SendKeyDirect("{Backspace}"), "instant"],

        ["c", "n", "global", QMK.SendKeyDirect("1")],
        ["c", "m", "global", QMK.SendKeyDirect("1")],
        ["c", ",", "global", QMK.SendKeyDirect("2")],
        ["c", ".", "global", QMK.SendKeyDirect("3")],
        ["c", "j", "global", QMK.SendKeyDirect("4")],
        ["c", "k", "global", QMK.SendKeyDirect("5")],
        ["c", "l", "global", QMK.SendKeyDirect("6")],
        ["c", "u", "global", QMK.SendKeyDirect("7")],
        ["c", "i", "global", QMK.SendKeyDirect("8")],
        ["c", "o", "global", QMK.SendKeyDirect("9")],
        ["c", "Space", "global", QMK.SendKeyDirect("0")],
        ["c", ";", "global", QMK.SendKeyDirect("{Backspace}")],
        ["c", "'", "global", QMK.SendKeyDirect("^{Backspace}")],
        ["c", "[", "global", QMK.SendKeyDirect(".")],
        ["c", "/", "global", QMK.SendKeyDirect(".")],

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
        ["q", ["global"], (*) => ShowHoldDemo()],
    ])

    QMK.SetupTaps([
        ["x", "global", QMK.SendKeyDirect("[QMK tap]")],
    ])
}

SetupDemoHotstrings() {
    QMK.SetupHotstrings([
        ["::qmkdemo", "global", "QMK.ahk is working!"],
        ["::addr", "global", "123 Example Street"],
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
    ToolTip("Q hold action fired.")

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