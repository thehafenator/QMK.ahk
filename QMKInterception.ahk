#Requires AutoHotkey v2.0
#SingleInstance Force
#Include lib\QMKVariables.ahk
#Include lib\MCodeLoader.ahk
#Include lib\MemoryModule.ahk
#Include Example QMK Shortcuts.ahk

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


; #Include QMK Example Shortcuts.ahk ; Comment this out/add your own shortcuts here.

; Hotkeys to view user settings
^!F1:: DllCall(QMK.Proc("QMK_ShowProfilingReport"))
^!F2:: QMKUserConfig.ShowGui()

; Add a hotkey to reset if needed
*#!r:: QMK.EmergencyReset()


; ^!F11:: QMK.SaveTrainingData() ; Advanced, can help with manual training of your dll. For most cases, this isn't needed. 
; ^!F5:: QMK.Toggle_ProfilingIni()
; ^!F9:: DllCall(QMK.Proc("QMK_ViewSettings")) ; mostly for debugging



SendMode "Input"
SetKeyDelay(-1, 0)
SetDefaultMouseSpeed(0)
A_HotkeyInterval := 100
A_MaxHotkeysPerInterval := 200
ProcessSetPriority("AboveNormal")


class QMK {

    static iniPath := A_ScriptDir . "\QMKconfig.ini"

    ; fallback values used only if INI keys are missing/invalid
    static userconfig := {
        applyUserConfig: false,
        useInterception: true,
        profilingEnabled: true,
        singleKeyHoldThreshold: 175.0,
        maxHoldThreshold: 1000.0,
        maxThresholdSuppress: true,
        useTrainingDll: false,
        maxBufferSize: 20,
        comboQuietDuration: 200.0,
        modifierThreshold: 1000.0,
        doubleTapThreshold: 200.0,
        repeatInitialDelay: 200,
        repeatInterval: 10,
    }

    static ReadIniBool(key, fallbackValue) {
        try value := IniRead(this.iniPath, "Settings", key, fallbackValue ? "true" : "false")
        catch
            value := fallbackValue ? "true" : "false"
        normalized := StrLower(Trim(value))
        return normalized = "1" || normalized = "true" || normalized = "yes" || normalized = "on"
    }

    static ReadIniNumber(key, fallbackValue) {
        try value := IniRead(this.iniPath, "Settings", key, fallbackValue)
        catch
            value := fallbackValue
        if !IsNumber(value)
            return fallbackValue
        return Number(value)
    }

    static EnsurePersistedSettings() {
        this.userconfig.applyUserConfig      := this.ReadIniBool("applyUserConfig", this.userconfig.applyUserConfig)
        this.userconfig.useInterception      := this.ReadIniBool("useInterception", this.userconfig.useInterception)
        this.userconfig.profilingEnabled     := this.ReadIniBool("profilingEnabled", this.userconfig.profilingEnabled)
        this.userconfig.useTrainingDll       := this.ReadIniBool("useTrainingDll", this.userconfig.useTrainingDll)
        this.userconfig.maxThresholdSuppress := this.ReadIniBool("maxThresholdSuppress", this.userconfig.maxThresholdSuppress)

        this.userconfig.singleKeyHoldThreshold := this.ReadIniNumber("singleKeyHoldThreshold", this.userconfig.singleKeyHoldThreshold)
        this.userconfig.maxHoldThreshold       := this.ReadIniNumber("maxHoldThreshold", this.userconfig.maxHoldThreshold)
        this.userconfig.maxBufferSize          := Round(this.ReadIniNumber("maxBufferSize", this.userconfig.maxBufferSize))
        this.userconfig.comboQuietDuration     := this.ReadIniNumber("comboQuietDuration", this.userconfig.comboQuietDuration)
        this.userconfig.modifierThreshold      := this.ReadIniNumber("modifierThreshold", this.userconfig.modifierThreshold)
        this.userconfig.doubleTapThreshold     := this.ReadIniNumber("doubleTapThreshold", this.userconfig.doubleTapThreshold)
        this.userconfig.repeatInitialDelay     := Round(this.ReadIniNumber("repeatInitialDelay", this.userconfig.repeatInitialDelay))
        this.userconfig.repeatInterval         := Round(this.ReadIniNumber("repeatInterval", this.userconfig.repeatInterval))

        this.userconfig.singleKeyHoldThreshold := Max(50.0, Min(1000.0, this.userconfig.singleKeyHoldThreshold))
        this.userconfig.maxHoldThreshold       := Max(300.0, Min(2000.0, this.userconfig.maxHoldThreshold))
        this.userconfig.maxBufferSize          := Max(5, Min(100, this.userconfig.maxBufferSize))
        this.userconfig.comboQuietDuration     := Max(0.0, Min(2000.0, this.userconfig.comboQuietDuration))
        this.userconfig.modifierThreshold      := Max(0.0, Min(1000.0, this.userconfig.modifierThreshold))
        this.userconfig.doubleTapThreshold     := Max(100.0, Min(600.0, this.userconfig.doubleTapThreshold))
        this.userconfig.repeatInitialDelay     := Max(50, this.userconfig.repeatInitialDelay)
        this.userconfig.repeatInterval         := Max(5, this.userconfig.repeatInterval)
    }

    static SaveUserConfigToIni() {
        IniWrite(this.userconfig.applyUserConfig ? "true" : "false", this.iniPath, "Settings", "applyUserConfig")
        IniWrite(this.userconfig.useInterception ? "true" : "false", this.iniPath, "Settings", "useInterception")
        IniWrite(this.userconfig.profilingEnabled ? "true" : "false", this.iniPath, "Settings", "profilingEnabled")
        IniWrite(this.userconfig.useTrainingDll ? "true" : "false", this.iniPath, "Settings", "useTrainingDll")
        IniWrite(this.userconfig.maxThresholdSuppress ? "true" : "false", this.iniPath, "Settings", "maxThresholdSuppress")

        IniWrite(this.userconfig.singleKeyHoldThreshold, this.iniPath, "Settings", "singleKeyHoldThreshold")
        IniWrite(this.userconfig.maxHoldThreshold, this.iniPath, "Settings", "maxHoldThreshold")
        IniWrite(this.userconfig.maxBufferSize, this.iniPath, "Settings", "maxBufferSize")
        IniWrite(this.userconfig.comboQuietDuration, this.iniPath, "Settings", "comboQuietDuration")
        IniWrite(this.userconfig.modifierThreshold, this.iniPath, "Settings", "modifierThreshold")
        IniWrite(this.userconfig.doubleTapThreshold, this.iniPath, "Settings", "doubleTapThreshold")
        IniWrite(this.userconfig.repeatInitialDelay, this.iniPath, "Settings", "repeatInitialDelay")
        IniWrite(this.userconfig.repeatInterval, this.iniPath, "Settings", "repeatInterval")
    }

    static Toggle_ProfilingIni() {
        this.userconfig.profilingEnabled := !this.userconfig.profilingEnabled
        IniWrite(this.userconfig.profilingEnabled ? "true" : "false", this.iniPath, "Settings", "profilingEnabled")
        ToolTip("Profiling: " . (this.userconfig.profilingEnabled ? "Enabled!" : "Disabled!"))
        SetTimer(() => ToolTip(), -500)
    }

    static Toggle_KernelInjectionIni() {
        this.userconfig.useInterception := !this.userconfig.useInterception
        IniWrite(this.userconfig.useInterception ? "true" : "false", this.iniPath, "Settings", "useInterception")
        ToolTip("Kernel Injection: " . (this.userconfig.useInterception ? "Enabled!" : "Disabled!"))
        SetTimer(() => ToolTip(), -500)
    }


    static hModule := 0
    static hInterception := 0
    static _procCache := Map()
    static pProcessKeyEvent := 0
    static pAnyPhysicalModifier := 0
    static pPhysModDown := 0
    static pPhysModDownVK := 0
    static pPhysModUp := 0
    static pIsPhysicalKeyDown := 0
    static DoubleTap := 0

    ; Callback storage
    static holdCallbacks := Map()
    static holdCallbacksById := Map()
    static needsState := Map()
    static comboCallbacks := Map()
    static instantComboCallbacks := Map()
    static chordCallbacks := Map()
    static doubleTapCallbacks := Map()      ; hotkeyId â†’ { hasGlobal, globalCallback, contextSpecific[], ... }
    static doubleTapCallbacksById := Map()  ; callbackId â†’ callback
    static doubleTapNeedsState := Map()     ; hotkeyId â†’ bool
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
    static VK_HOME := 0x24
    static VK_END := 0x23
    static VK_UP := 0x26
    static VK_DOWN := 0x28
    static MOD_CTRL := 0x01
    static MOD_SHIFT := 0x02
    static MOD_ALT := 0x04
    static MOD_WIN := 0x08
    static _shutdownHookRegistered := false
    static _messageHandlersRegistered := false
    static _isShuttingDown := false

static __New() {
    ; TEST: disabled exit cleanup registration.
    ; if !QMK._shutdownHookRegistered {
    ;     OnExit((ExitReason, ExitCode) => QMK.Shutdown(ExitReason, ExitCode))
    ;     QMK._shutdownHookRegistered := true
    ; }
    QMK.EnsurePersistedSettings()
    try {
        dllToLoad := QMK.userconfig.useTrainingDll ? qmkcore64zigtrainingdll : qmkcore64zigprofiling
        QMK.hModule := MemoryModule.LoadLibrary(QMK._B64ToBuffer(dllToLoad))
    }
    catch as err {
        MsgBox("Failed to load QMKCore from memory.`n`nError: " . err.Message)
        ExitApp()
    }
    ;   DllCall(QMK.Proc("QMK_InstallLLHook"))
    if !QMK.hModule {
        MsgBox("MemoryModule returned null for QMKCore.")
        ExitApp()
    }
    QMK.pProcessKeyEvent := QMK.Proc("QMK_ProcessKeyEvent")
    QMK.pAnyPhysicalModifier := QMK.Proc("QMK_AnyPhysicalModifier")
    QMK.pPhysModDown := QMK.Proc("QMK_PhysModDown")
    QMK.pPhysModDownVK := QMK.Proc("QMK_PhysModDownVK")
    QMK.pPhysModUp := QMK.Proc("QMK_PhysModUp")
    QMK.pIsPhysicalKeyDown := QMK.Proc("QMK_IsPhysicalKeyDown")
    QMK.DoubleTap := QMK.Proc("QMK_SetupDoubleTap")
    if !QMK.pProcessKeyEvent || !QMK.pAnyPhysicalModifier || !QMK.pPhysModDown || !QMK.pPhysModDownVK || !QMK.pPhysModUp || !QMK.pIsPhysicalKeyDown {
        MsgBox("Failed to resolve one or more hot-path QMK exports.")
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

    ; --- REGISTER MESSAGE HANDLERS FIRST ---
    ; Must be live before QMK_SetAHKThreadId so the background thread's
    ; 0x8003/0x8004 message is never dropped. RegisterAllKeys (0x8003) only
    ; fires when the Zig background thread confirms interception is unavailable.
    OnMessage(0x8001, (*) => QMK.ProcessPendingCallbacks())
    OnMessage(0x8002, (*) => QMK.ProcessPendingTimers())
    OnMessage(0x8003, (*) => QMK.RegisterAllKeys())
    OnMessage(0x8004, (*) => QMK.UnregisterAllKeys())
    QMK._messageHandlersRegistered := true

    ; --- INJECT CALLBACKS & AUTO-START ZIG ---
    DllCall(QMK.Proc("QMK_SetInterceptionCallbacks"),
        "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_create_context"),
        "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_destroy_context"),
        "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_send"),
        "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_is_keyboard"),
        "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_set_filter"),
        "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_receive"),
        "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_wait_with_timeout"))

    ; Apply User Config — pass ms as Double, Zig converts to ticks internally.
    ; Called BEFORE SetAHKThreadId so g_userConfigApplied is set before the
    ; background thread might read it.
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

    ; Expose thread ID LAST — the instant this is set, Zig posts 0x8003/0x8004.
    ; All OnMessage handlers are already registered above.
    DllCall(QMK.Proc("QMK_SetAHKThreadId"), "UInt", DllCall("kernel32\GetCurrentThreadId", "UInt"))
}


; static __New() {
;     ; TEST: disabled exit cleanup registration.
;     ; if !QMK._shutdownHookRegistered {
;     ;     OnExit((ExitReason, ExitCode) => QMK.Shutdown(ExitReason, ExitCode))
;     ;     QMK._shutdownHookRegistered := true
;     ; }
;     QMK.EnsurePersistedSettings()
;     try {
;         dllToLoad := QMK.userconfig.useTrainingDll ? qmkcore64zigtrainingdll : qmkcore64zigprofiling
;         QMK.hModule := MemoryModule.LoadLibrary(QMK._B64ToBuffer(dllToLoad))
;     }
;     catch as err {
;         MsgBox("Failed to load QMKCore from memory.`n`nError: " . err.Message)
;         ExitApp()
;     }
;     ;   DllCall(QMK.Proc("QMK_InstallLLHook"))
;     if !QMK.hModule {
;         MsgBox("MemoryModule returned null for QMKCore.")
;         ExitApp()
;     }
;     QMK.pProcessKeyEvent := QMK.Proc("QMK_ProcessKeyEvent")
;     QMK.pAnyPhysicalModifier := QMK.Proc("QMK_AnyPhysicalModifier")
;     QMK.pPhysModDown := QMK.Proc("QMK_PhysModDown")
;     QMK.pPhysModDownVK := QMK.Proc("QMK_PhysModDownVK")
;     QMK.pPhysModUp := QMK.Proc("QMK_PhysModUp")
;     QMK.pIsPhysicalKeyDown := QMK.Proc("QMK_IsPhysicalKeyDown")
;     QMK.DoubleTap := QMK.Proc("QMK_SetupDoubleTap")
;     if !QMK.pProcessKeyEvent || !QMK.pAnyPhysicalModifier || !QMK.pPhysModDown || !QMK.pPhysModDownVK || !QMK.pPhysModUp || !QMK.pIsPhysicalKeyDown {
;         MsgBox("Failed to resolve one or more hot-path QMK exports.")
;         ExitApp()
;     }
;     try {
;         QMK.hInterception := MemoryModule.LoadLibrary(QMK._B64ToBuffer(interception64))
;     } catch as err {
;         MsgBox("Failed to load interception from memory.`n`nError: " . err.Message)
;         ExitApp()
;     }
;     if !QMK.hInterception {
;         MsgBox("MemoryModule returned null for interception.")
;         ExitApp()
;     }

;     ; --- INJECT CALLBACKS & AUTO-START ZIG ---
;     ; (This will now seamlessly initialize the memory arrays too)
;     DllCall(QMK.Proc("QMK_SetInterceptionCallbacks"),
;         "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_create_context"),
;         "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_destroy_context"),
;         "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_send"),
;         "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_is_keyboard"),
;         "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_set_filter"),
;         "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_receive"),
;         "Ptr", MemoryModule.GetProcAddress(QMK.hInterception, "interception_wait_with_timeout"))

;     ; Apply User Config (if enabled)
;     if (QMK.userconfig.applyUserConfig) {
;         DllCall(QMK.Proc("QMK_SetUserConfig"),
;             "Int",   QMK.userconfig.applyUserConfig ? 1 : 0,
;             "Int",   QMK.userconfig.useInterception ? 1 : 0,
;             "Int",   QMK.userconfig.profilingEnabled ? 1 : 0,
;             "Int64", QMK.userconfig.singleKeyHoldThreshold,
;             "Int64", QMK.userconfig.maxHoldThreshold,
;             "Int",   QMK.userconfig.maxThresholdSuppress ? 1 : 0,
;             "Int",   QMK.userconfig.maxBufferSize,
;             "Int64", QMK.userconfig.comboQuietDuration,
;             "Int64", QMK.userconfig.modifierThreshold,
;             "Int64", QMK.userconfig.doubleTapThreshold,
;             "Int",   QMK.userconfig.repeatInitialDelay,
;             "Int",   QMK.userconfig.repeatInterval)
;     }

; DllCall(QMK.Proc("QMK_SetAHKThreadId"), "UInt", DllCall("kernel32\GetCurrentThreadId", "UInt"))

;         ; Register the message handlers
;         OnMessage(0x8001, (*) => QMK.ProcessPendingCallbacks())
;         OnMessage(0x8002, (*) => QMK.ProcessPendingTimers())
;         QMK._messageHandlersRegistered := true
;         OnMessage(0x8003, (*) => QMK.RegisterAllKeys())   ; interception unavailable â†’ use AHK hotkeys
;         OnMessage(0x8004, (*) => QMK.UnregisterAllKeys())  ; interception acquired    â†’ drop AHK hotkeys
; }

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
    static Shutdown(exitReason := "", *) {
        if QMK._isShuttingDown
            return
        if (exitReason = "Reload")
            return
        QMK._isShuttingDown := true

        if QMK._messageHandlersRegistered {
            try OnMessage(0x8001, 0)
            try OnMessage(0x8002, 0)
            try OnMessage(0x8003, 0)
            try OnMessage(0x8004, 0)
            QMK._messageHandlersRegistered := false
        }

        ; TEST: disabled shutdown cleanup/disconnect calls.
        ; try QMK.UnregisterAllKeys()

        for _, timerFunc in QMK.activeTimerFuncs
            try SetTimer(timerFunc, 0)
        QMK.activeTimerFuncs := Map()

        if QMK.hModule {
            ; try QMK.EmergencyReset(false)
            ; try DllCall(QMK.Proc("QMK_DestroyInterception"))
        }
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
    static _kbStateBuf := Buffer(256, 0)

    static CheckPhysicalModifiers2() {
        DllCall("GetKeyboardState", "Ptr", QMK._kbStateBuf.Ptr)
        return (NumGet(QMK._kbStateBuf, 0x11, "UChar") & 0x80)  ; Ctrl
        || (NumGet(QMK._kbStateBuf, 0x10, "UChar") & 0x80)  ; Shift
        || (NumGet(QMK._kbStateBuf, 0x12, "UChar") & 0x80)  ; Alt
        || (NumGet(QMK._kbStateBuf, 0x5B, "UChar") & 0x80)  ; LWin
        || (NumGet(QMK._kbStateBuf, 0x5C, "UChar") & 0x80)  ; RWin
    }
    static AnyPhysicalModifier() {
        return DllCall(QMK.pAnyPhysicalModifier, "Int")
    }
    static PhysModDown(mask) {
        DllCall(QMK.pPhysModDown, "Int", mask)
    }
    static PhysModDownKey(vk) {
        DllCall(QMK.pPhysModDownVK, "Int", vk)
    }
    static PhysModUp(mask) {
        DllCall(QMK.pPhysModUp, "Int", mask)
    }
    static IsPhysicalKeyDown(keyOrVk) {
        vk := (Type(keyOrVk) = "String") ? QMK.GetVK(keyOrVk) : keyOrVk
        if (!vk)
            return false
        return DllCall(QMK.pIsPhysicalKeyDown, "Int", vk, "Int")
    }
    ; At init, tell Zig our thread ID once

    static CheckPhysicalModifiersAHK() {
        return GetKeyState("Ctrl", "P")
            || GetKeyState("Shift", "P")
            || GetKeyState("Alt", "P")
            || GetKeyState("LWin", "P")
            || GetKeyState("RWin", "P")
    }

    static OnKeyDown(vk) {
        DllCall(QMK.pProcessKeyEvent, "Int", vk, "Int", 1)
    }

    static OnKeyUp(vk) {
        DllCall(QMK.pProcessKeyEvent, "Int", vk, "Int", 0)
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
                        QMK.ScheduleCallback(callback)
                case 1, 2: ; Combo / InstantCombo
                    if (QMK.comboCallbacks.Has(callbackId)) {
                        callback := QMK.comboCallbacks[callbackId]
                        QMK.ScheduleCallback(callback)
                    } else if (QMK.instantComboCallbacks.Has(callbackId)) {
                        callback := QMK.instantComboCallbacks[callbackId]
                        QMK.ScheduleCallback(callback)
                    }
                case 5: ; Chord
                    if (QMK.chordCallbacks.Has(callbackId)) {
                        callback := QMK.chordCallbacks[callbackId]
                        QMK.ScheduleCallback(callback)
                    }
                case 6: ; Modifier double-tap
                    hotkeyId := k1 . "_doubletap"
                    callback := QMK.FindMatchingModDoubleTapCallback(hotkeyId)
                    if (callback != "")
                        QMK.ScheduleCallback(callback)
                case 99: ; Emergency reset
                    SendEvent("{Ctrl up}{Shift up}{Alt up}{LWin up}{Capslock up}")
            }
        }
        DllCall(QMK.Proc("QMK_ClearPendingCallbacks"))
    }
    static ScheduleCallback(callback) {
        SetTimer((*) => QMK.InvokeCallback(callback), -1)
    }
    static InvokeCallback(callback) {
        if (callback = "")
            return
        if (HasMethod(callback, "Call")) {
            callback.Call()
            return
        }
        if (Type(callback) = "String") {
            Func(callback).Call()
            return
        }
        callback()
    }
    static ProcessPendingTimers() {
        count := DllCall(QMK.Proc("QMK_GetPendingTimerCount"), "Int")
        if (count == 0)
            return
        Loop count {
            delay := 0
            ttype := 0
            ct := 0
            DllCall(QMK.Proc("QMK_GetPendingTimer"),
                "Int",    A_Index - 1,
                "Ptr",    QMK.timerIdBuffer.Ptr,
                "Int*",   &delay,
                "Int*",   &ttype,
                "Ptr",    QMK.timerPkBuffer.Ptr,
                "Ptr",    QMK.timerSkBuffer.Ptr,
                "Int64*", &ct)
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
            "Str",   timerId,
            "Int",   timerType,
            "Str",   primaryKey,
            "Str",   secondaryKey,
            "Int64", captureTime)
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
    static GetKey(vk) {
        static keyMap := Map(
            65, "a", 66, "b", 67, "c", 68, "d", 69, "e", 70, "f", 71, "g", 72, "h", 73, "i", 74, "j",
            75, "k", 76, "l", 77, "m", 78, "n", 79, "o", 80, "p", 81, "q", 82, "r", 83, "s", 84, "t",
            85, "u", 86, "v", 87, "w", 88, "x", 89, "y", 90, "z",
            49, "1", 50, "2", 51, "3", 52, "4", 53, "5", 54, "6", 55, "7", 56, "8", 57, "9", 48, "0",
            219, "[", 221, "]", 186, ";", 222, "'", 188, ",", 190, ".", 191, "/", 220, "\", 192, "``", 189, "-", 187, "=",
            32, "Space", 9, "Tab", 13, "Enter", 8, "Backspace", 46, "Delete", 45, "Insert",
            36, "Home", 35, "End", 33, "PgUp", 34, "PgDn", 38, "Up", 40, "Down", 37, "Left", 39, "Right", 27, "Esc",
            20, "CapsLock", 145, "ScrollLock", 144, "NumLock",
            162, "LCtrl", 163, "RCtrl", 160, "LShift", 161, "RShift", 164, "LAlt", 165, "RAlt", 91, "LWin", 92, "RWin",
            112, "F1", 113, "F2", 114, "F3", 115, "F4", 116, "F5", 117, "F6", 118, "F7", 119, "F8", 120, "F9", 121, "F10",
            122, "F11", 123, "F12"
        )
        return keyMap.Has(vk) ? keyMap[vk] : ""
    }
    ; =======================================================================
    ; USER API 
    ; ========================================================================
    static SetupModifier(key, modifierName) {
        DllCall(QMK.Proc("QMK_SetupModifier"), "Str", key, "Str", modifierName)
    }
    static FinalizeKeymap() {
        DllCall(QMK.Proc("QMK_FinalizeKeyGate"))
        ; if !QMK.WarmHotPathFromProfile()
            DllCall(QMK.Proc("QMK_WarmHotPath"))
        ; ToolTip("Finalized Gate and warmed hotpath")
    }
    ; static SaveTrainingData() {
    ;     if (!QMK.userconfig.useTrainingDll) {
    ;         ToolTip("Not using training dll. Reset via user settings and reload script")
    ;         SetTimer(() => ToolTip(), -2500)
    ;         return
    ;     }

    ;     DirCreate(profileDir)

    ;     ; Remove old broken snapshots so the final build only sees fresh files.
    ;     ; try FileDelete(profileDir . "\qmk_pgo_*.profraw") ; no, we don't want to do this. we want to have MANY captures that we can continue to build from

    ;     stamp := FormatTime(, "yyyyMMdd-HHmmss") . "-" . A_TickCount
    ;     profilePath := profileDir . "\qmk_pgo_" . stamp . ".profraw"

    ;     try result := DllCall(QMK.Proc("QMK_WriteLLVMProfileTo"), "AStr", profilePath, "Int")
    ;     catch as err {
    ;         ToolTip("PGO save failed: " . err.Message)
    ;         SetTimer(() => ToolTip(), -2500)
    ;         return
    ;     }

    ;     if (result == 0 && FileExist(profilePath)) {
    ;         ToolTip("PGO training saved: " . FileGetSize(profilePath) . " bytes`n" . profilePath)
    ;     } else {
    ;         ToolTip("PGO save returned " . result . "; no file at`n" . profilePath)
    ;     }

    ;     SetTimer(() => ToolTip(), -2500)
    ; }
    static SaveTrainingData() {
                if (!QMK.userconfig.useTrainingDll) {
                    ToolTip("Not using training dll. Reset via user settings and reload script")
                    SetTimer(() => ToolTip(), -2500)
                    return
                }
        profileDir := "C:\Users\" . A_UserName . "\OneDrive\Documents\AutoHotkey\lib\Libraries\QMKInterception\QMKTrainingData"
        DirCreate(profileDir)

        ; Remove old broken snapshots so the final build only sees fresh files.
        ; try FileDelete(profileDir . "\qmk_pgo_*.profraw") ; no, we don't want to do this. we want to have MANY captures that we can continue to build from

        stamp := FormatTime(, "yyyyMMdd-HHmmss") . "-" . A_TickCount
        profilePath := profileDir . "\qmk_pgo_" . stamp . ".profraw"

        try result := DllCall(QMK.Proc("QMK_WriteLLVMProfileTo"), "AStr", profilePath, "Int")
        catch as err {
            ToolTip("PGO save failed: " . err.Message)
            SetTimer(() => ToolTip(), -2500)
            return
        }

        if (result == 0 && FileExist(profilePath)) {
            ToolTip("PGO training saved: " . FileGetSize(profilePath) . " bytes`n" . profilePath)
        } else {
            ToolTip("PGO save returned " . result . "; no file at`n" . profilePath)
        }

        SetTimer(() => ToolTip(), -2500)
    }
    static WarmHotPathFromProfile() {
        profilePath := A_ScriptDir . "\qmk_profile.bin"
        if !FileExist(profilePath)
            return false
        try f := FileOpen(profilePath, "r")
        catch
            return false
        size := f.Length
        if (size < 16 || size > 1024) {
            f.Close()
            return false
        }
        raw := Buffer(size, 0)
        bytesRead := f.RawRead(raw, size)
        f.Close()
        if (bytesRead < 16)
            return false
        magic := NumGet(raw, 0, "UInt")
        version := NumGet(raw, 4, "UInt")
        vkCount := NumGet(raw, 8, "UInt")
        bgCount := NumGet(raw, 12, "UInt")
        if (magic != 0x514D4B50 || version != 1 || vkCount > 64 || bgCount > 32)
            return false
        needed := 16 + vkCount * 5 + bgCount * 9
        if (bytesRead < needed)
            return false

        vkBuf := Buffer(Max(1, vkCount) * 4, 0)
        pos := 16
        Loop vkCount {
            vk := NumGet(raw, pos, "UChar")
            NumPut("Int", vk, vkBuf, (A_Index - 1) * 4)
            pos += 5
        }

        bgBuf := Buffer(Max(1, bgCount) * 8, 0)
        Loop bgCount {
            vk1 := NumGet(raw, pos, "UChar")
            vk2 := NumGet(raw, pos + 1, "UChar")
            NumPut("Int", vk1, bgBuf, (A_Index - 1) * 8)
            NumPut("Int", vk2, bgBuf, (A_Index - 1) * 8 + 4)
            pos += 9
        }

        DllCall(QMK.Proc("QMK_WarmHotPathCustom"),
            "Ptr", vkBuf.Ptr, "Int", vkCount,
            "Ptr", bgBuf.Ptr, "Int", bgCount)
        return true
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
    ; -----------------------------------------------------------------------
    ; SetupDoubleTap â€” same context/priority model as SetupHold but
    ; triggered by a double-tap of a modifier key (detected entirely in Zig).
    ; Usage: QMK.SetupDoubleTap("LCtrl", ["global"], () => MyAction())
    ; The key name must be a modifier VK name: LCtrl/RCtrl/LAlt/RAlt/LShift/RShift/LWin/RWin.
    ; -----------------------------------------------------------------------
    static SetupDoubleTap(key, contexts, callback) {
        if (!IsObject(contexts) || contexts.Length == 0)
            contexts := ["global"]
        hotkeyId := key . "_doubletap"
        if (QMK.doubleTapCallbacks.Has(hotkeyId))
            holder := QMK.doubleTapCallbacks[hotkeyId]
        else {
            holder := {
                hasGlobal: false,
                hasBrowser: false,
                hasContextMenu: false,
                contextSpecific: [],
                globalCallback: ""
            }
        }
        QMK.doubleTapCallbacks[hotkeyId] := holder
        QMK.doubleTapNeedsState[hotkeyId] := QMK.doubleTapNeedsState.Has(hotkeyId) ? QMK.doubleTapNeedsState[hotkeyId] : false
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
            QMK.doubleTapCallbacksById[callbackId] := callback
            QMK.doubleTapNeedsState[hotkeyId] := true
        }
        if (holder.contextSpecific.Length > 0)
            QMK.SortContexts(holder.contextSpecific)
        firstCallbackId := holder.contextSpecific.Length > 0 ?
            holder.contextSpecific[1].callbackId : QMK.nextCallbackId++
        DllCall(QMK.DoubleTap, "Str", key, "Int", firstCallbackId)
    }
    static FindMatchingModDoubleTapCallback(hotkeyId) {
        if (!QMK.doubleTapCallbacks.Has(hotkeyId))
            return ""
        holder := QMK.doubleTapCallbacks[hotkeyId]
        ; Fast path: only global callback exists
        if (holder.hasGlobal && !QMK.doubleTapNeedsState[hotkeyId])
            return holder.globalCallback
        state := QMK.GetWindowState()
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
                QMK.InvokeCallback(holdCallback)
            else {
                hotkeyId := key . "_hold"
                callback := QMK.FindMatchingCallback(hotkeyId)
                if (callback != "")
                    QMK.InvokeCallback(callback)
            }
        } else {
            if IsObject(tapAction)
                QMK.InvokeCallback(tapAction)
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
    static registeredMods := false
    static activeTimerFuncs := Map()

    static RegisterAllKeys() {
        Suspend(true)

        ; --- Modifier tracking hotkeys (InputLevel 2, passthrough via ~) ---
        ; These feed PhysModDown/Up into Zig so it has accurate modifier state
        ; when interception is not available.
        if !QMK.registeredMods {
            static modHotkeys := [
                ["~*LCtrl",    () => QMK.PhysModDownKey(0xA2)],
                ["~*RCtrl",    () => QMK.PhysModDownKey(0xA3)],
                ["~*LAlt",     () => QMK.PhysModDownKey(0xA4)],
                ["~*RAlt",     () => QMK.PhysModDownKey(0xA5)],
                ["~*LShift",   () => QMK.PhysModDownKey(0xA0)],
                ["~*RShift",   () => QMK.PhysModDownKey(0xA1)],
                ["~*LWin",     () => QMK.PhysModDownKey(0x5B)],
                ["~*RWin",     () => QMK.PhysModDownKey(0x5C)],
                ["~*LCtrl up", () => QMK.PhysModUp(0xA2)],
                ["~*RCtrl up", () => QMK.PhysModUp(0xA3)],
                ["~*LAlt up",  () => QMK.PhysModUp(0xA4)],
                ["~*RAlt up",  () => QMK.PhysModUp(0xA5)],
                ["~*LShift up",() => QMK.PhysModUp(0xA0)],
                ["~*RShift up",() => QMK.PhysModUp(0xA1)],
                ["~*LWin up",  () => QMK.PhysModUp(0x5B)],
                ["~*RWin up",  () => QMK.PhysModUp(0x5C)],
            ]
            for entry in modHotkeys {
                try Hotkey(entry[1], entry[2], "I2")
            }
            QMK.registeredMods := true
        }

        ; --- Regular keys (InputLevel 2, suppressed via $*) ---
        for key in QMK.allKeys {
            if !QMK.registeredKeys.Has(key) {
                keyDown := ((k) => (*) => QMK.OnKeyDown(k))(key)
                keyUp   := ((k) => (*) => QMK.OnKeyUp(k))(key)
                try {
                    Hotkey("$*" . key, keyDown, "I2")
                    Hotkey("$*" . key . " up", keyUp, "I2")
                    QMK.registeredKeys[key] := true
                }
            }
        }

        Suspend(false)
    }

    static UnregisterAllKeys() {
        Suspend(true)

        ; --- Modifier tracking hotkeys ---
        if QMK.registeredMods {
            static modHotkeys := [
                "~*LCtrl",    "~*RCtrl",    "~*LAlt",     "~*RAlt",
                "~*LShift",   "~*RShift",   "~*LWin",     "~*RWin",
                "~*LCtrl up", "~*RCtrl up", "~*LAlt up",  "~*RAlt up",
                "~*LShift up","~*RShift up","~*LWin up",  "~*RWin up",
            ]
            for hk in modHotkeys
                try Hotkey(hk, "Off")
            QMK.registeredMods := false
        }

        ; --- Regular keys ---
        for key in QMK.registeredKeys {
            try {
                Hotkey("$*" . key, "Off")
                Hotkey("$*" . key . " up", "Off")
            }
        }
        QMK.registeredKeys := Map()

        Suspend(false)
    }
    static EmergencyReset(tooltips := true) {
        DllCall(QMK.Proc("QMK_EmergencyReset"))
        ; DllCall(QMK.Proc("QMK_UninstallLLHook"))
        QMK.activeTimerFuncs := Map()
        this.capslockconsumed := true
        QMK.PhysModUp(0x01)
        QMK.PhysModUp(0x02)
        QMK.PhysModUp(0x04)
        QMK.PhysModUp(0x08)
        SendEvent("{Ctrl up}{Shift up}{Alt up}{LWin up}{Capslock up}")
        if tooltips {
            ToolTip("QMK Emergency Reset!")
            SetTimer(() => ToolTip(), -2000)
        }
        ; Install LL hook if requested â€” falls back silently if it fails
        ; if (QMK.userconfig.useLLHook) {
        ;     DllCall(QMK.Proc("QMK_InstallLLHook"))
        ;     }
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

        if (InStr(context, "ahk_class"))
            return { type: QMK.CONTEXT_CLASS, priority: 4 }

        if (lowerContext == "browser" || lowerContext == "browsers")
            return { type: QMK.CONTEXT_BROWSER, priority: 5 }

        if (InStr(context, "ahk_exe") || InStr(context, ".exe"))
            return { type: QMK.CONTEXT_EXE, priority: 6 }

        if (InStr(context, "."))
            return { type: QMK.CONTEXT_URL, priority: 2 }

        if (context == "" || lowerContext == "global")
            return { type: QMK.CONTEXT_GLOBAL, priority: 7 }

        return { type: QMK.CONTEXT_TITLE, priority: 3 }
    }
    ; static ParseContext(context) {
    ;     lowerContext := StrLower(context)
    ;     if (context == "#32768" || context == "ahk_class #32768")
    ;         return { type: QMK.CONTEXT_MENU, priority: 1 }
    ;     if (context != "" && lowerContext != "global" && lowerContext != "browser" && lowerContext != "browsers"
    ;         && !InStr(context, "ahk_class") && !InStr(context, "ahk_exe") && !InStr(context, ".exe"))
    ;         return { type: QMK.CONTEXT_TITLE, priority: 3 }
    ;     if (InStr(context, "ahk_class"))
    ;         return { type: QMK.CONTEXT_CLASS, priority: 4 }
    ;     if (lowerContext == "browser" || lowerContext == "browsers")
    ;         return { type: QMK.CONTEXT_BROWSER, priority: 5 }
    ;     if (InStr(context, "ahk_exe") || InStr(context, ".exe"))
    ;         return { type: QMK.CONTEXT_EXE, priority: 6 }
    ;     if (InStr(context, "."))
    ;         return { type: QMK.CONTEXT_URL, priority: 2 }
    ;     if (context == "" || lowerContext == "global")
    ;         return { type: QMK.CONTEXT_GLOBAL, priority: 7 }
    ;     return { type: QMK.CONTEXT_TITLE, priority: 3 }
    ; }
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
                normalized := StrReplace(context, "ahk_class ")
                return state.activeClass != "" && InStr(state.activeClass, normalized) > 0
            case QMK.CONTEXT_EXE:
                normalized := StrReplace(context, "ahk_exe ")
                return state.activeExe != "" && InStr(state.activeExe, normalized) > 0
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



class QMKUserConfig {
    static window := ""
    static controls := Map()
    static statusText := ""

    static WIN_W := 640
    static TAB_H := 390
    static COL_LABEL := 220
    static COL_EDIT := 90
    static COL_UNIT := 36
    static COL_RANGE := 240
    static INNER_W := 600

    static ShowGui() {
        if (this.window) {
            this.PopulateControlsFromCurrent()
            this.SetStatus("Loaded current settings from memory.")
            this.window.Show()
            return
        }
        this.BuildGui()
        this.PopulateControlsFromCurrent()
        this.SetStatus("Settings are saved to QMKconfig.ini. Apply User Config controls whether they are pushed into QMK.")
        this.window.Show("w" . (this.WIN_W + 40) . " h580")
    }

    static BuildGui() {
        this.controls := Map()
        g := Gui("+MinSize680x580", "QMK User Settings")
        g.MarginX := 20
        g.MarginY := 18
        g.BackColor := "F6F7FB"
        g.SetFont("s10", "Segoe UI")
        g.OnEvent("Close", (*) => this.window.Hide())
        g.OnEvent("Escape", (*) => this.window.Hide())

        hdr := g.AddText("xm ym w" . this.WIN_W . " h30 c1F2937", "QMK User Settings")
        hdr.SetFont("s18 w700", "Segoe UI")
        sub := g.AddText("xm y+6 w" . this.WIN_W . " c5F6B7A"
            , "Tune runtime behavior, review clamp ranges, and persist to QMKconfig.ini.")
        sub.SetFont("s9", "Segoe UI")

        tabs := g.AddTab3("xm y+14 w" . this.WIN_W . " h" . this.TAB_H, ["General", "Timing", "Repeat"])

        tabs.UseTab("General")
        this.RenderTab(g, "General"
            , "Core behavior toggles"
            , "These switches affect whether user settings are applied and how QMK sends keys.")

        tabs.UseTab("Timing")
        this.RenderTab(g, "Timing"
            , "Timing thresholds"
            , "Values are clamped before saving; ranges below match the current script defaults.")

        tabs.UseTab("Repeat")
        this.RenderTab(g, "Repeat"
            , "Double-tap repeat"
            , "Controls the repeat loop triggered by a double-tap-and-hold action.")

        tabs.UseTab()

        btnY := 500
        this.statusText := g.AddText("xm y" . (btnY - 28) . " w" . this.WIN_W . " h18 c475467", "")
        this.statusText.SetFont("s9", "Segoe UI")

        bApply := g.AddButton("xm y" . btnY . " w100 h30 Default", "Apply")
        bSave := g.AddButton("x+8 yp w100 h30", "Save Only")
        bReload := g.AddButton("x+8 yp w120 h30", "Reload From INI")
        bDefaults := g.AddButton("x+8 yp w120 h30", "Reset Defaults")
        bClose := g.AddButton("x+8 yp w84 h30", "Close")

        bApply.OnEvent("Click", (*) => this.SaveFromGui(true))
        bSave.OnEvent("Click", (*) => this.SaveFromGui(false))
        bReload.OnEvent("Click", (*) => this.ReloadFromIni())
        bDefaults.OnEvent("Click", (*) => this.ResetDefaultsInGui())
        bClose.OnEvent("Click", (*) => this.window.Hide())

        HotIfWinActive("ahk_id " . g.Hwnd)
        Hotkey("^s", (*) => (this.SaveFromGui(true), Send("{Escape}")), "On")
        HotIfWinActive()

        this.window := g
    }

    static RenderTab(g, groupName, heading, subheading) {
        h := g.AddText("xm y+16 w" . this.INNER_W . " h22 c243447", heading)
        h.SetFont("s12 w700", "Segoe UI")
        s := g.AddText("xm y+4 w" . this.INNER_W . " c667085", subheading)
        s.SetFont("s9", "Segoe UI")

        for def in this.GetUserConfigSchema() {
            if (def.group != groupName)
                continue
            if (def.type = "bool")
                this.AddBoolRow(g, def)
            else
                this.AddNumRow(g, def)
        }
    }

    static AddBoolRow(g, def) {
        cb := g.AddCheckBox("xm y+14 w" . this.INNER_W . " h20", def.label)
        cb.SetFont("s10 w600", "Segoe UI")
        hint := g.AddText("xm y+3 w" . this.INNER_W . " c667085", def.rangeText . "  -  " . def.description)
        hint.SetFont("s9", "Segoe UI")
        this.controls[def.key] := { input: cb, def: def }
    }

    static AddNumRow(g, def) {
        lbl := g.AddText("xm y+14 w" . this.COL_LABEL . " h20 c243447", def.label)
        lbl.SetFont("s10 w600", "Segoe UI")

        edt := g.AddEdit("x+10 yp-2 w" . this.COL_EDIT . " h24")

        unitText := def.HasOwnProp("unit") ? def.unit : ""
        unt := g.AddText("x+6 yp+5 w" . this.COL_UNIT . " c667085", unitText)
        unt.SetFont("s9", "Segoe UI")

        rng := g.AddText("x+10 yp-5 w" . this.COL_RANGE . " h20 c667085", def.rangeText)
        rng.SetFont("s9", "Segoe UI")

        dsc := g.AddText("xm y+4 w" . this.INNER_W . " h16 c9AA0B4", def.description)
        dsc.SetFont("s9", "Segoe UI")

        this.controls[def.key] := { input: edt, def: def }
    }

    static PopulateControlsFromCurrent() {
        for key, bundle in this.controls {
            def := bundle.def
            value := this.GetConfigValue(key)
            if (def.type = "bool")
                bundle.input.Value := value ? 1 : 0
            else
                bundle.input.Value := this.FormatSettingValue(def, value)
        }
    }

    static ResetDefaultsInGui() {
        for key, bundle in this.controls {
            def := bundle.def
            if (def.type = "bool")
                bundle.input.Value := def.default ? 1 : 0
            else
                bundle.input.Value := this.FormatSettingValue(def, def.default)
        }
        this.SetStatus("Restored script defaults in the editor. Nothing has been saved yet.")
    }

    static ReloadFromIni() {
        QMK.EnsurePersistedSettings()
        this.PopulateControlsFromCurrent()
        this.SetStatus("Reloaded settings from QMKconfig.ini.")
    }

    static SaveFromGui(applyNow := true) {
        pending := Map()
        for key, bundle in this.controls {
            def := bundle.def
            if (def.type = "bool") {
                pending[key] := !!bundle.input.Value
                continue
            }

            raw := Trim(bundle.input.Value)
            if (raw = "") {
                MsgBox(def.label . " cannot be blank.", "QMK User Settings")
                bundle.input.Focus()
                return
            }
            if !IsNumber(raw) {
                MsgBox(def.label . " must be numeric.", "QMK User Settings")
                bundle.input.Focus()
                return
            }

            numericValue := Number(raw)
            clamped := this.ClampSettingValue(def, numericValue)
            pending[key] := clamped
            if (clamped != numericValue)
                bundle.input.Value := this.FormatSettingValue(def, clamped)
        }

        for key, value in pending
            this.SetConfigValue(key, value)

        this.PersistUserConfig()

        if (applyNow) {
            this.ApplyUserConfigNow()
            if (QMK.userconfig.applyUserConfig)
                this.SetStatus("Saved to QMKconfig.ini and applied to the running QMK core.")
            else
                this.SetStatus("Saved to QMKconfig.ini. Apply User Config is off, so runtime was not updated.")
        } else {
            this.SetStatus("Saved to QMKconfig.ini without applying to the running QMK core.")
        }
    }

    static SetStatus(message) {
        if (this.statusText)
            this.statusText.Text := message
    }

    static GetSettingDefinition(key) {
        for def in this.GetUserConfigSchema() {
            if (def.key = key)
                return def
        }
        return ""
    }

    static GetConfigValue(key) {
        return QMK.userconfig.%key%
    }

    static SetConfigValue(key, value) {
        QMK.userconfig.%key% := value
    }

    static ClampSettingValue(def, value) {
        switch def.type {
            case "bool":
                return value ? true : false
            case "int":
                value := Round(Number(value))
            default:
                value := Number(value)
        }

        if (def.HasOwnProp("min") && def.min != "")
            value := Max(def.min, value)
        if (def.HasOwnProp("max") && def.max != "")
            value := Min(def.max, value)
        return value
    }

    static FormatSettingValue(def, value) {
        if (def.type = "bool")
            return value ? "true" : "false"
        if (def.type = "int")
            return Round(value)
        decimals := def.HasOwnProp("decimals") ? def.decimals : 1
        return Format("{:." . decimals . "f}", value)
    }

    static ReadIniNumber(key, defaultValue) {
        try value := IniRead(QMK.iniPath, "Settings", key, defaultValue)
        catch
            value := defaultValue
        if !IsNumber(value)
            return defaultValue
        return Number(value)
    }

    static ReadIniBool(key, defaultValue := false) {
        try value := IniRead(QMK.iniPath, "Settings", key, defaultValue ? "true" : "false")
        catch
            return defaultValue

        value := Trim(StrLower(value))
        return (value = "1" || value = "true" || value = "yes" || value = "on")
    }

    static PersistUserConfig() {
        for def in this.GetUserConfigSchema() {
            value := this.GetConfigValue(def.key)
            if (def.type = "bool")
                value := value ? "true" : "false"
            else if (def.type = "int")
                value := Round(value)
            else
                value := this.FormatSettingValue(def, value)
            IniWrite(value, QMK.iniPath, "Settings", def.key)
        }
    }

    static ApplyUserConfigNow() {
        if !(QMK.hModule && QMK.Proc("QMK_SetUserConfig"))
            return false

        try DllCall(QMK.Proc("QMK_SetUserConfig"),
            "Int",    QMK.userconfig.applyUserConfig ? 1 : 0,
            "Int",    QMK.userconfig.useInterception ? 1 : 0,
            "Int",    QMK.userconfig.profilingEnabled ? 1 : 0,
            "Double", QMK.userconfig.singleKeyHoldThreshold,
            "Double", QMK.userconfig.maxHoldThreshold,
            "Int",    QMK.userconfig.maxThresholdSuppress ? 1 : 0,
            "Int",    QMK.userconfig.maxBufferSize,
            "Double", QMK.userconfig.comboQuietDuration,
            "Double", QMK.userconfig.modifierThreshold,
            "Double", QMK.userconfig.doubleTapThreshold,
            "Int",    QMK.userconfig.repeatInitialDelay,
            "Int",    QMK.userconfig.repeatInterval)
        catch Error as err {
            MsgBox("Settings were saved, but applying them to the running QMK core failed.`n`n" . err.Message, "QMK User Settings")
            return false
        }
        return true
    }

    static ResetUserConfigToDefaults() {
        for def in this.GetUserConfigSchema()
            this.SetConfigValue(def.key, def.default)
    }

    static GetUserConfigSchema() {
        return [
            { key: "applyUserConfig", group: "General", type: "bool", label: "Apply User Config", default: true
            , rangeText: "true / false", description: "When off, values can still be saved but are not pushed into the running QMK core." },

            { key: "useInterception", group: "General", type: "bool", label: "Use Interception", default: true
            , rangeText: "true / false", description: "True uses the interception driver path. False falls back to SendInput." },

            { key: "profilingEnabled", group: "General", type: "bool", label: "Profiling Enabled", default: true
            , rangeText: "true / false", description: "Turns core profiling on or off for runtime diagnostics." },

            { key: "maxThresholdSuppress", group: "General", type: "bool", label: "Suppress Over-Max Holds", default: true
            , rangeText: "true / false", description: "If enabled, a solo key held past Max Hold Threshold will not fire its hold action. Combos and chords using that held key can still fire." },

            { key: "useTrainingDll", group: "General", type: "bool", label: "Use Training DLL", default: false
            , rangeText: "true / false", description: "When on, loads the training DLL for PGO data collection. Requires script reload to take effect." },

            { key: "singleKeyHoldThreshold", group: "Timing", type: "float", label: "Single Key Hold Threshold", default: 175.0
            , min: 50.0, max: 1000.0, decimals: 1, unit: "ms", rangeText: "50.0 - 1000.0"
            , description: "How long a single key must be held before it counts as held." },

            { key: "maxHoldThreshold", group: "Timing", type: "float", label: "Max Hold Threshold", default: 1000.0
            , min: 300.0, max: 2000.0, decimals: 1, unit: "ms", rangeText: "300.0 - 2000.0"
            , description: "Maximum solo-hold duration before the hold action is suppressed; does not disable combos or chords while the key remains held." },

            { key: "maxBufferSize", group: "Timing", type: "int", label: "Max Buffer Size", default: 20
            , min: 5, max: 100, unit: "", rangeText: "5 - 100"
            , description: "Maximum number of buffered keys before eviction." },

            { key: "comboQuietDuration", group: "Timing", type: "float", label: "Combo Quiet Duration", default: 200.0
            , min: 0.0, max: 2000.0, decimals: 1, unit: "ms", rangeText: "0.0 - 2000.0"
            , description: "Quiet period after a combo fires to reduce mismatches." },

            { key: "modifierThreshold", group: "Timing", type: "float", label: "Modifier Threshold", default: 1000.0
            , min: 0.0, max: 1000.0, decimals: 1, unit: "ms", rangeText: "0.0 - 1000.0"
            , description: "Window for same-type modifier chaining." },

            { key: "doubleTapThreshold", group: "Repeat", type: "float", label: "Double Tap Threshold", default: 200.0
            , min: 100.0, max: 600.0, decimals: 1, unit: "ms", rangeText: "100.0 - 600.0"
            , description: "Window used to detect a double tap." },

            { key: "repeatInitialDelay", group: "Repeat", type: "int", label: "Repeat Initial Delay", default: 200
            , min: 50, max: "", unit: "ms", rangeText: "50+"
            , description: "Delay before repeat starts after a valid double-tap-and-hold." },

            { key: "repeatInterval", group: "Repeat", type: "int", label: "Repeat Interval", default: 10
            , min: 5, max: "", unit: "ms", rangeText: "5+"
            , description: "Time between repeated key sends while repeat is active." }
        ]
    }
}
