#Requires AutoHotkey v2.0

/*
    QMK.ahk User API Examples
    Project:
    https://github.com/thehafenator/QMK.ahk
    Allowing QMK-like behavior in AutoHotkey with a Zig DLL
    Last Updated: 08.27.2026
    Version 1.0 -  08.27.2026 release date
    =========================
    Brief change log:
    Version 08.27.2026:
    - First official/stable release. Includes following features:
        - Hold shortcuts
        - Modifiers (home row mods). Allow chaining, unless combo or chord overrides. 
        - Combos - 2-key shortcuts
        - Chords - 3, 4, or 5 key shortcuts
        - Hotkeys
        - Double tap shortcuts
        - Repeated tap - (double tap and hold a key to repeat it, like backspace)
        - FIFO Rollover support (keys sent in same order you type them)
        - Safety Exit/Reload in case of AutoHotkey freeze.
        - Quiet period (prevents accidental combo triggering)
        - Hotstrings, including pasting text and AHK callback
        - Context-Specific (different per application) 
        - Suspend and Suspend Exempt - per shortcut
        - Capture in Interception, low-level mouse hook in Zig, or via AHK hotkeys
        - Send keys in Interception or via SendInput 
        - The combination of the above two lets you try this script out without needing to install other dependencies or drivers. 
        - DLL integrated as machine-code base64 string for easier AHK compilation. See native code and compile natively if desired (see compiler below). Version using a DLL file directly to be made. 
         
        - User GUI for managing settings like:
        - Capturing with either Interception, low-level mouse hook, or AHK hotkeys
        - Send via Interception or SendInput
        - Option to toggle user config/default timings
        - Timing of holds, max hold, quiet period, modifier chaining, and repeat durations
        - Link to tutorial, and optional dependencies

        - User Compiler (Advanced, but for users to customize their own build)
        - Allows user to use profile guided optimization to compile more efficient machine code via Build tools and LLVM (fastest runtime, but requires more dependencies)
        - Standard Zig compilation path option - Zig version 0.16 required for build, though much easier to install. May be slightly slower, but still within 10us median key latency.

        - Speed Optimizations
        - Improved hotpath latency (median ~2 us PGO, or ~10us via standard zig compilation)
        - Improved startup load time (~10 ms, batched memory allocation for runtime user shortcuts)

    - Earlier versions of QMK.ahk were released in early 2025. The first was a direct implementation in AutoHotkey alone, and the second, an early alpha, used a combination of a Zig DLL and the Interception driver. Speed was very good in the latter, but needed additional tuning for release. Some syntax changes were made to improve load time.

    =========================

    This is a standalone example/reference file for understanding QMK.ahk
    syntax. It is not meant to be #Included as-is. Copy the shapes you want
    into your own shortcut file after QMK.ahk is loaded.

    These examples are intentionally basic. The same row shapes can go a long
    way once you start combining modifiers, combos, chords, contexts, hotkeys,
    and hotstrings.

    Some callbacks below use helper names from my own setup, such as media,
    edge, mm, VDA, and globals. Treat those as placeholders for your own
    AutoHotkey functions.

*/

/*
    Section 1: Recommended Starting 4 Shortcuts:
    Examples

*/
QMK.SetupHotkeys([
    ["*#Escape", "global", "panicExit", true],
    ["*^+r", "global", "nativeReload", true],
    ["^!s", "global", QMK.SuspendExempt((*) => QMK.Suspend())],
    ["F1", "global", (*) => QMKUserConfig.ShowGui()],
])

/*
    Practical note: In case AutoHotkey itself becomes unresponsive, these two hotkeys provide a safe way to exit or reload the QMK and AutoHotkey script from the DLL hook. If you have ever had a WinWait call in AutoHotkey that freezes your application indefinitely (waiting for a window that will never exist), this would be an instance where you would want to reload.

    Additionally, having a suspend hotkey like this can suspend both AHK and the Zig process, yet also let you resume them both without restarting. I find that having both exit and native reload suspend-exempt is helpful; they will still exit or reload the program, even if AutoHotkey and the Zig process are suspended.

    Unless your script has a #NoTrayIcon, you should be able to right click the tray icon and click "QMKSettings" to manage your preferences, but feel free to keep a hotkey like this F1 hotkey to also open the GUI. If you want to remove the tray icon, comment or delete these lines from the script:
  
    A_TrayMenu.Add("&QMK Settings", (*) => QMKUserConfig.ShowGui())
    A_TrayMenu.Default := "&QMK Settings"

From this menu, you should be able to change your settings from this GUI. See section 10 for more details. 
The QMK.SetupHotkeys() shown above will be explained in more detail in section 9. First, some basics.
*/

/*
    Section 2: Modifiers
*/
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

/*
Practical note - why use virtual modifiers?:
    Virtual modifiers, sometimes called 'home row modifiers', allow you to use any key as a modifier while it is being held. For example, pressing a+t together with the above block setting 'a' as Ctrl sends Ctrl+T, which opens a new tab in a browser without having to reach for the physical Control key.

    I use these primarily for ergonomics. The faster I type and the more shortcuts I try to use, especially with left-sided control keys, the more strain I notice. This also helps keep your fingers on the home row, which may be faster and may mean you do not need to look at the keyboard. It does take some getting used to for sure.
    Modifiers can be chained together (e.g., holding 'a' as Ctrl and 's' as Shift simultaneously to have 'asf' send ^+f).  
    I personally like asdf as Ctrl, Shift, Win, and Alt in the left hand because it kind of mirrors the physical modifiers on the left side of a standard keyboard. This meant I could kind of keep muscle memory in place. Using jkl; as a mirror offers a bit of flexibility. If s is 'Shift', but I want to press Shift+S together, having L also be Shift lets me send an uppercase 'S'. 
    
    Setup Modifier Shape:
        [key, modifierName] 
        [key, modifierName, context]
        [key, modifierName, context, suspendExempt] 
    Parameters:
        key
            The physical key that becomes a virtual modifier while held.
            Examples: "a", "CapsLock", "Space", ";".
        modifierName
            The virtual modifier role to apply. Common values are "Ctrl",
            "Shift", "Alt", and "Win", mimicking AutoHotkey naming conventions. 
        context
            Optional. "global" means the modifier works everywhere and is implied by default. App,
            window, and website contexts can narrow where the virtual modifier
            is active. See 'Section 3: Contexts' for more details.
        suspendExempt
            Optional true/false. true lets this modifier remain available while
            QMK is suspended.
    Put modifiers in families when you can. Calling QMK.SetupModifier() one at
    a time works, but grouped setup is easier to read and initializes much
    faster. 

*/

/*
    Section 3: Contexts
    Examples
*/
        QMK.SetupModifiers([
            ["Capslock", "Ctrl", "ahk_exe Code.exe, ahk_class Chrome_WidgetWin_1 ahk_exe msedge.exe", "false"],
            ["Capslock", "Escape", "ahk_class Chrome_WidgetWin_1 ahk_exe chrome.exe"],
        ])

/*
Practical Note:
Just like how AutoHotkey uses #HotIf directives to allow hotkeys in specific contexts, I've added this functionality to the DLL as well.
Notice the call above. This would allow me to use the CapsLock button as Ctrl in both VS Code or when Microsoft Edge is active. You'll also see in the first example that the ahk_class and ahk_exe are combined without a comma separating them, meaning both contexts must be true for it to work. When left blank, 'global' is implied, meaning the shortcut will run in all programs. 
Modifiers, combos, chords, holds, tap-holds, double-taps, hotkeys, and hotstrings can all be scoped by context.
The general priority rule is similar to my OnWebsite.ahk, 8Bitdo.ahk, and MouseGesture.ahk scripts:
1. ahk_class #32768  (win32 menus)
2. Specific website active (via OnWebsite.ahk). For example, "docs.google.com".
3. Specific class (ahk_class)
4. Specific executable (ahk_exe)
5. Global context ("global")
*/


/*
    Section 4: Two-Key Combinations: Combos
    Examples
*/
QMK.SetupCombos([
    ["a", "h", "global", QMK.SendKeyDirect("^{Left}")],
    ["a", "l", "global", QMK.SendKeyDirect("^{Right}")],
    ["a", ";", "global", QMK.SendKeyDirect("{Backspace}"), "instant"],
    ["CapsLock", "b", "global", (*) => ShowMenuWithDigits(MenuMap["default"])],
    ["CapsLock", "e", "global", (*) => edge.activate(true)],
    ["v", "k", "global", (*) => media.volume.up(), "instant"],
    ["v", "j", "global", (*) => media.volume.down(), "instant"],
])

/*

Practical Note:
    Combos are any two key combinations that can trigger sending specific keys or actions. Key remaps can be done here, though note that these will take priority over 2-key combinations of virtual modifiers. Holds and combos are probably my favorites.
    Ways I use this:
    As shown above, I like asdf as modifiers, and I also use hjkl for arrow keys. In my specific setup, wanting to mimic using Ctrl and the arrow keys to move around the document, I have a+h send Ctrl+Left, a+l send Ctrl+Right, and use a+; as Backspace.

    However, there may be times where you want an action other than sending a keystroke. For example, use V (as in 'volume') and the hjkl 'arrow' keys to increase/decrease the volume and skip forward/back tracks. This could be done with sending volume and media keys alone (see AutoHotkey documentation on keys for more detail), but my AHK script function uses a tooltip in the center of the screen. I also connect to see the name of the song playing after it changes. I also have v+m to mute.


    Other examples of combos I use:
    C + keys in the right hand for a 'calculator' - essentially letting me have a mini numpad on the right side of the keyboard without making me move my hands.
    B + j and k ('B' for 'Brightness' and jk for up/down) for a script to increase/decrease brightness on screen
    Timer script - I have a tooltip timer I use to keep track of task time (on Github). I set up combos of 1m for one minute, 2m for two minutes, 1+0 for ten minutes, and so on.
    X + hjkl (pseudo arrow keys) to move windows to previous/next screen
    f + hjkl (arrow keys) to move the mouse by itself on the screen. F+enter to click. F+i to scroll up, F+, to scroll down (j and k taken for mouse movements up/down). Very handy when mouse is not available.

    QMK.SetupCombos([
    ["a", "h", "global", QMK.SendKeyDirect("^{Left}")],
    ["a", "k", "global", QMK.SendKeyDirect("{Up}")],
    ["a", "j", "global", QMK.SendKeyDirect("{Down}")],
    ["a", "l", "global", QMK.SendKeyDirect("^{Right}")],
    ["a", "[", "global", QMK.SendKeyDirect("{Delete}")],
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
    ["b", "j", (*) => Brightness.AdjustScreenBrightness(-6)],
    ["b", "k", (*) => Brightness.AdjustScreenBrightness(6)],
    ["1", "m", (*) => (Run(lib "\Simple Timer.ahk 1"), SetTimer((*) => ToolTip(), -1000), ToolTip("1 minute timer started!"))],
    ["2", "m", (*) => (Run(lib "\Simple Timer.ahk 2"), SetTimer((*) => ToolTip(), -1000), ToolTip("2 minute timer started!"))],
    ["3", "m", (*) => (Run(lib "\Simple Timer.ahk 3"), SetTimer((*) => ToolTip(), -1000), ToolTip("3 minute timer started!"))],
    ["4", "m", (*) => (Run(lib "\Simple Timer.ahk 4"), SetTimer((*) => ToolTip(), -1000), ToolTip("4 minute timer started!"))],
    ["5", "m", (*) => (Run(lib "\Simple Timer.ahk 5"), SetTimer((*) => ToolTip(), -1000), ToolTip("5 minute timer started!"))],
    ["6", "m", (*) => (Run(lib "\Simple Timer.ahk 6"), SetTimer((*) => ToolTip(), -1000), ToolTip("6 minute timer started!"))],
    ["7", "m", (*) => (Run(lib "\Simple Timer.ahk 7"), SetTimer((*) => ToolTip(), -1000), ToolTip("7 minute timer started!"))],
    ["8", "m", (*) => (Run(lib "\Simple Timer.ahk 8"), SetTimer((*) => ToolTip(), -1000), ToolTip("8 minute timer started!"))],
    ["9", "m", (*) => (Run(lib "\Simple Timer.ahk 9"), SetTimer((*) => ToolTip(), -1000), ToolTip("9 minute timer started!"))],
    ["1", "0", (*) => (Run(lib "\Simple Timer.ahk 10"), SetTimer((*) => ToolTip(), -1000), ToolTip("10 minute timer started!"))],
    ["1", "2", (*) => (Run(lib "\Simple Timer.ahk 12"), SetTimer((*) => ToolTip(), -1000), ToolTip("12 minute timer started!"))],
    ["1", "3", (*) => (Run(lib "\Simple Timer.ahk 13"), SetTimer((*) => ToolTip(), -1000), ToolTip("13 minute timer started!"))],
    ["1", "4", (*) => (Run(lib "\Simple Timer.ahk 14"), SetTimer((*) => ToolTip(), -1000), ToolTip("14 minute timer started!"))],
    ["1", "5", (*) => (Run(lib "\Simple Timer.ahk 15"), SetTimer((*) => ToolTip(), -1000), ToolTip("15 minute timer started!"))],
    ["1", "6", (*) => (Run(lib "\Simple Timer.ahk 16"), SetTimer((*) => ToolTip(), -1000), ToolTip("16 minute timer started!"))],
    ["1", "7", (*) => (Run(lib "\Simple Timer.ahk 17"), SetTimer((*) => ToolTip(), -1000), ToolTip("17 minute timer started!"))],
    ["1", "8", (*) => (Run(lib "\Simple Timer.ahk 18"), SetTimer((*) => ToolTip(), -1000), ToolTip("18 minute timer started!"))],
    ["1", "9", (*) => (Run(lib "\Simple Timer.ahk 19"), SetTimer((*) => ToolTip(), -1000), ToolTip("19 minute timer started!"))],
    ["2", "0", (*) => (Run(lib "\Simple Timer.ahk 20"), SetTimer((*) => ToolTip(), -1000), ToolTip("20 minute timer started!"))],
    ["x", "h", (*) => mm.ThrowLeft()],
    ["x", "l", (*) => mm.ThrowRight()],
    ["x", "j", (*) => mm.GestureDL()],
    ["x", "k", (*) => mm.GestureUR()],
    ["x", "g", (*) => mm.SnapLeft()],
    ["x", ";", (*) => mm.SnapRight()],
    ["m", "h", (*) => mm.ThrowLeft()],
    ["m", "l", (*) => mm.ThrowRight()],
    ["f", "i", (*) => Scroll.up()],
    ["f", "m", (*) => Scroll.left()],
    ["f", ".", (*) => Scroll.right()],
    ["f", ",", (*) => Scroll.Down(), "instant"],
    ["f", "l", (*) => mouse.move("l")],
    ["f", "j", (*) => mouse.move("j")],
    ["f", "k", (*) => mouse.move("k")],
    ["f", "h", (*) => mouse.move("h")],
    ])

   These are just a few examples. A couple of syntax things you may notice: some rows used (*) and some did not. In AutoHotkey, a lambda function (*) => is a shorthand way to define a function without naming it. To call an AHK function that you have defined, you'll need a callback so that the DLL can let AutoHotkey know what to execute when the action is performed.

    These are both technically correct:
    QMK.SetupCombos([
    ["c", "n", "global", (*) => QMK.SendKeyDirect("1")],
    ["c", "n", "global", QMK.SendKeyDirect("1")],
    ])

    Both will send the same keys through the DLL send path (Interception Send or SendInput through the DLL). The only difference is that the first one is a bit slower because of a round trip from the DLL to AutoHotkey, then back to the DLL. The second one immediately sends the keys without the round trip. In most situations, there is no noticeable difference. AutoHotkey is single threaded though, so if AutoHotkey is processing other information at the same time, there may be some delay.

    SendKeyDirect can work similarly to AHK's Send syntax, with {} around special keys and ^!+, etc. for modifiers. Anything more complicated than a simple send could use a lambda function and a normal send through AutoHotkey. For actions that need multiple steps, or need to be blocked (first completes before second starts), normal AutoHotkey is the way to go.

        ["a", "k", "global", (*) => (SendEvent("This is a test"), Sleep(200), ToolTip("We sent it"), SetTimer(() => ToolTip(), -2000))],

    One line syntax like this can be tricky to read/write. If it's easier, you can always wrap your code in a separate function and call it like this:

    testfunction() {
        SendEvent("This is a test")
        Sleep(200)
        ToolTip("We sent it")
        SetTimer(() => ToolTip(), -2000)
    }

    QMK.SetupCombos([
     ["a", "k", "global", (*) => testfunction()],
    ])


    Another point to consider - combos overwrite any modifier behavior for the specific key combinations they define.
    QMK.SetupModifiers([
    ["a", "Ctrl", "global"],
    ])

    QMK.SetupCombos([
        ["a", "h", "global", QMK.SendKeyDirect("^{Left}")],
        ["a", "l", "global", QMK.SendKeyDirect("^{Right}")],
        ["a", "f", "global", (*) => globals.activaterun("Google", "https://www.google.com")],
    ])

    If "a" is configured as a virtual Ctrl modifier, "a+h" would normally
    behave like Ctrl+H. A combo row for "a" + "h" overrides that specific pair,
    so it can do something else instead.

    This lets a key be a modifier most of the time while reserving specific
    two-key combinations for navigation, editing, app controls, or menus.


    Shape:
        [key1, key2, context, action]
        [key1, key2, context, action, "instant"]
    Parameters:
        key1, key2
            The two keys that must be pressed together. Examples: "a" + "h",
            "CapsLock" + "b", "v" + "k".
        context
            "global", one context string, or an array of context strings.
        action
            QMK.SendKeyDirect("...") sends keys from the native QMK core.
            (*) => SomeAhkFunction() calls AutoHotkey. 
        "instant"
            Optional final flag. Without it, the combo respects the normal
            rollover/quiet-period timing from user settings. That lets you type
            normally with key overlap without every overlap firing a shortcut.
            With "instant", the combo fires immediately when QMK recognizes it,
            including in the middle of fast typing. Use instant combos on key
            pairs that are unlikely to appear in normal words.
*/



/*
Section 5: Quiet Period
Somewhere in this, you may have wondered, "With all of these combinations, will it randomly trigger any of my combinations?"

The answer is no, not for the most part. Right click your tray icon and click on 'QMK Settings' to see the quiet period and set it under 'Quiet Period Duration' on the Timing tab. Default is 150 milliseconds. During normal typing, if keys overlap inside this duration, the combo will not trigger. If you are experiencing unexpected combo triggers, you may need to increase this duration. 

Two exceptions to this rule: 
- if the combo is marked as instant
- retroactive timing: If two keys are pressed almost simultaneously, and the second key is lifted before the first key, QMK can still fire the combo if the quiet period expires before the first is released. 

Retroactive firing allows combos to still fire even if you are typing them quickly, but still allows normal typing to not be disturbed. 

Normal QMK firmware, and possibly other similar keyboard firmware like ZMK and Kanata, typically get around accidental triggers by a hard rule: the quiet period must be over before the second key can be typed. The upside is that there are very few accidental triggers. The downside is that fast typing, overlapping keys, or key 'rolling' is not always well supported. For example, in typing 'nation', the 'tion' keys may overlap with 3-4 keys pressed close together. You may type 'nation' normally, but if you lift those keys out of order, you may get 'natoin' instead. Or, it may ignore some of your shortcuts. Or, you may have to get used to typing with only one key down at a time, which is a major pain point and often a reason people leave. 

In developing QMK, I decided having a quiet period but with retroactive timing, that can be adjusted, was the best approach. A pain point was 'c+numpad' to type in long numbers more quickly. It kept missing the first key in the sequence (ex. instead of sending 2026, it would send 026 because I pressed c and , to quickly in succession). To avoid missing shortcuts with these two keys, while respecting the quiet period for normal typing, we check if 'c' is still pressed down after , is released and we are beyond the default (150) ms from the initial 'c' key press. This ensures no keys were missed. 

Additionally, the QMKCore engine tracks key press time on down, and makes sure it stays in the same order it was pressed down when sending to the operating system. 

If you still find accidental triggers, also try decreasing the modifier chaining window to a smaller value. For modifiers to be chained, they must be in those same time constraints. 

*/

/*
    Section 6: Three-, Four-, and Five-Key Chords
    Examples
*/
QMK.SetupChords([
    ["a", "s", "j", "global", QMK.SendKeyDirect("+{Down}")],
    ["a", "s", "k", "global", QMK.SendKeyDirect("+{Up}")],
    ["a", "s", "d", "h", "global", (*) => VDA.GoLeft()],
    ["a", "s", "d", "l", "global", (*) => VDA.GoRight()],
    ["a", "s", "d", "f", "o", "global", (*) => outlookdesktop.activate(true)],
])

/*

    By this point, I think you get the idea of the basic syntax structure for QMK Shortcuts - for letters, contexts, and callbacks. Chords can be 3, 4, or 5 keys long.

    Practical note: I use these to mimic Control+Win+Right and Control+Win+Left to navigate between virtual desktops. (I am using a modified version of a virtual desktop activator for this that I found online, but you could also send Native key combinations directly. This just lets me loop back from last to first again, and also lets me 'grab' the current window and take it to the next desktop)
    Other uses for me include expanding my 'left hand modifiers' and 'right hand arrow keys' - allowing me to use asl to send Control Shift Right and ash to send Control Shift Left.
    
    QMK.SetupChords([
    ["a", "s", "l", "global", QMK.SendKeyDirect("^+{Right}")],
    ["a", "h", "global", QMK.SendKeyDirect("^+{Left}")],
    ])

    An important note to keep in mind: not all keyboards, especially some laptops, can support certain combinations of keyboard keys being pressed simultaneously.
    I believe the AutoHotkey documentation also touches on this. I'm not an expert on this, and this is likely an oversimplification, but they way some keyboards determine which keys are down are from looking at the flow ofelectricity in a grid/circuit and infer which key was pressed from the column/row changes. If the right combination of keys are pressed at once, the last key might not register. I have a laptop where pressing 'ash' together does not work, yet it works on other keyboards. This is a hardware level issue, not a software one. See https://keyboardchecker.com/ or similar to check your keys if running into issues.

    Shape:

        [key1, key2, key3, context, action]
        [key1, key2, key3, context, action, "instant"]
        [key1, key2, key3, key4, context, action]
        [key1, key2, key3, key4, key5, context, action]

    Parameters:

        key1 ... key5
            The physical keys in the chord. Three-key chords are good for
            frequent commands that should not collide with normal two-key
            typing overlap. Four- and five-key chords are useful for heavier
            commands you want to be hard to trigger accidentally.

        context
            "global", one context string, or an array of context strings.

        action
            Use QMK.SendKeyDirect("...") for native key sending, or a callback
            for AutoHotkey work.

        "instant"
            Optional final flag. Without it, the chord respects the normal
            timing. With it, the chord fires as soon as the key group is
            recognized. Instant can also be paired with callback actions.
*/

/*
    Section 7: Holds, Taps, Tap-Holds, and Double-Taps
    Examples
*/
QMK.SetupHolds([
    ["a", ["global"], (*) => anki.activate(true)],
    ["e", ["global"], (*) => edge.activate(true)],
    ["f", ["global"], (*) => globals.activaterun("ChatGPT", "https://chatgpt.com/?temporary-chat=true")],
    ["o", ["global"], (*) => Onenote.activate(true)],
    ["p", ["global"], (*) => phonelink.activate(true)],
    ["h", ["global"], (*) => mm.SnapLeft()],
    ["j", ["global"], (*) => mm.GestureDL()],
    ["k", ["global"], (*) => mm.GestureUR()],
    ["l", ["global"], (*) => mm.SnapRight("A")],
])

QMK.SetupTaps([
    ["h", "School - Anki", QMK.SendKeyDirect("1")],
    ["j", "School - Anki", QMK.SendKeyDirect("2")],
    ["k", "School - Anki", QMK.SendKeyDirect("4")],
    ["l", "School - Anki", QMK.SendKeyDirect("{Enter}")],
])


QMK.SetupDoubleTaps([
    ["LCtrl", "outlook.live.com", (*) => outlookdesktop.activate(true)],
])

/*
    Holds might be not just my favorite of all of the QMK Shortcuts, but anything in AutoHotkey in general. Nothing in AutoHotkey has reduced friction between switching windows as much as this has for me. No global two or three shortcut to forget/I won't use because only one hand is on the keyboard. No more grabbing the mouse, opening a window, putting my hands back on the application, and thinking, "What was I doing again?"

    Though you could use these as you like, I have personally found that keeping the holds global, and tying each key to a specific application it will activate, helps me remember the best and doesn't interfere with previously established shortcuts. 

    Some practical things I use:
    A for Anki (flashcard app)
    E for Edge (web browser), cycles through active ones if I repeat. If only one, minimizes and goes back to the previous application. (Checking something on the browser? Hold e about as long as a blink (150ms, edit in QMK Settings), see the information, then hold again.
    C for 'Calendar' - Activates Edge, navigates to Google Calendar if available
    F for 'find' in ChatGPT (web app)
    O for OneNote (note-taking app)
    P for Phone Link (phone integration app)
    H for Snap Left (window management)
    J for Gesture Down-Left (window management)
    K for Gesture Up-Right (window management)
    L for Snap Right (window management)



    Double taps are nice too. I don't use them as often, but double tapping Lctrl for me is sometimes my 'default' or most used shortcut in my head for each application I am in. If I am ever trying to get work done quickly, I just leave my finger on this, and double tap. Often use in times for multistep actions I am doing. 

For other keys that are not defined, you can double tap to have those keys repeat (delay configurable in User Settings). For example, double tap and hold 'Backspace' to quickly delete multiple characters. This was the compromise I came to with holds. If we can't repeat keys by holding, a quick double tap to repeat gets the job done. Other ones include other keys we might hold like the arrow keys or even - to make a separator in a text document, etc. 
    

    Shape:
        QMK.SetupHolds([
            [key, context, holdAction],
        ])
        QMK.SetupTaps([
            [key, context, QMK.SendKeyDirect(tapAction)],
            [key, context, QMK.SendKeyDirect(tapAction), holdCallback],
            [key, context, QMK.SendKeyDirect(tapAction), holdCallback, thresholdMs],
        ])
        QMK.SetupTap({ key: key, context: context, tap: QMK.SendKeyDirect(tapAction) })
        QMK.SetupDoubleTaps([
            [key, context, action],
            [key, context, action, suspendExempt],
        ])

    Parameters:
        key
            The key being watched.

        context
            "global", one context string, or an array of context strings.
        tapAction
            The key/text/callback to use for a 1:1 tap remap. Use
            QMK.SendKeyDirect("...") for simple key sends so the send stays in
            the QMK DLL path.
        thresholdMs
            Tap-hold timing for that row. A quick release takes the tap path;
            holding past the threshold takes the hold path.
        tapAction, holdAction, cleanupAction, action
            QMK.SendKeyDirect("...") for native key sends, or callbacks for
            AutoHotkey behavior. cleanupAction is optional and runs when the
            tap-hold needs a cleanup step after the hold path.
        suspendExempt
            Optional true/false. true lets the row remain available while QMK is
            suspended.

    Double-taps fire when the same key is pressed twice inside the
    doubleTapThreshold user setting.
*/

/*
    Section 8: Hotstrings
    Examples
*/
QMK.SetupHotstrings([
    [":*:addr", "global", "123 Example Street"],
    [":*:email", "global", "user@example.com"],
    [":*:sig", "ahk_exe OUTLOOK.EXE", (*) => PasteEmailSignature()],
])

/*
    Note: You can still use regularly defined AutoHotkey hotkeys and hotstrings without passing them into QMK. The same is true for hotkeys.

    Normally, AutoHotkey is excellent at hotkeys and hotstrings. I found in my setup, after a certain number of hotkeys and hotstrings though, there was visible delay while I was typing. Even after optimizing the QMKCore hotpath to about its maximum efficacy (2 us, two millionths of a second, or roughly 7,800 times faster than 1 frame is processed on a 60 Hz display), I was still getting noticeable lag.

    I thought it was this: 
    Input >> QMK process (fast) >> Operating system
    But in reality the shape is more like this:
    Input >> QMKCore (fast) >> AHK script and other programs with keyboard hooks >> operating system

    I realized that because AutoHotkey is single-threaded and handles all hotkeys and hotstrings in one process, it can become a bottleneck when too many custom #HotIf conditionals are present. This is because AutoHotkey evaluates each condition and hotstring match when keys are pressed. My custom hotkeys/hotstrings were causing noticeable lag. 



    
    QMK adds another option
    for people with many keyboard rules: put hotstrings in setup blocks so the
    native core can filter and dispatch them.

    For small setups, regular AutoHotkey hotstrings may feel identical. If your
    script starts to feel laggy because many hotkeys, hotstrings, and keyboard
    functions all run in one AutoHotkey process, move some busy text expansion
    rules into QMK.SetupHotstrings().



    Shape:

        [hotstringSpec, context, replacement]
        [hotstringSpec, context, callback]

    Parameters:

        hotstringSpec
            AutoHotkey-style hotstring trigger text. Examples: ":*:addr",
            ":*:email", ":*:sig".

        context
            "global", one context string, or an array of context strings.

        replacement
            Text to emit.

        callback
            AutoHotkey function to call when the hotstring fires.


*/

/*
    Section 9: Hotkeys
    Examples
*/
QMK.SetupHotkeys([
    ["!h", "global", QMK.SendKeyDirect("{Left}")],
    ["!j", "global", QMK.SendKeyDirect("{Down}")],
    ["!k", "global", QMK.SendKeyDirect("{Up}")],
    ["!l", "global", QMK.SendKeyDirect("{Right}")],
])

/*
    Shape:

        [hotkeySpec, context, action]
        [hotkeySpec, context, action, suspendExempt]

    Parameters:

        hotkeySpec
            AutoHotkey-style hotkey text. Examples: "!h", "^!s", "F2".

        context
            "global", one context string, or an array of context strings.

        action
            QMK.SendKeyDirect("...") for native key sends, a special native
            action string like "panicExit", or an AutoHotkey callback.

        suspendExempt
            Optional true/false. true lets the hotkey remain available while
            QMK is suspended.
*/


            
/*

Section 10: User Settings:

    Your user settings are stored in QMKconfig.ini edited through the Tray Menu "QMK Settings".

    If the tray item is unavailable, add your own hotkey to call QMKUserConfig.ShowGui().

    Useful settings:
        applyUserConfig
            Whether saved settings are pushed into the running QMK core.

        inputBackend
            auto, interception, llhook, or ahk_hotkeys.
            Auto will choose the fastest available backend. Interception >> llhook in Zig DLL >> AHK hotkeys.

            Interception is a kernel driver and is the fastest, but does require the Interception driver to be installed, which requires administrative privileges. This is the same driver used by many similar projects. llhook is fast as well, but may be slightly slower depending on other low-level hooks running in other programs (other AHK scripts, PowerToys, etc.), and AutoHotkey hooks.

            If just trying out the library, the low-level hook is sufficient and has almost no issues. If there is any concern/hesitation, use AHK to set up the hooks. Note that because AHK is single threaded and has other tasks running, it may introduce latency.

            I do not play online multiplayer games, but note that Interception and llhooks may have anti-cheat/bans depending on the game. Use at your own risk.

    sendMode:
        auto, interception, or sendinput.
        Auto chooses Interception send if installed, otherwise falls back to SendInput.

    singleKeyHoldThreshold:
        Hold timing for single-key hold behavior.
    maxHoldThreshold and maxThresholdSuppress:
        Long-hold suppression behavior.

    quietPeriodDuration:
        Protects normal typing from accidental combos and chords.

    modifierGestureWindow:
        Timing window for modifier gestures.
    doubleTapThreshold:
        Double-tap timing.

    repeatInitialDelay and repeatInterval:
        Repeat behavior timing.

*/

/*
    Section 11: Compiling Your Own Core
    Notes

    User shortcuts stay in AutoHotkey. They are passed into QMK at runtime;
    no need to compile or edit the Zig just to add shortcuts.

    Compile QMKCore when you want to build the native core for your machine,
    update the bundled native library, or test a native-code change.

    You will need:

    Either:
     1. - AutoHotkey v2 and Zig 0.16. (Uses the Zig build, almost as fast as option 2 and easiest to setup/compile - smaller program to download)
     or
     2. - Windows environment with MSVC build tools. Clang/LLVM installed. (Faster with Profile Guided Optimization, though requires multiple downloads, setup steps, and more disk space).

     A) Launch the QMKCompiler. Press either "Zig Settings", or "PGO Settings", for "Zig Build", or "Full PGO Build", respectively. 
     B) Hover over the various dependencies. If green, the correct dependency is in the correct place. If red, open Explorer to locate and fix the missing dependencies.
     

     Once that is done, hit 'compile' and watch. This will build the native core for your machine and embed the base64 code into 'QMKVariables.ahk' in the 'lib' folder. 

     C) If any errors occur during compilation, refer to the QMKCompiler logs for troubleshooting steps. Ensure all dependencies are correctly installed and paths are properly set. The AHK file does have some command line properties, so you might be able to debug some of those online. I made this compiler to make it easier to compile. A future step would be to make it easier to select various flags. From my testing, this seems to be the easiest for most users. AI might be able to give better suggestions for compiler errors.

*/
