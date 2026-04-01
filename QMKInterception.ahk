#Requires AutoHotkey v2.0
#SingleInstance Force
#Include lib\QMKVariables.ahk
#Include lib\MCodeLoader.ahk
#Include lib\MemoryModule.ahk


^!F1:: DllCall(QMK.Proc("QMK_ShowProfilingReport"))
^!F2:: DllCall(QMK.Proc("QMK_ToggleKernelInjection"))
^!F3:: DllCall(QMK.Proc("QMK_ToggleProfilingEnabled"))
^!F9:: DllCall(QMK.Proc("QMK_ViewSettings"))

*#!r:: QMK.EmergencyReset()

SendMode "Input"
SetKeyDelay(-1, 0)
SetDefaultMouseSpeed(0)
A_HotkeyInterval := 100
A_MaxHotkeysPerInterval := 200
ProcessSetPriority("AboveNormal")

class QMK {

        static userconfig := {
            applyUserConfig: false,             ; (true/false, default false) set true to apply all of these timing settings on load. Turn off to compare to default settings. Your specific holds, modifiers, combos, etc., will not be affected
            useInterception: true,              ; (true/false, default true) false = SendInput fallback (no driver needed). True if interception is installed
            profilingEnabled: true,             ; (true/false, default true) false = no performance overhead (almost nothing) on hot path
            ; Timing                            
            singleKeyHoldThreshold: 175.0,      ; (50.0 - 1000.0, default 175.0) ms a single key needs to be held before it is considered "held"
            maxHoldThreshold: 1000.0,           ; (300.0 - 2000.0, default 1000.0) ms max hold before suppression kicks in. Useful if making typing mistake
            maxThresholdSuppress: true,         ; (true/false, default true) if true, keys held past maxHoldThreshold are negated
            maxBufferSize: 30,                  ; (5 - 100, default 50) max keys buffered before eviction
            comboQuietDuration: 300.0,          ; (0.0 - 2000.0, default 200.0) ms quiet period after a combo fires. Try to match doubleTapThreshold for best (tested) results to avoid mismatches.
            modifierThreshold: 1000.0,          ; (0.0 - 1000.0, default 1000.0) ms window for same-type modifier chaining

            ; Double-tap repeat (e.g. double-tap+hold Backspace to repeat)
            doubleTapThreshold: 300.0,          ; (100.0 - 600.0, default 200.0) ms window to detect a double-tap
            repeatInitialDelay: 300,            ; (50+, default 300) ms before repeat starts after double-tap. Safety floor of 50ms to prevent accidental repeat.
            repeatInterval: 20                  ; (5+, default 20) ms between each repeated key. Hardcoded safety floor of 5ms prevents OS runaway. I tested with 0, which sent over ~100,000+ characters a second. Not advised. 5 is nice though.
        }
 
    static hModule := 0
    static hInterception := 0
    static _procCache := Map()

    ; Callback storage
    static holdCallbacks := Map()
    static holdCallbacksById := Map()
    static needsState := Map()
    static comboCallbacks := Map()
    static instantComboCallbacks := Map()
    static chordCallbacks := Map()
    static nextCallbackId := 1
    static ignoredKeys := Map()

    ; Context priority constants
    static CONTEXT_MENU := 1
    static CONTEXT_URL := 2
    static CONTEXT_TITLE := 3
    static CONTEXT_CLASS := 4
    static CONTEXT_BROWSER := 5
    static CONTEXT_EXE := 6
    static CONTEXT_GLOBAL := 7
    static capslockconsumed := false
    static browsers := [
        "ahk_class Chrome_WidgetWin_1 ahk_exe chrome.exe",
        "ahk_class Chrome_WidgetWin_1 ahk_exe msedge.exe",
        "ahk_class MozillaWindowClass ahk_exe firefox.exe",
        "ahk_class Chrome_WidgetWin_1 ahk_exe thorium.exe",
        "ahk_class Chrome_WidgetWin_1 ahk_exe floorp.exe"
    ]

    ; Pre-allocated buffers
    ; OPTIMIZED: Smaller pre-allocated buffers (plenty for your current setup)
    static callbackKey1Buffer := Buffer(256)   ; was 256
    static callbackKey2Buffer := Buffer(256)   ; was 256
    static timerIdBuffer := Buffer(256)   ; was 256
    static timerPkBuffer := Buffer(256)   ; was 256
    static timerSkBuffer := Buffer(256)   ; was 256
    static keyEventResultBuffer := Buffer(256) ;

    static VK_CONTROL := 0x11
    static VK_SHIFT := 0x10
    static VK_MENU := 0x12
    static VK_LWIN := 0x5B
    static VK_RWIN := 0x5C

static __New() {
try {
        QMK.hModule := MemoryModule.LoadLibrary(QMK._B64ToBuffer(qmkcore64zigprofiling))
}
 catch as err {
        MsgBox("Failed to load QMKCore from memory.`n`nError: " . err.Message)
        ExitApp()
    }
    if !QMK.hModule {
        MsgBox("MemoryModule returned null for QMKCore.")
        ExitApp()
    }
    try {
        QMK.hInterception := MemoryModule.LoadLibrary(QMK._B64ToBuffer(interception64))
    } catch as err {
        MsgBox("Failed to load interception from memory.`n`nError: " . err.Message)
        ExitApp()
    }
    if !QMK.hInterception {
        MsgBox("MemoryModule returned null for interception.")
        ExitApp()
    }

    ; --- INJECT CALLBACKS & AUTO-START ZIG ---
    ; (This will now seamlessly initialize the memory arrays too)
    DllCall(QMK.Proc("QMK_SetInterceptionCallbacks"),
        "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_create_context"),
        "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_destroy_context"),
        "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_send"),
        "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_is_keyboard"))

    ; Apply User Config (if enabled)
    if (QMK.userconfig.applyUserConfig) {
        DllCall(QMK.Proc("QMK_SetUserConfig"),
            "Int", QMK.userconfig.applyUserConfig ? 1 : 0,
            "Int", QMK.userconfig.useInterception ? 1 : 0,
            "Int", QMK.userconfig.profilingEnabled ? 1 : 0,
            "Double", QMK.userconfig.singleKeyHoldThreshold,
            "Double", QMK.userconfig.maxHoldThreshold,
            "Int", QMK.userconfig.maxThresholdSuppress ? 1 : 0,
            "Int", QMK.userconfig.maxBufferSize,
            "Double", QMK.userconfig.comboQuietDuration,
            "Double", QMK.userconfig.modifierThreshold,
            "Double", QMK.userconfig.doubleTapThreshold,
            "Int", QMK.userconfig.repeatInitialDelay,
            "Int", QMK.userconfig.repeatInterval)
    }
}
    static Proc(funcName) {
        if QMK._procCache.Has(funcName)
            return QMK._procCache[funcName]
        addr := MemoryModule.GetProcAddress(QMK.hModule, funcName)
        if !addr
            throw Error("QMKCore export not found: " . funcName)
        QMK._procCache[funcName] := addr
        return addr
    }
    static _B64ToBuffer(b64str) {
        if !DllCall("crypt32\CryptStringToBinary", "Str", b64str, "UInt", 0, "UInt", 1,
            "Ptr", 0, "UInt*", &sz := 0, "Ptr", 0, "Ptr", 0)
            throw OSError("CryptStringToBinary size failed")
        buf := Buffer(sz)
        if !DllCall("crypt32\CryptStringToBinary", "Str", b64str, "UInt", 0, "UInt", 1,
            "Ptr", buf, "UInt*", &sz, "Ptr", 0, "Ptr", 0)
            throw OSError("CryptStringToBinary decode failed")
        return buf
    }
    ; ========================================================================
    ; EVENT HANDLERS
    ; ========================================================================
    static CheckPhysicalModifiers() {
        return (DllCall("GetAsyncKeyState", "Int", QMK.VK_CONTROL, "Short") & 0x8000) ||
        (DllCall("GetAsyncKeyState", "Int", QMK.VK_SHIFT, "Short") & 0x8000) ||
        (DllCall("GetAsyncKeyState", "Int", QMK.VK_MENU, "Short") & 0x8000) ||
        (DllCall("GetAsyncKeyState", "Int", QMK.VK_LWIN, "Short") & 0x8000) ||
        (DllCall("GetAsyncKeyState", "Int", QMK.VK_RWIN, "Short") & 0x8000)
    }
    static AnyPhysicalModifier() {
        return DllCall(QMK.Proc("QMK_AnyPhysicalModifier"), "Int")
    }
     static OnKeyDown(key) {
        if (QMK.CheckPhysicalModifiers()) {
        ; if !(QMK.AnyPhysicalModifier()) {
            QMK.ignoredKeys[key] := true
            vk := QMK.GetVK(key)
            if (vk != 0)
                DllCall(QMK.Proc("QMK_SendKeyDirectFromDLL"), "Int", vk, "Int", 0)
            else
                SendInput("{" . key . "}")
            return
        }
        DllCall(QMK.Proc("QMK_ProcessKeyEvent"),
            "Str", key,
            "Int", 1,  ; isDown = true
            "Ptr", QMK.keyEventResultBuffer.Ptr)
        directProcessed := NumGet(QMK.keyEventResultBuffer, 0, "Int")
        slowCount := NumGet(QMK.keyEventResultBuffer, 4, "Int")
        timerCount := NumGet(QMK.keyEventResultBuffer, 8, "Int")
        if (slowCount > 0)
            QMK.ProcessPendingCallbacks()
        if (timerCount > 0)
            QMK.ProcessPendingTimers()
    }

    static OnKeyUp(key) {
        if (QMK.ignoredKeys.Has(key)) {
            QMK.ignoredKeys.Delete(key)
            return
        }
        DllCall(QMK.Proc("QMK_ProcessKeyEvent"),
            "Str", key,
            "Int", 0,  ; isDown = false
            "Ptr", QMK.keyEventResultBuffer.Ptr)
        directProcessed := NumGet(QMK.keyEventResultBuffer, 0, "Int")
        slowCount := NumGet(QMK.keyEventResultBuffer, 4, "Int")
        timerCount := NumGet(QMK.keyEventResultBuffer, 8, "Int")
        if (slowCount > 0)
            QMK.ProcessPendingCallbacks()
        if (timerCount > 0)
            QMK.ProcessPendingTimers()
    }

    ; ========================================================================
    ; CALLBACK PROCESSING (trimmed)
    ; ========================================================================

    static ProcessPendingCallbacks() {
        count := DllCall(QMK.Proc("QMK_GetPendingCallbackCount"), "Int")
        if (count == 0)
            return
        Loop count {
            callbackId := 0
            type := 0
            DllCall(QMK.Proc("QMK_GetPendingCallback"),
                "Int", A_Index - 1,
                "Int*", &callbackId,
                "Ptr", QMK.callbackKey1Buffer.Ptr,
                "Ptr", QMK.callbackKey2Buffer.Ptr,
                "Int*", &type)
            k1 := StrGet(QMK.callbackKey1Buffer)
            k2 := StrGet(QMK.callbackKey2Buffer)
            switch type {
                case 0: ; Hold
                    hotkeyId := k1 . "_hold"
                    callback := QMK.FindMatchingCallback(hotkeyId)
                    if (callback != "")
                        SetTimer((*) => (IsObject(callback) ? callback.Call() : callback()), -1)
                case 1, 2: ; Combo / InstantCombo
                    if (QMK.comboCallbacks.Has(callbackId)) {
                        callback := QMK.comboCallbacks[callbackId]
                        SetTimer((*) => (IsObject(callback) ? callback.Call() : callback()), -1)
                    } else if (QMK.instantComboCallbacks.Has(callbackId)) {
                        callback := QMK.instantComboCallbacks[callbackId]
                        SetTimer((*) => (IsObject(callback) ? callback.Call() : callback()), -1)
                    }
                case 5: ; Chord
                    if (QMK.chordCallbacks.Has(callbackId)) {
                        callback := QMK.chordCallbacks[callbackId]
                        SetTimer((*) => (IsObject(callback) ? callback.Call() : callback()), -1)
                    }
                case 99: ; Emergency reset
                    SendEvent("{Ctrl up}{Shift up}{Alt up}{LWin up}{Capslock up}")
            }
        }
        DllCall(QMK.Proc("QMK_ClearPendingCallbacks"))
    }
    static ProcessPendingTimers() {
        count := DllCall(QMK.Proc("QMK_GetPendingTimerCount"), "Int")
        if (count == 0)
            return
        Loop count {
            delay := 0
            ttype := 0
            ct := 0.0
            DllCall(QMK.Proc("QMK_GetPendingTimer"),
                "Int", A_Index - 1,
                "Ptr", QMK.timerIdBuffer.Ptr,
                "Int*", &delay,
                "Int*", &ttype,
                "Ptr", QMK.timerPkBuffer.Ptr,
                "Ptr", QMK.timerSkBuffer.Ptr,
                "Double*", &ct)
            timerId := StrGet(QMK.timerIdBuffer)
            primaryKey := StrGet(QMK.timerPkBuffer)
            secondaryKey := StrGet(QMK.timerSkBuffer)
            timerFunc := ((tid, tt, pk, sk, ctime) => (*) => QMK.OnTimerFired(tid, tt, pk, sk, ctime))(
                timerId, ttype, primaryKey, secondaryKey, ct)
            QMK.activeTimerFuncs[timerId] := timerFunc
            SetTimer(timerFunc, -delay)
        }
        DllCall(QMK.Proc("QMK_ClearPendingTimers"))
    }
    static OnTimerFired(timerId, timerType, primaryKey, secondaryKey, captureTime) {
        QMK.activeTimerFuncs.Delete(timerId)
        DllCall(QMK.Proc("QMK_TimerFired"),
            "Str", timerId,
            "Int", timerType,
            "Str", primaryKey,
            "Str", secondaryKey,
            "Double", captureTime)
        QMK.ProcessPendingCallbacks()
        QMK.ProcessPendingTimers()
    }
    static GetVK(key) {
        static vkMap := Map(
            "a", 65, "b", 66, "c", 67, "d", 68, "e", 69, "f", 70, "g", 71, "h", 72, "i", 73, "j", 74,
            "k", 75, "l", 76, "m", 77, "n", 78, "o", 79, "p", 80, "q", 81, "r", 82, "s", 83, "t", 84,
            "u", 85, "v", 86, "w", 87, "x", 88, "y", 89, "z", 90,
            "1", 49, "2", 50, "3", 51, "4", 52, "5", 53, "6", 54, "7", 55, "8", 56, "9", 57, "0", 48,
            "[", 219, "]", 221, ";", 186, "'", 222, ",", 188, ".", 190, "/", 191, "\", 220, "``", 192, "-", 189, "=", 187,
            "Space", 32, "Tab", 9, "Enter", 13, "Backspace", 8, "Delete", 46, "Insert", 45,
            "Home", 36, "End", 35, "PgUp", 33, "PgDn", 34, "Up", 38, "Down", 40, "Left", 37, "Right", 39, "Esc", 27,
            "CapsLock", 20, "ScrollLock", 145, "NumLock", 144,
            "LCtrl", 162, "RCtrl", 163, "LShift", 160, "RShift", 161, "LAlt", 164, "RAlt", 165, "LWin", 91, "RWin", 92
        )
        return vkMap.Has(key) ? vkMap[key] : 0
    }
    ; =======================================================================
    ; USER API 
    ; ========================================================================
    static SetupModifier(key, modifierName) {
        DllCall(QMK.Proc("QMK_SetupModifier"), "Str", key, "Str", modifierName)
    }
    static SetupHold(key, contexts, callback) {
        if (!IsObject(contexts) || contexts.Length == 0)
            contexts := ["global"]
        hotkeyId := key . "_hold"
        if (!QMK.holdCallbacks.Has(hotkeyId)) {
            QMK.holdCallbacks[hotkeyId] := {
                hasGlobal: false,
                hasBrowser: false,
                hasContextMenu: false,
                contextSpecific: [],
                globalCallback: ""
            }
            QMK.needsState[hotkeyId] := false
        }
        holder := QMK.holdCallbacks[hotkeyId]
        for ctx in contexts {
            contextInfo := QMK.ParseContext(ctx)
            if (contextInfo.type == QMK.CONTEXT_GLOBAL) {
                holder.globalCallback := callback
                holder.hasGlobal := true
                continue
            }
            if (contextInfo.type == QMK.CONTEXT_BROWSER)
                holder.hasBrowser := true
            else if (contextInfo.type == QMK.CONTEXT_MENU)
                holder.hasContextMenu := true
            callbackId := QMK.nextCallbackId++
            holder.contextSpecific.Push({
                context: ctx,
                callback: callback,
                callbackId: callbackId,
                priority: contextInfo.priority,
                contextType: contextInfo.type
            })
            QMK.holdCallbacksById[callbackId] := callback
            QMK.needsState[hotkeyId] := true
        }
        if (holder.contextSpecific.Length > 0)
            QMK.SortContexts(holder.contextSpecific)
        firstCallbackId := holder.contextSpecific.Length > 0 ?
            holder.contextSpecific[1].callbackId : QMK.nextCallbackId++

        DllCall(QMK.Proc("QMK_SetupHold"), "Str", key, "Int", firstCallbackId)
    }
    static SetupCombo(primaryKey, secondaryKey, callback) {
        callbackId := QMK.nextCallbackId++
        QMK.comboCallbacks[callbackId] := callback
        DllCall(QMK.Proc("QMK_SetupCombo"), "Str", primaryKey, "Str", secondaryKey, "Int", callbackId)
    }
    static SetupInstantCombo(primaryKey, secondaryKey, callback) {
        callbackId := QMK.nextCallbackId++
        QMK.instantComboCallbacks[callbackId] := callback
        DllCall(QMK.Proc("QMK_SetupInstantCombo"), "Str", primaryKey, "Str", secondaryKey, "Int", callbackId)
    }
    static SetupInternalCombo(primaryKey, secondaryKey, modPrefix, targetKey) {
        DllCall(QMK.Proc("QMK_SetupInternalCombo"), "Str", primaryKey, "Str", secondaryKey, "Str", modPrefix, "Str", targetKey)
    }
    static SetupInternalInstantCombo(primaryKey, secondaryKey, modPrefix, targetKey) {
        DllCall(QMK.Proc("QMK_SetupInternalInstantCombo"), "Str", primaryKey, "Str", secondaryKey, "Str", modPrefix, "Str", targetKey)
    }
    static SetupChord(k1 := "", k2 := "", k3 := "", k4 := "", k5 := "", callback := "") {
        callbackId := QMK.nextCallbackId++
        QMK.chordCallbacks[callbackId] := callback
        DllCall(QMK.Proc("QMK_SetupChord"), "Str", k1, "Str", k2, "Str", k3, "Str", k4, "Str", k5, "Int", callbackId)
    }
    static SetupInternalChord(k1, k2, k3, k4 := "", k5 := "", mod := "", target := "") {
        DllCall(QMK.Proc("QMK_SetupInternalChord"), "Str", k1, "Str", k2, "Str", k3, "Str", k4, "Str", k5, "Str", mod, "Str", target)
    }
    static NoModifiers() {
        return DllCall(QMK.Proc("QMK_NoModifiersHeld"), "Int")
    }
    static Tap(tapAction, holdCallback := "") {
        key := StrReplace(StrReplace(StrReplace(StrReplace(A_ThisHotkey, "~", ""), " up", ""), "$", ""), "*", "")
        isHold := !KeyWait(key, "T0.2")
        KeyWait(key)

        if isHold {
            if (holdCallback != "")
                holdCallback.Call()
            else {
                hotkeyId := key . "_hold"
                callback := QMK.FindMatchingCallback(hotkeyId)
                if (callback != "")
                    callback.Call()
            }
        } else {
            if IsObject(tapAction)
                tapAction.Call()
            else {
                vk := QMK.GetVK(tapAction)
                if (vk != 0)
                    DllCall(QMK.Proc("QMK_SendKeyDirectFromDLL"), "Int", vk, "Int", 0)
                else
                    SendEvent("{" . tapAction . "}")
            }
        }
    }
    ; ========================================================================
    ; KEY REGISTRATION
    ; ========================================================================
    static allKeys := ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
        "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
        "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
        "[", "]", ";", "'", ",", ".", "/", "\", "``", "-", "=",
        "Space", "Tab", "Enter", "Backspace", "Delete", "Insert", "Home", "End", "PgUp", "PgDn",
        "Up", "Down", "Left", "Right", "Esc", "CapsLock", "ScrollLock", "NumLock",
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"
    ]
    static registeredKeys := Map()
    static activeTimerFuncs := Map()
    static RegisterAllKeys() {
        Suspend(true) 
        for key in QMK.allKeys {
            if !QMK.registeredKeys.Has(key) {
                keyDown := ((k) => (*) => QMK.OnKeyDown(k))(key)
                keyUp := ((k) => (*) => QMK.OnKeyUp(k))(key)
                try {
                    Hotkey("$*" . key, keyDown, "I2")
                    Hotkey("$*" . key . " up", keyUp, "I2")
                    QMK.registeredKeys[key] := true
                }
            }
        }
        Suspend(false) 
    }
    static EmergencyReset(tooltips := true) {
        DllCall(QMK.Proc("QMK_EmergencyReset"))
        QMK.activeTimerFuncs := Map()
        this.capslockconsumed := true
        SendEvent("{Ctrl up}{Shift up}{Alt up}{LWin up}{Capslock up}")
        if tooltips {
            ToolTip("QMK Emergency Reset!")
            SetTimer(() => ToolTip(), -2000)
        }
    }

    ; ========================================================================
    ; CONTEXT MATCHING - NO CACHE, ONLY CHECK WHEN HOLD FIRES
    ; ========================================================================

    static GetWindowState() {
        ; NO CACHE - just get current state when needed
        state := {
            hasContextMenu: WinExist("ahk_class #32768") ? true : false,
            activeWin: "",
            activeClass: "",
            activeExe: "",
            activeHwnd: 0,
            isBrowser: false,
            currentUrl: ""
        }
        if (!state.hasContextMenu) {
            try {
                state.activeHwnd := WinGetID("A")
                state.activeWin := WinGetTitle("A")
                state.activeClass := WinGetClass("A")
                state.activeExe := WinGetProcessName("A")
                ; Check if browser
                state.isBrowser := false
                for criteria in QMK.browsers {
                    if (WinActive(criteria)) {
                        state.isBrowser := true
                        ; Get URL using UIA like OnWebsite.ahk does
                        try {
                            state.currentUrl := QMK.GetBrowserURL()
                        } catch {
                            state.currentUrl := ""
                        }
                        break
                    }
                }
            } catch {
                state.activeHwnd := 0
                state.activeWin := ""
                state.activeClass := ""
                state.activeExe := ""
                state.isBrowser := false
                state.currentUrl := ""
            }
        }
        return state
    }
    static ParseContext(context) {
        lowerContext := StrLower(context)
        if (context == "#32768" || context == "ahk_class #32768")
            return { type: QMK.CONTEXT_MENU, priority: 1 }
        if (InStr(context, "."))
            return { type: QMK.CONTEXT_URL, priority: 2 }
        if (context != "" && lowerContext != "global" && lowerContext != "browser" && lowerContext != "browsers"
            && !InStr(context, "ahk_class") && !InStr(context, "ahk_exe") && !InStr(context, ".exe"))
            return { type: QMK.CONTEXT_TITLE, priority: 3 }
        if (InStr(context, "ahk_class"))
            return { type: QMK.CONTEXT_CLASS, priority: 4 }
        if (lowerContext == "browser" || lowerContext == "browsers")
            return { type: QMK.CONTEXT_BROWSER, priority: 5 }
        if (InStr(context, "ahk_exe") || InStr(context, ".exe"))
            return { type: QMK.CONTEXT_EXE, priority: 6 }
        if (context == "" || lowerContext == "global")
            return { type: QMK.CONTEXT_GLOBAL, priority: 7 }
        return { type: QMK.CONTEXT_TITLE, priority: 3 }
    }
    static SortContexts(contextArray) {
        n := contextArray.Length
        Loop n - 1 {
            i := A_Index
            Loop n - i {
                j := A_Index
                if (contextArray[j].priority > contextArray[j + 1].priority) {
                    temp := contextArray[j]
                    contextArray[j] := contextArray[j + 1]
                    contextArray[j + 1] := temp
                }
            }
        }
    }
    static FindMatchingCallback(hotkeyId) {
        if (!QMK.holdCallbacks.Has(hotkeyId))
            return ""
        holder := QMK.holdCallbacks[hotkeyId]
        ; Fast path: only global callback exists
        if (holder.hasGlobal && !QMK.needsState[hotkeyId])
            return holder.globalCallback
        ; Get fresh window state (only when hold fires AND context-specific callbacks exist)
        state := QMK.GetWindowState()
        ; Early exit: context menu check
        if (state.hasContextMenu) {
            if (holder.hasContextMenu) {
                for entry in holder.contextSpecific {
                    if (entry.contextType == QMK.CONTEXT_MENU)
                        return entry.callback
                }
            }
            return holder.hasGlobal ? holder.globalCallback : ""
        }
        for entry in holder.contextSpecific {
            if (QMK.MatchesContext(entry.context, entry.contextType, state))
                return entry.callback
        }
        return holder.hasGlobal ? holder.globalCallback : ""
    }
    static MatchesContext(context, contextType, state) {
        switch contextType {
            case QMK.CONTEXT_MENU:
                return state.hasContextMenu
            case QMK.CONTEXT_GLOBAL:
                return true
            case QMK.CONTEXT_BROWSER:
                return state.isBrowser
            case QMK.CONTEXT_TITLE:
                return state.activeWin != "" && InStr(state.activeWin, context) > 0
            case QMK.CONTEXT_CLASS:
                return state.activeClass != "" && InStr(state.activeClass, context) > 0
            case QMK.CONTEXT_EXE:
                return state.activeExe != "" && InStr(state.activeExe, context) > 0
            case QMK.CONTEXT_URL:
                return state.isBrowser && state.HasOwnProp("currentUrl") && InStr(state.currentUrl, context) > 0
        }
        return false
    }
    static GetBrowserURL() {
        ; Use OnWebsite.ahk's cached URL
        ; This leverages the On class's sophisticated caching and UIA integration
        try {
            if (IsSet(On) && On.LastResult.inBrowser) {
                return On.LastResult.url
            }
        }
        return ""
    }
    static IsBrowserActive() {
        ; Use OnWebsite.ahk's browser detection
        try {
            if (IsSet(On)) {
                return On.LastResult.inBrowser
            }
        }
        return false
    }
}
