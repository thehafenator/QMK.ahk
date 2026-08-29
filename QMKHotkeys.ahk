QMK.SetupTapHolds([
    ["CapsLock", "global", 200, (*) => ShowMenuWithDigits(MenuMap["default"]), (*) => WebsiteMenus()],
    ["``", "global", 300, (*) => ShowMenuWithDigits(MenuMap["default"]), (*) => WebsiteMenus()],
])

explorercontext := ["ahk_class #32770", "ahk_class CabinetWClass ahk_exe explorer.exe", "ahk_class#32770 ahk_exe msedge.exe", "Open", "Open File"]
panoptoContext := ["panopto.com", "hosted.panopto.com"]
teamsMuteContext := ["ahk_exe ms-teams.exe", "ahk_exe Teams.exe"]
outlookMuteContext := ["ahk_exe OUTLOOK.EXE", "ahk_exe olk.exe"]
butterflyContext := ["butterflynetwork.myabsorb.com", "butterflynetwork.com"]
uiaViewerContext := ["UIAViewer ahk_exe AutoHotkey64.exe", "UIAViewer ahk_class AutoHotkeyGUI ahk_exe AutoHotkey64_UIA.exe", "UIAViewer"]



QMK.SetupHotkeys([
    ; global
    ["^!Rshift", "global", QMK.SendKeyDirect("^{Home}")],
    ["^Rshift", "global", QMK.SendKeyDirect("^{End}")],
    ["*#Escape", "global", "panicExit", true],
    ["*^+r", "global", "nativeReload", true],
    ["^Space", "global", (*) => globals.togglealwaysontop()],
    ["^q", "global", (*) => globals.quitminimize()],
    ["^!+q", "global", (*) => globals.quitall()],
    ["^!s", "global", QMK.SuspendExempt((*) => QMK.Suspend())],
    ["^!F1", "global", (*) => DllCall(QMK.Proc("QMK_ShowProfilingReport"))],
    ["^!F2", "global", (*) => SetTimer((*) => QMKUserConfig.ShowGui(), -1)],
    ["^!f4", "global", (*) => globals.togglescriptstartuptooltip()],
    ["^!F5", "global", (*) => SetTimer((*) => QMK.Toggle_ProfilingIni(), -1)],
    ["^!f6", "global", (*) => globals.TestTimerPrecision(1000)],
    ["^!f7", "global", (*) => (Tooltip(globals.NtQueryTimerResolution() . "ms!"), SetTimer(() => ToolTip(), -300))],
    ["^!F9", "global", (*) => DllCall(QMK.Proc("QMK_ViewSettings"))],
    ["^!F11", "global", (*) => QMK.SaveTrainingData()],
    ["^+m", "global", (*) => (ToolTip("Opening VS Code..."), SetTimer(() => ToolTip(), -200), OpenInVsCode(lib "\Macropad.ahk", lib "\Macropad Includes.ahk", QMKFolder "\QMKHotkeys.ahk", QMKFolder "\QMK Shortcuts.ahk", lib "\LazyLoad.ahk"), vscode.activate())],

    ["~j & Tab", "global", QMK.SendKeyDirect("!{Tab}")],
    ["^+#r", "global", (*) => CreateRecipeGUI()],
    ["PrintScreen", "global", (*) => ToggleSnipVisibility()],
    ["F8", "global", (*) => ToggleSnipVisibility()],
    ["F2", "global", (*) => QMKUserConfig.ShowGui()],
    ["!+l", "global", (*) => fileexplorer.navrun(Libraries)],
    ["#+d", "global", (*) => fileexplorer.navrun(A_Desktop)],
    ["!+d", "global", (*) => fileexplorer.navrun(Downloads)],
    ["!+b", "global", (*) => fileexplorer.navrun(lib "\..\..\BUCOM\Fall 2025\BingEtAl\10.06.2025")],
    ["^#p", "global", (*) => ShowMenuWithDigits(MenuMap["pollev"])],
    ["!f", "global", (*) => (SendAsPaste(Prompts.lofixformating), chatgpt.switchtomodel("Instant"), chatgpt.enter())],
    ["^!+r", "global", (*) => (globals.activaterun("Research Princinciples", rp_journal_url), Run(rp_other_url))],

    ["~CapsLock & e", "global", (*) => edge.activate(false)],
    ["~CapsLock & a", "global", (*) => anki.activate(false)],
    ["~CapsLock & p", "global", (*) => phonelink.activate(false)],
    ["!F12", "global", (*) => openinvscode(Scripts "\Recently-Modified-Files\Recently Modified Files.ahk")],
    ["#q", "global", (*) => openquickcode()],
    ["^!+r", "global", (*) => (globals.activaterun("Research Princinciples", rp_journal_url), Run(rp_other_url))],
    ["!+u", "global", (*) => ShowMenuWithDigits(MenuMap["websites"])],
    ["#+p", "global", (*) => ShowMenuWithDigits(MenuMap["programs"])],
    ["!+f", "global", (*) => ShowMenuWithDigits(MenuMap["fileexplorer"])],
    ["^!+d", "global", (*) => ShowMenuWithDigits(MenuMap["windowssettings"])],
    ["!+a", "global", (*) => ShowMenuWithDigits(MenuMap["autofill"])],
    ["^!+b", "global", (*) => ShowMenuWithDigits(MenuMap["bucom"])],
    ["!+s", "global", (*) => ShowMenuWithDigits(MenuMap["Spotify"])],
    ["#c", "global", (*) => globals.showtextundermouse()],
    ["^!+f", "global", (*) => Run('"' TreeSearcher '"')],
    ["^!F8", "global", (*) => Run("notepad.exe " "" SchoolSettingsPath "" "")],
    ["#b", "global", (*) => globals.togglebluetooth()],
    ["!+e", "global", (*) => editmacropad()],
    ; ["^RButton", "global", (*) => Rbuttonshowmacropadmain()],
    ; ["+RButton", "global", (*) => WebsiteMenus()],
    ["~LShift & CapsLock", "global", (*) => (SetCapsLockState("AlwaysOff"), WebsiteMenus(), QMK.EmergencyReset(false))],
    ; ["~MButton & XButton2", "global", (*) => ShowMenuWithDigits(MenuMap["mediacontrols"])],
    ; ["~XButton2 & MButton", "global", (*) => ShowMenuWithDigits(MenuMap["mediacontrols"])],
    ; ["^MButton", "global", (*) => ShowMenuWithDigits(MenuMap["mediacontrols"])],
    ["#f", "global", QMK.SendKeyDirect("F11")],
    ["#Delete", "global", (*) => globals.emptyrecyclebin()],
    ["#!d", "global", (*) => globals.toggletaskbar()],
    ["^!u", "global", (*) => globals.runuiaviewer()],
    ; ["~RButton & WheelUp", "global", (*) => (SendInput("^{+}"), KeyWait("RButton", "U"))],
    ; ["~RButton & WheelDown", "global", (*) => (SendInput("^{-}"), KeyWait("RButton", "U"))],
    ["#Left", "global", (*) => mm.SnapLeft()],
    ["#Right", "global", (*) => mm.SnapRight()],
    ["#Up", "global", (*) => WinMaximize("A")],
    ["#m", "global", (*) => WinMinimize("A")],
    ["#Down", "global", (*) => mm.GestureD()],
    ["#+Up", "global", (*) => mm.GestureD()],
    ["!+Up", "global", (*) => mm.GestureD()],
    ["^!+F1", "global", (*) => mm.GestureD()],
    ["#Space", "global", (*) => chatgpt.temporarysearch()],
    ["^#Space", "global", (*) => chatgpt.temporarysearch()],
    ["!#Space", "global", QMK.SendKeyDirect("!{Space}")],
    ["^!+y", "global", (*) => globals.youtubesearch()],
    ["^#!Down", "global", (*) => Brightness.AdjustScreenBrightness(-6)],
    ["^#!Up", "global", (*) => Brightness.AdjustScreenBrightness(6)],
    ["^#!k", "global", (*) => Brightness.AdjustScreenBrightness(6)],
    ["^#!j", "global", (*) => Brightness.AdjustScreenBrightness(-6)],
    ["#Wheelup", "global", (*) => Brightness.AdjustScreenBrightness(6)],
    ["#Wheeldown", "global", (*) => Brightness.AdjustScreenBrightness(-6)],
    ["^#!WheelUp", "global", (*) => Brightness.AdjustScreenBrightness(6)],
    ["^#!Wheeldown", "global", (*) => Brightness.AdjustScreenBrightness(-6)],
    ["#+x", "global", (*) => globals.Paste(1)],
    ["#y", "global", (*) => globals.Copy(2)],
    ["#+y", "global", (*) => globals.Paste(2)],
    ["~XButton2 & WheelUp", "global", (*) => SendInput("{^WheelUp}")],
    ["~XButton2 & WheelDown", "global", (*) => SendInput("{^WheelDown}")],
    ["~XButton1 & WheelUp", "global", (*) => SendInput("{WheelLeft}")],
    ["~XButton1 & WheelDown", "global", (*) => SendInput("{WheelRight}")],
    ["!``", "global", (*) => QMK.PasteTextWithDll("``")],
    ["#h", "global", (*) => mm.SnapLeft()],
    ["#l", "global", (*) => mm.SnapRight()],
    ["*+#Enter", "global", (*) => Run("C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe")],
    ["^#h", "global", QMK.SendKeyDirect("^#{Left}")],
    ["^#l", "global", QMK.SendKeyDirect("^#{Right}")],
    ["#j", "global", (*) => mm.GestureD()],
    ["#k", "global", (*) => mm.GestureUR()],
    ["!#l", "global", QMK.SendKeyDirect("#{Right}")],
    ["!#h", "global", QMK.SendKeyDirect("#{Left}")],
    ["^!k", "global", QMK.SendKeyDirect("^!k")],
    ["^!Up", "global", QMK.SendKeyDirect("^!{Up}")],
    ["^!j", "global", QMK.SendKeyDirect("^!j")],
    ["^!Down", "global", QMK.SendKeyDirect("^!{Down}")],
    ["^!Space", "global", (*) => media.toggleplaypause()],
    ["^!p", "global", (*) => media.toggleplaypause()],
    ["^!Left", "global", (*) => media.previous()],
    ["^!h", "global", (*) => media.previous()],
    ["^!Right", "global", (*) => media.next()],
    ["^!l", "global", (*) => media.next()],
    ["!h", "global", QMK.SendKeyDirect("{Left}")],
    ["!j", "global", QMK.SendKeyDirect("{Down}")],
    ["!k", "global", QMK.SendKeyDirect("{Up}")],
    ["!l", "global", QMK.SendKeyDirect("{Right}")],
    ["*#enter", "global", (*) => Run("cmd.exe /k cd %USERPROFILE%")],
    ; ["!+c", "global", (*) => globals.activaterun("Google Calendar", "https://calendar.google.com/calendar/u/0/r")],
    ["!+g", "global", (*) => globals.activaterun("Gmail", "https://mail.google.com")],
    ["!+j", "global", (*) => globals.activaterun("ChatGPT", "https://chatgpt.com/?temporary-chat=true&model=gpt-5-instant")],
    ["^!+j", "global", (*) => globals.activaterun("ChatGPT", "https://chatgpt.com/?model=gpt-5-instant")],
    ["!+k", "global", (*) => globals.activaterun("Claude", "https://claude.ai/new")],
    ["!+m", "global", (*) => globals.activaterun("AMBOSS", "https://next.amboss.com/us/chat")],
    ["^!g", "global", (*) => globals.activaterun("Grok", "https://grok.com")],
    ["#!c", "global", (*) => globals.activaterun("Canvas", "https://baptistu.instructure.com/")],
    ["^!+g", "global", (*) => globals.activaterun("GroupMe", "https://web.groupme.com/chats")],
    ["^!+i", "global", (*) => globals.activaterun("Intedashboard", "https://v3.intedashboard.com/in/tests")],
    ["!+n", "global", (*) => notebooklm.quickcreate()],
    ["!+p", "global", (*) => globals.activaterun("Spotify for Creators", "https://creators.spotify.com/pod/show/7lNvdBsvWKhblGyVn80JTo/episodes?pageSize=30")],
    ["!+r", "global", (*) => globals.activaterun("Reddit", "https://www.reddit.com/")],
    ["!+y", "global", (*) => globals.activaterun("Youtube", "https://www.youtube.com")],
    ["^!y", "global", (*) => globals.activaterun("Youtube Studio", "https://studio.youtube.com/channel/UCyUoNJYNIxfZMxV7g9_D4Sw/videos")],
    ["^!e", "global", (*) => edge.activate(true)],
    ["!+o", "global", (*) => outlookdesktop.activate(true)],
    ["^!+o", "global", (*) => outlookdesktop.activate(true)],
    ["!+v", "global", (*) => vscode.activate(true)],
    ["!+w", "global", (*) => word.activate()],
    ["^+!t", "global", (*) => toggletheme()],
    ["!+t", "global", (*) => QMK.PasteTextWithDll(FormatTime(A_Now, "MM.dd.yyyy"))],
    ["#t", "global", (*) => Run(lib "\Simple Timer.ahk")],
    ["^+3", "global", (*) => (openinvscode(Libraries "\Browser Functions.ahk"), editmacropad("File:Browser Shortcuts.ahk"))],
    ["^!+m", "global", (*) => openinvscode(Libraries "\MouseGestures.ahk")],
    ["^+8", "global", (*) => openinvscode(Libraries "\8BitDo Class.ahk")],
    ["^!+w", "global", (*) => Run(Scripts "\WindowSpy.ahk")],
    ; ["^+!c", "global", (*) => openinvscode(lib "\Checklist.ahk")],
    ["~Ralt & AppsKey", "global", (*) => globals.runcalculator()],
    ["~Ralt & RCtrl", "global", (*) => globals.runcalculator()],
    ["~RCtrl & Ralt", "global", (*) => globals.runcalculator()],
    ["~RAlt & \", "global", QMK.SendKeyDirect("!{Tab}")],
    ["~RAlt & q", "global", (*) => globals.quitminimize()],

    ; Quick settings
    ["e", "Quick settings", (*) => globals.EnergySaver()],

    ; !ahk_exe Code.exe
    ["^!k", "!ahk_exe Code.exe", (*) => media.volume.up()],
    ["^!Up", "!ahk_exe Code.exe", (*) => media.volume.up()],
    ["^!j", "!ahk_exe Code.exe", (*) => media.volume.down()],
    ["^!Down", "!ahk_exe Code.exe", (*) => media.volume.down()],

    ; global
    ["SC120", "global", (*) => media.volume.mute()],
    ["SC12E", "global", (*) => media.volume.down()],
    ["SC130", "global", (*) => media.volume.up()],
    ["SC122", "global", (*) => media.toggleplaypause()],

    ; ahk_class #32768
    ; ["*LAlt", "ahk_class #32768", (*) => Send('{Blind}{vkE8}')],
    ; ["LAlt up", "ahk_class #32768", ""],

    ; ahk_exe Code.exe
    ["^j", "ahk_exe Code.exe", (*) => bwe({ LocalizedType: "check box", Name: "Toggle Panel (Ctrl+J)" })],
    ["^k", "ahk_exe Code.exe", (*) => bwe({ LocalizedType: "check box", Name: "Toggle Primary Side Bar (Ctrl+B)" })],
    ["^+s", "ahk_exe Code.exe", QMK.SendKeyDirect("^+s")],
    ["^!c", "ahk_exe Code.exe", (*) => globals.copy(1)],
    ["^!v", "ahk_exe Code.exe", (*) => globals.paste(1)],
    ["!x", "ahk_exe Code.exe", (*) => vscode.hotstringtosingleline()],
    ["!s", "ahk_exe Code.exe", (*) => vscode.addmenuseparator()],
    ["!r", "ahk_exe Code.exe", (*) => vscode.clickrunbutton()],
    ["^o", "ahk_exe Code.exe", (*) => vscode.open()],
    ["^!r", "ahk_exe Code.exe", (*) => vscode.renumbermenuitems()],
    ["^r", "ahk_exe Code.exe", (*) => vscode.regexsearch()],
    ["^#t", "ahk_exe Code.exe", (*) => vscode.tapdance()],
    ["^+o", "ahk_exe Code.exe", (*) => vscode.InsertOnWebsite()],
    ["^+w", "ahk_exe Code.exe", (*) => vscode.InsertOnWebsite()],
    ["^l", "ahk_exe Code.exe", (*) => vscode.lowercase()],
    ["!f", "ahk_exe Code.exe", (*) => (Send("^{f}"), vscode.regexsearch())],
    ; ["!l", "ahk_exe Code.exe", (*) => vscode.reducedoubleclick()], ; messes with the context 'open file'
    ["!j", "ahk_exe Code.exe", QMK.SendKeyDirect("!{Down}")],
    ["!k", "ahk_exe Code.exe", QMK.SendKeyDirect("!{Up}")],
    ["^!k", "ahk_exe Code.exe", QMK.SendKeyDirect("^+{Up}")],
    ["^!j", "ahk_exe Code.exe", QMK.SendKeyDirect("^+{Down}")],
    ["^+h", "ahk_exe Code.exe", (*) => vscode.InsertHotif()],
    ; ["~Capslock & t", "ahk_exe Code.exe", (*) => vscode.open()],
    ["^Capslock", "ahk_exe Code.exe", (*) => vscode.ToggleFolding()],

    ; baptistu.instructure.com/login/ldap
    ["^+l", "baptistu.instructure.com/login/ldap", (*) => canvas.Btsi2()],

    ; Med School - Anki
    ["#k", "Med School - Anki", (*) => Anki.GestureUR()],
    ["#j", "Med School - Anki", (*) => Anki.GestureDL()],
    ["~F1 & F2", "Med School - Anki", (*) => Anki.GestureDL()],
    ["~F2 & F1", "Med School - Anki", (*) => Anki.GestureDL()],
    ["~F3 & F4", "Med School - Anki", (*) => Anki.GestureUR()],
    ["~F4 & F3", "Med School - Anki", (*) => Anki.GestureUR()],
    ["l & 2", "Med School - Anki", QMK.SendKeyDirect("+{2}")],
    ["!a", "Med School - Anki", (*) => bwe({ LocalizedType: "link", Name: "AnKing Step Deck" }, "ControlClick")],
    ["!b", "Med School - Anki", (*) => bwe({ LocalizedType: "link", Name: "BHSU" }, "ControlClick")],
    ["^-", "Med School - Anki", QMK.SendKeyDirect("^+{-}")],
    ["^=", "Med School - Anki", QMK.SendKeyDirect("^+{=}")] ,
    ["~Right", "Med School - Anki", (*) => Anki.revealnext()],
    ["~Left", "Med School - Anki", QMK.Tap("1")],
    ; h/j/k/l tap+hold now handled by QMK.SetupTapHold in QMK Shortcuts.ahk
    ["~h", "Med School - Anki", QMK.Tap("1")],
    ["~k", "Med School - Anki", QMK.Tap("4")],
    ["Up", "Med School - Anki", QMK.Tap("4")],
    ["^n", "Med School - Anki", (*) => Anki.AddAnkingCard()],
    ["!n", "Med School - Anki", (*) => Anki.GestureDL()],
    ["!m", "Med School - Anki", (*) => Anki.GestureDL()],
    ["^+a", "Med School - Anki", (*) => Anki.OpenAddOns()],
    ["^+i", "Med School - Anki", (*) => Anki.ImportAndSelect()],
    ["^e", "Med School - Anki", (*) => Anki.EditImageOcclusion()],
    ["^y", "Med School - Anki", QMK.SendKeyDirect("^+{z}")],
    ["*^q", "Med School - Anki", (*) => anki.activate(true)],
    ["PgUp", "Med School - Anki", QMK.SendKeyDirect("{PgUp}")],
    ["F12", "Med School - Anki", QMK.SendKeyDirect("{PgDn}")],
    ["^Capslock", "Med School - Anki", (*) => anki.collapse()],
    ["~RShift", "Med School - Anki", QMK.SendKeyDirect("1")],
    ["~RShift & Enter", "Med School - Anki", (*) => _8.PressOnce("^{Delete}")],
    
    ["h", "Med School - Anki", QMK.Tap("1")],
    ["j", "Med School - Anki", QMK.Tap("2")],
    ["k", "Med School - Anki", QMK.Tap("4")],
    ["l", "Med School - Anki", QMK.Tap("{Enter}")],
    ; ["h", "Med School - Anki", (*) => QMK.Tap("1")],
    ; ["j", "Med School - Anki", (*) => QMK.Tap("2")],
    ; ["k", "Med School - Anki", (*) => QMK.Tap("4")],
    ; ["l", "Med School - Anki", (*) => QMK.Tap("{Enter}")],



    ; Add ahk_exe anki.exe
    ["!a", "Add ahk_exe anki.exe", (*) => Anki.ToggleBasicAndAnking()],
    ["!s", "Add ahk_exe anki.exe", (*) => Anki.ToggleBasicAndAnking()],
    ; ["!c", "Add ahk_exe anki.exe", (*) => QMK.SendKeyDirect("^!+c")],
    ; ["^+c", "Add ahk_exe anki.exe", (*) => QMK.SendKeyDirect("^+{c}")],
    ["^j", "Add ahk_exe anki.exe", QMK.SendKeyDirect("@")],
    ["^Enter", "Add ahk_exe anki.exe", (*) => Anki.AddClearAfterEnter()],
    ["^+n", "Add ahk_exe anki.exe", (*) => Anki.AddClearNoteType()],
    ["^Tab", "Add ahk_exe anki.exe", (*) => QMK.SendKeyDirect("{Tab 16}")],
    ["^+Tab", "Add ahk_exe anki.exe", (*) => QMK.SendKeyDirect("+{Tab 16}")],
    ["^+i", "Add ahk_exe anki.exe", QMK.SendKeyDirect("^+{o}")],
    ["^Capslock", "Add ahk_exe anki.exe", QMK.SendKeyDirect("^+o")],

    ; Browse ahk_exe anki.exe
    ; ["!j", "Browse ahk_exe anki.exe", (*) => QMK.SendKeyDirect("^j")],
    ["^m", "Browse ahk_exe anki.exe", (*) => Anki.BrowseMoveToCardiacDeck()],
    ["^!m", "Browse ahk_exe anki.exe", (*) => Anki.BrowseMoveToCardiacDeckAndAdd()],
    ["^+b", "Browse ahk_exe anki.exe", QMK.SendKeyDirect("^!b")],
    ["!c", "Browse ahk_exe anki.exe", (*) => Anki.browse.samecloze()],
    ["^+c", "Browse ahk_exe anki.exe", (*) => Anki.browse.newcloze()],
    ; ["!+c", "Browse", (*) => Send("^+c")],
    ["!+c", "Browse", (*) => Anki.browse.samecloze()],
    ["^+c", "Browse", (*) => Anki.browse.newcloze()],
    ["!g", "Browse", (*) => Sendinput("{Tab}^{a}^{c}^{delete}+{Tab}^+{c}^{v}")],

    ["^Up", "Browse ahk_exe anki.exe", (*) => Anki.browse.moveup()],
    ["^Down", "Browse ahk_exe anki.exe", (*) => Anki.browse.movedown()],
    ["^j", "Browse ahk_exe anki.exe", (*) => Anki.browse.moveup()],
    ["^k", "Browse ahk_exe anki.exe", (*) => Anki.browse.movedown()],
    ["^Capslock", "Browse ahk_exe anki.exe", QMK.SendKeyDirect("^{Delete}")],

    ; Capture Image To Text
    ["Enter", "Capture Image To Text", (*) => Anki.CaptureImageToTextProcess()],
    ["^Enter", "Capture Image To Text", (*) => ControlClick("Button33")],
    ["^Capslock", "Capture Image To Text", (*) => ControlClick("Button33")],

    ; Contanki Options
    ["^e", "Contanki Options", (*) => Anki.ContankiGoToEdit()],
    ["^s", "Contanki Options", (*) => Anki.ContankiOptionsSave()],
    ["^Enter", "Contanki Options", (*) => Anki.ContankiOptionsSave()],
    ["^Capslock", "Contanki Options", (*) => Anki.ContankiOptionsSave()],

    ; Image Occlusion Enhanced - Add Mode
    ["F5", "Image Occlusion Enhanced - Add Mode", (*) => Anki.ImageOcclusionEnhancedAddModeHideOneGuessOne()],
    ["^Capslock", "Image Occlusion Enhanced - Add Mode", (*) => Anki.ImageOcclusionEnhancedAddModeSelectOption()],

    ; Import File ahk_exe anki.exe
    ["^n", "Import File ahk_exe anki.exe", (*) => Anki.ImportFile()],
    ["^Enter", "Import File ahk_exe anki.exe", (*) => Anki.ImportFile()],
    ["^Capslock", "Import File ahk_exe anki.exe", (*) => Anki.ImportFile()],

    ; Note Suggestion(s)
    ["^Enter", "Note Suggestion(s)", (*) => Anki.NoteSuggestions()],

    ; amazon.com
    ["^o", "amazon.com", (*) => bwe({ AutomationId: "nav-orders" })],
    ["^h", "amazon.com", (*) => bwe({ LocalizedType: "link", Name: "Amazon Prime" })],
    ["^f", "amazon.com", (*) => amazon.search()],
    ["^+f", "amazon.com", QMK.SendKeyDirect("^f")],

    ; ahk_exe ONENOTE.EXE
    ["^g", "ahk_exe ONENOTE.EXE", (*) => Send("{Blind}^!{h}")],
    ["!i", "ahk_exe ONENOTE.EXE", (*) => canvas.pastelearningobjectives()],
    ["^Tab", "ahk_exe ONENOTE.EXE", QMK.SendKeyDirect("^{PgDn}")],
    ["^+Tab", "ahk_exe ONENOTE.EXE", QMK.SendKeyDirect("^+{PgUp}")],
    ["!1", "ahk_exe ONENOTE.EXE", (*) => Onenote.gotosection("Sciences")],
    ["!s", "ahk_exe ONENOTE.EXE", (*) => Onenote.gotosection("Sciences")],
    ["!3", "ahk_exe ONENOTE.EXE", (*) => Onenote.gotosection("Study")],
    ["!t", "ahk_exe ONENOTE.EXE", (*) => Onenote.gotosection("Study")],
    ["!2", "ahk_exe ONENOTE.EXE", (*) => Onenote.gotosection("Clinical")],
    ["!c", "ahk_exe ONENOTE.EXE", (*) => Onenote.gotosection("Clinical")],
    ["!v", "ahk_exe ONENOTE.EXE", (*) => Onenote.gotosection("Clinical")],
    ["Up", "ahk_exe ONENOTE.EXE", (*) => ControlSend("{Up}", ControlGetFocus("A"), "A")],
    ["Down", "ahk_exe ONENOTE.EXE", (*) => ControlSend("{Down}", ControlGetFocus("A"), "A")],
    ["!f", "ahk_exe ONENOTE.EXE", (*) => (SendEvent("^{f}"), Sleep(200), SendEvent("{Left}{Right}"))],
    ["^!c", "ahk_exe ONENOTE.EXE", (*) => chatgpt.screenshot("ahk_class Framework::CFrame")],
    ["^#!Up", "ahk_exe ONENOTE.EXE", (*) => Send("^+>")],
    ["^#!Down", "ahk_exe ONENOTE.EXE", (*) => Send("^+<")],
    ["^n", "ahk_exe ONENOTE.EXE", QMK.SendKeyDirect("^!+n")],
    ["^+n", "ahk_exe ONENOTE.EXE", QMK.SendKeyDirect("^n")],
    ["!+v", "ahk_exe ONENOTE.EXE", (*) => onenote.ToggleView()],
    ["^+a", "ahk_exe ONENOTE.EXE", (*) => Onenote.MakeAnkiCard()],
    ["^+t", "ahk_exe ONENOTE.EXE", (*) => onenote.ToggleView()],
    ["^!f", "ahk_exe ONENOTE.EXE", QMK.SendKeyDirect("F11")],
    ["^f", "ahk_exe ONENOTE.EXE", (*) => Onenote.search()],
    ["!a", "ahk_exe ONENOTE.EXE", (*) => Onenote.Draw("Type")],
    ["^t", "ahk_exe ONENOTE.EXE", (*) => Onenote.Draw("Type")],
    ["!d", "ahk_exe ONENOTE.EXE", (*) => Onenote.Draw("Pen", "Black")],
    ["^d", "ahk_exe ONENOTE.EXE", (*) => Onenote.Draw("Pen", "Black")],
    ["!r", "ahk_exe ONENOTE.EXE", (*) => Onenote.Draw("Pen", "Red")],
    ["!g", "ahk_exe ONENOTE.EXE", (*) => Onenote.Draw("Highlighter", "Yellow")],
    ["!e", "ahk_exe ONENOTE.EXE", (*) => Onenote.Draw("StrokeEraser")],
    ["#e", "ahk_exe ONENOTE.EXE", (*) => Onenote.Draw("StrokeEraser")],
    ["^!e", "ahk_exe ONENOTE.EXE", (*) => Onenote.Draw("StrokeEraser")],
    ["^+i", "ahk_exe ONENOTE.EXE", (*) => Onenote.insert()],
    ["^+!I", "ahk_exe ONENOTE.EXE", (*) => onenote.insert(true)],
    ["^+y", "ahk_exe ONENOTE.EXE", (*) => Onenote.addyoutubelink()],
    ["^+q", "ahk_exe ONENOTE.EXE", (*) => onenote.addquizlink()],
    ["!Left", "ahk_exe ONENOTE.EXE", QMK.SendKeyDirect("^![")],
    ["!Right", "ahk_exe ONENOTE.EXE", QMK.SendKeyDirect("^!]")],
    ["^!i", "ahk_exe ONENOTE.EXE", (*) => canvas.save_download_insert_notebook()],
    ["!o", "ahk_exe ONENOTE.EXE", (*) => Onenote.GestureUR()],
    ["!n", "ahk_exe ONENOTE.EXE", (*) => Onenote.GestureDL()],
    ["^+j", "ahk_exe ONENOTE.EXE", QMK.SendKeyDirect("^{Tab}")],
    ["^+k", "ahk_exe ONENOTE.EXE", QMK.SendKeyDirect("^+{Tab}")],
    ["^Down", "ahk_exe ONENOTE.EXE", QMK.SendKeyDirect("^{PgDn}")],
    ["^Up", "ahk_exe ONENOTE.EXE", QMK.SendKeyDirect("^{PgUp}")],
    ["^!Up", "ahk_exe ONENOTE.EXE", (*) => onenote.previoussubject()],
    ["^!Down", "ahk_exe ONENOTE.EXE", (*) => onenote.nextsubject()],
    ["~Ralt & i", "ahk_exe ONENOTE.EXE", (*) => (QMK.onenoteRAltUsed := true, onenote.insertmultiple())],
    ["~RAlt", "ahk_exe ONENOTE.EXE", (*) => Send('{Blind}{vkE8}')],
    ["*RAlt up", "ahk_exe ONENOTE.EXE", (*) => ((HasProp(QMK, "onenoteRAltUsed") && QMK.onenoteRAltUsed) ? (QMK.onenoteRAltUsed := false) : Send("{F11}"), Send('{Blind}{Ctrl}{Alt up}{Ctrl up}'), Send('{Blind}{LAlt up}{LControl up}{RAlt up}'))],
    ["^Capslock", "ahk_exe ONENOTE.EXE", (*) => Onenote.ToggleListItems()],
    ["~Capslock & f", "ahk_exe ONENOTE.EXE", (*) => Onenote.search()],



    ; global
    ["#o", "global", (*) => mm.GestureUR()],
    ["#n", "global", (*) => mm.GestureDL()],
    ["#u", "global", (*) => mm.GestureUL()],
    ["#o", "global", (*) => mm.GestureUR()],
    ["#+h", "global", (*) => mm.ThrowLeft()],
    ["#+j", "global", (*) => mm.GestureD()],
    ["#+k", "global", (*) => mm.GestureUR()],
    ["#+l", "global", (*) => mm.ThrowRight()],
    ["~F1 & F4", "global", (*) => mm.GestureUL()],
    ["~F4 & F1", "global", (*) => mm.GestureUL()],
    ["~F2 & F3", "global", (*) => mm.GestureDR()],
    ["~F3 & F2", "global", (*) => mm.GestureDR()],
    ["~F3 & F4", "global", (*) => mm.GestureUR()],
    ["~F4 & F3", "global", (*) => mm.GestureUR()],
    ["~F2 & F1", "global", (*) => mm.GestureDL()],
    ["~F1 & F2", "global", (*) => mm.GestureDL()],

    ; Checklist: ahk_class AutoHotkeyGUI
    ["a", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.AddNewTask()],

    ["Escape", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.ExitApp()],

    ["^s", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.ExitApp()],
    ["^r", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.ReloadApp()],
    ["^y", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.Redo()],
    ["^z", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.Undo()],
    ["^e", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.AddNewTask()],
    ["^0", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.RemoveAllColors()],
    ["!v", "Checklist: ahk_class AutoHotkeyGUI", (*) => Checklist.MenuMap["viewmenu"].Show()],
    ["!f", "Checklist: ahk_class AutoHotkeyGUI", (*) => Checklist.MenuMap["viewmenu"].Show()],
    ["^j", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.ChangeDirection("down")],
    ["^n", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.ChangeDirection("down")],
    ["^Down", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.ChangeDirection("down")],
    ["^Tab", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.ChangeDirection("down")],
    ["^k", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.ChangeDirection("up")],
    ["^Up", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.ChangeDirection("up")],
    ["^+Tab", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.ChangeDirection("up")],
    ["~#Escape", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.ExitApp()],
    ["!d", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.SetCategoryFilter("Default")],
    ["!b", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.SetCategoryFilter("books")],
    ["!h", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.SetCategoryFilter("habits")],
    ["!p", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.SetCategoryFilter("personal")],
    ["!s", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.SetCategoryFilter("school")],
    ["!a", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.SetCategoryFilter("showAll")],
    ["~0", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.ClearCellColor())],
    ["~Up", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.MoveMouseToColumnRow("up"))],
    ["~Down", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.MoveMouseToColumnRow("down"))],
    ["~h", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.MoveMouseToColumnRow("left"))],
    ["~Left", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.MoveMouseToColumnRow("left"))],
    ["~l", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.MoveMouseToColumnRow("right"))],
    ["~Right", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.MoveMouseToColumnRow("right"))],
    ["~Shift", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.selectfirstlistview())],
    ["~1", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.SetCellColor("Red", "Black"))],
    ["~r", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.SetCellColor("Red", "Black"))],
    ["~g", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.SetCellColor("Green", "Black"))],
    ["~b", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.SetCellColor("Blue", "White"))],
    ["2", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.SetCellColor("Orange", "Black")],
    ["o", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.SetCellColor("Orange", "Black")],
    ["~3", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.SetCellColor("Yellow", "Black"))],
    ["~y", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.SetCellColor("Yellow", "Black"))],
    ["~4", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.SetCellColor("Green", "Black"))],
    ["~5", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.SetCellColor("Blue", "White"))],
    ["~6", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.SetCellColor("Purple", "White"))],
    ["~v", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.SetCellColor("Purple", "White"))],
    ["~7", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.SetCellColor("White", "Black"))],
    ["~w", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.SetCellColor("White", "Black"))],
    ["~8", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.SetCellColor("Black", "white"))],
    ["~Escape", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.ExitApp())],
    ["^s", "Checklist: ahk_class AutoHotkeyGUI", QMK.Tap("Enter")],
    ["~Down", "Checklist: ahk_class AutoHotkeyGUI", QMK.Tap("Tab")],
    ["~Up", "Checklist: ahk_class AutoHotkeyGUI", QMK.Tap("+Tab")],
    ["k", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.ChangeDirection("up")],
    ["j", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.ChangeDirection("down")],
    ["backspace", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.DeleteTask(clist.LV)],
    ["delete", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.DeleteTask(clist.LV)],
    ["^+e", "Checklist: ahk_class AutoHotkeyGUI", (*) => Send("{F2}")],
    ["~Delete", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.DeleteTask(clist.LV)],
    ["^d", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.DeleteTask(clist.LV)],
    ["!Up", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.MoveTask("up")],
    ["!Down", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.MoveTask("down")],
    ["^h", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.HideShowCompleted()],
    ["~-", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(clist.ExecuteItemAction(clist.LV.GetNext()))],
    ["~c", "Checklist: ahk_class AutoHotkeyGUI", (*) => QMK.Tap(Click())],
    ["^Enter", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.AddNewTask()],
    ["~+Capslock", "Checklist: ahk_class AutoHotkeyGUI", (*) => (QMK.NoModifiers() && !iseditcontrol() ? ShowMenuWithDigits(Checklist.contextmenu) : "")],
    ["~CapsLock & Enter", "Checklist: ahk_class AutoHotkeyGUI", (*) => (QMK.NoModifiers() && !iseditcontrol() ? clist.DeleteTask(clist.LV) : "")],
    ["^CapsLock", "Checklist: ahk_class AutoHotkeyGUI", (*) => (QMK.NoModifiers() && !iseditcontrol() ? clist.HideShowCompleted() : "")],
    ["~CapsLock & j", "Checklist: ahk_class AutoHotkeyGUI", (*) => (QMK.NoModifiers() && !iseditcontrol() ? clist.ChangeDirection("down") : "")],
    ["~CapsLock & k", "Checklist: ahk_class AutoHotkeyGUI", (*) => (QMK.NoModifiers() && !iseditcontrol() ? clist.ChangeDirection("up") : "")],
    ["a & k", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.ChangeDirection("up")],
    ["a & j", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.ChangeDirection("down")],
    ["a & Delete", "Checklist: ahk_class AutoHotkeyGUI", (*) => clist.DeleteTask(clist.LV)],

    ; SnipperWindow ahk_class AutoHotkeyGUI
    ["c", "SnipperWindow ahk_class AutoHotkeyGUI", (*) => SnipperCycleColor()],
    ["backspace", "SnipperWindow ahk_class AutoHotkeyGUI", (*) => SnipperAddBorder()],
    ["^backspace", "SnipperWindow ahk_class AutoHotkeyGUI", (*) => SnipperCycleColor()],
    ["^c", "SnipperWindow ahk_class AutoHotkeyGUI", (*) => copyactivesniptoclipboard()],
    ["Escape", "SnipperWindow ahk_class AutoHotkeyGUI", (*) => CloseSnip()],
    ["Right", "SnipperWindow ahk_class AutoHotkeyGUI", (*) => MoveActiveSnip(1, 0)],
    ["Left", "SnipperWindow ahk_class AutoHotkeyGUI", (*) => MoveActiveSnip(-1, 0)],
    ["Up", "SnipperWindow ahk_class AutoHotkeyGUI", (*) => MoveActiveSnip(0, -1)],
    ["Down", "SnipperWindow ahk_class AutoHotkeyGUI", (*) => MoveActiveSnip(0, 1)],
    ["^Right", "SnipperWindow ahk_class AutoHotkeyGUI", (*) => MoveActiveSnip(10, 0)],
    ["^Left", "SnipperWindow ahk_class AutoHotkeyGUI", (*) => MoveActiveSnip(-10, 0)],
    ["^Up", "SnipperWindow ahk_class AutoHotkeyGUI", (*) => MoveActiveSnip(0, -10)],
    ["^Down", "SnipperWindow ahk_class AutoHotkeyGUI", (*) => MoveActiveSnip(0, 10)],

    ; Canvas Lecture Manager
    ["-", "Canvas Lecture Manager", (*) => canvas.LinkExtractor.DecreaseSingleItemCount()],
    ["=", "Canvas Lecture Manager", (*) => canvas.LinkExtractor.IncreaseSingleItemCount()],
    ["^e", "Canvas Lecture Manager", (*) => Canvas.LinkExtractor.EditSelectedRow()],
    ["^z", "Canvas Lecture Manager", (*) => Canvas.LinkExtractor.Undo()],
    ["^r", "Canvas Lecture Manager", (*) => Canvas.LinkExtractor.EditSelectedRow()],
    ["Delete", "Canvas Lecture Manager", (*) => Canvas.LinkExtractor.DeleteSelected()],
    ["^d", "Canvas Lecture Manager", (*) => Canvas.LinkExtractor.DeleteSelected()],
    ["^Up", "Canvas Lecture Manager", (*) => Canvas.LinkExtractor.IncrementPrefixes()],
    ["^Down", "Canvas Lecture Manager", (*) => Canvas.LinkExtractor.DecrementPrefixes()],
    ["^g", "Canvas Lecture Manager", (*) => Canvas.LinkExtractor.MakePages()],
    ["^+c", "Canvas Lecture Manager", (*) => Canvas.LinkExtractor.CopyLectureList()],
    ["^o", "Canvas Lecture Manager", (*) => Canvas.LinkExtractor.OpenLibraryFolder()],
    ["^s", "Canvas Lecture Manager", (*) => Canvas.LinkExtractor.SaveLectureListDialog()],
    ["^CapsLock", "Canvas Lecture Manager", (*) => Canvas.LinkExtractor.DeleteSelected()],

    ; baptistu.one45.com/index.php?login_message
    ["^n", "baptistu.one45.com/index.php?login_message", (*) => one45.login()],

    ; baptistu.one45.com/
    ["^s", "baptistu.one45.com/", (*) => one45.Submit()],
    ["!c", "baptistu.one45.com/", (*) => one45.mycalendar()],
    ["^n", "baptistu.one45.com/", (*) => one45.fillgood()],

    ; next.amboss.com

    ["!f", "next.amboss.com", (*) => (QMK.PasteTextWithDll(Prompts.lofixformating), chatgpt.switchtomodel("Instant"), chatgpt.enter())],
    ["^+a", "next.amboss.com", (*) => QMK.PasteTextWithDll(Prompts.AnswerLearningObjectives)],
    ["!q", "next.amboss.com", (*) => QMK.PasteTextWithDll(Prompts.QuizMeLO)],
    ["^+e", "next.amboss.com", (*) => QMK.PasteTextWithDll(Prompts.QuizMeLO)],
    ["^m", "next.amboss.com", (*) => QMK.PasteTextWithDll(Prompts.QuizMeLO)],
    ["^h", "next.amboss.com", (*) => QMK.PasteTextWithDll(Prompts.HighYield)],
    ["^+s", "next.amboss.com", (*) => QMK.PasteTextWithDll(Prompts.PostQuizSummary)],
    ["^+c", "next.amboss.com", (*) => chatgpt.downloadlastresponseastxt()],
    ["^b", "next.amboss.com", (*) => bwe({ LocalizedType: "button", Name: "PREVIOUS" })],
    ["^p", "next.amboss.com", (*) => bwe({ LocalizedType: "button", Name: "PREVIOUS" })],
    ["^CapsLock", "next.amboss.com", (*) => amboss.togglecollapse()],
    ["!d", "next.amboss.com", (*) => amboss.gotosection("Definitions")],
    ["!s", "next.amboss.com", (*) => amboss.gotosection("Summary")],
    ["!e", "next.amboss.com", (*) => amboss.gotosection("Epidemiology")],
    ["^e", "next.amboss.com", (*) => amboss.gotosection("Etiology")],
    ["^f", "next.amboss.com", (*) => amboss.find()],
    ["~CapsLock & f", "next.amboss.com", (*) => amboss.find()],
    ["^+f", "next.amboss.com", QMK.SendKeyDirect("^f")],
    ["^+i", "next.amboss.com", (*) => amboss.insert()],
    ["^u", "next.amboss.com", (*) => amboss.insert()],

    ; ankiuser.net/study, anki web
    ["l", "ankiuser.net/study", (*) => QMK.Tap(bwe([{ LocalizedType: "button", Name: "Show Answer" }], "Invoke"))],
    ["right", "ankiuser.net/study", (*) => QMK.Tap(bwe([{ LocalizedType: "button", Name: "Show Answer" }], "Invoke"))],
    ["h", "ankiuser.net/study", QMK.Tap("1")],
    ["left", "ankiuser.net/study", QMK.Tap("1")],
    ["j", "ankiuser.net/study", QMK.Tap("2")],
    ["down", "ankiuser.net/study", QMK.Tap("2")],
    ["k", "ankiuser.net/study", QMK.Tap("4")],
    ["up", "ankiuser.net/study", QMK.Tap("4")],
    ["e", "ankiuser.net/study",  QMK.Tap(bwe([{ LocalizedType: "link", Name: "Edit" }], "Invoke"))],
    ["^s", "ankiuser.net/edit/", (*) => ankiweb.save()],



    ; audible.com
    ["^p", "audible.com", (*) => bwe([{ AutomationId: "adbl-cp-play-btn" }, { AutomationId: "adbl-cp-pause-btn" }]) ],
    ["~Space", "audible.com", (*) => bwe([{ AutomationId: "adbl-cp-play-btn" }, { AutomationId: "adbl-cp-pause-btn" }])],
    ["^Right", "audible.com", (*) => bwe({ LocalizedType: "button", Name: "Forward 30 seconds" })],
    ["^b", "audible.com", (*) => bwe({ LocalizedType: "button", Name: "Rewind 30 seconds" })],
    ["^Left", "audible.com", (*) => bwe({ LocalizedType: "button", Name: "Rewind 30 seconds" })],
    ["^+Right", "audible.com", (*) => bwe({ LocalizedType: "button", Name: "Play Next Chapter" })],
    ["^+Left", "audible.com", (*) => bwe({ LocalizedType: "button", Name: "Play Previous Chapter" })],

    ; the-automator.com
    ["^Capslock", "the-automator.com", (*) => bwe({ LocalizedType: "link", Name: "Downloads" }, "Invoke")],
    ["^d", "the-automator.com", (*) => getactiveelement().FindElement({ LocalizedType: "link", Name: "Downloads" }).Click()],
    ["^f", "the-automator.com", (*) => bwe({ LocalizedType: "edit", Name: ".*Search for:*", matchmode: "RegEx", CaseSense: 0 })],
    ["^+f", "the-automator.com", QMK.SendKeyDirect("^f")],

    ; Bitwarden
    ["^f", "Bitwarden", (*) => bwe({ AutomationId: "search-id-0" })],
    ["^g", "Bitwarden", (*) => bwe([{ LocalizedType: "link", Name: "Generator" }, { LocalizedType: "button", Name: "Generate password" }, { LocalizedType: "button", Name: "Generate password" }], 1000)],
    ["!g", "Bitwarden", (*) => bwe([{ LocalizedType: "link", Name: "Generator" }, { LocalizedType: "button", Name: "Generate password" }, { LocalizedType: "button", Name: "Generate password" }], 1000)],
    ["^s", "Bitwarden", (*) => bwe([{ LocalizedType: "button", Name: "Save" }, { LocalizedType: "button", Name: "Use this password" }, { LocalizedType: "button", Name: "Save" }])],
    ["^b", "Bitwarden", (*) => Send("{Browser_Back}")],
    ["^+b", "Bitwarden", (*) => Send("{Browser_Forward}")],
    ["^m", "Bitwarden", (*) => bwp("VR0", 1000, ControlClick)],
    ["^n", "Bitwarden", (*) => bitwarden.newlogin()],
    ["^+n", "Bitwarden", (*) => bitwarden.newlogin()],
    ["!v", "Bitwarden", (*) => bwe({ LocalizedType: "link", Name: "Vault" })],
    ["^0", "Bitwarden", (*) => bwp("VRq0/", 1000, ControlClick)],
    ["^+k", "Bitwarden", (*) => QMK.PasteTextWithDll("20")],   
    ["^+l", "Bitwarden", (*) => (QMK.PasteTextWithDll("17BrassBandYPM"), SendEvent("{Enter}"))],
    ; app.bootcamp.com
    ["^+f", "app.bootcamp.com", QMK.SendKeyDirect("^f")],

    ; chatgpt.com
    ["^CapsLock", "chatgpt.com", (*) => bwe({ LocalizedType: "link", Name: "New chat" })],
    ["~RAlt", "chatgpt.com", (*) => Send('{Blind}{vkE8}')],
    ["*RAlt up", "chatgpt.com", (*) => (Send('{Blind}{Ctrl}{Alt up}{Ctrl up}'), chatgpt.togglesidebar(), Send('{Blind}{LAlt up}{LControl up}{RAlt up}'))],
    ["!t", "chatgpt.com", (*) => chatgpt.toggletemporary()],
    

    ; claude.ai
    ["^o", "claude.ai", (*) => QMK.PasteTextWithDll(Prompts.AnswerLearningObjectives)],
    ["^h", "claude.ai", (*) => QMK.PasteTextWithDll(Prompts.HighYield)],
    ["^+i", "claude.ai", (*) => claude.insert()],
    ["^u", "claude.ai", (*) => claude.insert()],
    ["~Ralt", "claude.ai", (*) => claude.togglesidebar()],

    ; churchofjesuschrist.org
    ["^p", "churchofjesuschrist.org", (*) => churchofjesuschrist.play()],
    ["^Capslock", "churchofjesuschrist.org", (*) => churchofjesuschrist.mark()],
    ["!s", "churchofjesuschrist.org", (*) => churchofjesuschrist.signin()],
    ["~RAlt", "churchofjesuschrist.org", (*) => Send('{Blind}{vkE8}')],
    ["*RAlt up", "churchofjesuschrist.org", (*) => (Send('{Blind}{Ctrl}{Alt up}{Ctrl up}'), bwe([{ LocalizedType: "button", Name: "Close Panel" }, { LocalizedType: "button", Name: "Table of Contents" }]))],
    ["^d", "churchofjesuschrist.org", (*) => churchofjesuschrist.deletebookmark()],
    ["~Escape", "churchofjesuschrist.org", (*) => churchofjesuschrist.closenote()],

    ; chat.deepseek.com
    ["^o", "chat.deepseek.com", (*) => QMK.PasteTextWithDll(Prompts.AnswerLearningObjectives)],
    ["^h", "chat.deepseek.com", (*) => QMK.PasteTextWithDll(Prompts.HighYield)],

    ; disneyplus.com
    ["^f", "disneyplus.com", (*) => disneyplus.search()],
    ["~Capslock & f", "disneyplus.com", (*) => disneyplus.search()],
    ["^+f", "disneyplus.com", QMK.SendKeyDirect("^f")],

    ; facebook.com/marketplace
    ["^s", "facebook.com/marketplace", (*) => bwe({ LocalizedType: "button", Name: "Save" })],

    ; grok.com
    ["!f", "grok.com", (*) => QMK.PasteTextWithDll(Prompts.FeedPracticeQuestions)],
    ["^+f", "grok.com", (*) => QMK.PasteTextWithDll(Prompts.FeedPracticeQuestions)],
    ["!q", "grok.com", (*) => QMK.PasteTextWithDll(Prompts.QuizMeLO)],
    ["^+e", "grok.com", (*) => QMK.PasteTextWithDll(Prompts.QuizMeLO)],
    ["^h", "grok.com", (*) => QMK.PasteTextWithDll(Prompts.MedicalProfessor)],
    ["^+s", "grok.com", (*) => QMK.PasteTextWithDll(Prompts.PostQuizSummary)],
    ["^d", "grok.com", (*) => grok.downloadtestartifact()],
    ["Ralt", "grok.com", (*) => grok.togglesidebar()],
    ["^n", "grok.com", (*) => bwe([{ LocalizedType: "button", Name: "New chat" }, { LocalizedType: "link", Value: "https://grok.com/" }])],
    ["^+a", "grok.com", (*) => QMK.PasteTextWithDll(Prompts.AnswerLearningObjectives)],
    ["^Capslock", "grok.com", (*) => bwe([{ LocalizedType: "button", Name: "New chat" }, { LocalizedType: "link", Value: "https://grok.com/" }])],
    ["^+i", "grok.com", (*) => grok.insert()],
    ["!t", "grok.com", (*) => bwe([{ LocalizedType: "link", Name: "Switch to Default Chat" }, { LocalizedType: "link", Name: "Switch to Private Chat" }])],
    ["!a", "grok.com", (*) => SendPrompt("a")],
    ["!b", "grok.com", (*) => SendPrompt("b")],
    ["!c", "grok.com", (*) => SendPrompt("c")],
    ["!d", "grok.com", (*) => SendPrompt("d")],
    ["!e", "grok.com", (*) => QMK.PasteTextWithDll("e")],
    ["^+n", "grok.com", (*) => SendPrompt("Next Question")],

    ; groupme.com
    ["^s", "groupme.com", (*) => groupme.grablogincode()],
    ["^n", "groupme.com", (*) => groupme.grablogincode()],
    ["^g", "groupme.com", (*) => groupme.grablogincode()],
    ["!l", "groupme.com", (*) => groupme.loginfull()],
    ["^+o", "groupme.com", (*) => groupme.logout()],
    ["^+i", "groupme.com", (*) => groupme.insert()],

    ; docs.google.com/document
    ["^d", "docs.google.com/document", (*) => googledocs.download()],
    ["^+c", "docs.google.com/document", (*) => googledocs.formatpainter()],
    ["^Enter", "docs.google.com/document", (*) => Send("{Blind} ^{enter}")],
    ["~Capslock & f", "docs.google.com/document", QMK.SendKeyDirect("^f")],

    ; docs.google.com/forms
    ["^u", "docs.google.com/forms", (*) => googleforms.uncategorized()],
    ["^g", "docs.google.com/forms", (*) => googleforms.foodGroceries()],
    ["!g", "docs.google.com/forms", (*) => googleforms.foodGroceries()],
    ["^m", "docs.google.com/forms", (*) => googleforms.michael()],
    ["!t", "docs.google.com/forms", (*) => googleforms.transportation()],
    ["!I", "docs.google.com/forms", (*) => googleforms.internet()],
    ["^I", "docs.google.com/forms", (*) => googleforms.internet()],
    ["!d", "docs.google.com/forms", (*) => googleforms.debit()],
    ["!l", "docs.google.com/forms", (*) => googleforms.linsey()],
    ["^n", "docs.google.com/forms", (*) => googleforms.next()],
    ["^b", "docs.google.com/forms", (*) => googleforms.back()],
    ["^p", "docs.google.com/forms", (*) => googleforms.back()],
    ["^d", "docs.google.com/forms", (*) => googleforms.next()],
    ["!a", "docs.google.com/forms", (*) => googleforms.purchaseAmount()],
    ["!c", "docs.google.com/forms", (*) => googleforms.giftcardsnap()],
    ["!s", "docs.google.com/forms", (*) => googleforms.giftcardsnap()],
    ["^s", "docs.google.com/forms", (*) => googleforms.giftcardsnap()],
    ["~RAlt", "docs.google.com/forms", (*) => Send('{Blind}{vkE8}')],
    ["*RAlt up", "docs.google.com/forms", (*) => (Send('{Blind}{Ctrl}{Alt up}{Ctrl up}'), googleforms.openSpreadsheet(), Send('{Blind}{LAlt up}{LControl up}{RAlt up}'))],

    ; mail.google.com/mail/u/0/#inbox
    ["^d", "mail.google.com/mail/u/0/#inbox", (*) => gmail.delete()],
    ["^Capslock", "mail.google.com/mail/u/0/#inbox", (*) => gmail.delete()],
    ["~RAlt", "mail.google.com/mail/u/0/#inbox", (*) => Send('{Blind}{vkE8}')],
    ["*RAlt up", "mail.google.com/mail/u/0/#inbox", (*) => (Send('{Blind}{Ctrl}{Alt up}{Ctrl up}'), bwe({ LocalizedType: "button", Name: "Main menu" }), Send('{Blind}{LAlt up}{LControl up}{RAlt up}')),],
    ["^l", "mail.google.com/mail/u/0/#inbox", (*) => gmail.actionrequired()],
    ["!a", "mail.google.com/mail/u/0/#inbox", (*) => gmail.actionrequired()],
    ["^k", "mail.google.com/mail/u/0/#inbox", (*) => gmail.awaitingreply()],
    ["!w", "mail.google.com/mail/u/0/#inbox", (*) => gmail.awaitingreply()],
    ["!r", "mail.google.com/mail/u/0/#inbox", (*) => gmail.readlater()],
    ["!i", "mail.google.com/mail/u/0/#inbox", (*) => gmail.importantdocuments()],
    ["^i", "mail.google.com/mail/u/0/#inbox", (*) => gmail.importantdocuments()],
    ["^j", "mail.google.com/mail/u/0/#inbox", (*) => gmail.readlater()],
    ["!f", "mail.google.com/mail/u/0/#inbox", (*) => gmail.forward()],
    ["^s", "mail.google.com/mail/u/0/#inbox", (*) => gmail.simplesnooze()],
    ["!d", "mail.google.com/mail/u/0/#inbox", (*) => gmail.unsubscribe()],
    ["!u", "mail.google.com/mail/u/0/#inbox", (*) => gmail.unsubscribe()],
    ["^+i", "mail.google.com/mail/u/0/#inbox", (*) => gmail.insertfiles()],
    ["^z", "mail.google.com/mail/u/0/#inbox", (*) => gmail.undo()],
    ["!Capslock", "mail.google.com/mail/u/0/#inbox", (*) => ShowMenuWithDigits(MenuMap["Gmail2"])],
    ["!c", "mail.google.com/mail/u/0/#inbox", (*) => gmail.calendar()],
    ["^m", "mail.google.com/mail/u/0/#inbox", (*) => bwe({ LocalizedType: "button", Name: "Main menu" })],
    ["^+f", "mail.google.com/mail/u/0/#inbox", (*) => gmail.findonpage()],
    ["^h", "mail.google.com/mail/u/0/#inbox", (*) => gmail.home()],
    ["!k", "mail.google.com/mail/u/0/#inbox", (*) => gmail.keep()],
    ["!t", "mail.google.com/mail/u/0/#inbox", (*) => gmail.tasks()],
    ["^n", "mail.google.com/mail/u/0/#inbox", (*) => gmail.new()],
    ["^p", "mail.google.com/mail/u/0/#inbox", (*) => gmail.nextmessage()],
    ["^+l", "mail.google.com/mail/u/0/#inbox", (*) => gmail.previousmessage()],
    ["^+left", "mail.google.com/mail/u/0/#inbox", (*) => gmail.nextmessage()],
    ["!l", "mail.google.com/mail/u/0/#inbox", QMK.SendKeyDirect("^l")],
    ["^+right", "mail.google.com/mail/u/0/#inbox", (*) => gmail.previousmessage()],
    ["^e", "mail.google.com/mail/u/0/#inbox", (*) => gmail.removefrominbox()],
    ["^f", "mail.google.com/mail/u/0/#inbox", (*) => gmail.searchinbox()],
    ["~CapsLock & f", "mail.google.com/mail/u/0/#inbox", (*) => gmail.searchinbox()],
    ["^Enter", "mail.google.com/mail/u/0/#inbox", (*) => gmail.tryenter()],

    ; google.com/search
    ["^f", "google.com/search", QMK.SendKeyDirect("/")],
    ["~CapsLock & f", "google.com/search", QMK.SendKeyDirect("/")],
    ["^+f", "google.com/search", QMK.SendKeyDirect("^f")],
    ["!I", "google.com/search", (*) => bwe({ LocalizedType: "link", Name: "Images" })],
    ["!a", "google.com/search", (*) => bwe({ LocalizedType: "link", Name: "All" })],
    ["!v", "google.com/search", (*) => bwe({ LocalizedType: "link", Name: "Videos" })],

    ; gemini.google.com
    ["^+i", "gemini.google.com", (*) => gemini.insert()],

    ; google.com/maps
    ["^f", "google.com/maps", (*) => bwe({ AutomationId: "searchbox-searchbutton" }, "Invoke")],
    ["~Capslock & f", "google.com/maps", (*) => bwe({ AutomationId: "searchbox-searchbutton" }, "Invoke")],
    ["^+f", "google.com/maps", QMK.SendKeyDirect("^f")],

    ; calendar.google.com
    ["!h", "calendar.google.com", (*) => googlecalendar.previous()],
    ["!l", "calendar.google.com", (*) => googlecalendar.next()],
    ["!n", "calendar.google.com", (*) => googlecalendar.arrowhandlerright()],
    ["Right", "calendar.google.com", (*) => googlecalendar.arrowhandlerright()],
    ["^Right", "calendar.google.com", (*) => googlecalendar.arrowhandlerright()],
    ["^l", "calendar.google.com", (*) => googlecalendar.arrowhandlerright()],
    ["^p", "calendar.google.com", (*) => googlecalendar.arrowhandlerleft()],
    ["Left", "calendar.google.com", (*) => googlecalendar.arrowhandlerleft()],
    ["^Left", "calendar.google.com", (*) => googlecalendar.arrowhandlerleft()],
    ["^h", "calendar.google.com", (*) => googlecalendar.arrowhandlerleft()],
    ["~RAlt", "calendar.google.com", (*) => Send('{Blind}{vkE8}')],
    ["*RAlt up", "calendar.google.com", (*) => (Send('{Blind}{Ctrl}{Alt up}{Ctrl up}'), googlecalendar.togglesidebar(), Send('{Blind}{LAlt up}{LControl up}{RAlt up}')),],
    ["!d", "calendar.google.com", (*) => googlecalendar.view("day")],
    ["!w", "calendar.google.com", (*) => googlecalendar.view("week")],
    ["!m", "calendar.google.com", (*) => googlecalendar.view("month")],
    ["!y", "calendar.google.com", (*) => googlecalendar.view("year")],
    ["!l", "calendar.google.com", (*) => googlecalendar.next()],
    ["!s", "calendar.google.com", (*) => googlecalendar.togglecalendar("SCO Calendar")],
    ["^!d", "calendar.google.com", (*) => googlecalendar.googlesuites("Drive")],
    ["^k", "calendar.google.com", (*) => googlecalendar.googlesuites("Keep")],
    ["!k", "calendar.google.com", (*) => googlecalendar.googlesuites("Keep")],
    ["!+t", "calendar.google.com", (*) => googlecalendar.googlesuites("Tasks")],
    ["^m", "calendar.google.com", (*) => googlecalendar.googlesuites("Maps")],
    ["^n", "calendar.google.com", (*) => googlecalendar.new("Event")],
    ["!t", "calendar.google.com", (*) => googlecalendar.new("Task")],
    ["^+c", "calendar.google.com", (*) => bwe({ LocalizedType: "button", Name: "Mark completed" })],
    ["^d", "calendar.google.com", (*) => googlecalendar.duplicate()],
    ["^z", "calendar.google.com", (*) => googlecalendar.undo()],
    ["^Capslock", "calendar.google.com", (*) => googlecalendar.delete()],
    ["~Escape", "calendar.google.com", (*) => googlecalendar.exit()],
    ["^o", "calendar.google.com", (*) => googlecalendar.togglecalendar("Our Calendar")],
    ["^!m", "calendar.google.com", (*) => googlecalendar.togglecalendar("Main Calendar")],
    ["!f", "calendar.google.com", (*) => googlecalendar.togglecalendar("Family Calendar")],
    ["!b", "calendar.google.com", (*) => googlecalendar.togglecalendar("Kool Kids Calendar")],
    ["^b", "calendar.google.com", (*) => googlecalendar.togglecalendar("Birthdays")],
    ["^!t", "calendar.google.com", (*) => googlecalendar.togglecalendar("Tasks")],

    ; docs.google.com/presentation
    ["^e", "docs.google.com/presentation", (*) => googleslides.center()],
    ["^l", "docs.google.com/presentation", (*) => googleslides.leftalign()],
    ["^f", "docs.google.com/presentation", (*) => googleslides.searchbox()],
    ["~CapsLock & f", "docs.google.com/presentation", (*) => googleslides.searchbox()],
    ["^+f", "docs.google.com/presentation", QMK.SendKeyDirect("^f")],
    ["^n", "docs.google.com/presentation", (*) => bwe({ AutomationId: "newSlideButton" })],
    ["^+n", "docs.google.com/presentation", QMK.SendKeyDirect("^n")],
    ["^+I", "docs.google.com/presentation", (*) => googleslides.image()],

    ; drive.google.com
    ["^n", "drive.google.com", (*) => googledrive.insert()],
    ["^+i", "drive.google.com", (*) => googledrive.insert()],
    ["^u", "drive.google.com", (*) => googledrive.insert()],
    ["^f", "drive.google.com", (*) => googledrive.search()],
    ["~CapsLock & f", "drive.google.com", (*) => googledrive.search()],
    ["^+f", "drive.google.com", QMK.SendKeyDirect("^f")],
    ["^d", "drive.google.com", (*) => googledrive.delete()],

    ; keep.google.com
    ["^f", "keep.google.com", (*) => googlekeep.search()],
    ["~CapsLock & f", "keep.google.com", (*) => googlekeep.search()],
    ["^+f", "keep.google.com", QMK.SendKeyDirect("^f")],

    ; photos.google.com
    ["^s", "photos.google.com", (*) => googlephotos.save()],
    ["^+i", "photos.google.com", (*) => googlephotos.upload()],
    ["^Capslock", "photos.google.com", (*) => googlephotos.delete()],
    ["^f", "photos.google.com", QMK.SendKeyDirect("/")],
    ["^+f", "photos.google.com", QMK.SendKeyDirect("^f")],

    ; contacts.google.com
    ["^f", "contacts.google.com", (*) => googlecontacts.search()],
    ["~CapsLock & f", "contacts.google.com", (*) => googlecontacts.search()],
    ["^+f", "contacts.google.com", QMK.SendKeyDirect("^f")],

    ; notebooklm.google.com
    ["^l", "notebook.google.com", (*) => QMK.PasteTextWithDll(Prompts.LinseyNotebookLM)],
    ["^+i", "notebook.google.com", (*) => notebooklm.insert()],
    ["^+c", "notebook.google.com", (*) => notebooklm.prompttoclipboard()],
    ["!d", "notebook.google.com", (*) => notebooklm.newandinsert()],
    ["^d", "notebook.google.com", (*) => notebooklm.download()],
    ["^Enter", "notebook.google.com", (*) => bwe({ LocalizedType: "button", Name: "Generate" })],
    ["^!+i", "notebook.google.com", (*) => notebooklm.insertfromcurrentonenote()],

    ; intedashboard.com
    ["^Enter", "intedashboard.com", (*) => intedashboard.submitevaluation()],
    ["^+Enter", "intedashboard.com", (*) => intedashboard.submitevaluation()],
    ["^s", "intedashboard.com", (*) => intedashboard.Click("Save Answer")],
    ["!s", "intedashboard.com", (*) => intedashboard.Click("Save Answer")],
    ["^n", "intedashboard.com", (*) => intedashboard.next()],
    ["!a", "intedashboard.com", (*) => bfn(1, { LocalizedType: "radio button" })],
    ["!b", "intedashboard.com", (*) => bfn(2, { LocalizedType: "radio button" })],
    ["!c", "intedashboard.com", (*) => bfn(3, { LocalizedType: "radio button" })],
    ["!d", "intedashboard.com", (*) => bfn(4, { LocalizedType: "radio button" })],
    ["!e", "intedashboard.com", (*) => bfn(5, { LocalizedType: "radio button" })],
    ["!Capslock", "intedashboard.com", (*) => ShowMenuWithDigits(MenuMap["InteDashboard2"])],

    ; monkeytype.com
    ["^n", "monkeytype.com", (*) => bwe({ LocalizedType: "button", Name: "Next test" })],
    ["^Capslock", "monkeytype.com", (*) => bwe({ LocalizedType: "button", Name: "Repeat test" })],

    ; outlook.live.com
    ["^n", "outlook.live.com", QMK.SendKeyDirect("c")],
    ["^+I", "outlook.live.com", (*) => outlook.insert()],
    ["!f", "outlook.live.com", (*) => outlook.forward()],
    ["^f", "outlook.live.com", QMK.SendKeyDirect("/")],
    ["~CapsLock & f", "outlook.live.com", QMK.SendKeyDirect("/")],
    ["^+f", "outlook.live.com", QMK.SendKeyDirect("^f")],
    ["^z", "outlook.live.com", (*) => bwe({ LocalizedType: "button", Name: "Undo" })],

    ; panopto.com, hosted.panopto.com
    ["^d", panoptoContext, (*) => panopto.download()],
    ["^+d", panoptoContext, (*) => panopto.ytdlp()],
    ["~c", panoptoContext, (*) => QMK.Tap(panopto.togglecaptions())],

    ; reddit.com
    ["^s", "reddit.com", (*) => bwe({ LocalizedType: "button", Name: ".*Save*", matchmode: "RegEx", CaseSense: 0 })],
    ["Ralt", "reddit.com", (*) => reddit.togglesidebar()],

    ; redketchup.io
    ["^+I", "redketchup.io", (*) => redketchup.converttoico()],

    ; pollev.com
    ["!a", "pollev.com", (*) => pollev.select(1, "A")],
    ["!b", "pollev.com", (*) => pollev.select(2, "B")],
    ["!c", "pollev.com", (*) => pollev.select(3, "C")],
    ["!d", "pollev.com", (*) => pollev.select(4, "D")],
    ["!e", "pollev.com", (*) => pollev.select(5, "E")],

    ; open.spotify.com
    ["^f", "open.spotify.com", (*) => bwe({ Type: "Group", LocalizedType: "search" })],
    ["^+f", "open.spotify.com", QMK.SendKeyDirect("^f")],

    ; creators.spotify.com/pod/show
    ["!s", "creators.spotify.com/pod/show", (*) => spotifypodcast.scheduledatebytitlenumber()],

    ; creators.spotify.com
    ["^+I", "creators.spotify.com", (*) => spotifypodcast.new()],
    ["!s", "creators.spotify.com", (*) => spotifypodcast.scheduledatebytitlenumber()],

    ; uccu.com
    ["^g", "uccu.com", (*) => SetTimer(() => globals.activaterun("Gmail", "https://mail.google.com"))],

    ; webpathology.com
    ["right", "webpathology.com", (*) => webpathology.next()],
    ["l", "webpathology.com", (*) => QMK.Tap(webpathology.next())],
    ["left", "webpathology.com", (*) => QMK.Tap(webpathology.previous())],
    ["h", "webpathology.com", (*) => webpathology.previous()],

    ; webpath.med.utah.edu
    ["right", "webpath.med.utah.edu", (*) => QMK.Tap(webpath.next())],
    ["l", "webpath.med.utah.edu", (*) => QMK.Tap(webpath.next())],
    ["left", "webpath.med.utah.edu", (*) => QMK.Tap(webpath.previous())],
    ["h", "webpath.med.utah.edu", (*) => QMK.Tap(webpath.previous())],
    ["^h", "webpath.med.utah.edu", (*) => webpath.home()],
    ["!a", "webpath.med.utah.edu", (*) => webpath.select("A")],
    ["!b", "webpath.med.utah.edu", (*) => webpath.select("B")],
    ["!c", "webpath.med.utah.edu", (*) => webpath.select("C")],
    ["!d", "webpath.med.utah.edu", (*) => webpath.select("D")],
    ["!e", "webpath.med.utah.edu", (*) => webpath.select("E")],

    ; studio.youtube.com
    ["^+!i", "studio.youtube.com", (*) => youtube.studio.insertfromonenotetitle()],
    ["^+I", "studio.youtube.com", (*) => youtube.studio.insert()],
    ["^d", "studio.youtube.com", (*) => youtube.studio.addvideodetails()],
    ["~RAlt", "studio.youtube.com", (*) => Send('{Blind}{vkE8}')],
    ["*RAlt up", "studio.youtube.com", (*) => (Send('{Blind}{Ctrl}{Alt up}{Ctrl up}'), bwe({ AutomationId: "collapse-expand-icon" }), Send('{Blind}{LAlt up}{LControl up}{RAlt up}'))],

    ; youtube.com
    ["^f", "youtube.com", QMK.SendKeyDirect("/")],
    ; ["^f", "youtube.com", (*) => Send("{Blind}/")],

    ["~CapsLock & f", "youtube.com", QMK.SendKeyDirect("/")],
    ["^+f", "youtube.com", QMK.SendKeyDirect("^f")],
    ["^n", "youtube.com", (*) => youtube.skipadd()],
    ["^Enter", "youtube.com", (*) => bwe({ LocalizedType: "button", Name: "Search" }, ControlClick)],
    ["~RAlt", "youtube.com", (*) => Send('{Blind}{vkE8}')],
    ["*RAlt up", "youtube.com", (*) => (Send('{Blind}{Ctrl}{Alt up}{Ctrl up}'), bwe({ AutomationId: "button" }), Send('{Blind}{LAlt up}{LControl up}{RAlt up}')),],
    ["F5", "youtube.com", (*) => youtube.videowatchcalendarevent()],
    ["F6", "youtube.com", (*) => youtube.videotocalendarevent()],
    ["^s", "youtube.com", (*) => bwe({ LocalizedType: "link", Name: "Subscriptions" })],
    ["^h", "youtube.com", (*) => bwe({ AutomationId: "logo" })],

    ; https://zoom.us
    ["F5", "https://zoom.us", (*) => zoom.createstudycalendarevent()],
    ["F6", "https://zoom.us", (*) => zoom.createstudytask()],
    ["^d", "https://zoom.us", (*) => bwe({ LocalizedType: "link", Name: ".*Download*", matchmode: "RegEx", CaseSense: 0 })],

    ; ahk_exe EXCEL.EXE
    ["^f", "ahk_exe EXCEL.EXE", (*) => excelfindandreplace()],
    ["^+m", "ahk_exe EXCEL.EXE", QMK.SendKeyDirect("^+m")],



    ; Hotstring Helper ahk_class AutoHotkeyGUI
    ["^Enter", "Hotstring Helper ahk_class AutoHotkeyGUI", (*) => Hotstringhelperappendbutton()],
    ["^Capslock", "Hotstring Helper ahk_class AutoHotkeyGUI", (*) => Hotstringhelperappendbutton()],

    ; Image Capture
    ["Enter", "Image Capture", (*) => ControlClick("Button19")],
    ["+Enter", "Image Capture", (*) => ControlClick("Button19")],
    ["^+Enter", "Image Capture", (*) => ControlClick("OK")],

    ; ahk_exe Prompt Assistant.exe
    ["^n", "ahk_exe Prompt Assistant.exe", (*) => ControlClick("Button1")],
    ["^e", "ahk_exe Prompt Assistant.exe", (*) => promptassistantedit()],
    ["^delete", "ahk_exe Prompt Assistant.exe", (*) => ControlClick("Button3")],
    ["!up", "ahk_exe Prompt Assistant.exe", (*) => ControlClick("Button4")],
    ["!down", "ahk_exe Prompt Assistant.exe", (*) => ControlClick("Button5")],
    ["^s", "ahk_exe Prompt Assistant.exe", (*) => ControlClick("Button8")],

    ; QuickCodeTester*
    ["^/", "QuickCodeTester*", QMK.SendKeyDirect("^k")],
    ["^+/", "QuickCodeTester*", QMK.SendKeyDirect("^+k")],

    ; Quick Edit
    ["^enter", "Quick Edit", (*) => ControlClick("Button1")],
    ["^Capslock", "Quick Edit", (*) => ControlClick("Button1")],
    ["F1", "Quick Edit", (*) => ControlClick("Button1")],
    ["^c", "Quick Edit", (*) => ControlClick("Button1")],

    ; Save Screenshot
    ["^i", "Save Screenshot", (*) => SendText(A_Clipboard)],

    ; Simple Timer
    ["j", "Simple Timer", QMK.Tap("Down")],
    ["k", "Simple Timer", QMK.Tap("Up")],
    ["l", "Simple Timer", QMK.Tap("Right")],
    ["1", "Simple Timer", (*) => QMK.Tap(bwe({ LocalizedType: "button", Name: "1m" }, "Click"))],
    ["2", "Simple Timer", (*) => QMK.Tap(bwe({ LocalizedType: "button", Name: "2m", AutomationId: "5" }, "Click"))],
    ["5", "Simple Timer", (*) => QMK.Tap(bwe({ LocalizedType: "button", Name: "5m" }, "Click"))],
    ["0", "Simple Timer", (*) => QMK.Tap(bwe({ LocalizedType: "button", Name: "10m" }))],
    ["c", "Simple Timer", (*) => QMK.Tap(bwe({ LocalizedType: "button", Name: "Custom Timer" }))],
    ["^Enter", "Simple Timer", (*) => QMK.Tap(bwe({ LocalizedType: "button", Name: "Custom Timer" }))],
    ["^Capslock", "Simple Timer", (*) => QMK.Tap(bwe({ LocalizedType: "button", Name: "Pomodoro Timer" }))],
    ["p", "Simple Timer", (*) => QMK.Tap(bwe({ LocalizedType: "button", Name: "Pomodoro Timer" }))],

    ; Pomodoro Timer ahk_class AutoHotkeyGUI
    ["2", "Pomodoro Timer ahk_class AutoHotkeyGUI", (*) => QMK.Tap(UIA.ElementFromHandle(WinActive("A")).WaitElement({ LocalizedType: "text", Name: "2" }, 1000).Walktree("-1").ControlClick())],
    ["3", "Pomodoro Timer ahk_class AutoHotkeyGUI", (*) => QMK.Tap(UIA.ElementFromHandle(WinActive("A")).WaitElement({ LocalizedType: "text", Name: "3" }, 1000).Walktree("-1").ControlClick())],
    ["4", "Pomodoro Timer ahk_class AutoHotkeyGUI", (*) => QMK.Tap(UIA.ElementFromHandle(WinActive("A")).WaitElement({ LocalizedType: "text", Name: "4" }, 1000).Walktree("-1").ControlClick())],
    ["5", "Pomodoro Timer ahk_class AutoHotkeyGUI", (*) => QMK.Tap(UIA.ElementFromHandle(WinActive("A")).WaitElement({ LocalizedType: "text", Name: "5" }, 1000).Walktree("-1").ControlClick())],
    ["c", "Pomodoro Timer ahk_class AutoHotkeyGUI", (*) => QMK.Tap(bwe({ LocalizedType: "button", Name: "Custom" }))],
    ["s", "Pomodoro Timer ahk_class AutoHotkeyGUI", (*) => QMK.Tap(bwe({ LocalizedType: "button", Name: "Start Pomodoro" }))],

    ; Custom Timer ahk_exe AutoHotkey64.exe
    ["c", "Custom Timer ahk_exe AutoHotkey64.exe", (*) => QMK.Tap(bwe({ LocalizedType: "button", Name: "Cancel" }))],
    ["~Space", "Custom Timer ahk_exe AutoHotkey64.exe", (*) => QMK.Tap(bwe({ LocalizedType: "button", Name: "OK" }))],

    ; Messenger ahk_class Chrome_WidgetWin_1 ahk_exe msedge.exe
    ["^d", "Messenger ahk_class Chrome_WidgetWin_1 ahk_exe msedge.exe", (*) => bwe({ LocalizedType: "link", Name: "Download" })],

    ; ahk_exe Notepad.exe ahk_class Notepad
    ["^+s", "ahk_exe Notepad.exe ahk_class Notepad", QMK.SendKeyDirect("^+s")],
    ["!s", "ahk_exe Notepad.exe ahk_class Notepad", (*) => notepad.strikethrough()],
    ["^7", "ahk_exe Notepad.exe ahk_class Notepad", (*) => notepad.strikethrough()],

    ; !ahk_exe ONENOTE.EXE
    ["^k", "!ahk_exe ONENOTE.EXE", QMK.SendKeyDirect("^{Up}")],
    ["^j", "!ahk_exe ONENOTE.EXE", QMK.SendKeyDirect("^{Down}")],

    ; ahk_exe olk.exe
    ["^!r", "ahk_exe olk.exe", (*) => outlookdesktop.reservestudyroom()],
    ["^+I", "ahk_exe olk.exe", (*) => outlookdesktop.insert()],
    ["^n", "ahk_exe olk.exe", (*) => outlookdesktop.newmail()],
    ["!f", "ahk_exe olk.exe", (*) => outlookdesktop.forward()],
    ["^z", "ahk_exe olk.exe", (*) => outlookdesktop.undo()],
    ["^f", "ahk_exe olk.exe", QMK.SendKeyDirect("!q")],
    ["^h", "ahk_exe olk.exe", (*) => outlookdesktop.home()],
    ["!s", "ahk_exe olk.exe", (*) => bwe({ LocalizedType: "tree item", Name: "Sent Items" })],
    ["!c", "ahk_exe olk.exe", (*) => bwe({ LocalizedType: "toggle button", Name: "Calendar" })],
    ["^Capslock", "ahk_exe olk.exe", (*) => outlookdesktop.delete()],
    ["~Capslock & f", "ahk_exe olk.exe", QMK.SendKeyDirect("!q")],

    ; ahk_exe PhoneExperienceHost.exe
    ["^+n", "ahk_exe PhoneExperienceHost.exe", (*) => phonelink.newmessage()],
    ["^n", "ahk_exe PhoneExperienceHost.exe", (*) => phonelink.newmessage("Linsey Hafen", "7346211818")],
    ["^+l", "ahk_exe PhoneExperienceHost.exe", (*) => phonelink.newmessage("Linsey Hafen", "7346211818")],
    ["^r", "ahk_exe PhoneExperienceHost.exe", (*) => phonelink.reloadnotifications()],
    ["^p", "ahk_exe PhoneExperienceHost.exe", (*) => phonelink.playpause()],
    ["^g", "ahk_exe PhoneExperienceHost.exe", (*) => groupme.grablogincode()],
    ["^Capslock", "ahk_exe PhoneExperienceHost.exe", (*) => phonelink.clearnotifications()],

    ; ahk_exe POWERPNT.EXE
    ["^e", "ahk_exe POWERPNT.EXE", (*) => PowerPoint.export()],
    ["^+c", "ahk_exe POWERPNT.EXE", (*) => powerpoint.formatpainter()],
    ["^+p", "ahk_exe POWERPNT.EXE", (*) => powerpoint.printtopdf()],
    ["+Capslock", "ahk_exe POWERPNT.EXE", (*) => ShowMenuWithDigits(PowerPointMenu) ],



    ; ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1
    ["^+a", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => spotify.addtoplaylistmanual("Repro 2")],
    ["^!Left", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => spotify.scrubbackorprevious()],
    ["^!h", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => (!WinActive("ahk_exe ONENOTE.EXE") ? spotify.scrubbackorprevious() : "")],
    ["^!Right", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => spotify.scrubforwardornext()],
    ["^!l", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => spotify.scrubforwardornext()],
    ["Right", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => spotify.scrubforwardornext()],
    ["Left", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => spotify.scrubbackorprevious()],
    ["!+Space", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => spotify.toggleplaypause()],
    ["^!p", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => spotify.toggleplaypause()],
    ["^p", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => spotify.toggleplaypause()],
    ["^n", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => spotify.scrubforwardornext()],
    ["^b", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => spotify.scrubbackorprevious()],
    ["^!+h", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => media.connectheadphones()],

    ; Spotify
    ["^b", "Spotify", (*) => spotify.scrubbackorprevious()],

    ; ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1
    ["^s", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => Spotify.toggleshuffle()],
    ["!s", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => Spotify.toggleshuffle()],
    ["!Right", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => Spotify.scrubforward()],
    ["!Left", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => Spotify.scrubback()],
    ["^d", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => Spotify.addtoplaylist("Date Night")],
    ["^f", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", QMK.SendKeyDirect("^l")],
    ["^+f", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", QMK.SendKeyDirect("^l")],
    ["^m", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => ShowMenuWithDigits(SpotifyMenu)],

    ; global
    ["!+h", "global", (*) => media.connectheadphones()],

    ; ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1
    ["~RAlt", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => Send('{Blind}{vkE8}')],
    ["*RAlt up", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => (Send('{Blind}{Ctrl}{Alt up}{Ctrl up}'), (HasProp(QMK, "spotifyRAltUsed") && QMK.spotifyRAltUsed) ? (QMK.spotifyRAltUsed := false) : spotify.togglefullscreen(), Send('{Blind}{LAlt up}{LControl up}{RAlt up}')),],
    ["~RAlt & Left", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => (QMK.spotifyRAltUsed := true, spotify.scrubbackorprevious())],
    ["~RAlt & Right", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", (*) => (QMK.spotifyRAltUsed := true, spotify.scrubforwardornext())],
    ["~CapsLock & f", "ahk_exe Spotify.exe ahk_class Chrome_WidgetWin_1", QMK.SendKeyDirect("^l")],

    ; Spotify
    ["^+s", "Spotify", QMK.SendKeyDirect("^+s")],

    ; BrowserActive()
    ["!+s", "BrowserActive()", (*) => spotifypodcast.quickcreate()],
    ["^!r", "BrowserActive()", QMK.SendKeyDirect("^F5")],
    ["^o", "BrowserActive()", (*) => (SendInput("^o"), fileexplorer.selectfirstresult("Open"))],

    ; ahk_exe vlc.exe
    ["e", "ahk_exe vlc.exe", QMK.Tap("]")],
    ["w", "ahk_exe vlc.exe", QMK.Tap("[")],

    ; ahk_exe WINWORD.EXE
    ["^+d", "ahk_exe WINWORD.EXE", (*) => word.settheme("D")],
    ["^+w", "ahk_exe WINWORD.EXE", (*) => word.settheme("W")],
    ["^+e", "ahk_exe WINWORD.EXE", (*) => word.settheme("B")],
    ["^+x", "ahk_exe WINWORD.EXE", (*) => word.settheme("U")],
    ["^+q", "ahk_exe WINWORD.EXE", (*) => word.settheme("C")],
    ["^+i", "ahk_exe WINWORD.EXE", (*) => word.insert()],
    ["^t", "ahk_exe WINWORD.EXE", (*) => word.settimesnewroman()],
    ["^+c", "ahk_exe WINWORD.EXE", (*) => word.formatpainter()],
    ["^+v", "ahk_exe WINWORD.EXE", (*) => word.formatpainter()],
    ["^+s", "ahk_exe WINWORD.EXE", (*) => word.saveas()],
    ["^o", "ahk_exe WINWORD.EXE", (*) => word.open()],

    ; Microsoft Excel
    ["^+l", "Microsoft Excel", QMK.SendKeyDirect("^+l")],
    ["^+k", "Microsoft Excel", QMK.SendKeyDirect("^+k")],
    ["^+j", "Microsoft Excel", QMK.SendKeyDirect("^+j")],
    ["^!l", "Microsoft Excel", QMK.SendKeyDirect("^!l")],
    ["^!k", "Microsoft Excel", QMK.SendKeyDirect("^!k")],
    ["^!j", "Microsoft Excel", QMK.SendKeyDirect("^!j")],
    ["^!m", "Microsoft Excel", QMK.SendKeyDirect("^!m")],
    ["^!+m", "Microsoft Excel", QMK.SendKeyDirect("^!+m")],
    ["^+8", "Microsoft Excel", QMK.SendKeyDirect("^+8")],

    ; Microsoft Word
    ["^+l", "Microsoft Word", QMK.SendKeyDirect("^+l")],
    ["^+k", "Microsoft Word", QMK.SendKeyDirect("^+k")],
    ["^+j", "Microsoft Word", QMK.SendKeyDirect("^+j")],

    ; OneNote
    ["^+l", "OneNote", QMK.SendKeyDirect("^+l")],
    ["^+k", "OneNote", QMK.SendKeyDirect("^+k")],

    ; ahk_exe ms-teams.exe, ahk_exe Teams.exe
    ["^+m", teamsMuteContext, QMK.SendKeyDirect("^+m")],

    ; ahk_exe OUTLOOK.EXE, ahk_exe olk.exe
    ["^+m", outlookMuteContext, QMK.SendKeyDirect("^+m")],

    ; Outlook
    ["^+r", "Outlook", QMK.SendKeyDirect("^+r")],

    ; File Explorer
    ["^+n", "File Explorer", QMK.SendKeyDirect("^+n")],

    ; Task List
    ["^Enter", "Task List", (*) => PreferencesGUI.tasklistsavebutton()],
    ["^s", "Task List", (*) => PreferencesGUI.tasklistsavebutton()],
    ["Escape", "Task List", (*) => PreferencesGUI.tasklistsavebutton()],
    ["^Up", "Task List", (*) => ControlSend("{Up}", "ComboBox1", "Task List")],
    ["^Down", "Task List", (*) => ControlSend("{Down}", "ComboBox1", "Task List")],
    ["^Tab", "Task List", (*) => ControlSend("{Down}", "ComboBox1", "Task List")],
    ["^+Tab", "Task List", (*) => ControlSend("{Down}", "ComboBox1", "Task List")],
    ["^j", "Task List", (*) => ControlSend("{Down}", "ComboBox1", "Task List")],
    ["^k", "Task List", (*) => ControlSend("{Up}", "ComboBox1", "Task List")],
    ["~j & k", "Task List", (*) => PreferencesGUI.tasklistsavebutton()],
    ["~k & j", "Task List", (*) => PreferencesGUI.tasklistsavebutton()],
    ["^Capslock", "Task List", (*) => PreferencesGUI.tasklistsavebutton()],
    ["~CapsLock & J", "Task List", (*) => ControlSend("{Down}", "ComboBox1", "Task List")],
    ["~CapsLock & K", "Task List", (*) => ControlSend("{Up}", "ComboBox1", "Task List")],

; baptistu.instructure.com
["~RButton & WheelDown", "baptistu.instructure.com", (*) => SendInput("w")],
["~RButton & WheelUp", "baptistu.instructure.com", (*) => SendInput("e")],
["^h", "baptistu.instructure.com", (*) => bwe({ LocalizedType: "link", Name: "Dashboard" })],
["!d", "baptistu.instructure.com", (*) => bwe({ LocalizedType: "link", Name: "Dashboard" })],
    ["^+d", "baptistu.instructure.com", (*) => Canvas.LinkExtractor.ExtractLinks()],
    ["^!d", "baptistu.instructure.com", (*) => Canvas.downloadpowershell()],
    ["~RAlt & d", "baptistu.instructure.com", (*) => (QMK.canvasRAltUsed := true, Canvas.downloadpowershell2())],
    ["^+s", "baptistu.instructure.com", (*) => canvas.learningobjectivetotxt()],
    ["^+c", "baptistu.instructure.com", (*) => canvas.learningobjectivetotxt()],
    ["!t", "baptistu.instructure.com", (*) => canvas.togglesidebar()],
    ["!a", "baptistu.instructure.com", (*) => canvas.navigate("Assignments")],
    ["!g", "baptistu.instructure.com", (*) => canvas.navigate("Grades")],
    ["!m", "baptistu.instructure.com", (*) => canvas.navigate("Modules")],
    ["!n", "baptistu.instructure.com", (*) => canvas.navigate("Announcements")],
    ["!p", "baptistu.instructure.com", (*) => canvas.navigate("Panopto")],
    ["!q", "baptistu.instructure.com", (*) => canvas.navigate("Quizzes")],
    ["!s", "baptistu.instructure.com", (*) => canvas.navigate("Syllabus")],
    ["!Capslock", "baptistu.instructure.com", (*) => ShowMenuWithDigits(MenuMap["Canvas2"])],
    ["^+!i", "baptistu.instructure.com", (*) => canvas.save_download_insert_notebook()],
    ["^d", "baptistu.instructure.com", (*) => canvas.download()],
    ["^+i", "baptistu.instructure.com", (*) => canvas.insert()],
    ["^Enter", "baptistu.instructure.com", (*) => canvas.submitquiz()],
    ["^n", "baptistu.instructure.com", (*) => bwe({ Name: "NextQuestion", LocalizedType: "button" })],
    ["~n", "baptistu.instructure.com", (*) => QMK.Tap(bwe({ Name: "NextQuestion", LocalizedType: "button" }))],
    ["~p", "baptistu.instructure.com", (*) => QMK.Tap(bwe({ Name: "PreviousQuestion", LocalizedType: "button" }))],
    ["^p", "baptistu.instructure.com", (*) => bwe({ Name: "PreviousQuestion", LocalizedType: "button" })],
    ["F5", "baptistu.instructure.com", (*) => canvas.createcalendarevent()],
    ["F6", "baptistu.instructure.com", (*) => canvas.createcalendartask()],
    ["~RAlt", "baptistu.instructure.com", (*) => Send('{Blind}{vkE8}')],
    ["*RAlt up", "baptistu.instructure.com", (*) => ((HasProp(QMK, "canvasRAltUsed") && QMK.canvasRAltUsed) ? (QMK.canvasRAltUsed := false) : canvas.togglesidebar(), Send('{Blind}{LAlt up}{LControl up}{RAlt up}'))],

    ; ahk_class AutoHotkeyGUI
    ; moodle.sco.edu
    ["^+s", "moodle.sco.edu", (*) => Canvas.LinkExtractor.ExtractLinks()],

    ; Edit Current, Add ahk_class Qt691QWindowIcon
    ["!c", "Add ahk_class Qt691QWindowIcon", (*) => Anki.browse.samecloze()],
    ["^+c", "Add ahk_class Qt691QWindowIcon", (*) => Anki.browse.newcloze()],
    ["!h", "Add ahk_class Qt691QWindowIcon", QMK.SendKeyDirect("{Left}")],
    ["!j", "Add ahk_class Qt691QWindowIcon", QMK.SendKeyDirect("{Down}")],
    ["!k", "Add ahk_class Qt691QWindowIcon", QMK.SendKeyDirect("{Up}")],
    ["!l", "Add ahk_class Qt691QWindowIcon", QMK.SendKeyDirect("{Right}")],
    ["^e", "Add ahk_class Qt691QWindowIcon", (*) => Anki.EditCurrentEditImageOcclusion()],
    ["^n", "Add ahk_class Qt691QWindowIcon", (*) => Anki.EditCurrentSetNoteTypeY()],
    ["^s", "Add ahk_class Qt691QWindowIcon", (*) => QMK.SendKeyDirect("{Escape}{Ctrl up}")],
    ["^Tab", "Add ahk_class Qt691QWindowIcon", (*) => QMK.SendKeyDirect("{Tab 16}")],
    ["^+Tab", "Add ahk_class Qt691QWindowIcon", (*) => QMK.SendKeyDirect("+{Tab 16}")],
    ["^Capslock", "Add ahk_class Qt691QWindowIcon", QMK.SendKeyDirect("^{Enter}")],

            ["!c", "Edit Current", (*) => Send("{Blind}^+!{c}")],
            ["^+c", "Edit Current", (*) => Send("{Blind}^+{c}")],
            ["^s", "Edit Current", (*) => Send("{Blind}{Escape}")],

            ["!h", "Edit Current", QMK.SendKeyDirect("{Left}")],
            ["!j", "Edit Current", QMK.SendKeyDirect("{Down}")],
            ["!k", "Edit Current", QMK.SendKeyDirect("{Up}")],
            ["!l", "Edit Current", QMK.SendKeyDirect("{Right}")],
            ["^e", "Edit Current", (*) => Anki.EditCurrentEditImageOcclusion()],
            ["^n", "Edit Current", (*) => Anki.EditCurrentSetNoteTypeY()],
            ["^s", "Edit Current", (*) => QMK.SendKeyDirect("{Escape}{Ctrl up}")],
            ["^Tab", "Edit Current", (*) => QMK.SendKeyDirect("{Tab 16}")],
            ["^+Tab", "Edit Current", (*) => QMK.SendKeyDirect("+{Tab 16}")],
            ["^Capslock", "Edit Current", QMK.SendKeyDirect("^{Enter}")],

    ; ahk_exe msedge.exe. Microsoft edge settings
    ["^+,", "ahk_exe msedge.exe", (*) => edge.setgoogleasdefault()],
        ["^.", "ahk_exe msedge.exe", (*) => edge.setgoogleasdefault()],

    ; butterflynetwork.myabsorb.com, butterflynetwork.com
    ["~c", butterflyContext, (*) => QMK.Tap(butterfly.captions())],
    ["^f", butterflyContext, (*) => butterfly.find()],
    ["~Capslock & f", butterflyContext, (*) => butterfly.find()],
    ["^+f", butterflyContext, QMK.SendKeyDirect("^f")],

    ; Settings ahk_class ApplicationFrameWindow
    ["^b", "Settings ahk_class ApplicationFrameWindow", (*) => softconnectairpods()],
    ["!b", "Settings ahk_class ApplicationFrameWindow", (*) => SetTimer(hardresetairpods, -1)],
    ["^+i", "Settings ahk_class ApplicationFrameWindow", (*) => bluetoothsettingsadddevice()],
    ["!t", "Settings ahk_class ApplicationFrameWindow", (*) => bluetoothsettingstogglebluetooth()],
    ["!8", "Settings ahk_class ApplicationFrameWindow", (*) => quickhardreset8bitdo()],
    ["^Capslock", "Settings ahk_class ApplicationFrameWindow", (*) => bluetoothsettingsremoveairpods()],


    ;explorercontext    ; ahk_class #32770, ahk_class CabinetWClass ahk_exe explorer.exe, ahk_class#32770 ahk_exe msedge.exe, Open
    ["^d", explorercontext, (*) => fileexplorer.navrun(Downloads)],
    ["!q", explorercontext, (*) => fileexplorer.navrun(QMKFolder "\")],
    ["^!#+s", explorercontext, (*) => fileexplorer.navrun(Startup)],
    ["!+r", explorercontext, (*) => fileexplorer.removewords("MD, phd, M.D., DO, D.O., Ph.D.")],
    ["^CapsLock", explorercontext, QMK.SendKeyDirect("Delete")],
    ["^+c", explorercontext, (*) => (Send("^+{c}"), Sleep(100), ToolTip("Copied to clipboard: " A_Clipboard), SetTimer(() => ToolTip(), -1000))],
    ["!c", explorercontext, (*) => fileexplorer.navrun("C:\")],
    ["!l", explorercontext, (*) => fileexplorer.navrun(lib)],
    ["^d", explorercontext, (*) => fileexplorer.navrun(Downloads)],
    ["^!l", explorercontext, (*) => fileexplorer.navrun(Libraries)],
    ["!+l", explorercontext, (*) => fileexplorer.navrun(Libraries)],
    ["^g", explorercontext, (*) => fileexplorer.navrun(lib "\..\..\BUCOM\Spring 2025\GI 2")],
    ["!g", explorercontext, (*) => fileexplorer.navrun(lib "\..\GitHub\")],
    ["^I", explorercontext, (*) => fileexplorer.navrun(lib "\..\..\BUCOM\Spring 2025\Anatomy Images")],
    ["!i", explorercontext, (*) => fileexplorer.navrun(icons)],
    ["^k", explorercontext, (*) => fileexplorer.navrun(A_Desktop)],
    ["!f", explorercontext, (*) => fileexplorer.navrun(lib "\Functions")],
    ["!s", explorercontext, (*) => fileexplorer.navrun(Scripts)],
    ["#+e", explorercontext, (*) => fileexplorer.navrun(Libraries "\Extensions\youtube-tab-navigation")],
    ["!r", explorercontext, (*) => fileexplorer.renameasonenotepagetitle()],
    ["^Up", explorercontext, QMK.SendKeyDirect("!Up")],
    ["^h", explorercontext, QMK.SendKeyDirect("!Up")],

    ; UIAViewer ahk_exe AutoHotkey64.exe, UIAViewer ahk_class AutoHotkeyGUI ahk_exe AutoHotkey64_UIA.exe, UIAViewer
    ["^n", uiaViewerContext, (*) => UIAViewerClickMacroSidebar()],
    ["!a", uiaViewerContext, (*) => UIAViewerAddElement()],
    ["^!c", uiaViewerContext, (*) => UIAViewerCopyContent()],
    ["^+c", uiaViewerContext, (*) => UIAViewerAddClick()],
    ["!c", uiaViewerContext, (*) => UIAViewerAddClick()],
    ["!e", uiaViewerContext, (*) => UIAViewerAddExpand()],
    ["^I", uiaViewerContext, (*) => UIAViewerAddInvoke()],
    ["!i", uiaViewerContext, (*) => UIAViewerAddInvoke()],
    ["^h", uiaViewerContext, (*) => UIAViewerAddHighlight()],
    ["!h", uiaViewerContext, (*) => UIAViewerAddHighlight()],
    ["!s", uiaViewerContext, (*) => UIAViewerAddSetValue()],
    ["!k", uiaViewerContext, (*) => UIAViewerAddControlClick()],
    ["^o", uiaViewerContext, (*) => UIAViewerAddControlClick()],
    ["!d", uiaViewerContext, (*) => UIAViewerAddDump()],
    ["!r", uiaViewerContext, (*) => UIAViewerAddRegex()],
    ["~Rshift", uiaViewerContext, (*) => UIAViewerAddRegex()],
    ["!+r", uiaViewerContext, (*) => UIAViewerAddRegexH()],
    ["^CapsLock", uiaViewerContext, (*) => UIAViewerSetStandard()],
    ["^d", uiaViewerContext, (*) => UIAViewerSetStandard()],
    ["!n", uiaViewerContext, (*) => UIAViewerInsertStartTemplate()],
    ["!v", uiaViewerContext, (*) => ViewerCode_ConvertUIA()],

    ; Capture Image To Text and Find Text Tool
    ["Enter", "Capture Image To Text and Find Text Tool", (*) => ControlClick("Button9")],
    ["F7", "Capture Image To Text and Find Text Tool", (*) => FindTextClickCapture()],
    ["F1", "Capture Image To Text and Find Text Tool", (*) => CopyFindTextCode()],
    ["^+c", "Capture Image To Text and Find Text Tool", (*) => CopyFindTextCode()],

    ;epic
    ["^+l", "ahk_exe wfica32.exe", (*) => (Sendinput("michael.hafen{tab}"), Sendaspaste(epcwp), SendInput("{enter}"), sleep(3000), SendInput("{Enter 2}"))],

])




 
