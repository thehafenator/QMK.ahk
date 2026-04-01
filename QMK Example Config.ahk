#Requires AutoHotkey v2.0
#SingleInstance Force
#Include QMKInterception.ahk

; Feel free to comment these in/out or delete. Simply to have some ideas for you to try before making your own
; #Include OnWebsite.ahk
; #Include Monitor Manager.ahk
; #Include TabActivator.ahk
; #Include Scroll.ahk
; #Include UIA/UIA.ahk

; I prefer asdf to be Control shift win alt, similar to if my hands moved down to the left of the keyboard to keep muscle memory.
QMK.SetupModifier("a", "Ctrl")
QMK.SetupModifier("s", "Shift")
QMK.SetupModifier("d", "Win")
QMK.SetupModifier("f", "Alt")
QMK.SetupModifier("j", "Alt")
QMK.SetupModifier("k", "Win")
QMK.SetupModifier("l", "Shift")
QMK.SetupModifier(";", "Ctrl")

; A pattern you'll see is using hjkl as arrow keys. With 'a' as control in my head, I want a+hjkl to mimic Ctl+ Left/Down/Up/Right
; "a" layer + arrow keys/other. Note that combos override the 'a' keys, 'modifier' behavior for 2 key combos only.
; Note - "SetupInternalCombo" will send a set of keys through the interception driver (if installed) or through sendinput via the Zig DLL. 
; Here, the first to parameters are the letters to press, the third parameter is the modifier string (^+#!, for Control, Shift, Win, Alt, just like Autohotkey)
; For SetupInternalCombos to work, either 
; 1. The first key must be down for at least past 300 (default, change in userconfig) ms, then the second is pressed (simple timing)
; 2. The second key is released up, but the first key is still down past the the 300 ms. (Retroactive timing) 
; Number 1. and 2. are how rollover are supported within the Quiet period.
; Use 'SetupCombo (see two sections below) for combos with Autohotkey callbacks. 
QMK.SetupInternalCombo("a", "h", "^", "Left")
QMK.SetupInternalCombo("a", "k", "", "Up")
QMK.SetupInternalCombo("a", "j", "", "Down")
QMK.SetupInternalCombo("a", "l", "^", "Right")
QMK.SetupInternalCombo("a", "[", "", "Delete")
QMK.SetupInternalCombo("z", "h", "^+", "Left")

; Similarly, Chords are now supported! (3 or 4 keys). Following a is control and s is h, I want 'a'+'s'+'l' to mimic ^+right, and 'a'+'s'+'h' to mimic ^+left
QMK.SetupInternalChord("a", "s", "l", "", "^+", "Right")
QMK.SetupInternalChord("a", "s", "h", "", "^+", "Left")
QMK.SetupInternalChord("a", "s", "'", "", "^", "Delete")
QMK.SetupInternalChord("a", "s", ";", "", "", "Delete")
QMK.SetupInternalChord("a", "s", "]", "", "^", "Delete")
QMK.SetupInternalChord("a", "s", "k", "", "+", "Up")
QMK.SetupInternalChord("a", "s", "j", "", "+", "Down")
QMK.SetupInternalChord("a", "s", "g", "", "+", "End")
QMK.SetupInternalChord(";", "l", "g", "", "+", "Home")
QMK.SetupInternalChord(";", "l", "h", "", "^+", "Left")
QMK.SetupInternalChord(";", "l", "Tab", "", "^+", "Tab")

; Chords can be a helpful way to have a given set of 3 keys map to a specific AHK-action as well, not just a remap. 
; These chords don't have the word 'Internal', which is named for the functions that send remapped keys through the DLL
; QMK.SetupChord("s", "f", "c", "", "", (*) => globals.activaterun("Google Calendar", "https://calendar.google.com/calendar/u/0/r"))
; QMK.SetupChord("s", "f", "d", "", "", (*) => fileexplorer.navrun(Downloads))
; QMK.SetupChord("s", "f", "g", "", "", (*) => globals.activaterun("Gmail", "https://mail.google.com"))
; QMK.SetupChord("s", "f", "h", "", "", (*) => media.connectheadphones())
; QMK.SetupChord("s", "f", "j", "", "", (*) => globals.activaterun("ChatGPT", "https://chatgpt.com/?temporary-chat=true&model=gpt-5-instant"))
; QMK.SetupChord("s", "f", "k", "", "", (*) => globals.activaterun("Claude", "https://claude.ai/new"))
; QMK.SetupChord("s", "f", "l", "", "", (*) => fileexplorer.navrun(Libraries))
; QMK.SetupChord("s", "f", "m", "", "", (*) => globals.activaterun("AMBOSS", "https://next.amboss.com/us"))
; QMK.SetupChord("s", "f", "n", "", "", (*) => notebooklm.quickcreate())
; QMK.SetupChord("s", "f", "o", "", "", (*) => onenote.activate(true))
; QMK.SetupChord("s", "f", "p", "", "", (*) => globals.activaterun("Spotify for Creators", "https://creators.spotify.com/pod/show/7lNvdBsvWKhblGyVn80JTo/episodes?pageSize=30"))
; QMK.SetupChord("s", "f", "r", "", "", (*) => globals.activaterun("Reddit", "https://www.reddit.com/"))
; QMK.SetupChord("s", "f", "t", "", "", (*) => SendAsPaste(FormatTime(A_Now, "MM.dd.yyyy")))
; QMK.SetupChord("s", "f", "y", "", "", (*) => globals.activaterun("Youtube", "https://www.youtube.com"))

; SetupInternalInstantCombo - Same as SetupInternalInstant combo, but fire always, regardless of quiet period. Sends through DLL >> Interception or Sendinput
; Note that you typically want to avoid using InstantCombo Remapping for keys that may overlap when typing.
; extra 'a' keys - I'll always want these combinations to trigger instantly
QMK.SetupInternalInstantCombo("a", ";", "", "Backspace")
QMK.SetupInternalInstantCombo("a", "'", "^", "Backspace")
QMK.SetupInternalInstantCombo(";", "a", "^", "a")

; Another Example of Internal Combo - have C + keys on the right mimic a numpad
; c - 'Calculator' layer - makes numpad with 'c' pressed down
QMK.SetupInternalCombo("c", "n", "", "1")
QMK.SetupInternalCombo("c", "m", "", "1")
QMK.SetupInternalCombo("c", ",", "", "2")
QMK.SetupInternalCombo("c", ".", "", "3")
QMK.SetupInternalCombo("c", "j", "", "4")
QMK.SetupInternalCombo("c", "k", "", "5")
QMK.SetupInternalCombo("c", "l", "", "6")
QMK.SetupInternalCombo("c", "u", "", "7")
QMK.SetupInternalCombo("c", "i", "", "8")
QMK.SetupInternalCombo("c", "o", "", "9")
QMK.SetupInternalCombo("c", "Space", "", "0")
QMK.SetupInternalCombo("c", ";", "", "Backspace")
QMK.SetupInternalCombo("c", "'", "^", "Backspace")
QMK.SetupInternalCombo("c", "[", "", ".")
QMK.SetupInternalCombo("c", "/", "", ".")

; Move the mouse with hjkl and click while 'f' is down
; Note that SetupInternalCombo has an alternative "SetupCombo" that calls back to AHK for an AHK-specific Function
QMK.SetupCombo("f", "i", (*) => Scroll.up())
QMK.SetupCombo("f", "l", (*) => mouse.move("l"))
QMK.SetupCombo("f", "j", (*) => mouse.move("j"))
QMK.SetupCombo("f", "k", (*) => mouse.move("k"))
QMK.SetupCombo("f", "h", (*) => mouse.move("h"))


; g is another 'layer' for moving in text edits like 'a', but bigger movements "Go" + HJKL)
QMK.SetupInternalInstantCombo("g", ";", "^", "Delete")
QMK.SetupInternalInstantCombo("g", "'", "^", "Delete")
QMK.SetupInternalCombo("g", "j", "", "Down")
QMK.SetupInternalCombo("g", "k", "", "Up")
QMK.SetupInternalCombo("g", "h", "", "Home")
QMK.SetupInternalCombo("g", "l", "", "End")
QMK.SetupInternalCombo("g", "u", "^", "Home")
QMK.SetupInternalCombo("g", "n", "^", "End")
QMK.SetupInternalCombo("g", "d", "^", "End")
QMK.SetupInternalCombo("g", ";", "", "Delete")

; needed a combo to send escape
QMK.SetupInternalInstantCombo("j", "k", "", "Esc")
QMK.SetupInternalInstantCombo("k", "j", "", "Esc")


; p layer - Program Layer. "Program" + ______. Included here for ideas
; QMK.SetupCombo("p", "a", (*) => anki.activate(true))
; QMK.SetupCombo("p", "z", (*) => zen.activate(true))
; QMK.SetupCombo("p", "s", (*) => spotify.activate(true))
; QMK.SetupCombo("p", "l", (*) => logi.activate(true))
; QMK.SetupCombo("p", "m", (*) => messenger.activate(true))
; QMK.SetupCombo("p", "w", (*) => word.activate())
; QMK.SetupCombo("p", "d", (*) => runchecklist())
; QMK.SetupCombo("p", "o", (*) => Onenote.activate(true))
; QMK.SetupCombo("p", "u", (*) => outlookdesktop.activate(true))

; s is shift, and whenever I press 's' quickly with these, I'll always want them to fire immediately (no rolloever support) 
QMK.SetupInstantCombo("s", ";", (*) => SendEvent("{:}"))
QMK.SetupInstantCombo("s", "'", (*) => SendEvent("{`"}"))

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
; QMK.SetupHold("h", ["global"], (*) => mm.SnapLeft("A"))
; QMK.SetupHold("j", ["global"], (*) => mm.GestureDL())
; QMK.SetupHold("k", ["global"], (*) => mm.GestureUR())
; QMK.SetupHold("l", ["global"], (*) => mm.SnapRight("A"))

; additional - matches my mouse gestures
;QMK.SetupHold("u", ["global"], (*) => mm.GestureUL())
; QMK.SetupHold("o", ["global"], (*) => mm.GestureUR())
; QMK.SetupHold("n", ["global"], (*) => mm.GestureDL())
; QMK.SetupHold("m", ["global"], (*) => mm.GestureDL())
; QMK.SetupHold(".", ["global"], (*) => mm.GestureDR())

; ; additional keys that override global in certain contexts, for when the mm. gestures don't work as expected
; QMK.SetupHold("k", ["ahk_exe ONENOTE.EXE"], (*) => onenote.GestureUR())
; QMK.SetupHold("j", ["ahk_exe ONENOTE.EXE"], (*) => onenote.GestureDL())
; QMK.SetupHold("j", ["ahk_exe anki.exe"], (*) => anki.GestureDL())
; QMK.SetupHold("k", ["ahk_exe anki.exe"], (*) => anki.GestureUR())

; holds to run activate or hide certain programs. This is what I found the most helpful. Speeds up workflows a bunch.
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





