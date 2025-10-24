#Requires AutoHotkey v2.0
#SingleInstance Force

; Reccommended dependencies (mostly for first-time use to assess potential functionality, feel free to delete what you would like)
#Include Monitor Manager.ahk
#Include scroll.ahk
#Include mouse.ahk
#Include OnWebsite.ahk ; leave uncommented for website-specific support, though it does require OnWebsite.ahk (On class) and Descolada's UIA library
#Include UIA\Lib\UIA.ahk
#Include UIA\Lib\UIA_Browser.ahk
#Include Monitor Manager.ahk
#Include TabActivator.ahk



QMK.SetupModifier("a", "Ctrl")
QMK.SetupModifier("s", "Shift")
QMK.SetupModifier("d", "Win")
QMK.SetupModifier("f", "Alt") 
QMK.SetupModifier("j", "Alt") 
QMK.SetupModifier("k", "Win")

QMK.SetupModifier("l", "Shift")
QMK.SetupModifier(";", "Ctrl")


; Window managment - "a" layer + arrow keys/other. Note that combos override the 'a' keys, 'modifier' behavior for 2 key combos only.
QMK.SetupCombo("a", "h", (*) => mm.SnapLeft("A"))
QMK.SetupCombo("a", "l", (*) => mm.SnapRight("A"))
QMK.SetupCombo("a", "j", (*) => mm.GestureDL())
QMK.SetupCombo("a", "k", (*) => mm.GestureUR())
QMK.SetupCombo("a", "g", (*) => Send("!{Tab}"))
; extra 'a' keys - I'll always want these combinations to trigger instantly
QMK.SetupInstantCombo("a", ";", (*) => SendEvent("{Backspace}"))
QMK.SetupInstantCombo("a", "'", (*) => SendEvent("^{Backspace}"))
QMK.SetupInstantCombo(";", "a", (*) => SendEvent("^{a}"))

; additional window managment - move to next screen (also use 'ds + h or l')
QMK.SetupCombo("x", "h", (*) => mm.ThrowLeft("A"))
QMK.SetupCombo("x", "l", (*) => mm.ThrowRight("A"))
QMK.SetupCombo("m", "h", (*) => mm.ThrowLeft("A"))
QMK.SetupCombo("m", "l", (*) => mm.ThrowRight("A"))

; c - 'Calculator' layer - makes numpad with 'c' pressed down
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

; Move the mouse with hjkl and click while 'd' is down
QMK.SetupCombo("d", "l",  (*) => SetTimer(mouse.move, -1)) 
QMK.SetupCombo("d", "i", (*) => SetTimer(() => Scroll.up(), -1)) 
QMK.SetupCombo("d", "j",  (*) => SetTimer(mouse.move, -1))
QMK.SetupCombo("d", "k", (*) =>  SetTimer(mouse.move, -1))
QMK.SetupCombo("d", "f", (*) => SendEvent("+#{s}"))
QMK.SetupCombo("d", "h",  (*) => SetTimer(mouse.move, -1))
QMK.SetupCombo("d", "u", (*) => Send("{Browser_Back}"))
QMK.SetupCombo("d", "p", (*) => Send("{Browser_Forward}"))
QMK.SetupCombo("d", ",", (*) => SetTimer(() => Scroll.Down(), -1)) 
QMK.SetupCombo("d", "Enter", (*) => SetTimer(() => mouse.click("d"), -1))

; f layer is for editing - moving cursor 
QMK.SetupCombo("f", "h", (*) => SendEvent("^{Left}"))
QMK.SetupCombo("f", "k", (*) => SendEvent("{Up}"))
QMK.SetupCombo("f", "j", (*) => SendEvent("{Down}"))
QMK.SetupCombo("f", "l", (*) => SendEvent("^{Right}"))
QMK.SetupInstantCombo("f", ";", (*) => SendEvent("{Backspace}"))
QMK.SetupInstantCombo("f", "'", (*) => SendEvent("{Delete}"))

; g is another layer for moving, though bigger movements "Go" + ___. 
QMK.SetupInstantCombo("g", ";", (*) => SendEvent("^{Backspace}"))
QMK.SetupInstantCombo("g", "'", (*) => SendEvent("^{Delete}"))
QMK.SetupCombo("g", "j", (*) => Send("{Down}"))
QMK.SetupCombo("g", "k", (*) => Send("{Up}"))
QMK.SetupCombo("g", "h", (*) => Send("{Home}"))
QMK.SetupCombo("g", "l", (*) => Send("{End}"))
QMK.SetupCombo("g", "u", (*) => Send("^{Home}")) ; go up
QMK.SetupCombo("g", "n", (*) => Send("^{End}")) 

; needed a combo to send escape
QMK.SetupinstantCombo("j", "k", (*) => Send("{Escape}"))
QMK.SetupinstantCombo("k", "j", (*) => Send("{Escape}"))

; p layer - Program Layer. "Program" + ______. Included here for ideas
; QMK.SetupCombo("p", "a", (*) => anki.activate(true))
; QMK.SetupCombo("p", "z", (*) => zen.activate(true))
; QMK.SetupCombo("p", "s", (*) => spotify.activate(true))
; QMK.SetupCombo("p", "m", (*) => messenger.activate(true))
; QMK.SetupCombo("p", "w", (*) => word.activate())
; QMK.SetupCombo("p", "d", (*) => runchecklist())
; QMK.SetupCombo("p", "o", (*) => Onenote.activate(true))
; QMK.SetupCombo("p", "u", (*) => outlookdesktop.activate(true))

; s is shift, and whenever I press 's' quickly with these, I'll always want them to fire immediately (no rolloever support) 
QMK.SetupInstantCombo("s", ";", (*) => SendEvent("{:}"))
QMK.SetupInstantCombo("s", "'", (*) => SendEvent("{`"}"))

; if having issues with typing modifiers then the spacebar, comment these in
; QMK.SetupCombo("a", "Space", (*) => SendEvent("a "))
; QMK.SetupCombo("s", "Space", (*) => SendEvent("s "))
; QMK.SetupCombo("d", "Space", (*) => SendEvent("d "))
; QMK.SetupCombo("f", "Space", (*) => SendEvent("f "))


; 'v' for 'volume' layer - "Volume" _____. Here for ideas, but can post if there is interest
; QMK.SetupCombo("v", "j", (*) => media.volume.down())
; QMK.SetupCombo("v", "k", (*) => media.volume.up())
; QMK.SetupCombo("v", "m", (*) => media.volume.mute())
; QMK.SetupCombo("v", "l", (*) => media.next())
; QMK.SetupCombo("v", "h", (*) => media.previous())
; QMK.SetupCombo("v", "p", (*) => media.toggleplaypause())

; 'w' for "website" layer - "Website" + _____. Mostly including for ideas. Both require the UIA library, but other code is in
; QMK.SetupCombo("w", "c", (*) => chatgpt.screenshot())
; QMK.SetupCombo("w", "d", (*) => globals.activaterun("Google Docs", "https://docs.google.com/"))
; QMK.SetupCombo("w", "g", (*) => globals.activaterun("Gmail", "https://mail.google.com"))
; QMK.SetupCombo("w", "j", (*) => globals.activaterun("ChatGPT", "https://chatgpt.com/?temporary-chat=true&model=gpt-5-instant"))
; QMK.SetupCombo("w", "k", (*) => globals.activaterun("Claude", "https://claude.ai/new"))
; QMK.SetupCombo("w", "n", (*) => globals.activaterun("NotebookLM", "https://notebooklm.google.com/"))
; QMK.SetupCombo("w", "r", (*) => globals.activaterun("Grok", "https://grok.com"))
; QMK.SetupCombo("w", "p", (*) => globals.activaterun("Spotify for Creators", "https://creators.spotify.com/pod/show/7lNvdBsvWKhblGyVn80JTo/episodes?pageSize=30"))
; QMK.SetupCombo("w", "y", (*) => globals.activaterun("Youtube", "https://www.youtube.com"))

; "." layer for choosing spotify playlists. Included for ideas. If interested I can send this, though its not as polished
; QMK.SetupCombo(".", "l", (*) => Spotify.PlayPlaylist("Liked Songs"))     

; holds - single key down only - 'hjkl' - moves the window to left half, right half, maximize/fullscreen, unfullscreen/restore
QMK.SetupHold("h", ["global"], (*) => mm.SnapLeft("A"))
QMK.SetupHold("j", ["global"], (*) => mm.GestureDL())
QMK.SetupHold("k", ["global"], (*) => mm.GestureUR())
QMK.SetupHold("l", ["global"], (*) => mm.SnapRight("A"))

; additional - matches my mouse gestures
QMK.SetupHold("u", ["global"], (*) => mm.GestureUL())
QMK.SetupHold("o", ["global"], (*) => mm.GestureUR())
QMK.SetupHold("n", ["global"], (*) => mm.GestureDL())
QMK.SetupHold("m", ["global"], (*) => mm.GestureDL())
QMK.SetupHold(".", ["global"], (*) => mm.GestureDR())


; ; additional keys that override global in certain contexts, for when the mm. gestures don't work as expected
; QMK.SetupHold("k", ["ahk_exe ONENOTE.EXE"], (*) => onenote.GestureUR())
; QMK.SetupHold("j", ["ahk_exe ONENOTE.EXE"], (*) => onenote.GestureDL())
; QMK.SetupHold("j", ["ahk_exe anki.exe"], (*) => anki.GestureDL())
; QMK.SetupHold("k", ["ahk_exe anki.exe"], (*) => anki.GestureUR())


; holds to run activate or hide certain programs here for ideas
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


; Win32 Menus Holds - only works when when 32 menus open
; QMK.SetupHold("n", ["ahk_class #32768"], (*) => media.next())
; QMK.SetupHold("p", ["ahk_class #32768"], (*) => media.previous())
QMK.SetupHold("l", ["ahk_class #32768"], (*) => (ToolTip(">>>> Moved Right!"), Send("^#{Right}"), SetTimer((*) => ToolTip(), -1000)))
QMK.SetupHold("h", ["ahk_class #32768"], (*) => (ToolTip("<<<< Moved Left!"), Send("^#{Left}"), SetTimer((*) => ToolTip(), -1000)))
QMK.SetupHold("k", ["ahk_class #32768"], (*) => (ToolTip("New Desktop!"), SetTimer(() => ToolTip(), -1000), Send("^#d")))
QMK.SetupHold("j", ["ahk_class #32768"], (*) => (ToolTip("Closed Desktop!"), SetTimer(() => ToolTip(), -1000), Send("^#{F4}")))

;{{
; --- Timers ---

; pressing 2 numbers will start my timer script as a tooltip in the bottom right corner counting down. If interested, I'll post the update
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
; QMK.SetupCombo("1", "2", (*) => (Run(lib "\Simple Timer.ahk 12"), SetTimer((*) => ToolTip(), -1000), ToolTip("12 minute timer started!")))
; QMK.SetupCombo("1", "3", (*) => (Run(lib "\Simple Timer.ahk 13"), SetTimer((*) => ToolTip(), -1000), ToolTip("13 minute timer started!")))
; QMK.SetupCombo("1", "4", (*) => (Run(lib "\Simple Timer.ahk 14"), SetTimer((*) => ToolTip(), -1000), ToolTip("14 minute timer started!")))
; QMK.SetupCombo("1", "5", (*) => (Run(lib "\Simple Timer.ahk 15"), SetTimer((*) => ToolTip(), -1000), ToolTip("15 minute timer started!")))
; QMK.SetupCombo("1", "6", (*) => (Run(lib "\Simple Timer.ahk 16"), SetTimer((*) => ToolTip(), -1000), ToolTip("16 minute timer started!")))
; QMK.SetupCombo("1", "7", (*) => (Run(lib "\Simple Timer.ahk 17"), SetTimer((*) => ToolTip(), -1000), ToolTip("17 minute timer started!")))
; QMK.SetupCombo("1", "8", (*) => (Run(lib "\Simple Timer.ahk 18"), SetTimer((*) => ToolTip(), -1000), ToolTip("18 minute timer started!")))
; QMK.SetupCombo("1", "9", (*) => (Run(lib "\Simple Timer.ahk 19"), SetTimer((*) => ToolTip(), -1000), ToolTip("19 minute timer started!")))
; QMK.SetupCombo("2", "0", (*) => (Run(lib "\Simple Timer.ahk 20"), SetTimer((*) => ToolTip(), -1000), ToolTip("20 minute timer started!")))
; QMK.SetupCombo("2", "1", (*) => (Run(lib "\Simple Timer.ahk 21"), SetTimer((*) => ToolTip(), -1000), ToolTip("21 minute timer started!")))
; QMK.SetupCombo("2", "3", (*) => (Run(lib "\Simple Timer.ahk 23"), SetTimer((*) => ToolTip(), -1000), ToolTip("23 minute timer started!")))
; QMK.SetupCombo("2", "4", (*) => (Run(lib "\Simple Timer.ahk 24"), SetTimer((*) => ToolTip(), -1000), ToolTip("24 minute timer started!")))
; QMK.SetupCombo("2", "5", (*) => (Run(lib "\Simple Timer.ahk 25"), SetTimer((*) => ToolTip(), -1000), ToolTip("25 minute timer started!")))
; QMK.SetupCombo("2", "6", (*) => (Run(lib "\Simple Timer.ahk 26"), SetTimer((*) => ToolTip(), -1000), ToolTip("26 minute timer started!")))
; QMK.SetupCombo("2", "7", (*) => (Run(lib "\Simple Timer.ahk 27"), SetTimer((*) => ToolTip(), -1000), ToolTip("27 minute timer started!")))
; QMK.SetupCombo("2", "8", (*) => (Run(lib "\Simple Timer.ahk 28"), SetTimer((*) => ToolTip(), -1000), ToolTip("28 minute timer started!")))
; QMK.SetupCombo("2", "9", (*) => (Run(lib "\Simple Timer.ahk 29"), SetTimer((*) => ToolTip(), -1000), ToolTip("29 minute timer started!")))
; QMK.SetupCombo("3", "0", (*) => (Run(lib "\Simple Timer.ahk 30"), SetTimer((*) => ToolTip(), -1000), ToolTip("30 minute timer started!")))
; QMK.SetupCombo("3", "1", (*) => (Run(lib "\Simple Timer.ahk 31"), SetTimer((*) => ToolTip(), -1000), ToolTip("31 minute timer started!")))
; QMK.SetupCombo("3", "2", (*) => (Run(lib "\Simple Timer.ahk 32"), SetTimer((*) => ToolTip(), -1000), ToolTip("32 minute timer started!")))
; QMK.SetupCombo("3", "4", (*) => (Run(lib "\Simple Timer.ahk 34"), SetTimer((*) => ToolTip(), -1000), ToolTip("34 minute timer started!")))
; QMK.SetupCombo("3", "5", (*) => (Run(lib "\Simple Timer.ahk 35"), SetTimer((*) => ToolTip(), -1000), ToolTip("35 minute timer started!")))
; QMK.SetupCombo("3", "6", (*) => (Run(lib "\Simple Timer.ahk 36"), SetTimer((*) => ToolTip(), -1000), ToolTip("36 minute timer started!")))
; QMK.SetupCombo("3", "7", (*) => (Run(lib "\Simple Timer.ahk 37"), SetTimer((*) => ToolTip(), -1000), ToolTip("37 minute timer started!")))
; QMK.SetupCombo("3", "8", (*) => (Run(lib "\Simple Timer.ahk 38"), SetTimer((*) => ToolTip(), -1000), ToolTip("38 minute timer started!")))
; QMK.SetupCombo("3", "9", (*) => (Run(lib "\Simple Timer.ahk 39"), SetTimer((*) => ToolTip(), -1000), ToolTip("39 minute timer started!")))
; QMK.SetupCombo("4", "0", (*) => (Run(lib "\Simple Timer.ahk 40"), SetTimer((*) => ToolTip(), -1000), ToolTip("40 minute timer started!")))
; QMK.SetupCombo("4", "1", (*) => (Run(lib "\Simple Timer.ahk 41"), SetTimer((*) => ToolTip(), -1000), ToolTip("41 minute timer started!")))
; QMK.SetupCombo("4", "2", (*) => (Run(lib "\Simple Timer.ahk 42"), SetTimer((*) => ToolTip(), -1000), ToolTip("42 minute timer started!")))
; QMK.SetupCombo("4", "3", (*) => (Run(lib "\Simple Timer.ahk 43"), SetTimer((*) => ToolTip(), -1000), ToolTip("43 minute timer started!")))
; QMK.SetupCombo("4", "5", (*) => (Run(lib "\Simple Timer.ahk 45"), SetTimer((*) => ToolTip(), -1000), ToolTip("45 minute timer started!")))
; QMK.SetupCombo("4", "6", (*) => (Run(lib "\Simple Timer.ahk 46"), SetTimer((*) => ToolTip(), -1000), ToolTip("46 minute timer started!")))
; QMK.SetupCombo("4", "7", (*) => (Run(lib "\Simple Timer.ahk 47"), SetTimer((*) => ToolTip(), -1000), ToolTip("47 minute timer started!")))
; QMK.SetupCombo("4", "8", (*) => (Run(lib "\Simple Timer.ahk 48"), SetTimer((*) => ToolTip(), -1000), ToolTip("48 minute timer started!")))
; QMK.SetupCombo("4", "9", (*) => (Run(lib "\Simple Timer.ahk 49"), SetTimer((*) => ToolTip(), -1000), ToolTip("49 minute timer started!")))
; QMK.SetupCombo("5", "0", (*) => (Run(lib "\Simple Timer.ahk 50"), SetTimer((*) => ToolTip(), -1000), ToolTip("50 minute timer started!")))
; QMK.SetupCombo("5", "1", (*) => (Run(lib "\Simple Timer.ahk 51"), SetTimer((*) => ToolTip(), -1000), ToolTip("51 minute timer started!")))
; QMK.SetupCombo("5", "2", (*) => (Run(lib "\Simple Timer.ahk 52"), SetTimer((*) => ToolTip(), -1000), ToolTip("52 minute timer started!")))
; QMK.SetupCombo("5", "3", (*) => (Run(lib "\Simple Timer.ahk 53"), SetTimer((*) => ToolTip(), -1000), ToolTip("53 minute timer started!")))
; QMK.SetupCombo("5", "4", (*) => (Run(lib "\Simple Timer.ahk 54"), SetTimer((*) => ToolTip(), -1000), ToolTip("54 minute timer started!")))
; QMK.SetupCombo("5", "6", (*) => (Run(lib "\Simple Timer.ahk 56"), SetTimer((*) => ToolTip(), -1000), ToolTip("56 minute timer started!")))
; QMK.SetupCombo("5", "7", (*) => (Run(lib "\Simple Timer.ahk 57"), SetTimer((*) => ToolTip(), -1000), ToolTip("57 minute timer started!")))
; QMK.SetupCombo("5", "8", (*) => (Run(lib "\Simple Timer.ahk 58"), SetTimer((*) => ToolTip(), -1000), ToolTip("58 minute timer started!")))
; QMK.SetupCombo("5", "9", (*) => (Run(lib "\Simple Timer.ahk 59"), SetTimer((*) => ToolTip(), -1000), ToolTip("59 minute timer started!")))
; QMK.SetupCombo("6", "0", (*) => (Run(lib "\Simple Timer.ahk 60"), SetTimer((*) => ToolTip(), -1000), ToolTip("60 minute timer started!")))
; QMK.SetupCombo("6", "1", (*) => (Run(lib "\Simple Timer.ahk 61"), SetTimer((*) => ToolTip(), -1000), ToolTip("61 minute timer started!")))
; QMK.SetupCombo("6", "2", (*) => (Run(lib "\Simple Timer.ahk 62"), SetTimer((*) => ToolTip(), -1000), ToolTip("62 minute timer started!")))
; QMK.SetupCombo("6", "3", (*) => (Run(lib "\Simple Timer.ahk 63"), SetTimer((*) => ToolTip(), -1000), ToolTip("63 minute timer started!")))
; QMK.SetupCombo("6", "4", (*) => (Run(lib "\Simple Timer.ahk 64"), SetTimer((*) => ToolTip(), -1000), ToolTip("64 minute timer started!")))
; QMK.SetupCombo("6", "5", (*) => (Run(lib "\Simple Timer.ahk 65"), SetTimer((*) => ToolTip(), -1000), ToolTip("65 minute timer started!")))
; ; skip 66
; QMK.SetupCombo("6", "7", (*) => (Run(lib "\Simple Timer.ahk 67"), SetTimer((*) => ToolTip(), -1000), ToolTip("67 minute timer started!")))
; QMK.SetupCombo("6", "8", (*) => (Run(lib "\Simple Timer.ahk 68"), SetTimer((*) => ToolTip(), -1000), ToolTip("68 minute timer started!")))
; QMK.SetupCombo("6", "9", (*) => (Run(lib "\Simple Timer.ahk 69"), SetTimer((*) => ToolTip(), -1000), ToolTip("69 minute timer started!")))
; QMK.SetupCombo("7", "0", (*) => (Run(lib "\Simple Timer.ahk 70"), SetTimer((*) => ToolTip(), -1000), ToolTip("70 minute timer started!")))
; QMK.SetupCombo("7", "1", (*) => (Run(lib "\Simple Timer.ahk 71"), SetTimer((*) => ToolTip(), -1000), ToolTip("71 minute timer started!")))
; QMK.SetupCombo("7", "2", (*) => (Run(lib "\Simple Timer.ahk 72"), SetTimer((*) => ToolTip(), -1000), ToolTip("72 minute timer started!")))
; QMK.SetupCombo("7", "3", (*) => (Run(lib "\Simple Timer.ahk 73"), SetTimer((*) => ToolTip(), -1000), ToolTip("73 minute timer started!")))
; QMK.SetupCombo("7", "4", (*) => (Run(lib "\Simple Timer.ahk 74"), SetTimer((*) => ToolTip(), -1000), ToolTip("74 minute timer started!")))
; QMK.SetupCombo("7", "5", (*) => (Run(lib "\Simple Timer.ahk 75"), SetTimer((*) => ToolTip(), -1000), ToolTip("75 minute timer started!")))
; QMK.SetupCombo("7", "6", (*) => (Run(lib "\Simple Timer.ahk 76"), SetTimer((*) => ToolTip(), -1000), ToolTip("76 minute timer started!")))
; ; skip 77
; QMK.SetupCombo("7", "8", (*) => (Run(lib "\Simple Timer.ahk 78"), SetTimer((*) => ToolTip(), -1000), ToolTip("78 minute timer started!")))
; QMK.SetupCombo("7", "9", (*) => (Run(lib "\Simple Timer.ahk 79"), SetTimer((*) => ToolTip(), -1000), ToolTip("79 minute timer started!")))
; QMK.SetupCombo("8", "0", (*) => (Run(lib "\Simple Timer.ahk 80"), SetTimer((*) => ToolTip(), -1000), ToolTip("80 minute timer started!")))
; QMK.SetupCombo("8", "1", (*) => (Run(lib "\Simple Timer.ahk 81"), SetTimer((*) => ToolTip(), -1000), ToolTip("81 minute timer started!")))
; QMK.SetupCombo("8", "2", (*) => (Run(lib "\Simple Timer.ahk 82"), SetTimer((*) => ToolTip(), -1000), ToolTip("82 minute timer started!")))
; QMK.SetupCombo("8", "3", (*) => (Run(lib "\Simple Timer.ahk 83"), SetTimer((*) => ToolTip(), -1000), ToolTip("83 minute timer started!")))
; QMK.SetupCombo("8", "4", (*) => (Run(lib "\Simple Timer.ahk 84"), SetTimer((*) => ToolTip(), -1000), ToolTip("84 minute timer started!")))
; QMK.SetupCombo("8", "5", (*) => (Run(lib "\Simple Timer.ahk 85"), SetTimer((*) => ToolTip(), -1000), ToolTip("85 minute timer started!")))
; QMK.SetupCombo("8", "6", (*) => (Run(lib "\Simple Timer.ahk 86"), SetTimer((*) => ToolTip(), -1000), ToolTip("86 minute timer started!")))
; QMK.SetupCombo("8", "7", (*) => (Run(lib "\Simple Timer.ahk 87"), SetTimer((*) => ToolTip(), -1000), ToolTip("87 minute timer started!")))
; ; skip 88
; QMK.SetupCombo("8", "9", (*) => (Run(lib "\Simple Timer.ahk 89"), SetTimer((*) => ToolTip(), -1000), ToolTip("89 minute timer started!")))
; QMK.SetupCombo("9", "0", (*) => (Run(lib "\Simple Timer.ahk 90"), SetTimer((*) => ToolTip(), -1000), ToolTip("90 minute timer started!")))
; QMK.SetupCombo("9", "1", (*) => (Run(lib "\Simple Timer.ahk 91"), SetTimer((*) => ToolTip(), -1000), ToolTip("91 minute timer started!")))
; QMK.SetupCombo("9", "2", (*) => (Run(lib "\Simple Timer.ahk 92"), SetTimer((*) => ToolTip(), -1000), ToolTip("92 minute timer started!")))
; QMK.SetupCombo("9", "3", (*) => (Run(lib "\Simple Timer.ahk 93"), SetTimer((*) => ToolTip(), -1000), ToolTip("93 minute timer started!")))
; QMK.SetupCombo("9", "4", (*) => (Run(lib "\Simple Timer.ahk 94"), SetTimer((*) => ToolTip(), -1000), ToolTip("94 minute timer started!")))
; QMK.SetupCombo("9", "5", (*) => (Run(lib "\Simple Timer.ahk 95"), SetTimer((*) => ToolTip(), -1000), ToolTip("95 minute timer started!")))
; QMK.SetupCombo("9", "6", (*) => (Run(lib "\Simple Timer.ahk 96"), SetTimer((*) => ToolTip(), -1000), ToolTip("96 minute timer started!")))
; QMK.SetupCombo("9", "7", (*) => (Run(lib "\Simple Timer.ahk 97"), SetTimer((*) => ToolTip(), -1000), ToolTip("97 minute timer started!")))
; QMK.SetupCombo("9", "8", (*) => (Run(lib "\Simple Timer.ahk 98"), SetTimer((*) => ToolTip(), -1000), ToolTip("98 minute timer started!")))
; ; skip 99


; ; only remap if sending virtually - useful for if you already have certain combos, like ^+l mapped to other things. Only work when the physical control key is not pressed
; #Hotif !GetKeyState('LControl', 'p')
; ^#h::ToolTip("<<<< Moved Left!"), Send("^#{Left}"), SetTimer(() => ToolTip(), -500)
; ^#l::ToolTip(">>>> Moved Right!"), Send("^#{Right}"), SetTimer(() => ToolTip(), -500)
; ^+l::^+Right
; ^+h::^+left
; ^+k::+Up
; ^+j::+Down
; ^+c::^c
; #hotif




