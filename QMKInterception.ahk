#Requires AutoHotkey v2.0
#SingleInstance Force
ProcessSetPriority("AboveNormal")
SendMode "Input"
; Let panic/reset hotkeys interrupt wait-heavy workflows as soon as AHK can yield.
Thread "Interrupt", 0, 0
SetKeyDelay(-1, 0)
SetDefaultMouseSpeed(0)
A_HotkeyInterval := 100
A_MaxHotkeysPerInterval := 200
ProcessSetPriority("AboveNormal")
#Include %A_LineFile%\..\lib\MemoryModule\MemoryModule.ahk
#Include %A_LineFile%\..\lib\QMKVariables.ahk

class QMKNativeLoader {
    static hModule := 0
    static hInterception := 0
    static _procCache := Map()
    static SHARED_MEM_BYTES := 6336
    static SHARED_NAME := "QMKCore_SharedBuffer"
    static CAPACITY := 256
    static MASK := 255
    static SLOT_SIZE := 24
    static OFF_HEAD := 0x00
    static OFF_TAIL := 0x40
    static OFF_SLOTS := 0xC0
    static hMap := 0
    static pIpcBuf := 0
    static pWaitOnAddress := 0
    static callbacks := []
    static comptimeCallbackCount := 0
    static _resolved := false
    static _ipcTimerFn := ""
    static _ipcDraining := false
    static pProcessKeyEvent := 0
    static pAnyPhysicalModifier := 0
    static pPhysModDown := 0
    static pPhysModDownVK := 0
    static pPhysModUp := 0
    static pIsPhysicalKeyDown := 0
    static pPasteTextWithDll := 0

    ; Native paste payloads. A hotstring whose action is a plain string carries
    ; its text inside the DLL; the record's callbackId field holds
    ; NATIVE_PAYLOAD_ID_BASE - payloadOffset instead of an AHK callback index.
    ; Must match NATIVE_PAYLOAD_ID_BASE in QMKCore.zig.
    static NATIVE_PAYLOAD_ID_BASE := -0x40000000
    static nativeHotstringCount := 0
    static ahkHotstringCount := 0
    static nativeHotstringChars := 0
    static suspendExemptCallbackPtrs := Map()
    static _insideCallbackDispatch := false

    ; Callback storage
    static nextCallbackId := 1
    static ignoredKeys := Map()
    static bulkSetupDepth := 0
    static bulkSetupDllActive := false
    static allowAhkKeyhooks := false
    static CONTEXT_MENU := 1
    static CONTEXT_URL := 2
    static CONTEXT_TITLE := 3
    static CONTEXT_CLASS := 4
    static CONTEXT_BROWSER := 5
    static CONTEXT_EXE := 6
    static CONTEXT_GLOBAL := 7
    static CONTEXT_COMPOUND := 8

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
    static HOTKEY_MOD_CTRL := 0x01
    static HOTKEY_MOD_ALT := 0x02
    static HOTKEY_MOD_SHIFT := 0x04
    static HOTKEY_MOD_WIN := 0x08
    static _shutdownHookRegistered := false
    static _messageHandlersRegistered := false
    static _isShuttingDown := false
    static _contextMenuLastState := -1

    static Init() {
        OnError(ObjBindMethod(QMK, "HandleSetupSyntaxError"))
        QMK.EnsurePersistedSettings()
        try {
            dllToLoad := QMK.GetCoreDllPayload()
            QMK.hModule := MemoryModule.LoadLibrary(QMK._B64ToBuffer(dllToLoad))
        } catch as err {
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
        QMK.pPasteTextWithDll := QMK.Proc("QMK_Paste")
        if !QMK.pProcessKeyEvent || !QMK.pAnyPhysicalModifier || !QMK.pPhysModDown || !QMK.pPhysModDownVK || !QMK.pPhysModUp || !QMK.pIsPhysicalKeyDown || !QMK.pPasteTextWithDll {
            MsgBox("Failed to resolve one or more hot-path QMK exports.")
            ExitApp()
        }
        if !QMK._shutdownHookRegistered {
            OnExit(ObjBindMethod(QMK, "Shutdown"))
            QMK._shutdownHookRegistered := true
        }
        QMK.allowAhkKeyhooks := true
        callbacks := QMK.ResolveInterceptionCallbacks()

        ; --- REGISTER SHARED IPC BEFORE ZIG STARTS ---
        QMK.InitIPC()

        if procStartupConfig := QMK.ProcOptional("QMK_SetStartupInputConfig")
            DllCall(procStartupConfig,
                "Int", QMK.CaptureBackendCode(),
                "Int", QMK.SendModeCode(),
                "Int", QMK.userconfig.profilingEnabled ? 1 : 0)
        else if procSetBackend := QMK.ProcOptional("QMK_SetInputBackend")
            DllCall(procSetBackend, "Int", QMK.CaptureBackendCode(), "Int")

        ; --- INJECT CALLBACKS & AUTO-START ZIG ---
        DllCall(QMK.Proc("QMK_SetInterceptionCallbacks"),
            "Ptr", callbacks.create,
            "Ptr", callbacks.destroy,
            "Ptr", callbacks.send,
            "Ptr", callbacks.isKeyboard,
            "Ptr", callbacks.setFilter,
            "Ptr", callbacks.receive,
            "Ptr", callbacks.waitWithTimeout)

        ; Apply User Config — pass ms as Double, Zig converts to ticks internally.
        ; Called BEFORE SetAHKThreadId so g_userConfigApplied is set before the
        ; background thread might read it.
        if (QMK.userconfig.applyUserConfig)
            QMK.ApplyUserConfigToCore(false)
        ; Expose thread ID LAST — the instant this is set, Zig posts 0x8003/0x8004.
        ; All OnMessage handlers are already registered above.
        QMK.StartIPC()
    }

    static ResolveInterceptionCallbacks() {
        callbacks := {
            create: 0,
            destroy: 0,
            send: 0,
            isKeyboard: 0,
            setFilter: 0,
            receive: 0,
            waitWithTimeout: 0
        }
        if !QMK.ShouldLoadInterceptionDll()
            return callbacks

        if !QMK.hInterception {
            try {
                QMK.hInterception := MemoryModule.LoadLibrary(QMK._B64ToBuffer(interception64))
            } catch as err {
                QMK.hInterception := 0
                QMK.DebugLog("interception load failed; using SendInput/AHK keyhook fallback: " err.Message)
                return callbacks
            }
        }

        callbacks.create := MemoryModule.GetProcAddress(QMK.hInterception, "interception_create_context")
        callbacks.destroy := MemoryModule.GetProcAddress(QMK.hInterception, "interception_destroy_context")
        callbacks.send := MemoryModule.GetProcAddress(QMK.hInterception, "interception_send")
        callbacks.isKeyboard := MemoryModule.GetProcAddress(QMK.hInterception, "interception_is_keyboard")
        callbacks.setFilter := MemoryModule.GetProcAddress(QMK.hInterception, "interception_set_filter")
        callbacks.receive := MemoryModule.GetProcAddress(QMK.hInterception, "interception_receive")
        callbacks.waitWithTimeout := MemoryModule.GetProcAddress(QMK.hInterception, "interception_wait_with_timeout")
        return callbacks
    }

    static ApplyUserConfigToCore(refreshInputLayer := false) {
        if !(QMK.hModule && QMK.ProcOptional("QMK_SetUserConfig"))
            return false

        try {
            if !QMK.userconfig.applyUserConfig {
                QMK.DebugLog("applyUserConfig is false; persisted settings only, runtime core untouched")
                return true
            }

            backendCode := QMK.CaptureBackendCode()
            sendModeCode := QMK.SendModeCode()
            if refreshInputLayer {
                ; Keep AHK fallback armed while native capture is transitioning.
                QMK.RegisterAllKeys()
                callbacks := QMK.ResolveInterceptionCallbacks()
                DllCall(QMK.Proc("QMK_SetInterceptionCallbacks"),
                    "Ptr", callbacks.create,
                    "Ptr", callbacks.destroy,
                    "Ptr", callbacks.send,
                    "Ptr", callbacks.isKeyboard,
                    "Ptr", callbacks.setFilter,
                    "Ptr", callbacks.receive,
                    "Ptr", callbacks.waitWithTimeout)

                if procApplyInputConfig := QMK.ProcOptional("QMK_ApplyInputConfig") {
                    DllCall(procApplyInputConfig,
                        "Int", backendCode,
                        "Int", sendModeCode,
                        "Int", QMK.userconfig.profilingEnabled ? 1 : 0,
                        "Int", 1,
                        "Int")
                } else {
                    if procStartupConfig := QMK.ProcOptional("QMK_SetStartupInputConfig")
                        DllCall(procStartupConfig,
                            "Int", backendCode,
                            "Int", sendModeCode,
                            "Int", QMK.userconfig.profilingEnabled ? 1 : 0)
                    if procSetBackend := QMK.ProcOptional("QMK_SetInputBackend")
                        DllCall(procSetBackend, "Int", backendCode, "Int")
                }
            }

            DllCall(QMK.Proc("QMK_SetUserConfig"),
                "Int", 1,
                "Int", sendModeCode,
                "Int", QMK.userconfig.profilingEnabled ? 1 : 0,
                "Double", QMK.userconfig.singleKeyHoldThreshold,
                "Double", QMK.userconfig.maxHoldThreshold,
                "Int", QMK.userconfig.maxThresholdSuppress ? 1 : 0,
                "Int", QMK.userconfig.maxBufferSize,
                "Double", QMK.userconfig.quietPeriodDuration,
                "Double", QMK.userconfig.modifierGestureWindow,
                "Double", QMK.userconfig.doubleTapThreshold,
                "Int", QMK.userconfig.repeatInitialDelay,
                "Int", QMK.userconfig.repeatInterval)

            if refreshInputLayer {
                if backendCode != 3 && QMK.WaitForNativeInputBackend(backendCode)
                    QMK.UnregisterAllKeys()
                else
                    QMK.RegisterAllKeys()
            }
        } catch Error as err {
            QMK.DebugLog("runtime user config apply failed: " err.Message)
            return false
        }
        return true
    }

    static WaitForNativeInputBackend(requestedBackend, timeoutMs := 500) {
        procStatus := QMK.ProcOptional("QMK_GetInputBackendStatus")
        if !procStatus
            return false

        deadline := A_TickCount + timeoutMs
        loop {
            status := DllCall(procStatus, "Int")
            if requestedBackend = 1 {
                if status = 1
                    return true
            } else if requestedBackend = 2 {
                if status = 2
                    return true
            } else if requestedBackend = 0 {
                if status = 1 || status = 2
                    return true
            } else if requestedBackend = 3 {
                if status = 3
                    return true
            }

            if A_TickCount >= deadline
                break
            Sleep(10)
        }
        return false
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
    static ProcOptional(funcName) {
        if QMK._procCache.Has(funcName)
            return QMK._procCache[funcName]
        addr := MemoryModule.GetProcAddress(QMK.hModule, funcName)
        if addr
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
        if QMK._ipcTimerFn
            try SetTimer(QMK._ipcTimerFn, 0)

        if QMK.hModule {
            ; try QMK.EmergencyReset(false)
            if procShutdown := QMK.ProcOptional("QMK_ShutdownNativeInput") {
                try DllCall(procShutdown)
            } else if procDestroy := QMK.ProcOptional("QMK_DestroyInterception") {
                try DllCall(procDestroy)
            }
        }
        if QMK.pIpcBuf {
            try DllCall("kernel32\UnmapViewOfFile", "Ptr", QMK.pIpcBuf)
            QMK.pIpcBuf := 0
        }
        if QMK.hMap {
            try DllCall("kernel32\CloseHandle", "Ptr", QMK.hMap)
            QMK.hMap := 0
        }
    }
    ; ========================================================================
    ; EVENT HANDLERS
    ; ========================================================================
    static AnyPhysicalModifier() {
        return DllCall(QMK.pAnyPhysicalModifier, "Int")
    }
    static CheckPhysicalModifiers() {
        return QMK.AnyPhysicalModifier()
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
        if (Type(keyOrVk) = "String")
            return DllCall(QMK.Proc("QMK_IsPhysicalKeyDownEntry"), "Str", String(keyOrVk), "Int")
        return DllCall(QMK.pIsPhysicalKeyDown, "Int", keyOrVk, "Int")
    }
    static OnKeyDown(vk) {
        DllCall(QMK.pProcessKeyEvent, "Int", vk, "Int", 1)
    }

    static OnKeyUp(vk) {
        DllCall(QMK.pProcessKeyEvent, "Int", vk, "Int", 0)
    }

    static InitIPC() {
        QMK.hMap := DllCall("kernel32\CreateFileMappingW",
            "Ptr", -1,
            "Ptr", 0,
            "UInt", 0x04,
            "UInt", 0,
            "UInt", QMK.SHARED_MEM_BYTES,
            "Str", QMK.SHARED_NAME,
            "Ptr")
        if !QMK.hMap
            throw Error("CreateFileMappingW failed. LastError=" DllCall("GetLastError"))

        QMK.pIpcBuf := DllCall("kernel32\MapViewOfFile", "Ptr", QMK.hMap, "UInt", 0xF001F, "UInt", 0, "UInt", 0, "UPtr", 0, "Ptr")
        if !QMK.pIpcBuf
            throw Error("MapViewOfFile failed. LastError=" DllCall("GetLastError"))

        strBufSize := DllCall(QMK.Proc("QMK_GetDynamicCallbackBufferBytes"), "UInt")
        if (strBufSize < 1024)
            strBufSize := 1024
        strBuf := Buffer(strBufSize, 0)
        count := 0
        pRing := DllCall(QMK.Proc("QMK_RegisterDynamicCallbacks"),
            "Ptr", QMK.hMap,
            "Ptr", strBuf.Ptr,
            "UInt", strBuf.Size,
            "UInt*", &count,
            "Cdecl Ptr")
        if !pRing
            throw Error("QMK_RegisterDynamicCallbacks returned null.")

        ptr := strBuf.Ptr
        Loop count {
            name := StrGet(ptr, "UTF-8")
            ptr += StrLen(name) + 1
            QMK.callbacks.Push(name)   ; resolved to Func objects by ResolveCallbacks()
            if (name = "_keep")
                QMK.DebugLog("registered _keep callback index " (A_Index - 1) " from DLL callback table")
        }
        QMK.comptimeCallbackCount := count
        QMK.nextCallbackId := count
        QMK._ipcTimerFn := ObjBindMethod(QMK, "PollIPC")
    }

    static ResolveWaitOnAddress() {
        if QMK.pWaitOnAddress
            return QMK.pWaitOnAddress
        for dllName in ["kernel32.dll", "KernelBase.dll"] {
            hMod := DllCall("kernel32\GetModuleHandleA", "AStr", dllName, "Ptr")
            if !hMod
                hMod := DllCall("kernel32\LoadLibraryA", "AStr", dllName, "Ptr")
            if hMod {
                proc := DllCall("kernel32\GetProcAddress", "Ptr", hMod, "AStr", "WaitOnAddress", "Ptr")
                if proc {
                    QMK.pWaitOnAddress := proc
                    return proc
                }
            }
        }
        throw Error("WaitOnAddress export not found in kernel32.dll or KernelBase.dll.")
    }

    static StartIPC() {
        SetTimer(QMK._ipcTimerFn, -1)
    }

    ; Call once at the end of your last #Include, after all AHK functions are defined.
    ; Upgrades every precompiled string entry in callbacks[] to a direct Func object
    ; so InvokeCallback never touches a string at dispatch time.
    static ResolveCallbacks() {
        Loop QMK.comptimeCallbackCount {
            cb := QMK.callbacks[A_Index]
            if (cb = "" || Type(cb) != "String")
                continue
            fn := 0
            try {
                fn := Func(cb)
            }
            if (Type(fn) = "Func")
                QMK.callbacks[A_Index] := fn
        }
    }

    static RegisterRuntimeCallback(callback) {
        idx := QMK.callbacks.Length
        QMK.callbacks.Push(callback)
        QMK.nextCallbackId := QMK.callbacks.Length
        return idx
    }

    static MissingCallback(name) {
        captured := name
        return (*) => ToolTip("QMKCore: no AHK function for '" captured "'")
    }

    static ReportCallbackFailure(label, detail := "") {
        message := "QMK callback dispatch failed: " label (detail != "" ? " - " detail : "")
        QMK.DebugLog(message)
        ToolTip(message)
        SetTimer(() => ToolTip(), -2500)
    }

    static DebugCallbackName(callbackIdx) {
        ptr := DllCall(QMK.Proc("QMK_GetDynamicCallbackName"), "Int", callbackIdx, "Ptr")
        return ptr ? StrGet(ptr) : ""
    }

    static DebugLog(message) {
        try FileAppend(FormatTime(, "yyyy-MM-dd HH:mm:ss") " " message "`n", A_Temp "\qmk_keep_debug.log")
    }

    static PollIPC(*) {
        ; A callback that opens a modal menu keeps pumping messages while it blocks,
        ; so this timer can fire again in the middle of a drain. The guard plus the
        ; early tail publish below stop a nested drain from replaying the slot that
        ; is still in flight, which is what showed the same menu twice.
        if (QMK._ipcDraining)
            return
        QMK._ipcDraining := true
        try {
            ptrHead := QMK.pIpcBuf + QMK.OFF_HEAD
            loop {
                head := NumGet(QMK.pIpcBuf, QMK.OFF_HEAD, "Int64")
                tail := NumGet(QMK.pIpcBuf, QMK.OFF_TAIL, "Int64")

                if (head = tail) {
                    DllCall(QMK.ResolveWaitOnAddress(),
                        "Ptr", ptrHead,
                        "Int64*", head,
                        "Ptr", 8,
                        "UInt", 15)
                    SetTimer(QMK._ipcTimerFn, -1)
                    return
                }

                while (tail < head) {
                    base := QMK.pIpcBuf + QMK.OFF_SLOTS + ((tail & QMK.MASK) * QMK.SLOT_SIZE)
                    callbackIdx := NumGet(base, 16, "Int64")
                    tail += 1
                    NumPut("Int64", tail, QMK.pIpcBuf, QMK.OFF_TAIL)
                    QMK.DispatchIPC(callbackIdx)
                }

                SetTimer(QMK._ipcTimerFn, -1)
                return
            }
        } finally {
            QMK._ipcDraining := false
        }
    }

    static DispatchIPC(callbackIdx) {
        switch callbackIdx {
            case -1:
                return
            case -2:
                QMK.ProcessPendingTimers()
            case -3:
                QMK.RegisterAllKeys()
            case -4:
                QMK.UnregisterAllKeys()
            case -99:
                QMK.EmergencyReset(false)
            default:
                ahkIdx := callbackIdx + 1
                if (ahkIdx >= 1 && ahkIdx <= QMK.callbacks.Length) {
                    callback := QMK.callbacks[ahkIdx]
                    callbackName := ""
                    try callbackName := (Type(callback) = "Func") ? callback.Name : callback
                    if (callbackName = "_keep")
                        QMK.DebugLog("dispatch callbackIdx " callbackIdx " ahkIdx " ahkIdx " -> _keep")
                    try {
                        QMK.ScheduleCallback(callback)
                    } catch as err {
                        QMK.ReportCallbackFailure("callbackIdx " callbackIdx, err.Message)
                    } finally {
                        if ackProc := QMK.ProcOptional("QMK_AcknowledgeTapHoldCallback")
                            DllCall(ackProc)
                    }
                } else {
                    QMK.ReportCallbackFailure("callbackIdx " callbackIdx, "out of range")
                }
        }
    }

    ; ========================================================================
    ; CALLBACK PROCESSING (trimmed)
    ; ========================================================================

    static ScheduleCallback(callback) {
        ; Direct call: callback fires immediately in the poll loop.
        QMK.InvokeCallback(callback)
    }
    static InvokeCallback(callback) {
        ; Fast path: precompiled entries are Func objects after ResolveCallbacks().
        ; String fallback handles any runtime-registered plain-string callbacks.
        if (Type(callback) = "String") {
            if (callback = "")
                return
            ; Lazy resolve: first time we hit a string, all includes are loaded.
            ; Upgrade the whole table once, then fall through with the name we have.
            if (!QMK._resolved) {
                QMK.ResolveCallbacks()
                QMK._resolved := true
            }
            try fn := Func(callback)
            catch {
                QMK.MissingCallback(callback).Call()
                QMK.DebugLog("missing string callback: " callback)
                return
            }
            wasInsideCallbackDispatch := QMK._insideCallbackDispatch
            QMK._insideCallbackDispatch := true
            try {
                fn.Call()
            } finally {
                QMK._insideCallbackDispatch := wasInsideCallbackDispatch
            }
            return
        }
        if (!IsObject(callback) || !HasMethod(callback, "Call")) {
            QMK.ReportCallbackFailure("non-callable callback", Type(callback))
            return
        }
        wasInsideCallbackDispatch := QMK._insideCallbackDispatch
        QMK._insideCallbackDispatch := true
        try {
            callback.Call()
        } finally {
            QMK._insideCallbackDispatch := wasInsideCallbackDispatch
        }
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
                "Int", A_Index - 1,
                "Ptr", QMK.timerIdBuffer.Ptr,
                "Int*", &delay,
                "Int*", &ttype,
                "Ptr", QMK.timerPkBuffer.Ptr,
                "Ptr", QMK.timerSkBuffer.Ptr,
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
            "Str", timerId,
            "Int", timerType,
            "Str", primaryKey,
            "Str", secondaryKey,
            "Int64", captureTime)
        SetTimer(QMK._ipcTimerFn, -1)
    }
    static GetVK(key) {
        return DllCall(QMK.Proc("QMK_GetVKFromNameEntry"), "Str", String(key), "Int")
    }
}

class QMKSettings extends QMKNativeLoader {
    static ProductionDir() {
        SplitPath(A_LineFile, , &dir)
        return dir
    }

    static iniPath := this.ProductionDir() . "\QMKconfig.ini"

    ; fallback values used only if INI keys are missing/invalid
    static userconfig := {
        applyUserConfig: false,
        useInterception: true,
        sendMode: "auto",
        inputBackend: "auto",
        profilingEnabled: true,
        singleKeyHoldThreshold: 175.0,
        maxHoldThreshold: 1000.0,
        maxThresholdSuppress: true,
        maxBufferSize: 20,
        quietPeriodDuration: 200.0,
        modifierGestureWindow: 1000.0,
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

    static ReadIniText(key, fallbackValue) {
        try value := IniRead(this.iniPath, "Settings", key, fallbackValue)
        catch
            value := fallbackValue
        return Trim(value)
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
        this.userconfig.applyUserConfig := this.ReadIniBool("applyUserConfig", this.userconfig.applyUserConfig)
        this.userconfig.useInterception := this.ReadIniBool("useInterception", this.userconfig.useInterception)
        this.userconfig.sendMode := StrLower(this.ReadIniText("sendMode", this.userconfig.useInterception ? "auto" : "sendinput"))
        if !(this.userconfig.sendMode = "auto"
            || this.userconfig.sendMode = "interception"
            || this.userconfig.sendMode = "sendinput")
            this.userconfig.sendMode := this.userconfig.useInterception ? "auto" : "sendinput"
        this.userconfig.useInterception := this.userconfig.sendMode != "sendinput"
        this.userconfig.inputBackend := StrLower(this.ReadIniText("inputBackend", this.userconfig.inputBackend))
        if !(this.userconfig.inputBackend = "auto"
            || this.userconfig.inputBackend = "interception"
            || this.userconfig.inputBackend = "llhook"
            || this.userconfig.inputBackend = "ahk_hotkeys")
            this.userconfig.inputBackend := "auto"
        this.userconfig.profilingEnabled := this.ReadIniBool("profilingEnabled", this.userconfig.profilingEnabled)
        this.userconfig.maxThresholdSuppress := this.ReadIniBool("maxThresholdSuppress", this.userconfig.maxThresholdSuppress)

        this.userconfig.singleKeyHoldThreshold := this.ReadIniNumber("singleKeyHoldThreshold", this.userconfig.singleKeyHoldThreshold)
        this.userconfig.maxHoldThreshold := this.ReadIniNumber("maxHoldThreshold", this.userconfig.maxHoldThreshold)
        this.userconfig.maxBufferSize := Round(this.ReadIniNumber("maxBufferSize", this.userconfig.maxBufferSize))
        this.userconfig.quietPeriodDuration := this.ReadIniNumber("quietPeriodDuration", this.userconfig.quietPeriodDuration)
        this.userconfig.modifierGestureWindow := this.ReadIniNumber("modifierGestureWindow", this.userconfig.modifierGestureWindow)
        this.userconfig.doubleTapThreshold := this.ReadIniNumber("doubleTapThreshold", this.userconfig.doubleTapThreshold)
        this.userconfig.repeatInitialDelay := Round(this.ReadIniNumber("repeatInitialDelay", this.userconfig.repeatInitialDelay))
        this.userconfig.repeatInterval := Round(this.ReadIniNumber("repeatInterval", this.userconfig.repeatInterval))

        this.userconfig.singleKeyHoldThreshold := Max(50.0, Min(1000.0, this.userconfig.singleKeyHoldThreshold))
        this.userconfig.maxHoldThreshold := Max(300.0, Min(2000.0, this.userconfig.maxHoldThreshold))
        this.userconfig.maxBufferSize := Max(5, Min(100, this.userconfig.maxBufferSize))
        this.userconfig.quietPeriodDuration := Max(0.0, Min(2000.0, this.userconfig.quietPeriodDuration))
        this.userconfig.modifierGestureWindow := Max(0.0, Min(1000.0, this.userconfig.modifierGestureWindow))
        this.userconfig.doubleTapThreshold := Max(100.0, Min(600.0, this.userconfig.doubleTapThreshold))
        this.userconfig.repeatInitialDelay := Max(50, this.userconfig.repeatInitialDelay)
        this.userconfig.repeatInterval := Max(5, this.userconfig.repeatInterval)
    }

    static SaveUserConfigToIni() {
        IniWrite(this.userconfig.applyUserConfig ? "true" : "false", this.iniPath, "Settings", "applyUserConfig")
        IniWrite(this.userconfig.useInterception ? "true" : "false", this.iniPath, "Settings", "useInterception")
        IniWrite(this.userconfig.sendMode, this.iniPath, "Settings", "sendMode")
        IniWrite(this.userconfig.inputBackend, this.iniPath, "Settings", "inputBackend")
        IniWrite(this.userconfig.profilingEnabled ? "true" : "false", this.iniPath, "Settings", "profilingEnabled")
        IniWrite(this.userconfig.maxThresholdSuppress ? "true" : "false", this.iniPath, "Settings", "maxThresholdSuppress")

        IniWrite(this.userconfig.singleKeyHoldThreshold, this.iniPath, "Settings", "singleKeyHoldThreshold")
        IniWrite(this.userconfig.maxHoldThreshold, this.iniPath, "Settings", "maxHoldThreshold")
        IniWrite(this.userconfig.maxBufferSize, this.iniPath, "Settings", "maxBufferSize")
        IniWrite(this.userconfig.quietPeriodDuration, this.iniPath, "Settings", "quietPeriodDuration")
        IniWrite(this.userconfig.modifierGestureWindow, this.iniPath, "Settings", "modifierGestureWindow")
        IniWrite(this.userconfig.doubleTapThreshold, this.iniPath, "Settings", "doubleTapThreshold")
        IniWrite(this.userconfig.repeatInitialDelay, this.iniPath, "Settings", "repeatInitialDelay")
        IniWrite(this.userconfig.repeatInterval, this.iniPath, "Settings", "repeatInterval")
    }

    static Toggle_ProfilingIni() {
        this.userconfig.profilingEnabled := !this.userconfig.profilingEnabled
        IniWrite(this.userconfig.profilingEnabled ? "true" : "false", this.iniPath, "Settings", "profilingEnabled")
        this.ApplyUserConfigToCore(false)
        ToolTip("Profiling: " . (this.userconfig.profilingEnabled ? "Enabled!" : "Disabled!"))
        SetTimer(() => ToolTip(), -500)
    }

    static Toggle_KernelInjectionIni() {
        this.userconfig.useInterception := !this.userconfig.useInterception
        this.userconfig.sendMode := this.userconfig.useInterception ? "interception" : "sendinput"
        IniWrite(this.userconfig.useInterception ? "true" : "false", this.iniPath, "Settings", "useInterception")
        IniWrite(this.userconfig.sendMode, this.iniPath, "Settings", "sendMode")
        this.ApplyUserConfigToCore(true)
        ToolTip("SendMode: " . this.SendModeLabel(this.userconfig.sendMode))
        SetTimer(() => ToolTip(), -500)
    }

    static CaptureBackendCode() {
        switch StrLower(this.userconfig.inputBackend) {
            case "interception":
                return 1
            case "llhook":
                return 2
            case "ahk_hotkeys":
                return 3
            default:
                return 0
        }
    }

    static SendModeCode() {
        switch StrLower(this.userconfig.sendMode) {
            case "sendinput":
                return 0
            case "interception":
                return 1
            default:
                return -1
        }
    }

    static ShouldLoadInterceptionDll() {
        backend := StrLower(this.userconfig.inputBackend)
        sendMode := StrLower(this.userconfig.sendMode)
        return sendMode != "sendinput" || backend = "auto" || backend = "interception"
    }

    static GetCoreDllPayload() {
        return QMKCore
    }
}

class QMKGui extends QMKSettings {
    static PushContextMenuState(hasContextMenu, force := false) {
        newState := hasContextMenu ? 1 : 0
        if (!force && QMK._contextMenuLastState == newState)
            return
        proc := QMK.ProcOptional("QMK_SetContextMenuState")
        if !proc
            return
        QMK._contextMenuLastState := newState
        DllCall(proc, "Int", newState)
        if !hasContextMenu
            QMK.ClearContextMenuDigitAccessMap()
    }

    static SyncContextMenuState(force := false) {
        if proc := QMK.ProcOptional("QMK_RefreshContextMenuState")
            QMK._contextMenuLastState := DllCall(proc, "Int")
    }

    ; The digit access map stays empty on purpose. Numbered menu items are now
    ; resolved by AutoHotkey hotkeys that are armed only while a menu is up
    ; (ShowMenuWithDigits in Macropad Functions.ahk), so QMKCore must let 0-9
    ; through to the OS. RefreshContextMenuDigitAccessMap and the
    ; QMK_SetContextMenuDigitAccessMap export are kept as a fallback for menus
    ; that are ever built dynamically; nothing calls the refresh automatically.
    static PreArmContextMenu() {
        QMK.PushContextMenuState(true, true)
    }

    static ClearContextMenuDigitAccessMap() {
        proc := QMK.ProcOptional("QMK_SetContextMenuDigitAccessMap")
        if !proc
            return
        buf := Buffer(10 * 4, 0)
        DllCall(proc, "Ptr", buf.Ptr, "UInt", 10)
    }

    static RefreshContextMenuDigitAccessMap() {
        proc := QMK.ProcOptional("QMK_SetContextMenuDigitAccessMap")
        if !proc
            return false
        buf := Buffer(10 * 4, 0)
        try {
            hwnd := WinExist("ahk_class #32768 ahk_exe AutoHotkey64_UIA.exe") || WinExist("ahk_class #32768 ahk_exe AutoHotkey64.exe") || WinExist("ahk_class #32768")
            if hwnd {
                menuElement := UIA.ElementFromHandle(hwnd)
                menuItems := menuElement.FindElements({ LocalizedType: "menu item" })
                for item in menuItems {
                    itemName := item.Name
                    if RegExMatch(itemName, "^([0-9])\. ", &digitMatch) {
                        accessKey := QMK.MenuAccessKeyFromItem(item)
                        if accessKey != "" {
                            vk := QMK.GetVK(accessKey)
                            if vk != 0
                                NumPut("Int", vk, buf, Integer(digitMatch[1]) * 4)
                        }
                    }
                }
            }
        }
        DllCall(proc, "Ptr", buf.Ptr, "UInt", 10)
        return true
    }

    static MenuAccessKeyFromItem(item) {
        accessKey := ""
        try accessKey := Trim(item.AccessKey)
        if accessKey != "" {
            accessKey := RegExReplace(accessKey, "i)^(Alt|Ctrl|Shift|Win)\+", "")
            if StrLen(accessKey) = 1
                return StrLower(accessKey)
        }
        itemName := ""
        try itemName := item.Name
        if RegExMatch(itemName, "&([^&\s])", &m)
            return StrLower(m[1])
        return ""
    }
}

class QMKUserConfig {
    static window := ""
    static controls := Map()
    static statusText := ""
    static inputBackendStatusText := ""
    static tabs := ""

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
        this.RefreshInputBackendGuiState(false)
        this.RefreshNativeBackendStatus()
        this.tabs.Choose(1)
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

        tabs := g.AddTab3("xm y+14 w" . this.WIN_W . " h" . this.TAB_H, ["Input", "General", "Timing", "Repeat", "Compile", "Tutorial"])
        this.tabs := tabs

        tabs.UseTab("Input")
        this.RenderInputTab(g)

        tabs.UseTab("General")
        this.RenderTab(g, "General"
            , "Core behavior toggles"
            , "These switches affect how user settings are applied to the running QMK core.")

        tabs.UseTab("Timing")
        this.RenderTab(g, "Timing"
            , "Timing thresholds"
            , "Values are clamped before saving; ranges below match the current script defaults.")

        tabs.UseTab("Repeat")
        this.RenderTab(g, "Repeat"
            , "Double-tap repeat"
            , "Controls the repeat loop triggered by a double-tap-and-hold action.")

        tabs.UseTab("Compile")
        this.RenderCompileTab(g)

        tabs.UseTab("Tutorial")
        this.RenderTutorialTab(g)

        tabs.UseTab()

        btnY := 500
        this.statusText := g.AddText("xm y" . (btnY - 28) . " w" . this.WIN_W . " h18 c475467", "")
        this.statusText.SetFont("s9", "Segoe UI")

        bApply := g.AddButton("xm y" . btnY . " w100 h30 Default", "Apply")
        bSave := g.AddButton("x+8 yp w100 h30", "Save Only")
        bReload := g.AddButton("x+8 yp w120 h30", "Reload From INI")
        bDefaults := g.AddButton("x+8 yp w120 h30", "Reset Defaults")
        bClose := g.AddButton("x+8 yp w84 h30", "Close")
        bFolder := g.AddButton("xm y+6 w220 h28", "Open QMKInterception Folder")

        bApply.OnEvent("Click", (*) => this.SaveFromGui(true))
        bSave.OnEvent("Click", (*) => this.SaveFromGui(false))
        bReload.OnEvent("Click", (*) => this.ReloadFromIni())
        bDefaults.OnEvent("Click", (*) => this.ResetDefaultsInGui())
        bClose.OnEvent("Click", (*) => this.window.Hide())
        bFolder.OnEvent("Click", (*) => Run(QMKUserConfig.ProjectRoot()))

        ; No AHK keyhooks: save through the visible Apply/Save buttons only.

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
            else if (def.type = "enum")
                this.AddEnumRow(g, def)
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

    static AddEnumRow(g, def) {
        labels := []
        for option in def.options
            labels.Push(option.label)

        lbl := g.AddText("xm y+14 w" . this.COL_LABEL . " h20 c243447", def.label)
        lbl.SetFont("s10 w600", "Segoe UI")

        ddl := g.AddDropDownList("x+10 yp-2 w330 r6", labels)

        rng := g.AddText("x+10 yp+5 w" . (this.COL_RANGE - 140) . " h20 c667085", def.rangeText)
        rng.SetFont("s9", "Segoe UI")

        dsc := g.AddText("xm y+4 w" . this.INNER_W . " h16 c9AA0B4", def.description)
        dsc.SetFont("s9", "Segoe UI")

        this.controls[def.key] := { input: ddl, def: def }
        if (def.key = "inputBackend" || def.key = "sendMode")
            ddl.OnEvent("Change", (*) => this.RefreshInputBackendGuiState(true))
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

    static RenderInputTab(g) {
        h := g.AddText("xm y+16 w" . this.INNER_W . " h22 c243447", "Capture Backend and SendMode")
        h.SetFont("s12 w700", "Segoe UI")
        s := g.AddText("xm y+4 w" . this.INNER_W . " c667085"
            , "Choose how physical keys enter QMK, then choose how QMK sends synthetic keys back to Windows.")
        s.SetFont("s9", "Segoe UI")

        statusLbl := g.AddText("xm y+14 w130 h20 c243447", "Native backend")
        statusLbl.SetFont("s10 w600", "Segoe UI")
        this.inputBackendStatusText := g.AddText("x+10 yp w310 h20 c475467", "Not checked")
        this.inputBackendStatusText.SetFont("s9", "Segoe UI")
        refreshBtn := g.AddButton("x+10 yp-4 w118 h28", "Refresh Status")
        refreshBtn.OnEvent("Click", (*) => this.RefreshNativeBackendStatus())

        for def in this.GetUserConfigSchema() {
            if (def.group != "Input")
                continue
            if (def.type = "bool")
                this.AddBoolRow(g, def)
            else if (def.type = "enum")
                this.AddEnumRow(g, def)
            else
                this.AddNumRow(g, def)
        }

        note := g.AddText("xm y+16 w" . this.INNER_W . " h86 c475467"
            , "Capture Backend controls physical key capture. SendMode controls synthetic key output. SendInput only still uses QMKCore.dll's SendInput worker; it does not call AutoHotkey Send. AutoHotkey Hotkeys disables native capture and keeps AHK hotkeys armed.")
        note.SetFont("s9", "Segoe UI")
        this.RefreshNativeBackendStatus()
    }

    static RenderCompileTab(g) {
        h := g.AddText("xm y+16 w" . this.INNER_W . " h22 c243447", "Build tools")
        h.SetFont("s12 w700", "Segoe UI")
        s := g.AddText("xm y+4 w" . this.INNER_W . " c667085"
            , "Open the PGO compiler window when you want to rebuild QMKCore.")
        s.SetFont("s9", "Segoe UI")

        pgoBtn := g.AddButton("xm y+18 w230 h32", "Open PGO Compiler")

        pgoBtn.OnEvent("Click", (*) => this.RunPgoCompilerCommand())

        info := g.AddText("xm y+18 w" . this.INNER_W . " h170 c475467"
            , "Profile-guided Optimization (PGO): uses your current setup and synthetic keystrokes so the optimized DLL better matches your shortcut layout and common key paths.`n`nPGO dependencies: Zig 0.16, LLVM clang, llvm-profdata, AutoHotkey v2, QMKCore.zig, QMKVariables.ahk, and QMKconfig.ini.")
        info.SetFont("s9", "Segoe UI")
    }

    static RenderTutorialTab(g) {
        h := g.AddText("xm y+8 w" . this.INNER_W . " h22 c243447", "Quick start")
        h.SetFont("s12 w700", "Segoe UI")

        text := g.AddText("xm y+3 w" . this.INNER_W . " h78 c475467"
            , "QMKInterception is an AutoHotkey library that lets users mimic QMK-style keyboard behavior without interfering with normal AutoHotkey functions. This is possible through low-level keyboard hooks, or by installing with the Interception driver (recommended).")
        text.SetFont("s9", "Segoe UI")

        this.AddLinkRow(g, "GitHub tutorial page", "For detailed install steps, usage notes, and examples, view the QMKInterception.ahk page on GitHub.", "https://github.com/thehafenator/QMK.ahk")
        this.AddLinkRow(g, "Interception driver", "If Interception is not detected, QMK uses normal AutoHotkey hooks, which work but may interfere if another script or keyboard program launches after it.", "https://github.com/oblitum/Interception")
        this.AddLinkRow(g, "Interception driver fix", "Separate project recommended when Windows hits the Interception 10-keyboard / 10-mouse device limit, especially with reconnecting Bluetooth devices.", "https://github.com/hygorostrowskij/interception-driver-fix")
        this.AddLinkRow(g, "Zig 0.16 download", "Recommended if you want to build the DLL for your own machine. Zig compiles QMKCore.zig into native code tuned for your CPU architecture.", "https://ziglang.org/download/")
        this.AddLinkRow(g, "LLVM / Clang", "Needed for Profile-guided Optimization (PGO). LLVM/Clang offers the highest optimization path, but requires larger build tools.", "https://releases.llvm.org/download.html")
    }

    static AddLinkRow(g, label, description, url) {
        link := g.AddText("xm y+7 w170 h20 c0563C1", label)
        link.SetFont("s9 underline", "Segoe UI")
        link.OnEvent("Click", (*) => Run(url))
        body := g.AddText("x+8 yp w" . (this.INNER_W - 190) . " h34 c475467", description)
        body.SetFont("s9", "Segoe UI")
    }

    static ProjectRoot() {
        SplitPath(QMKSettings.ProductionDir(), , &root)
        return root
    }

    static RunPgoCompilerCommand(arg := "") {
        productionDir := QMKSettings.ProductionDir()
        script := productionDir . "\QMKCompiler.ahk"
        if !FileExist(script) {
            MsgBox("PGO compiler script not found:`n" . script, "QMK Compile")
            return
        }
        suffix := arg = "" ? "" : " " . arg
        this.SetStatus("Opening QMK PGO compiler" . (arg = "" ? "." : " command: " arg))
        Run('"' . A_AhkPath . '" "' . script . '"' . suffix, productionDir)
    }

    static PopulateControlsFromCurrent() {
        for key, bundle in this.controls {
            def := bundle.def
            value := this.GetConfigValue(key)
            if (def.type = "bool")
                bundle.input.Value := value ? 1 : 0
            else if (def.type = "enum")
                bundle.input.Choose(this.EnumIndexForValue(def, value))
            else
                bundle.input.Value := this.FormatSettingValue(def, value)
        }
        this.RefreshInputBackendGuiState(false)
        this.RefreshNativeBackendStatus()
    }

    static ResetDefaultsInGui() {
        for key, bundle in this.controls {
            def := bundle.def
            if (def.type = "bool")
                bundle.input.Value := def.default ? 1 : 0
            else if (def.type = "enum")
                bundle.input.Choose(this.EnumIndexForValue(def, def.default))
            else
                bundle.input.Value := this.FormatSettingValue(def, def.default)
        }
        this.RefreshInputBackendGuiState(true)
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
            if (def.type = "enum") {
                idx := bundle.input.Value
                if (idx < 1 || idx > def.options.Length)
                    idx := this.EnumIndexForValue(def, def.default)
                pending[key] := def.options[idx].value
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

        if (pending.Has("sendMode"))
            pending["useInterception"] := pending["sendMode"] != "sendinput"

        for key, value in pending
            this.SetConfigValue(key, value)

        this.PersistUserConfig()

        if (applyNow) {
            this.ApplyUserConfigNow()
            if (QMK.userconfig.applyUserConfig)
                this.SetStatus("Saved to QMKconfig.ini and applied to the running QMK core.")
            else
                this.SetStatus("Saved to QMKconfig.ini. Apply User Config is off, so runtime was not updated.")
            this.RefreshNativeBackendStatus()
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

    static EnumIndexForValue(def, value) {
        for idx, option in def.options {
            if (option.value = value)
                return idx
        }
        return 1
    }

    static ChooseEnumValue(key, value) {
        if !this.controls.Has(key)
            return
        bundle := this.controls[key]
        if (bundle.def.type = "enum")
            bundle.input.Choose(this.EnumIndexForValue(bundle.def, value))
    }

    static PendingEnumValue(key) {
        if !this.controls.Has(key)
            return ""
        bundle := this.controls[key]
        if (bundle.def.type != "enum")
            return ""
        idx := bundle.input.Value
        if (idx < 1 || idx > bundle.def.options.Length)
            idx := this.EnumIndexForValue(bundle.def, bundle.def.default)
        return bundle.def.options[idx].value
    }

    static RefreshInputBackendGuiState(enforce := true) {
        if !(this.controls.Has("inputBackend") && this.controls.Has("sendMode"))
            return

        sendMode := this.PendingEnumValue("sendMode")
        backend := this.PendingEnumValue("inputBackend")

        if (this.controls.Has("inputBackend")) {
            tip := "Capture Backend: " . this.InputBackendLabel(backend) . ". SendMode: " . this.SendModeLabel(sendMode) . "."
            this.controls["inputBackend"].input.ToolTip := tip
        }
        if (this.controls.Has("sendMode"))
            this.controls["sendMode"].input.ToolTip := sendMode = "sendinput"
                ? "QMKCore.dll sends synthetic keys through its SendInput worker only; it does not call AutoHotkey Send."
                : "QMKCore.dll sends synthetic keys through the highest available send path; Auto prefers Interception driver sends and falls back to the DLL SendInput worker."
    }

    static RefreshNativeBackendStatus() {
        if !this.inputBackendStatusText
            return
        this.inputBackendStatusText.Text := this.NativeBackendStatusText()
    }

    static NativeBackendStatusText() {
        if !(QMK.hModule && QMK.ProcOptional("QMK_GetInputBackendStatus"))
            return "Native status unavailable"
        try status := DllCall(QMK.Proc("QMK_GetInputBackendStatus"), "Int")
        catch
            return "Native status unavailable"
        switch status {
            case 1:
                return "Capture: Interception driver active"
            case 2:
                return "Capture: Zig low-level hook active"
            case 3:
                return "Capture: AutoHotkey hotkeys active"
            default:
                return "Capture: native inactive"
        }
    }

    static InputBackendLabel(value) {
        switch StrLower(String(value)) {
            case "interception":
                return "Interception Driver Capture"
            case "llhook":
                return "Zig Low-Level Hook"
            case "ahk_hotkeys":
                return "AutoHotkey Hotkeys"
            default:
                return "Auto"
        }
    }

    static SendModeLabel(value) {
        switch StrLower(String(value)) {
            case "auto":
                return "Auto"
            case "sendinput":
                return "SendInput only"
            default:
                return "Interception driver sends"
        }
    }

    static ClampSettingValue(def, value) {
        switch def.type {
            case "bool":
                return value ? true : false
            case "enum":
                return value
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
        if (def.type = "enum")
            return value
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
        QMK.userconfig.useInterception := QMK.userconfig.sendMode != "sendinput"
        IniWrite(QMK.userconfig.useInterception ? "true" : "false", QMK.iniPath, "Settings", "useInterception")
    }

    static ApplyUserConfigNow() {
        try {
            if QMK.ApplyUserConfigToCore(true)
                return true
        } catch Error as err {
            MsgBox("Settings were saved, but applying them to the running QMK core failed.`n`n" . err.Message, "QMK User Settings")
            return false
        }
        MsgBox("Settings were saved, but applying them to the running QMK core failed.", "QMK User Settings")
        return false
    }

    static ResetUserConfigToDefaults() {
        for def in this.GetUserConfigSchema()
            this.SetConfigValue(def.key, def.default)
    }

    static GetUserConfigSchema() {
        return [{ key: "inputBackend", group: "Input", type: "enum", label: "Capture Backend", default: "auto"
            , options: [{ value: "auto", label: "Auto" }, { value: "interception", label: "Interception Driver Capture" }, { value: "llhook", label: "Zig Low-Level Hook" }, { value: "ahk_hotkeys", label: "AutoHotkey Hotkeys" }
            ]
            , rangeText: "auto / interception / llhook / ahk_hotkeys", description: "Chooses how physical keys enter QMK." }, { key: "sendMode", group: "Input", type: "enum", label: "SendMode", default: "auto"
                , options: [{ value: "auto", label: "Auto" }, { value: "interception", label: "Interception driver sends" }, { value: "sendinput", label: "SendInput only" }
                ]
                , rangeText: "auto / interception / sendinput", description: "Chooses how QMKCore.dll sends synthetic keys back to Windows; SendInput only is still routed through the DLL." }, { key: "applyUserConfig", group: "General", type: "bool", label: "Apply User Config", default: true
                    , rangeText: "true / false", description: "When off, values can still be saved but are not pushed into the running QMK core." }, { key: "profilingEnabled", group: "General", type: "bool", label: "Profiling Enabled", default: true
                    , rangeText: "true / false", description: "Turns core profiling on or off for runtime diagnostics." }, { key: "maxThresholdSuppress", group: "General", type: "bool", label: "Suppress Over-Max Holds", default: true
                        , rangeText: "true / false", description: "If enabled, a solo key held past Max Hold Threshold will not fire its hold action. Combos and chords using that held key can still fire." }, { key: "singleKeyHoldThreshold", group: "Timing", type: "float", label: "Single Key Hold Threshold", default: 175.0
                                , min: 50.0, max: 1000.0, decimals: 1, unit: "ms", rangeText: "50.0 - 1000.0"
                                , description: "How long a single key must be held before it counts as held." }, { key: "maxHoldThreshold", group: "Timing", type: "float", label: "Max Hold Threshold", default: 1000.0
                                    , min: 300.0, max: 2000.0, decimals: 1, unit: "ms", rangeText: "300.0 - 2000.0"
                                    , description: "Maximum solo-hold duration before the hold action is suppressed; does not disable combos or chords while the key remains held." }, { key: "maxBufferSize", group: "Timing", type: "int", label: "Max Buffer Size", default: 20
                                        , min: 5, max: 100, unit: "", rangeText: "5 - 100"
                                        , description: "Maximum number of buffered keys before eviction." }, { key: "quietPeriodDuration", group: "Timing", type: "float", label: "Quiet Period Duration", default: 200.0
                                            , min: 0.0, max: 2000.0, decimals: 1, unit: "ms", rangeText: "0.0 - 2000.0"
                                            , description: "How long typing stays protected from accidental combo/chord/modifier fallback after ordinary key activity." }, { key: "modifierGestureWindow", group: "Timing", type: "float", label: "Modifier Gesture Window", default: 1000.0
                                                , min: 0.0, max: 1000.0, decimals: 1, unit: "ms", rangeText: "0.0 - 1000.0"
                                                , description: "Maximum time between a held modifier-role key and a later partner key for same-mod/chord fallback grouping." }, { key: "doubleTapThreshold", group: "Repeat", type: "float", label: "Double Tap Threshold", default: 200.0
                                                    , min: 100.0, max: 600.0, decimals: 1, unit: "ms", rangeText: "100.0 - 600.0"
                                                    , description: "Window used to detect a double tap." }, { key: "repeatInitialDelay", group: "Repeat", type: "int", label: "Repeat Initial Delay", default: 200
                                                        , min: 50, max: "", unit: "ms", rangeText: "50+"
                                                        , description: "Delay before repeat starts after a valid double-tap-and-hold." }, { key: "repeatInterval", group: "Repeat", type: "int", label: "Repeat Interval", default: 10
                                                            , min: 5, max: "", unit: "ms", rangeText: "5+"
                                                            , description: "Time between repeated key sends while repeat is active." }
        ]
    }
}

class QMKTapDescriptor {
    __New(action, holdCallback := "", thresholdMs := 0, cleanupCallback := "") {
        this.action := action
        this.holdCallback := holdCallback
        this.thresholdMs := thresholdMs
        this.cleanupCallback := cleanupCallback
    }
}

class QMKSendKeyDirectDescriptor {
    __New(text) {
        this.text := text
    }
}

class QMKUserAPIs extends QMKGui {
    ; =======================================================================
    ; USER API
    ; ========================================================================
    static SetupModifier(key, modifierName, context := "global", suspendExempt := false) {
        return QMK.SetupModifiers([[key, modifierName, context, suspendExempt]])
    }
    static IsArrayLike(value) {
        return value is Array
    }
    static ContextText(contexts) {
        if !QMK.IsArrayLike(contexts)
            return String(contexts)
        if (contexts.Length == 0)
            throw Error("Context array cannot be empty")
        sep := Chr(0x1F)
        text := ""
        for context in contexts
            text .= (A_Index == 1 ? "" : sep) . String(context)
        return text
    }
    static SplitContextList(contexts := "") {
        if QMK.IsArrayLike(contexts)
            return contexts
        if IsObject(contexts)
            return [contexts]
        parsed := []
        for raw in StrSplit(String(contexts), ",") {
            ctx := Trim(raw)
            if (ctx != "")
                parsed.Push(ctx)
        }
        if (parsed.Length == 0)
            parsed.Push("global")
        return parsed
    }
    static NormalizeAhkHotkeySpec(hotkeySpec) {
        hotkeySpec := String(hotkeySpec)
        return RegExMatch(hotkeySpec, "^\{([^{}]+)\}$", &m) ? m[1] : hotkeySpec
    }
    static ZigHotkeySpecCompatible(hotkeySpec) {
        spec := Trim(QMK.NormalizeAhkHotkeySpec(hotkeySpec))
        if (spec = "")
            return false
        if InStr(spec, "&") {
            parts := StrSplit(spec, "&")
            if (parts.Length < 2)
                return false
            Loop parts.Length - 1 {
                prefix := QMK.StripAhkHotkeyPrefixes(parts[A_Index])
                if !QMK.IsPhysicalModifierName(prefix)
                    return false
            }
            return QMK.ZigHotkeySpecCompatible(parts[parts.Length])
        }
        spec := QMK.StripAhkHotkeyPrefixes(spec)
        if RegExMatch(spec, "i)\s+up$")
            spec := Trim(RegExReplace(spec, "i)\s+up$"))
        if (spec = "" || InStr(spec, "Wheel") || InStr(spec, "Button"))
            return false
        pos := 1
        while (pos <= StrLen(spec)) {
            ch := SubStr(spec, pos, 1)
            if !(ch = "^" || ch = "!" || ch = "+" || ch = "#")
                break
            pos += 1
        }
        return QMK.GetVK(SubStr(spec, pos)) != 0
    }
    static StripAhkHotkeyPrefixes(spec) {
        spec := Trim(String(spec))
        while (spec != "") {
            ch := SubStr(spec, 1, 1)
            if !(ch = "~" || ch = "$" || ch = "*")
                break
            spec := Trim(SubStr(spec, 2))
        }
        return spec
    }
    static IsPhysicalModifierName(name) {
        vk := QMK.GetVK(name)
        switch vk {
            case 0xA2, 0xA3, 0xA4, 0xA5, 0xA0, 0xA1, 0x5B, 0x5C:
                return true
        }
        return false
    }
    static NormalizeSetupRows(entries) {
        if !QMK.IsArrayLike(entries)
            return [entries]
        if (entries.Length > 0 && !IsObject(entries[1]))
            return [entries]
        return entries
    }
    static SetupRowPreview(entry) {
        try {
            if QMK.IsArrayLike(entry) {
                parts := []
                limit := Min(entry.Length, 5)
                Loop limit {
                    value := entry[A_Index]
                    parts.Push(IsObject(value) ? "<" Type(value) ">" : String(value))
                }
                text := ""
                for i, part in parts
                    text .= (i > 1 ? ", " : "") part
                return "[" text (entry.Length > limit ? ", ..." : "") "]"
            }
            if IsObject(entry)
                return "<" Type(entry) ">"
            return String(entry)
        } catch {
            return "<unprintable row>"
        }
    }
    static ThrowSetupRowError(family, rowIndex, reason, entry := "") {
        throw Error("QMK." family " row " rowIndex " failed: " reason, , QMK.SetupRowPreview(entry))
    }
    static ThrowSetupInstallError(family, loaded, expected, entry := "") {
        failedRow := loaded + 1
        throw Error("QMK." family " installed " loaded " of " expected " rows. First likely failed row: " failedRow, , QMK.SetupRowPreview(entry))
    }
    ;  works
    ; static HandleSetupSyntaxError(err, mode) {
    ;     ; Missing comma between array rows can turn:
    ;     ;
    ;     ;     ["row1"]
    ;     ;     ["row2"],
    ;     ;
    ;     ; into an attempted multi-parameter Array.__Item.Get call.

    ;     if (
    ;         !InStr(err.Message, "Too many parameters")
    ;         || !InStr(err.Extra, "Array.Prototype.__Item.Get")
    ;         || err.File = ""
    ;         || !FileExist(err.File)
    ;     )
    ;         return false

    ;     try {
    ;         lines := StrSplit(FileRead(err.File), "`n", "`r")

    ;         for i, line in lines {
    ;             current := Trim(line)

    ;             ; Must look like one of our array rows.
    ;             if !RegExMatch(current, "^\[")
    ;                 continue

    ;             ; Correctly terminated row.
    ;             if RegExMatch(current, "\],\s*(?:;.*)?$")
    ;                 continue

    ;             ; Candidate must end in ] without a comma.
    ;             if !RegExMatch(current, "\]\s*(?:;.*)?$")
    ;                 continue

    ;             ; Find the next nonblank / non-comment line.
    ;             j := i + 1

    ;             while (j <= lines.Length) {
    ;                 next := Trim(lines[j])

    ;                 if (
    ;                     next = ""
    ;                     || SubStr(next, 1, 1) = ";"
    ;                 ) {
    ;                     j++
    ;                     continue
    ;                 }

    ;                 ; Another array row follows => highly likely missing comma.
    ;                 if RegExMatch(next, "^\[") {
    ;                     MsgBox(
    ;                         "Likely missing comma after line " i ".`n`n"
    ;                         . "File:`n" err.File "`n`n"
    ;                         . "Line " i ":`n"
    ;                         . line "`n`n"
    ;                         . "Next row begins on line " j ":`n"
    ;                         . lines[j] "`n`n"
    ;                         . "Add a comma after line " i ".",
    ;                         "QMK Setup Error",
    ;                         16
    ;                     )

    ;                     return true
    ;                 }

    ;                 break
    ;             }
    ;         }
    ;     } catch {
    ;         ; Diagnostic failed, so let AutoHotkey show its normal error.
    ;     }

    ;     return false
    ; }
    static HandleSetupSyntaxError(err, mode) {
        if (
            !InStr(err.Message, "Too many parameters")
            || !InStr(err.Extra, "Array.Prototype.__Item.Get")
            || err.File = ""
            || !FileExist(err.File)
        )
            return false

        try {
            lines := StrSplit(FileRead(err.File), "`n", "`r")

            for i, line in lines {
                current := Trim(line)

                ; Must look like an array row.
                if !RegExMatch(current, "^\[")
                    continue

                ; Already has its comma.
                if RegExMatch(current, "\],\s*(?:;.*)?$")
                    continue

                ; Candidate must end in ] without a comma.
                if !RegExMatch(current, "\]\s*(?:;.*)?$")
                    continue

                ; Find next meaningful line.
                j := i + 1

                while (j <= lines.Length) {
                    next := Trim(lines[j])

                    if (
                        next = ""
                        || SubStr(next, 1, 1) = ";"
                    ) {
                        j++
                        continue
                    }

                    ; Another array row follows, so this is very likely the
                    ; missing-comma case which AHK interpreted as an array index.
                    if RegExMatch(next, "^\[") {
                        QMK.ShowSetupErrorDialog(
                            err,
                            i,
                            line,
                            j,
                            lines[j]
                        )

                        return true
                    }

                    break
                }
            }
        } catch {
            ; Let AutoHotkey display its original error if our
            ; custom diagnostic itself fails.
        }

        return false
    }

    static ShowSetupErrorDialog(err, badLine, badText, nextLine := 0, nextText := "") {
        lines := StrSplit(FileRead(err.File), "`n", "`r")

        ; AutoHotkey's normal error dialog shows roughly two source lines
        ; above and below the offending line.
        firstLine := Max(1, badLine - 2)
        lastLine := Min(lines.Length, badLine + 2)

        body :=
            "Error: Missing comma."
            . "`r`n`r`n"
            . "Specifically: Expected a comma after this array row."
            . "`r`n`r`n"
            . "`t---- " err.File
            . "`r`n"

        Loop lastLine - firstLine + 1 {
            n := firstLine + A_Index - 1

            body .= (
                n = badLine
                    ? "▶`t"
                : "`t"
            )

            body .= Format("{:03}", n)
                . ": "
                . lines[n]
                . "`r`n"
        }

        body .= "`r`n"
            . "Add a comma after line " badLine "."
            . "`r`n`r`n"
            . "Original error: "
            . err.Message
            . "`r`n"
            . "Specifically: "
            . err.Extra

        ; Match the normal AutoHotkey error-dialog feel:
        ; compact, fixed-size shell with selectable/copyable text.
        g := Gui(
            "+OwnDialogs -MaximizeBox -MinimizeBox",
            A_ScriptName
        )

        g.MarginX := 0
        g.MarginY := 0
        g.SetFont("s9", "Segoe UI")

        ; AutoHotkey uses a read-only RichEdit-style control.
        ; This keeps the message selectable and copyable.
        errorEdit := g.AddEdit(
            "x0 y0 w570 h185"
            . " ReadOnly -Wrap +HScroll +VScroll",
            body
        )

        g.SetFont("s8", "Segoe UI")

        ; Button layout modeled after AutoHotkey's own error box:
        ;
        ; Help | Edit | Reload | ExitApp              | Abort
        helpBtn := g.AddButton(
            "x10 y+7 w75 h24",
            "&Help"
        )

        editBtn := g.AddButton(
            "x+6 yp w75 h24",
            "&Edit"
        )

        reloadBtn := g.AddButton(
            "x+6 yp w75 h24",
            "&Reload"
        )

        exitBtn := g.AddButton(
            "x+6 yp w75 h24",
            "E&xitApp"
        )

        abortBtn := g.AddButton(
            "x+45 yp w75 h24 Default",
            "&Abort"
        )

        helpBtn.OnEvent(
            "Click",
            (*) => Run(
                "https://www.autohotkey.com/docs/v2/"
            )
        )

        editBtn.OnEvent(
            "Click",
            (*) => QMK.EditErrorSource(
                err.File,
                badLine
            )
        )

        reloadBtn.OnEvent(
            "Click",
            (*) => Reload()
        )

        exitBtn.OnEvent(
            "Click",
            (*) => ExitApp()
        )

        abortBtn.OnEvent(
            "Click",
            (*) => g.Destroy()
        )

        g.OnEvent(
            "Close",
            (*) => g.Destroy()
        )

        g.OnEvent(
            "Escape",
            (*) => g.Destroy()
        )

        ; Keep it close to the dimensions and proportions of the
        ; normal AutoHotkey v2 error dialog rather than making a
        ; large generic GUI.
        g.Show("w570 h225")

        ; Keep the OnError handler alive until the user closes the dialog.
        WinWaitClose("ahk_id " g.Hwnd)
    }

    static EditErrorSource(file, line := 1, column := 1) {
        target := file ":" line ":" column

        ; Try VS Code from PATH first.
        try {
            Run(
                'code --reuse-window --goto "' target '"',
                ,
                "Hide"
            )
            return true
        }

        ; Standard per-user VS Code install.
        localAppData := EnvGet("LOCALAPPDATA")
        if (localAppData != "") {
            codeExe := localAppData "\Programs\Microsoft VS Code\Code.exe"

            if FileExist(codeExe) {
                try {
                    Run(
                        '"' codeExe '" --reuse-window --goto "' target '"'
                    )
                    return true
                }
            }
        }

        ; Standard machine-wide VS Code install.
        programFiles := EnvGet("ProgramFiles")
        if (programFiles != "") {
            codeExe := programFiles "\Microsoft VS Code\Code.exe"

            if FileExist(codeExe) {
                try {
                    Run(
                        '"' codeExe '" --reuse-window --goto "' target '"'
                    )
                    return true
                }
            }
        }

        ; Generic fallback.
        try {
            Run('edit "' file '"')
            return true
        }

        ; Last resort.
        try {
            Run('notepad.exe "' file '"')
            return true
        }

        return false
    }
    static SendKeyDirect(key, modPrefix := "") {
        if (A_ThisHotkey = "" && !QMK._insideCallbackDispatch)
            return QMKSendKeyDirectDescriptor(QMK.SendKeyDirectSpecText(key, modPrefix))
        if (modPrefix = "" && InStr(String(key), "{"))
            return QMK.SendDirect(key)
        return DllCall(QMK.Proc("QMK_SendKeyDirectText"), "Str", String(key), "Str", String(modPrefix), "Int")
    }
    static SendKeyDirectSpecText(key, modPrefix := "") {
        keyText := String(key)
        if (modPrefix != "" && !InStr(keyText, "{") && StrLen(keyText) > 1)
            keyText := "{" keyText "}"
        return String(modPrefix) keyText
    }
    static SendDirect(sendSpec) {
        if !DllCall(QMK.Proc("QMK_SendDirectEntry"), "Str", String(sendSpec), "Int")
            throw Error("QMK.SendDirect supports one known Send-style key", , sendSpec)
        return true
    }
    static WriteAsciiBytes(buf, offset, text) {
        text := String(text)
        Loop StrLen(text) {
            ch := Ord(SubStr(text, A_Index, 1))
            NumPut("UChar", ch <= 0x7F ? ch : 63, buf, offset + A_Index - 1)
        }
        return StrLen(text)
    }
    static ModifierCellsFromRow(entry) {
        cells := []
        if IsObject(entry) && (entry.HasOwnProp("key") || entry.HasOwnProp("modifierName") || entry.HasOwnProp("modifier")) {
            if !entry.HasOwnProp("key")
                return false
            cells.Push(QMK.HotkeyCell(entry.key))
            cells.Push(QMK.HotkeyCell(entry.HasOwnProp("modifierName") ? entry.modifierName : entry.modifier))
            cells.Push(QMK.HotkeyCell(entry.HasOwnProp("context") ? entry.context : entry.HasOwnProp("contexts") ? entry.contexts : "global"))
            if entry.HasOwnProp("suspendExempt")
                cells.Push(QMK.HotkeyCell(entry.suspendExempt))
        } else {
            if !QMK.IsArrayLike(entry)
                return false
            for value in entry
                cells.Push(QMK.HotkeyCell(value))
        }
        return cells.Length >= 2 ? cells : false
    }
    static SetupModifiers(entries) {
        QMK.BeginSetup()
        try {
            entries := QMK.NormalizeSetupRows(entries)
            proc := QMK.ProcOptional("QMK_SetupModifierCellEntries")
            if !proc
                return QMK.SetupModifiersCompat(entries)
            rows := []
            totalTextChars := 0
            for rowIndex, entry in entries {
                cells := QMK.ModifierCellsFromRow(entry)
                if !cells
                    QMK.ThrowSetupRowError("SetupModifiers", rowIndex, "invalid modifier row", entry)
                if (cells.Length > 4)
                    QMK.ThrowSetupRowError("SetupModifiers", rowIndex, "too many cells", entry)
                for cell in cells {
                    if (cell.tag = 1 || cell.tag = 4)
                        totalTextChars += StrLen(cell.text) + 1
                }
                rows.Push(cells)
            }
            recordSize := 68
            buf := Buffer(rows.Length * recordSize, 0)
            textBuf := Buffer(Max(2, (totalTextChars + 1) * 2), 0)
            textOffset := 0
            for i, cells in rows {
                off := (i - 1) * recordSize
                NumPut("UChar", cells.Length, buf, off)
                for c, cell in cells {
                    cellOff := off + 4 + (c - 1) * 16
                    textLen := (cell.tag = 1 || cell.tag = 4) ? StrLen(cell.text) : 0
                    NumPut("UChar", cell.tag, buf, cellOff)
                    NumPut("UChar", QMK.HotkeyCellFlags(cell), buf, cellOff + 1)
                    NumPut("UInt", textOffset, buf, cellOff + 4)
                    NumPut("UShort", textLen, buf, cellOff + 8)
                    NumPut("Int", cell.callbackId, buf, cellOff + 12)
                    if textLen > 0
                        StrPut(cell.text, textBuf.Ptr + textOffset * 2, textLen + 1, "UTF-16")
                    if (cell.tag = 1 || cell.tag = 4)
                        textOffset += textLen + 1
                }
            }
            loaded := DllCall(proc, "Ptr", buf.Ptr, "UInt", rows.Length, "Ptr", textBuf.Ptr, "UInt", textOffset, "Int")
            if (loaded != rows.Length)
                QMK.ThrowSetupInstallError("SetupModifiers", loaded, rows.Length, entries[loaded + 1])
            return true
        } finally {
            QMK.EndSetup()
        }
    }
    static SetupModifiersCompat(entries) {
        proc := QMK.Proc("QMK_SetupModifierEntries")
        rows := []
        totalTextChars := 0
        for rowIndex, entry in entries {
            if QMK.IsArrayLike(entry) {
                if (entry.Length < 2)
                    QMK.ThrowSetupRowError("SetupModifiers", rowIndex, "expected key and modifier", entry)
                key := String(entry[1])
                modifierName := String(entry[2])
                contextText := entry.Length >= 3 ? QMK.ContextText(entry[3]) : "global"
                suspendExempt := entry.Length >= 4 ? !!entry[4] : false
            } else if IsObject(entry) && (entry.HasOwnProp("key") || entry.HasOwnProp("modifierName") || entry.HasOwnProp("modifier")) {
                if !entry.HasOwnProp("key")
                    return false
                key := String(entry.key)
                modifierName := String(entry.HasOwnProp("modifierName") ? entry.modifierName : entry.modifier)
                contextText := QMK.ContextText(entry.HasOwnProp("context") ? entry.context : entry.HasOwnProp("contexts") ? entry.contexts : "global")
                suspendExempt := entry.HasOwnProp("suspendExempt") ? !!entry.suspendExempt : false
            } else
                return false
            rows.Push({ key: key, modifierName: modifierName, context: contextText, suspendExempt: suspendExempt })
            totalTextChars += StrLen(key) + StrLen(modifierName) + StrLen(contextText)
        }
        recordSize := 32
        buf := Buffer(rows.Length * recordSize, 0)
        textBuf := Buffer(Max(2, (totalTextChars + 1) * 2), 0)
        textOffset := 0
        for i, row in rows {
            off := (i - 1) * recordSize
            keyLen := StrLen(row.key)
            modLen := StrLen(row.modifierName)
            contextLen := StrLen(row.context)
            NumPut("UInt", textOffset, buf, off)
            NumPut("UShort", keyLen, buf, off + 4)
            if keyLen > 0
                StrPut(row.key, textBuf.Ptr + textOffset * 2, keyLen + 1, "UTF-16")
            textOffset += keyLen
            NumPut("UInt", textOffset, buf, off + 8)
            NumPut("UShort", modLen, buf, off + 12)
            NumPut("UChar", row.suspendExempt ? 1 : 0, buf, off + 14)
            if modLen > 0
                StrPut(row.modifierName, textBuf.Ptr + textOffset * 2, modLen + 1, "UTF-16")
            textOffset += modLen
            NumPut("UInt", textOffset, buf, off + 16)
            NumPut("UShort", contextLen, buf, off + 20)
            if contextLen > 0
                StrPut(row.context, textBuf.Ptr + textOffset * 2, contextLen + 1, "UTF-16")
            textOffset += contextLen
        }
        return DllCall(proc, "Ptr", buf.Ptr, "UInt", rows.Length, "Ptr", textBuf.Ptr, "UInt", textOffset, "Int") == rows.Length
    }
    static BeginSetup() {
        QMK.bulkSetupDepth += 1
        if (QMK.bulkSetupDepth != 1)
            return
        proc := QMK.ProcOptional("QMK_BeginBulkSetup")
        if proc {
            DllCall(proc)
            QMK.bulkSetupDllActive := true
        }
    }
    static EndSetup(finalize := true) {
        if (QMK.bulkSetupDepth <= 0)
            return
        QMK.bulkSetupDepth -= 1
        if (QMK.bulkSetupDepth != 0)
            return
        if QMK.bulkSetupDllActive {
            if proc := QMK.ProcOptional("QMK_EndBulkSetup")
                DllCall(proc)
            QMK.bulkSetupDllActive := false
        }
        if finalize
            QMK.FinalizeKeymap()
    }
    static FinalizeKeymap() {
        DllCall(QMK.Proc("QMK_FinalizeKeyGate"))
        DllCall(QMK.Proc("QMK_WarmHotPath"))
    }
    static SaveTrainingData() {
        profileDir := QMKSettings.ProductionDir() . "\lib\TrainingData"
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
    static SetupContextActionRows(entries, actionKind) {
        QMK.BeginSetup()
        try {
            entries := QMK.NormalizeSetupRows(entries)
            proc := QMK.ProcOptional("QMK_SetupContextActionCellEntries")
            if !proc
                return QMK.SetupContextActionRowsCompat(entries, actionKind)
            rows := []
            totalTextChars := 0
            for rowIndex, entry in entries {
                cells := QMK.ContextActionCellsFromRow(entry)
                if !cells
                    QMK.ThrowSetupRowError("SetupContextActionRows", rowIndex, "invalid context-action row", entry)
                if (cells.Length > 4)
                    QMK.ThrowSetupRowError("SetupContextActionRows", rowIndex, "too many cells", entry)
                for cell in cells {
                    if (cell.tag = 1 || cell.tag = 4)
                        totalTextChars += StrLen(cell.text) + 1
                }
                rows.Push(cells)
            }
            recordSize := 68
            buf := Buffer(rows.Length * recordSize, 0)
            textBuf := Buffer(Max(2, (totalTextChars + 1) * 2), 0)
            textOffset := 0
            for i, cells in rows {
                off := (i - 1) * recordSize
                NumPut("UChar", cells.Length, buf, off)
                for c, cell in cells {
                    cellOff := off + 4 + (c - 1) * 16
                    textLen := (cell.tag = 1 || cell.tag = 4) ? StrLen(cell.text) : 0
                    NumPut("UChar", cell.tag, buf, cellOff)
                    NumPut("UChar", QMK.HotkeyCellFlags(cell), buf, cellOff + 1)
                    NumPut("UInt", textOffset, buf, cellOff + 4)
                    NumPut("UShort", textLen, buf, cellOff + 8)
                    NumPut("Int", cell.callbackId, buf, cellOff + 12)
                    if textLen > 0
                        StrPut(cell.text, textBuf.Ptr + textOffset * 2, textLen + 1, "UTF-16")
                    if (cell.tag = 1 || cell.tag = 4)
                        textOffset += textLen + 1
                }
            }
            loaded := DllCall(proc, "Ptr", buf.Ptr, "UInt", rows.Length, "UInt", actionKind, "Ptr", textBuf.Ptr, "UInt", textOffset, "Int")
            if (loaded != rows.Length)
                QMK.ThrowSetupInstallError("SetupContextActionRows", loaded, rows.Length, entries[loaded + 1])
            return true
        } finally {
            QMK.EndSetup()
        }
    }
    static ContextActionCellsFromRow(entry) {
        cells := []
        if IsObject(entry) && entry.HasOwnProp("key") {
            if entry.HasOwnProp("callback")
                action := entry.callback
            else if entry.HasOwnProp("action")
                action := entry.action
            else
                return false
            if !QMK.IsCallable(action)
                return false
            cells.Push(QMK.HotkeyCell(entry.key))
            cells.Push(QMK.HotkeyCell(entry.HasOwnProp("context") ? entry.context : entry.HasOwnProp("contexts") ? entry.contexts : "global"))
            cells.Push(QMK.HotkeyCell(action))
            if entry.HasOwnProp("suspendExempt")
                cells.Push(QMK.HotkeyCell(entry.suspendExempt))
        } else {
            if !QMK.IsArrayLike(entry) || entry.Length < 2
                return false
            if (entry.Length == 2) {
                if !QMK.IsCallable(entry[2])
                    return false
            } else if (entry.Length == 3 && QMK.IsCallable(entry[2])) {
                if IsObject(entry[3])
                    return false
            } else {
                if !QMK.IsCallable(entry[3])
                    return false
                if ((IsObject(entry[2]) && !QMK.IsArrayLike(entry[2]))
                    || (entry.Length >= 4 && IsObject(entry[4])))
                    return false
            }
            for value in entry
                cells.Push(QMK.HotkeyCell(value))
        }
        return cells.Length >= 2 ? cells : false
    }
    static SetupContextActionRowsCompat(entries, actionKind) {
        proc := QMK.Proc("QMK_SetupContextActionEntries")
        rows := []
        totalTextChars := 0
        for rowIndex, entry in entries {
            if IsObject(entry) && entry.HasOwnProp("key") {
                key := String(entry.key)
                contexts := entry.HasOwnProp("context") ? entry.context : entry.HasOwnProp("contexts") ? entry.contexts : "global"
                if entry.HasOwnProp("callback")
                    callback := entry.callback
                else if entry.HasOwnProp("action")
                    callback := entry.action
                else
                    QMK.ThrowSetupRowError("SetupContextActionRows", rowIndex, "missing callback/action", entry)
                suspendExempt := entry.HasOwnProp("suspendExempt") ? !!entry.suspendExempt : false
            } else if QMK.IsArrayLike(entry) {
                if (entry.Length < 2)
                    return false
                key := String(entry[1])
                if (entry.Length == 2) {
                    contexts := "global"
                    callback := entry[2]
                    suspendExempt := false
                } else if (entry.Length == 3 && QMK.IsCallable(entry[2])) {
                    contexts := "global"
                    callback := entry[2]
                    suspendExempt := !!entry[3]
                } else {
                    contexts := entry[2]
                    callback := entry[3]
                    suspendExempt := entry.Length >= 4 ? !!entry[4] : false
                }
            } else
                return false
            callbackId := QMK.RuntimeCallbackId(callback)
            if (callbackId < 0)
                return false
            suspendExempt := suspendExempt || QMK.CallbackIsSuspendExempt(callback)
            contextText := QMK.ContextText(contexts)
            rows.Push({ key: key, callbackId: callbackId, actionKind: actionKind, context: contextText, suspendExempt: suspendExempt })
            totalTextChars += StrLen(key) + StrLen(contextText)
        }
        recordSize := 32
        buf := Buffer(rows.Length * recordSize, 0)
        textBuf := Buffer(Max(2, (totalTextChars + 1) * 2), 0)
        textOffset := 0
        for i, row in rows {
            off := (i - 1) * recordSize
            keyLen := StrLen(row.key)
            contextLen := StrLen(row.context)
            NumPut("UInt", textOffset, buf, off)
            NumPut("UShort", keyLen, buf, off + 4)
            if keyLen > 0
                StrPut(row.key, textBuf.Ptr + textOffset * 2, keyLen + 1, "UTF-16")
            textOffset += keyLen
            NumPut("Int", row.callbackId, buf, off + 8)
            NumPut("UChar", row.actionKind, buf, off + 12)
            NumPut("UChar", row.suspendExempt ? 1 : 0, buf, off + 13)
            NumPut("UInt", textOffset, buf, off + 16)
            NumPut("UShort", contextLen, buf, off + 20)
            if contextLen > 0
                StrPut(row.context, textBuf.Ptr + textOffset * 2, contextLen + 1, "UTF-16")
            textOffset += contextLen
        }
        return DllCall(proc, "Ptr", buf.Ptr, "UInt", rows.Length, "Ptr", textBuf.Ptr, "UInt", textOffset, "Int") == rows.Length
    }
    static SetupHold(key, context := "global", callback := "", suspendExempt := false) {
        if QMK.IsCallable(context)
            return QMK.SetupHolds([[key, context, callback]])
        return QMK.SetupHolds([[key, context, callback, suspendExempt]])
    }
    static SetupHolds(entries) {
        if QMK.SetupContextActionRows(entries, 0)
            return true
        ; V1.11 correctness rule: holds must be installed into Zig with their
        ; context rows. Do not silently fall back to AHK-side context lookup.
        return false
    }
    static SetupDoubleTap(key, context := "global", callback := "", suspendExempt := false) {
        if QMK.IsCallable(context)
            return QMK.SetupDoubleTaps([[key, context, callback]])
        return QMK.SetupDoubleTaps([[key, context, callback, suspendExempt]])
    }
    static SetupDoubleTaps(entries) {
        if QMK.SetupContextActionRows(entries, 1)
            return true
        ; V1.11 correctness rule: double-taps must be installed into Zig with
        ; their context rows. Do not silently fall back to AHK-side context lookup.
        return false
    }
    static SetupCombo(primaryKey, secondaryKey, context := "global", callback := "", suspendExempt := false) {
        if QMK.IsCallable(context) {
            if (Type(callback) = "String" && callback = "")
                return QMK.SetupCombos([[primaryKey, secondaryKey, context]])
            return QMK.SetupCombos([[primaryKey, secondaryKey, context, callback]])
        }
        return QMK.SetupCombos([[primaryKey, secondaryKey, context, callback, "normal", "", suspendExempt]])
    }
    static ComboCellsFromRow(entry) {
        cells := []
        if IsObject(entry) && entry.HasOwnProp("primary") {
            if !QMK.SetupObjectActionIsValid(entry)
                return false
            action := QMK.SetupObjectAction(entry)
            cells.Push(QMK.HotkeyCell(entry.primary))
            cells.Push(QMK.HotkeyCell(entry.secondary))
            if entry.HasOwnProp("context")
                cells.Push(QMK.HotkeyCell(entry.context))
            else if entry.HasOwnProp("contexts")
                cells.Push(QMK.HotkeyCell(entry.contexts))
            else
                cells.Push(QMK.HotkeyCell("global"))
            cells.Push(QMK.HotkeyCell(action))
            modeText := entry.HasOwnProp("mode") ? entry.mode : entry.HasOwnProp("type") ? entry.type : "normal"
            cells.Push(QMK.HotkeyCell(QMK.ComboModeTextForAction(action, modeText)))
            cells.Push(QMK.HotkeyCell(entry.HasOwnProp("mods") ? entry.mods : entry.HasOwnProp("mod") ? entry.mod : ""))
            if entry.HasOwnProp("suspendExempt")
                cells.Push(QMK.HotkeyCell(entry.suspendExempt))
        } else {
            if !QMK.IsArrayLike(entry)
                return false
            actionIndex := entry.Length == 3 ? 3 : entry.Length >= 4 ? 4 : 0
            if !actionIndex
                return false
            if (actionIndex && !QMK.SetupActionValueIsValid(entry[actionIndex]))
                return false
            for index, value in entry {
                if (index == actionIndex + 1 && QMK.IsSendKeyDirectDescriptor(entry[actionIndex]))
                    value := QMK.ComboModeTextForAction(entry[actionIndex], value)
                cells.Push(QMK.HotkeyCell(value))
            }
            if (entry.Length < actionIndex + 1 && QMK.IsSendKeyDirectDescriptor(entry[actionIndex]))
                cells.Push(QMK.HotkeyCell(QMK.ComboModeTextForAction(entry[actionIndex], "")))
        }
        return cells.Length >= 3 ? cells : false
    }
    static ComboModeTextForAction(action, modeText) {
        modeText := String(modeText)
        if !QMK.IsSendKeyDirectDescriptor(action)
            return modeText
        mode := StrLower(Trim(modeText))
        if (mode = "" || mode = "internal" || mode = "remap")
            return "sendkeydirect"
        if (mode = "instant" || mode = "internalinstant" || mode = "instantinternal")
            return "sendkeydirectinstant"
        return modeText
    }
    static SetupCombos(entries) {
        QMK.BeginSetup()
        try {
            entries := QMK.NormalizeSetupRows(entries)
            proc := QMK.ProcOptional("QMK_SetupComboCellEntries")
            if !proc
                return QMK.SetupCombosCompat(entries)
            rows := []
            totalTextChars := 0
            for rowIndex, entry in entries {
                cells := QMK.ComboCellsFromRow(entry)
                if !cells
                    QMK.ThrowSetupRowError("SetupCombos", rowIndex, "invalid combo row", entry)
                if (cells.Length > 7)
                    QMK.ThrowSetupRowError("SetupCombos", rowIndex, "too many cells", entry)
                for cell in cells {
                    if (cell.tag = 1 || cell.tag = 4)
                        totalTextChars += StrLen(cell.text) + 1
                }
                rows.Push({ cells: cells })
            }
            recordSize := 116
            recordBuf := Buffer(Max(1, rows.Length * recordSize), 0)
            textBuf := Buffer(Max(2, (totalTextChars + 1) * 2), 0)
            textOffset := 0
            for i, row in rows {
                off := (i - 1) * recordSize
                NumPut("UChar", row.cells.Length, recordBuf, off)
                for cellIndex, cell in row.cells {
                    cellOff := off + 4 + ((cellIndex - 1) * 16)
                    textLen := (cell.tag = 1 || cell.tag = 4) ? StrLen(cell.text) : 0
                    NumPut("UChar", cell.tag, recordBuf, cellOff)
                    NumPut("UChar", QMK.HotkeyCellFlags(cell), recordBuf, cellOff + 1)
                    NumPut("UInt", textOffset, recordBuf, cellOff + 4)
                    NumPut("UShort", textLen, recordBuf, cellOff + 8)
                    NumPut("Int", cell.callbackId, recordBuf, cellOff + 12)
                    if (textLen > 0)
                        StrPut(cell.text, textBuf.Ptr + textOffset * 2, textLen + 1, "UTF-16")
                    if (cell.tag = 1 || cell.tag = 4)
                        textOffset += textLen + 1
                }
            }
            loaded := DllCall(proc, "Ptr", recordBuf.Ptr, "UInt", rows.Length, "Ptr", textBuf.Ptr, "UInt", textOffset, "Int")
            if (loaded != rows.Length)
                QMK.ThrowSetupInstallError("SetupCombos", loaded, rows.Length, entries[loaded + 1])
            return true
        } finally {
            QMK.EndSetup()
        }
    }
    static SetupCombosCompat(entries) {
        entries := QMK.NormalizeSetupRows(entries)
        proc := QMK.Proc("QMK_SetupComboEntries")
        rows := []
        totalTextChars := 0
        for rowIndex, entry in entries {
            if QMK.IsArrayLike(entry) {
                if (entry.Length < 3)
                    QMK.ThrowSetupRowError("SetupCombos", rowIndex, "expected primary, secondary, and action/context", entry)
                primary := String(entry[1])
                secondary := String(entry[2])
                if (entry.Length == 3) {
                    contexts := "global"
                    action := entry[3]
                    modeText := ""
                    modPrefix := ""
                    suspendExempt := false
                } else {
                    contexts := entry[3]
                    action := entry[4]
                    modeText := entry.Length >= 5 ? String(entry[5]) : ""
                    modPrefix := entry.Length >= 6 ? String(entry[6]) : ""
                    suspendExempt := entry.Length >= 7 ? !!entry[7] : false
                }
            } else if IsObject(entry) {
                primary := String(entry.HasOwnProp("primary") ? entry.primary : "")
                secondary := String(entry.HasOwnProp("secondary") ? entry.secondary : "")
                contexts := entry.HasOwnProp("context") ? entry.context : entry.HasOwnProp("contexts") ? entry.contexts : "global"
                modeText := entry.HasOwnProp("mode") ? String(entry.mode) : entry.HasOwnProp("type") ? String(entry.type) : ""
                action := entry.HasOwnProp("callback") ? entry.callback : entry.HasOwnProp("target") ? entry.target : entry.HasOwnProp("action") ? entry.action : ""
                modPrefix := entry.HasOwnProp("mods") ? String(entry.mods) : entry.HasOwnProp("mod") ? String(entry.mod) : ""
                suspendExempt := entry.HasOwnProp("suspendExempt") ? !!entry.suspendExempt : false
            } else
                return false
            if QMK.IsCallable(action) {
                callbackId := QMK.RegisterRuntimeCallback(action)
                suspendExempt := suspendExempt || QMK.CallbackIsSuspendExempt(action)
                targetText := ""
            } else if QMK.IsSendKeyDirectDescriptor(action) {
                callbackId := -1
                targetText := action.text
                modeText := QMK.ComboModeTextForAction(action, modeText)
            } else if IsObject(action) {
                return false
            } else {
                callbackId := -1
                targetText := String(action)
            }
            contextText := QMK.ContextText(contexts)
            rows.Push({ primary: primary, secondary: secondary, callbackId: callbackId, target: targetText, mode: modeText, mod: modPrefix, context: contextText, suspendExempt: suspendExempt })
            totalTextChars += StrLen(primary) + StrLen(secondary) + StrLen(targetText) + StrLen(modeText) + StrLen(modPrefix) + StrLen(contextText)
        }
        recordSize := 56
        buf := Buffer(rows.Length * recordSize, 0)
        textBuf := Buffer(Max(2, (totalTextChars + 1) * 2), 0)
        textOffset := 0
        for i, row in rows {
            off := (i - 1) * recordSize
            primaryLen := StrLen(row.primary)
            secondaryLen := StrLen(row.secondary)
            targetLen := StrLen(row.target)
            modeLen := StrLen(row.mode)
            modLen := StrLen(row.mod)
            contextLen := StrLen(row.context)
            NumPut("UInt", textOffset, buf, off)
            NumPut("UShort", primaryLen, buf, off + 4)
            if primaryLen > 0
                StrPut(row.primary, textBuf.Ptr + textOffset * 2, primaryLen + 1, "UTF-16")
            textOffset += primaryLen
            NumPut("UInt", textOffset, buf, off + 8)
            NumPut("UShort", secondaryLen, buf, off + 12)
            if secondaryLen > 0
                StrPut(row.secondary, textBuf.Ptr + textOffset * 2, secondaryLen + 1, "UTF-16")
            textOffset += secondaryLen
            NumPut("Int", row.callbackId, buf, off + 16)
            NumPut("UInt", textOffset, buf, off + 20)
            NumPut("UShort", targetLen, buf, off + 24)
            if targetLen > 0
                StrPut(row.target, textBuf.Ptr + textOffset * 2, targetLen + 1, "UTF-16")
            textOffset += targetLen
            NumPut("UInt", textOffset, buf, off + 28)
            NumPut("UShort", modeLen, buf, off + 32)
            if modeLen > 0
                StrPut(row.mode, textBuf.Ptr + textOffset * 2, modeLen + 1, "UTF-16")
            textOffset += modeLen
            NumPut("UInt", textOffset, buf, off + 36)
            NumPut("UShort", modLen, buf, off + 40)
            if modLen > 0
                StrPut(row.mod, textBuf.Ptr + textOffset * 2, modLen + 1, "UTF-16")
            textOffset += modLen
            NumPut("UChar", row.suspendExempt ? 1 : 0, buf, off + 42)
            NumPut("UInt", textOffset, buf, off + 44)
            NumPut("UShort", contextLen, buf, off + 48)
            if contextLen > 0
                StrPut(row.context, textBuf.Ptr + textOffset * 2, contextLen + 1, "UTF-16")
            textOffset += contextLen
        }
        return DllCall(proc, "Ptr", buf.Ptr, "UInt", rows.Length, "Ptr", textBuf.Ptr, "UInt", textOffset, "Int") == rows.Length
    }
    static SetupChord(keys, context := "global", callback := "", suspendExempt := false) {
        if QMK.IsCallable(context) {
            if (Type(callback) = "String" && callback = "")
                return QMK.SetupChords([[keys, context]])
            return QMK.SetupChords([[keys, context, callback]])
        }
        return QMK.SetupChords([[keys, context, callback, suspendExempt]])
    }
    static NormalizeChordRow(entry) {
        if QMK.IsArrayLike(entry) {
            if (entry.Length >= 4 && entry.Length <= 7 && QMK.IsSendKeyDirectDescriptor(entry[entry.Length])) {
                keyCount := entry.Length - 2
                keys := []
                Loop 5
                    keys.Push(A_Index <= keyCount ? entry[A_Index] : "")
                return { keys: keys, context: entry[entry.Length - 1], callback: entry[entry.Length], mode: "sendkeydirect", suspendExempt: false, mod: "", target: entry[entry.Length] }
            }
            if QMK.LooksLikeChordSendRow(entry) {
                keyCount := entry.Length - 3
                keys := []
                Loop 5
                    keys.Push(A_Index <= keyCount ? entry[A_Index] : "")
                return { keys: keys, context: entry[keyCount + 1], callback: entry[keyCount + 2], mode: "internal", suspendExempt: false, mod: String(entry[keyCount + 3]), target: entry[keyCount + 2] }
            }
            if (entry.Length >= 2 && QMK.IsArrayLike(entry[1])) {
                if (entry.Length == 2) {
                    return { keys: entry[1], context: "global", callback: entry[2], mode: "callback", suspendExempt: false, mod: "", target: "" }
                }
                return { keys: entry[1], context: entry[2], callback: entry[3], mode: "callback", suspendExempt: entry.Length >= 4 ? !!entry[4] : false, mod: "", target: "" }
            }
            if (entry.Length >= 7)
                return { keys: [entry[1], entry[2], entry[3], entry[4], entry[5]], context: entry[6], callback: entry[7], mode: "callback", suspendExempt: entry.Length >= 8 ? !!entry[8] : false, mod: "", target: "" }
            return { keys: [entry[1], entry[2], entry.Length >= 4 ? entry[3] : "", entry.Length >= 5 ? entry[4] : "", entry.Length >= 6 ? entry[5] : ""], context: "global", callback: entry[entry.Length], mode: "callback", suspendExempt: false, mod: "", target: "" }
        }
        keys := entry.HasOwnProp("keys") ? entry.keys : [entry.k1, entry.k2, entry.HasOwnProp("k3") ? entry.k3 : "", entry.HasOwnProp("k4") ? entry.k4 : "", entry.HasOwnProp("k5") ? entry.k5 : ""]
        action := QMK.SetupObjectAction(entry)
        mode := entry.HasOwnProp("mode") ? entry.mode : entry.HasOwnProp("type") ? entry.type : QMK.IsSendKeyDirectDescriptor(action) ? "sendkeydirect" : entry.HasOwnProp("target") ? "internal" : "callback"
        return {
            keys: keys,
            context: entry.HasOwnProp("context") ? entry.context : entry.HasOwnProp("contexts") ? entry.contexts : "global",
            callback: action,
            mode: mode,
            suspendExempt: entry.HasOwnProp("suspendExempt") ? !!entry.suspendExempt : false,
            mod: entry.HasOwnProp("mods") ? entry.mods : entry.HasOwnProp("mod") ? entry.mod : "",
            target: entry.HasOwnProp("target") ? entry.target : QMK.IsSendKeyDirectDescriptor(action) ? action : ""
        }
    }
    static ChordCellsFromRow(entry) {
        cells := []
        if IsObject(entry) && entry.HasOwnProp("keys") {
            if !QMK.SetupObjectActionIsValid(entry)
                return false
            cells.Push(QMK.HotkeyCell(entry.keys))
            if entry.HasOwnProp("context")
                cells.Push(QMK.HotkeyCell(entry.context))
            else if entry.HasOwnProp("contexts")
                cells.Push(QMK.HotkeyCell(entry.contexts))
            else
                cells.Push(QMK.HotkeyCell("global"))
            cells.Push(QMK.HotkeyCell(QMK.SetupObjectAction(entry)))
            action := QMK.SetupObjectAction(entry)
            cells.Push(QMK.HotkeyCell(entry.HasOwnProp("mode") ? entry.mode : entry.HasOwnProp("type") ? entry.type : QMK.IsSendKeyDirectDescriptor(action) ? "sendkeydirect" : entry.HasOwnProp("target") ? "internal" : "callback"))
            cells.Push(QMK.HotkeyCell(entry.HasOwnProp("mods") ? entry.mods : entry.HasOwnProp("mod") ? entry.mod : ""))
            if entry.HasOwnProp("suspendExempt")
                cells.Push(QMK.HotkeyCell(entry.suspendExempt))
        } else {
            if !QMK.IsArrayLike(entry)
                return false
            normalized := QMK.NormalizeChordRow(entry)
            if !QMK.SetupActionValueIsValid(normalized.callback)
                return false
            cells.Push(QMK.HotkeyCell(normalized.keys))
            cells.Push(QMK.HotkeyCell(normalized.context))
            cells.Push(QMK.HotkeyCell(normalized.callback))
            cells.Push(QMK.HotkeyCell(normalized.mode))
            cells.Push(QMK.HotkeyCell(normalized.mod))
            if normalized.suspendExempt
                cells.Push(QMK.HotkeyCell(true))
        }
        return cells.Length >= 2 ? cells : false
    }
    static SetupChords(entries) {
        QMK.BeginSetup()
        try {
            entries := QMK.NormalizeSetupRows(entries)
            ; Fast native chord grammar for the common global callback form:
            ; [k1, k2, callback] through [k1, k2, k3, k4, k5, callback].
            ; All of these use the existing 80-byte QMK_SetupChordEntries ABI,
            ; bypassing NormalizeChordRow/HotkeyCell/temp key arrays entirely.
            fastNative := entries.Length > 0
            if fastNative {
                for entry in entries {
                    if (!QMK.IsArrayLike(entry) || entry.Length < 3 || entry.Length > 6
                        || !QMK.IsCallable(entry[entry.Length])) {
                        fastNative := false
                        break
                    }
                    keyCount := entry.Length - 1
                    Loop keyCount {
                        if IsObject(entry[A_Index]) {
                            fastNative := false
                            break
                        }
                    }
                    if !fastNative
                        break
                }
            }
            if fastNative
                return QMK.SetupChordsFixedBlob(entries)
            proc := QMK.ProcOptional("QMK_SetupChordCellEntries")
            if !proc
                return QMK.SetupChordsCompat(entries)
            rows := []
            totalTextChars := 0
            for rowIndex, entry in entries {
                cells := QMK.ChordCellsFromRow(entry)
                if !cells
                    QMK.ThrowSetupRowError("SetupChords", rowIndex, "invalid chord row", entry)
                if (cells.Length > 8)
                    QMK.ThrowSetupRowError("SetupChords", rowIndex, "too many cells", entry)
                for cell in cells {
                    if (cell.tag = 1 || cell.tag = 4)
                        totalTextChars += StrLen(cell.text) + 1
                }
                rows.Push({ cells: cells })
            }
            recordSize := 132
            recordBuf := Buffer(Max(1, rows.Length * recordSize), 0)
            textBuf := Buffer(Max(2, (totalTextChars + 1) * 2), 0)
            textOffset := 0
            for i, row in rows {
                off := (i - 1) * recordSize
                NumPut("UChar", row.cells.Length, recordBuf, off)
                for cellIndex, cell in row.cells {
                    cellOff := off + 4 + ((cellIndex - 1) * 16)
                    textLen := (cell.tag = 1 || cell.tag = 4) ? StrLen(cell.text) : 0
                    NumPut("UChar", cell.tag, recordBuf, cellOff)
                    NumPut("UChar", QMK.HotkeyCellFlags(cell), recordBuf, cellOff + 1)
                    NumPut("UInt", textOffset, recordBuf, cellOff + 4)
                    NumPut("UShort", textLen, recordBuf, cellOff + 8)
                    NumPut("Int", cell.callbackId, recordBuf, cellOff + 12)
                    if (textLen > 0)
                        StrPut(cell.text, textBuf.Ptr + textOffset * 2, textLen + 1, "UTF-16")
                    if (cell.tag = 1 || cell.tag = 4)
                        textOffset += textLen + 1
                }
            }
            loaded := DllCall(proc, "Ptr", recordBuf.Ptr, "UInt", rows.Length, "Ptr", textBuf.Ptr, "UInt", textOffset, "Int")
            if (loaded != rows.Length)
                QMK.ThrowSetupInstallError("SetupChords", loaded, rows.Length, entries[loaded + 1])
            return true
        } finally {
            QMK.EndSetup()
        }
    }
    static SetupChordsFixedBlob(entries) {
        ; Keep the exact old QMK_SetupChordEntries name and 80-byte wire format.
        ; This is only an AHK-side packing optimization: same fields/text semantics
        ; as SetupChordsCompat, but no NormalizeChordRow/temporary row/key objects.
        proc := QMK.Proc("QMK_SetupChordEntries")
        recordSize := 80
        totalTextChars := 0

        ; Simple flat grammar only:
        ; [k1, k2, callback] through [k1, k2, k3, k4, k5, callback].
        ; Match the old compatibility format exactly: target="", mode="callback",
        ; mod="", context="global" for every row.
        for rowIndex, entry in entries {
            keyCount := entry.Length - 1
            callback := entry[entry.Length]
            if (keyCount < 2 || keyCount > 5 || !QMK.IsCallable(callback))
                QMK.ThrowSetupRowError("SetupChords", rowIndex, "fast chords require 2-5 keys and a callable callback", entry)

            Loop keyCount
                totalTextChars += StrLen(String(entry[A_Index]))

            ; Same text payloads the old SetupChordsCompat writes per row.
            totalTextChars += 8 + 6 ; "callback" + "global"
        }

        recordBuf := Buffer(Max(1, entries.Length * recordSize), 0)
        textBuf := Buffer(Max(2, (totalTextChars + 1) * 2), 0)
        textOffset := 0

        for i, entry in entries {
            off := (i - 1) * recordSize
            keyCount := entry.Length - 1

            ; Five key descriptors exactly like SetupChordsCompat. Empty key slots
            ; get the current text offset with length 0 rather than a special value.
            Loop 5 {
                keyText := A_Index <= keyCount ? String(entry[A_Index]) : ""
                keyLen := StrLen(keyText)
                fieldOff := off + (A_Index - 1) * 8
                NumPut("UInt", textOffset, recordBuf, fieldOff)
                NumPut("UShort", keyLen, recordBuf, fieldOff + 4)
                if keyLen > 0
                    StrPut(keyText, textBuf.Ptr + textOffset * 2, keyLen + 1, "UTF-16")
                textOffset += keyLen
            }

            callback := entry[entry.Length]
            callbackId := QMK.RegisterRuntimeCallback(callback)
            suspendExempt := QMK.CallbackIsSuspendExempt(callback)

            ; callbackId @40.
            NumPut("Int", callbackId, recordBuf, off + 40)

            ; target="" -- exact old compatibility representation.
            NumPut("UInt", textOffset, recordBuf, off + 44)
            NumPut("UShort", 0, recordBuf, off + 48)

            ; mode="callback" -- do not rely on an empty-mode shortcut here.
            modeText := "callback"
            modeLen := 8
            NumPut("UInt", textOffset, recordBuf, off + 52)
            NumPut("UShort", modeLen, recordBuf, off + 56)
            StrPut(modeText, textBuf.Ptr + textOffset * 2, modeLen + 1, "UTF-16")
            textOffset += modeLen

            ; mod="".
            NumPut("UInt", textOffset, recordBuf, off + 60)
            NumPut("UShort", 0, recordBuf, off + 64)
            NumPut("UChar", suspendExempt ? 1 : 0, recordBuf, off + 66)

            ; context="global" per row, exactly like the old compatibility packer.
            contextText := "global"
            contextLen := 6
            NumPut("UInt", textOffset, recordBuf, off + 68)
            NumPut("UShort", contextLen, recordBuf, off + 72)
            StrPut(contextText, textBuf.Ptr + textOffset * 2, contextLen + 1, "UTF-16")
            textOffset += contextLen
        }

        loaded := DllCall(proc, "Ptr", recordBuf.Ptr, "UInt", entries.Length, "Ptr", textBuf.Ptr, "UInt", textOffset, "Int")
        if (loaded != entries.Length)
            QMK.ThrowSetupInstallError("SetupChords", loaded, entries.Length, entries[loaded + 1])
        return true
    }
    static SetupChordsCompat(entries) {
        entries := QMK.NormalizeSetupRows(entries)
        proc := QMK.Proc("QMK_SetupChordEntries")
        rows := []
        totalTextChars := 0
        for rowIndex, entry in entries {
            row := QMK.NormalizeChordRow(entry)
            keys := row.keys
            if !QMK.IsArrayLike(keys) || keys.Length < 2
                QMK.ThrowSetupRowError("SetupChords", rowIndex, "expected at least two keys", entry)
            modeText := row.mode
            callbackId := -1
            targetText := ""
            if QMK.IsCallable(row.callback) {
                callbackId := QMK.RegisterRuntimeCallback(row.callback)
                row.suspendExempt := row.suspendExempt || QMK.CallbackIsSuspendExempt(row.callback)
            } else if QMK.IsSendKeyDirectDescriptor(row.callback) {
                targetText := row.callback.text
            } else if IsObject(row.callback) {
                QMK.ThrowSetupRowError("SetupChords", rowIndex, "callback/action is not callable or native text", entry)
            } else {
                targetText := String(row.target != "" ? row.target : row.callback)
            }
            keyTexts := []
            Loop 5
                keyTexts.Push(A_Index <= keys.Length ? String(keys[A_Index]) : "")
            modText := String(row.mod)
            contextText := QMK.ContextText(row.context)
            rows.Push({ keys: keyTexts.Clone(), callbackId: callbackId, target: targetText, mode: String(modeText), mod: modText, context: contextText, suspendExempt: row.suspendExempt })
            for keyText in keyTexts
                totalTextChars += StrLen(keyText)
            totalTextChars += StrLen(targetText) + StrLen(modeText) + StrLen(modText) + StrLen(contextText)
        }
        recordSize := 80
        buf := Buffer(rows.Length * recordSize, 0)
        textBuf := Buffer(Max(2, (totalTextChars + 1) * 2), 0)
        textOffset := 0
        for i, row in rows {
            off := (i - 1) * recordSize
            Loop 5 {
                keyText := row.keys[A_Index]
                keyLen := StrLen(keyText)
                fieldOff := off + (A_Index - 1) * 8
                NumPut("UInt", textOffset, buf, fieldOff)
                NumPut("UShort", keyLen, buf, fieldOff + 4)
                if keyLen > 0
                    StrPut(keyText, textBuf.Ptr + textOffset * 2, keyLen + 1, "UTF-16")
                textOffset += keyLen
            }
            targetLen := StrLen(row.target)
            modeLen := StrLen(row.mode)
            modLen := StrLen(row.mod)
            contextLen := StrLen(row.context)
            NumPut("Int", row.callbackId, buf, off + 40)
            NumPut("UInt", textOffset, buf, off + 44)
            NumPut("UShort", targetLen, buf, off + 48)
            if targetLen > 0
                StrPut(row.target, textBuf.Ptr + textOffset * 2, targetLen + 1, "UTF-16")
            textOffset += targetLen
            NumPut("UInt", textOffset, buf, off + 52)
            NumPut("UShort", modeLen, buf, off + 56)
            if modeLen > 0
                StrPut(row.mode, textBuf.Ptr + textOffset * 2, modeLen + 1, "UTF-16")
            textOffset += modeLen
            NumPut("UInt", textOffset, buf, off + 60)
            NumPut("UShort", modLen, buf, off + 64)
            if modLen > 0
                StrPut(row.mod, textBuf.Ptr + textOffset * 2, modLen + 1, "UTF-16")
            textOffset += modLen
            NumPut("UChar", row.suspendExempt ? 1 : 0, buf, off + 66)
            NumPut("UInt", textOffset, buf, off + 68)
            NumPut("UShort", contextLen, buf, off + 72)
            if contextLen > 0
                StrPut(row.context, textBuf.Ptr + textOffset * 2, contextLen + 1, "UTF-16")
            textOffset += contextLen
        }
        return DllCall(proc, "Ptr", buf.Ptr, "UInt", rows.Length, "Ptr", textBuf.Ptr, "UInt", textOffset, "Int") == rows.Length
    }
}

class QMKTextAndHotkeyAPIs extends QMKUserAPIs {
    static IsCallable(value) {
        return IsObject(value) && HasMethod(value, "Call")
    }
    static SuspendExempt(callback) {
        if IsObject(callback)
            QMK.suspendExemptCallbackPtrs[ObjPtr(callback)] := true
        return callback
    }
    static CallbackIsSuspendExempt(callback) {
        return IsObject(callback) && QMK.suspendExemptCallbackPtrs.Has(ObjPtr(callback))
    }
    static PasteTextWithDll(text) {
        ok := DllCall(QMK.pPasteTextWithDll, "Str", String(text), "Int")
        if (!ok)
            throw Error("QMK_Paste failed")
        return ok
    }

    static RuntimeCallbackId(callback) {
        if !QMK.IsCallable(callback)
            return -1
        return QMK.RegisterRuntimeCallback(callback)
    }
    static IsTapDescriptor(value) {
        return IsObject(value) && Type(value) = "QMKTapDescriptor"
    }
    static IsSendKeyDirectDescriptor(value) {
        return IsObject(value) && Type(value) = "QMKSendKeyDirectDescriptor"
    }
    static TapDescriptorHasHold(value) {
        return QMK.IsTapDescriptor(value) && !(Type(value.holdCallback) = "String" && value.holdCallback = "")
    }
    static TapHoldKeyFromHotkeySpec(spec) {
        text := Trim(String(spec))
        text := StrReplace(StrReplace(StrReplace(text, "~", ""), "$", ""), "*", "")
        text := StrReplace(text, " up", "")
        if (InStr(text, "&") || InStr(text, " "))
            return ""
        if RegExMatch(text, "[#!^+]")
            return ""
        return text
    }
    static TapDescriptorTapCallback(descriptor) {
        action := descriptor.action
        return (*) => QMK.Tap(action)
    }
    ; Preferred order: key, context, thresholdMs, tapCallback, holdCallback,
    ; cleanupCallback, suspendExempt.
    static SetupTapHold(key, context := "global", thresholdMs := 200, tapCallback := "", holdCallback := "", cleanupCallback := "", suspendExempt := false) {
        if QMK.IsCallable(context) {
            tapFn := context
            holdFn := thresholdMs
            threshold := IsNumber(tapCallback) ? tapCallback : 200
            cleanupFn := holdCallback
            contextValue := (Type(cleanupCallback) = "String" && cleanupCallback = "") ? "global" : cleanupCallback
            return QMK.SetupTapHolds([[key, contextValue, threshold, tapFn, holdFn, cleanupFn, suspendExempt]])
        }
        return QMK.SetupTapHolds([[key, context, thresholdMs, tapCallback, holdCallback, cleanupCallback, suspendExempt]])
    }
    static TapHoldCellsFromRow(entry) {
        if IsObject(entry) && entry.HasOwnProp("key") {
            tapCallback := entry.HasOwnProp("tapCallback") ? entry.tapCallback : entry.HasOwnProp("tap") ? entry.tap : ""
            holdCallback := entry.HasOwnProp("holdCallback") ? entry.holdCallback : entry.HasOwnProp("hold") ? entry.hold : ""
            cleanupCallback := entry.HasOwnProp("cleanupCallback") ? entry.cleanupCallback : entry.HasOwnProp("cleanup") ? entry.cleanup : ""
            if ((IsObject(tapCallback) && !QMK.IsCallable(tapCallback) && !QMK.IsTapDescriptor(tapCallback))
                || (IsObject(holdCallback) && !QMK.IsCallable(holdCallback))
                || (IsObject(cleanupCallback) && !QMK.IsCallable(cleanupCallback)))
                return false
            cells := []
            cells.Push(QMK.HotkeyCell(entry.key))
            cells.Push(QMK.HotkeyCell(entry.HasOwnProp("context") ? entry.context : entry.HasOwnProp("contexts") ? entry.contexts : "global"))
            cells.Push(QMK.HotkeyCell(entry.HasOwnProp("thresholdMs") ? entry.thresholdMs : entry.HasOwnProp("threshold") ? entry.threshold : 200))
            cells.Push(QMK.HotkeyCell(tapCallback))
            cells.Push(QMK.HotkeyCell(holdCallback))
            cells.Push(QMK.HotkeyCell(cleanupCallback))
            cells.Push(QMK.HotkeyCell(entry.HasOwnProp("suspendExempt") ? entry.suspendExempt : false))
            return cells
        }
        if !QMK.IsArrayLike(entry)
            return false
        if ((entry.Length >= 2 && IsObject(entry[2]) && !QMK.IsCallable(entry[2]) && !QMK.IsArrayLike(entry[2]))
            || (entry.Length >= 3 && IsObject(entry[3]) && !QMK.IsCallable(entry[3]))
            || (entry.Length >= 4 && IsObject(entry[4]) && !QMK.IsCallable(entry[4]))
            || (entry.Length >= 5 && IsObject(entry[5]) && !QMK.IsCallable(entry[5]))
            || (entry.Length >= 6 && IsObject(entry[6]) && !QMK.IsCallable(entry[6]) && !QMK.IsArrayLike(entry[6])))
            return false
        cells := []
        for value in entry
            cells.Push(QMK.HotkeyCell(value))
        return cells
    }
    static SetupTapHolds(entries) {
        QMK.BeginSetup()
        try {
            entries := QMK.NormalizeSetupRows(entries)
            proc := QMK.ProcOptional("QMK_SetupTapHoldCellEntries")
            if !proc
                return QMK.SetupTapHoldsCompat(entries)
            rows := []
            totalTextChars := 0
            for rowIndex, entry in entries {
                cells := QMK.TapHoldCellsFromRow(entry)
                if !cells
                    QMK.ThrowSetupRowError("SetupTapHolds", rowIndex, "invalid tap-hold row", entry)
                for cell in cells {
                    if (cell.tag = 1 || cell.tag = 4)
                        totalTextChars += StrLen(cell.text) + 1
                }
                rows.Push({ cells: cells })
            }
            recordSize := 116
            recordBuf := Buffer(Max(1, rows.Length * recordSize), 0)
            textBuf := Buffer(Max(2, (totalTextChars + 1) * 2), 0)
            textOffset := 0
            for i, row in rows {
                off := (i - 1) * recordSize
                NumPut("UChar", row.cells.Length, recordBuf, off)
                for cellIndex, cell in row.cells {
                    cellOff := off + 4 + ((cellIndex - 1) * 16)
                    textLen := (cell.tag = 1 || cell.tag = 4) ? StrLen(cell.text) : 0
                    NumPut("UChar", cell.tag, recordBuf, cellOff)
                    NumPut("UChar", QMK.HotkeyCellFlags(cell), recordBuf, cellOff + 1)
                    NumPut("UInt", textOffset, recordBuf, cellOff + 4)
                    NumPut("UShort", textLen, recordBuf, cellOff + 8)
                    NumPut("Int", cell.callbackId, recordBuf, cellOff + 12)
                    if (textLen > 0)
                        StrPut(cell.text, textBuf.Ptr + textOffset * 2, textLen + 1, "UTF-16")
                    if (cell.tag = 1 || cell.tag = 4)
                        textOffset += textLen + 1
                }
            }
            loaded := DllCall(proc, "Ptr", recordBuf.Ptr, "UInt", rows.Length, "Ptr", textBuf.Ptr, "UInt", textOffset, "Int")
            if (loaded != rows.Length)
                QMK.ThrowSetupInstallError("SetupTapHolds", loaded, rows.Length, entries[loaded + 1])
            return true
        } finally {
            QMK.EndSetup()
        }
    }
    static SetupTapHoldsCompat(entries) {
        entries := QMK.NormalizeSetupRows(entries)
        proc := QMK.Proc("QMK_SetupTapHoldEntries")
        rows := []
        totalTextChars := 0
        for rowIndex, entry in entries {
            if IsObject(entry) && entry.HasOwnProp("key") {
                key := String(entry.key)
                contexts := entry.HasOwnProp("context") ? entry.context : entry.HasOwnProp("contexts") ? entry.contexts : "global"
                thresholdMs := entry.HasOwnProp("thresholdMs") ? entry.thresholdMs : entry.HasOwnProp("threshold") ? entry.threshold : 200
                tapCallback := entry.HasOwnProp("tapCallback") ? entry.tapCallback : entry.HasOwnProp("tap") ? entry.tap : ""
                holdCallback := entry.HasOwnProp("holdCallback") ? entry.holdCallback : entry.HasOwnProp("hold") ? entry.hold : ""
                cleanupCallback := entry.HasOwnProp("cleanupCallback") ? entry.cleanupCallback : entry.HasOwnProp("cleanup") ? entry.cleanup : ""
                suspendExempt := entry.HasOwnProp("suspendExempt") ? !!entry.suspendExempt : false
            } else if QMK.IsArrayLike(entry) {
                key := String(entry[1])
                if (entry.Length >= 3 && QMK.IsCallable(entry[2])) {
                    contexts := entry.Length >= 6 ? entry[6] : "global"
                    thresholdMs := entry.Length >= 4 && IsNumber(entry[4]) ? entry[4] : 200
                    tapCallback := entry[2]
                    holdCallback := entry[3]
                    cleanupCallback := entry.Length >= 5 ? entry[5] : ""
                    suspendExempt := entry.Length >= 7 ? !!entry[7] : false
                } else {
                    contexts := entry.Length >= 2 ? entry[2] : "global"
                    thresholdMs := entry.Length >= 3 ? entry[3] : 200
                    tapCallback := entry.Length >= 4 ? entry[4] : ""
                    holdCallback := entry.Length >= 5 ? entry[5] : ""
                    cleanupCallback := entry.Length >= 6 ? entry[6] : ""
                    suspendExempt := entry.Length >= 7 ? !!entry[7] : false
                }
            } else
                QMK.ThrowSetupRowError("SetupTapHolds", rowIndex, "expected tap-hold row array or object", entry)
            if ((IsObject(tapCallback) && !QMK.IsCallable(tapCallback) && !QMK.IsTapDescriptor(tapCallback))
                || (IsObject(holdCallback) && !QMK.IsCallable(holdCallback))
                || (IsObject(cleanupCallback) && !QMK.IsCallable(cleanupCallback)))
                QMK.ThrowSetupRowError("SetupTapHolds", rowIndex, "tap/hold/cleanup callback is invalid", entry)
            if QMK.IsTapDescriptor(tapCallback)
                tapCallback := QMK.TapDescriptorTapCallback(tapCallback)
            tapId := QMK.RuntimeCallbackId(tapCallback)
            holdId := QMK.RuntimeCallbackId(holdCallback)
            cleanupId := QMK.RuntimeCallbackId(cleanupCallback)
            suspendExempt := suspendExempt || QMK.CallbackIsSuspendExempt(tapCallback)
                || QMK.CallbackIsSuspendExempt(holdCallback)
                || QMK.CallbackIsSuspendExempt(cleanupCallback)
            if (tapId < 0 && holdId < 0)
                QMK.ThrowSetupRowError("SetupTapHolds", rowIndex, "expected tap or hold callback", entry)
            contextText := QMK.ContextText(contexts)
            rows.Push({ key: key, thresholdMs: Round(thresholdMs), tapId: tapId, holdId: holdId, cleanupId: cleanupId, context: contextText, suspendExempt: suspendExempt })
            totalTextChars += StrLen(key) + StrLen(contextText)
        }
        recordSize := 40
        buf := Buffer(rows.Length * recordSize, 0)
        textBuf := Buffer(Max(2, (totalTextChars + 1) * 2), 0)
        textOffset := 0
        for i, row in rows {
            off := (i - 1) * recordSize
            keyLen := StrLen(row.key)
            contextLen := StrLen(row.context)
            NumPut("UInt", textOffset, buf, off)
            NumPut("UShort", keyLen, buf, off + 4)
            if keyLen > 0
                StrPut(row.key, textBuf.Ptr + textOffset * 2, keyLen + 1, "UTF-16")
            textOffset += keyLen
            NumPut("Int", row.tapId, buf, off + 8)
            NumPut("Int", row.holdId, buf, off + 12)
            NumPut("Int", row.cleanupId, buf, off + 16)
            NumPut("Int", row.thresholdMs, buf, off + 20)
            NumPut("UChar", row.suspendExempt ? 1 : 0, buf, off + 24)
            NumPut("UInt", textOffset, buf, off + 28)
            NumPut("UShort", contextLen, buf, off + 32)
            if contextLen > 0
                StrPut(row.context, textBuf.Ptr + textOffset * 2, contextLen + 1, "UTF-16")
            textOffset += contextLen
        }
        loaded := DllCall(proc, "Ptr", buf.Ptr, "UInt", rows.Length, "Ptr", textBuf.Ptr, "UInt", textOffset, "Int")
        if (loaded != rows.Length)
            QMK.ThrowSetupInstallError("SetupTapHolds", loaded, rows.Length, entries[loaded + 1])
        return true
    }
    static SetupHotstring(triggerSpec, context := "global", action := "", suspendExempt := false) {
        if QMK.IsCallable(context) {
            if (Type(action) = "String" && action = "")
                return QMK.SetupHotstrings([[triggerSpec, context]])
            return QMK.SetupHotstrings([[triggerSpec, context, action]])
        }
        if (Type(action) = "String" && action = "" && !(Type(context) = "String" && context = "global"))
            return QMK.SetupHotstrings([[triggerSpec, context]])
        if (!QMK.IsCallable(action) && Type(action) != "String")
            return QMK.SetupHotstrings([[triggerSpec, context, action]])
        return QMK.SetupHotstrings([[triggerSpec, context, action, suspendExempt]])
    }
    static Hotstring(name, replacement?, onOff?) {
        if (StrLower(name) == "endchars") {
            oldValue := "-()[]{}:;'" . Chr(34) . "/\,.?!`n `t"
            if IsSet(replacement) {
                if proc := QMK.ProcOptional("QMK_SetHotstringEndChars")
                    DllCall(proc, "Str", replacement, "Int")
            }
            return oldValue
        }
        if (StrLower(name) == "mousereset") {
            if IsSet(replacement) {
                if proc := QMK.ProcOptional("QMK_SetHotstringMouseReset")
                    DllCall(proc, "Int", !!replacement)
            }
            return true
        }
        if (StrLower(name) == "reset") {
            if proc := QMK.ProcOptional("QMK_ResetHotstringBuffer")
                DllCall(proc)
            return
        }
        if IsSet(replacement)
            return QMK.SetupHotstring(name, "global", replacement)
        if IsSet(onOff)
            return DllCall(QMK.Proc("QMK_SetRuntimeHotstringEnabledToggleEntry"), "Str", String(name), "Str", String(onOff), "Int")
        return -1
    }
    static HotstringCellsFromRow(entry) {
        cells := []
        if IsObject(entry) && (entry.HasOwnProp("trigger") || entry.HasOwnProp("spec")) {
            if entry.HasOwnProp("callback")
                action := entry.callback
            else if entry.HasOwnProp("text")
                action := entry.text
            else if entry.HasOwnProp("replacement")
                action := entry.replacement
            else
                return false
            if IsObject(action) && !QMK.IsCallable(action)
                return false
            cells.Push(QMK.HotkeyCell(entry.HasOwnProp("trigger") ? entry.trigger : entry.spec))
            cells.Push(QMK.HotkeyCell(entry.HasOwnProp("context") ? entry.context : entry.HasOwnProp("contexts") ? entry.contexts : "global"))
            cells.Push(QMK.HotkeyCell(action))
            if entry.HasOwnProp("options")
                cells.Push(QMK.HotkeyCell(entry.options))
            if entry.HasOwnProp("suspendExempt")
                cells.Push(QMK.HotkeyCell(entry.suspendExempt))
        } else {
            if !QMK.IsArrayLike(entry)
                return false
            actionIndex := entry.Length == 2 ? 2 : entry.Length == 3 && QMK.RawValueLooksBool(entry[3]) ? 2 : entry.Length >= 3 ? 3 : 0
            if (actionIndex > 0 && IsObject(entry[actionIndex]) && !QMK.IsCallable(entry[actionIndex]))
                return false
            for value in entry
                cells.Push(QMK.HotkeyCell(value))
        }
        return cells.Length >= 2 ? cells : false
    }
    static SetupHotstrings(entries) {
        QMK.BeginSetup()
        try {
            entries := QMK.NormalizeSetupRows(entries)
            return QMK.SetupHotstringsCompat(entries)
        } finally {
            QMK.EndSetup()
        }
    }
    static SetupHotstringsCompat(entries) {
        proc := QMK.Proc("QMK_SetupHotstringEntries")
        rows := []
        totalTextChars := 0
        nativeCount := 0
        for rowIndex, entry in entries {
            optionsText := ""
            suspendExempt := false
            if (QMK.IsArrayLike(entry)) {
                if (entry.Length < 2)
                    QMK.ThrowSetupRowError("SetupHotstrings", rowIndex, "expected trigger and action/context", entry)
                triggerSpec := String(entry[1])
                if (entry.Length == 3 && QMK.RawValueLooksBool(entry[3])) {
                    contextText := "global"
                    action := entry[2]
                    suspendExempt := !!entry[3]
                } else {
                    contextText := entry.Length >= 3 ? QMK.ContextText(entry[2]) : "global"
                    action := entry.Length >= 3 ? entry[3] : entry[entry.Length]
                }
                if (entry.Length >= 4) {
                    if (Type(entry[4]) = "String")
                        optionsText := entry[4]
                    else
                        suspendExempt := !!entry[4]
                }
                if (entry.Length >= 5)
                    suspendExempt := !!entry[5]
            } else if IsObject(entry) && (entry.HasOwnProp("trigger") || entry.HasOwnProp("spec")) {
                triggerSpec := String(entry.HasOwnProp("trigger") ? entry.trigger : entry.spec)
                contextText := QMK.ContextText(entry.HasOwnProp("context") ? entry.context : entry.HasOwnProp("contexts") ? entry.contexts : "global")
                optionsText := entry.HasOwnProp("options") ? String(entry.options) : ""
                suspendExempt := entry.HasOwnProp("suspendExempt") ? !!entry.suspendExempt : false
                if entry.HasOwnProp("callback")
                    action := entry.callback
                else if entry.HasOwnProp("text")
                    action := entry.text
                else if entry.HasOwnProp("replacement")
                    action := entry.replacement
                else
                    QMK.ThrowSetupRowError("SetupHotstrings", rowIndex, "missing callback/text/replacement", entry)
            } else
                QMK.ThrowSetupRowError("SetupHotstrings", rowIndex, "expected hotstring row array or object", entry)
            if IsObject(action) && !QMK.IsCallable(action)
                QMK.ThrowSetupRowError("SetupHotstrings", rowIndex, "action is an object but not callable", entry)
            isNative := !IsObject(action)
            actionText := isNative ? String(action) : ""
            callbackId := -1
            if isNative {
                nativeCount++
            } else {
                callbackId := QMK.RegisterRuntimeCallback(action)
                suspendExempt := suspendExempt || QMK.CallbackIsSuspendExempt(action)
            }
            rows.Push({ triggerSpec: triggerSpec, context: contextText, actionText: actionText, optionsText: optionsText, callbackId: callbackId, suspendExempt: suspendExempt, isNative: isNative })
            totalTextChars += StrLen(triggerSpec) + StrLen(contextText) + StrLen(optionsText) + (isNative ? StrLen(actionText) + 1 : 0)
        }
        recordSize := 40
        recordBuf := Buffer(Max(1, rows.Length * recordSize), 0)
        textBuf := Buffer(Max(2, (totalTextChars + 1) * 2), 0)
        textOffset := 0
        for i, row in rows {
            off := (i - 1) * recordSize
            specLen := StrLen(row.triggerSpec)
            ctxLen := StrLen(row.context)
            actionLen := StrLen(row.actionText)
            optionsLen := StrLen(row.optionsText)
            NumPut("UInt", textOffset, recordBuf, off)
            NumPut("UShort", specLen, recordBuf, off + 4)
            if specLen > 0
                StrPut(row.triggerSpec, textBuf.Ptr + textOffset * 2, specLen + 1, "UTF-16")
            textOffset += specLen
            NumPut("UInt", textOffset, recordBuf, off + 8)
            NumPut("UShort", ctxLen, recordBuf, off + 12)
            if ctxLen > 0
                StrPut(row.context, textBuf.Ptr + textOffset * 2, ctxLen + 1, "UTF-16")
            textOffset += ctxLen
            NumPut("UInt", textOffset, recordBuf, off + 16)
            NumPut("UShort", actionLen, recordBuf, off + 20)
            if actionLen > 0
                StrPut(row.actionText, textBuf.Ptr + textOffset * 2, actionLen + 1, "UTF-16")
            textOffset += actionLen + (row.isNative ? 1 : 0)
            NumPut("UInt", textOffset, recordBuf, off + 24)
            NumPut("UShort", optionsLen, recordBuf, off + 28)
            if optionsLen > 0
                StrPut(row.optionsText, textBuf.Ptr + textOffset * 2, optionsLen + 1, "UTF-16")
            textOffset += optionsLen
            NumPut("Int", row.callbackId, recordBuf, off + 32)
            NumPut("UChar", row.suspendExempt ? 1 : 0, recordBuf, off + 36)
            NumPut("UChar", row.isNative ? 1 : 0, recordBuf, off + 37)
        }
        QMK.nativeHotstringCount := nativeCount
        QMK.ahkHotstringCount := rows.Length - nativeCount
        QMK.nativeHotstringChars := textOffset
        loaded := DllCall(proc, "Ptr", recordBuf.Ptr, "UInt", rows.Length, "Ptr", textBuf.Ptr, "UInt", textOffset, "Int")
        if (loaded != rows.Length)
            QMK.ThrowSetupInstallError("SetupHotstrings", loaded, rows.Length, entries[loaded + 1])
        return true
    }
    static SetupHotkey(entryOrKind, args*) {
        row := [entryOrKind]
        for arg in args
            row.Push(arg)
        return QMK.SetupHotkeys([row])
    }
    static SetupTap(key, context := "global", tapAction := "", holdCallback := "", thresholdMs := 0, cleanupCallback := "", suspendExempt := false) {
        if (IsObject(key) && !QMK.IsCallable(key)
            && Type(context) = "String" && context = "global"
            && Type(tapAction) = "String" && tapAction = ""
            && Type(holdCallback) = "String" && holdCallback = ""
            && thresholdMs = 0
            && Type(cleanupCallback) = "String" && cleanupCallback = ""
            && suspendExempt = false)
            return QMK.SetupTaps([key])
        if ((Type(tapAction) = "String" && tapAction = "") && !(Type(context) = "String" && context = "global")) {
            tapAction := context
            context := "global"
        }
        return QMK.SetupTaps([[key, context, tapAction, holdCallback, thresholdMs, cleanupCallback, suspendExempt]])
    }
    static SetupTaps(entries) {
        rows := []
        for rowIndex, entry in QMK.NormalizeSetupRows(entries) {
            row := QMK.NormalizeTapRow(entry)
            if !row
                QMK.ThrowSetupRowError("SetupTaps", rowIndex, "invalid tap row", entry)
            tapAction := QMK.IsTapDescriptor(row.tapAction) ? row.tapAction : QMK.Tap(row.tapAction, row.holdCallback, row.thresholdMs, row.cleanupCallback)
            rows.Push([row.key, row.context, tapAction, row.suspendExempt])
        }
        return QMK.SetupHotkeys(rows)
    }
    static NormalizeTapRow(entry) {
        if IsObject(entry) && !QMK.IsArrayLike(entry) {
            if !entry.HasOwnProp("key")
                return false
            tapAction := entry.HasOwnProp("tapAction") ? entry.tapAction : entry.HasOwnProp("tap") ? entry.tap : entry.HasOwnProp("action") ? entry.action : ""
            holdCallback := entry.HasOwnProp("holdCallback") ? entry.holdCallback : entry.HasOwnProp("hold") ? entry.hold : ""
            cleanupCallback := entry.HasOwnProp("cleanupCallback") ? entry.cleanupCallback : entry.HasOwnProp("cleanup") ? entry.cleanup : ""
            thresholdMs := entry.HasOwnProp("thresholdMs") ? entry.thresholdMs : entry.HasOwnProp("threshold") ? entry.threshold : 0
            return {
                key: entry.key,
                context: entry.HasOwnProp("context") ? entry.context : entry.HasOwnProp("contexts") ? entry.contexts : "global",
                tapAction: tapAction,
                holdCallback: holdCallback,
                thresholdMs: thresholdMs,
                cleanupCallback: cleanupCallback,
                suspendExempt: entry.HasOwnProp("suspendExempt") ? !!entry.suspendExempt : false
            }
        }
        if !QMK.IsArrayLike(entry) || entry.Length < 2
            return false
        if (entry.Length == 2) {
            return { key: entry[1], context: "global", tapAction: entry[2], holdCallback: "", thresholdMs: 0, cleanupCallback: "", suspendExempt: false }
        }
        return {
            key: entry[1],
            context: entry[2],
            tapAction: entry[3],
            holdCallback: entry.Length >= 4 ? entry[4] : "",
            thresholdMs: entry.Length >= 5 ? entry[5] : 0,
            cleanupCallback: entry.Length >= 6 ? entry[6] : "",
            suspendExempt: entry.Length >= 7 ? !!entry[7] : false
        }
    }
    static SetupAhkHotkey(hotkeySpec, contextsOrCallback, callback := "", optionsText := "I2") {
        hotkeySpec := QMK.NormalizeAhkHotkeySpec(hotkeySpec)
        hasCallback := !(Type(callback) = "String" && callback = "")
        contexts := hasCallback ? QMK.SplitContextList(contextsOrCallback) : ["global"]
        action := hasCallback ? callback : contextsOrCallback
        if QMK.IsSendKeyDirectDescriptor(action) {
            nativeText := action.text
            action := ((text) => (*) => QMK.SendDirect(text))(nativeText)
        }
        if QMK.IsTapDescriptor(action)
            action := ((tapAction) => (*) => QMK.Tap(tapAction))(action.action)
        if !QMK.IsCallable(action) {
            nativeText := String(action)
            action := ((text) => (*) => QMK.PasteTextWithDll(text))(nativeText)
        }
        wrapped := QMK.WrapShortcutCallback(action, contexts)
        if (contexts.Length == 0 || (contexts.Length == 1 && contexts[1] = "global")) {
            Hotkey(hotkeySpec, wrapped, optionsText)
            return true
        }
        HotIf((*) => QMK.ContextPredicateMatches(contexts))
        try {
            Hotkey(hotkeySpec, wrapped, optionsText)
        } finally {
            HotIf()
        }
        return true
    }
    static WrapShortcutCallback(callback, contexts) {
        contexts := QMK.SplitContextList(contexts)
        if (contexts.Length == 0 || (contexts.Length == 1 && contexts[1] = "global"))
            return callback
        return (*) => (QMK.ContextPredicateMatches(contexts) ? QMK.InvokeCallback(callback) : "")
    }
    static ContextPredicateMatches(contexts) {
        contexts := QMK.SplitContextList(contexts)
        if (contexts.Length == 0)
            return true
        for ctx in contexts {
            if QMK.IsCallable(ctx) {
                if ctx.Call()
                    return true
                continue
            }
            if QMK.ContextMatches(ctx)
                return true
        }
        return false
    }
    static ContextMatches(ctx) {
        ctx := String(ctx)
        negate := SubStr(ctx, 1, 1) = "!"
        if negate
            ctx := Trim(SubStr(ctx, 2))
        contextInfo := QMK.ParseContext(ctx)
        matched := contextInfo.type = QMK.CONTEXT_GLOBAL
        if !matched && contextInfo.type = QMK.CONTEXT_MENU
            matched := WinExist("ahk_class #32768") ? true : false
        if !matched
            matched := QMK.MatchesWindowContext(ctx, contextInfo.type)
        return negate ? !matched : matched
    }
    static ParseContext(context) {
        lowerContext := StrLower(String(context))
        if (context = "" || lowerContext = "global")
            return { type: QMK.CONTEXT_GLOBAL }
        if (context = "#32768" || context = "ahk_class #32768")
            return { type: QMK.CONTEXT_MENU }
        if QMK.ContextHasCompoundAhkCriteria(context)
            return { type: QMK.CONTEXT_COMPOUND }
        if InStr(lowerContext, "ahk_class")
            return { type: QMK.CONTEXT_CLASS }
        if (lowerContext = "browser" || lowerContext = "browsers")
            return { type: QMK.CONTEXT_BROWSER }
        if InStr(lowerContext, "ahk_exe")
            return { type: QMK.CONTEXT_EXE }
        if InStr(context, ".")
            return { type: QMK.CONTEXT_URL }
        return { type: QMK.CONTEXT_TITLE }
    }
    static ContextHasCompoundAhkCriteria(context) {
        lowerContext := StrLower(String(context))
        classPos := InStr(lowerContext, "ahk_class")
        exePos := InStr(lowerContext, "ahk_exe")
        if (!classPos && !exePos)
            return false
        tokenCount := (classPos ? 1 : 0) + (exePos ? 1 : 0)
        firstToken := classPos && exePos ? Min(classPos, exePos) : (classPos ? classPos : exePos)
        return tokenCount > 1 || Trim(SubStr(context, 1, firstToken - 1)) != ""
    }
    static MatchesWindowContext(context, contextType) {
        try {
            switch contextType {
                case QMK.CONTEXT_COMPOUND:
                    return WinActive(context) ? true : false
                case QMK.CONTEXT_BROWSER:
                    for criteria in QMK.browsers {
                        if WinActive(criteria)
                            return true
                    }
                    return false
                case QMK.CONTEXT_TITLE:
                    return InStr(WinGetTitle("A"), context) > 0
                case QMK.CONTEXT_CLASS:
                    normalized := Trim(StrReplace(context, "ahk_class"))
                    return InStr(WinGetClass("A"), normalized) > 0
                case QMK.CONTEXT_EXE:
                    normalized := Trim(StrReplace(context, "ahk_exe"))
                    return InStr(WinGetProcessName("A"), normalized) > 0
                case QMK.CONTEXT_URL:
                    return QMK.BrowserUrlContains(context)
            }
        }
        return false
    }
    static BrowserUrlContains(context) {
        try {
            if On.Website(context)
                return true
            if On.LastResult.inBrowser
                return InStr(On.LastResult.url, context) > 0
        }
        return false
    }
    static NormalizeHotkeyRow(entry) {
        if IsObject(entry) && entry.HasOwnProp("spec") {
            contexts := entry.HasOwnProp("context") ? entry.context : entry.HasOwnProp("contexts") ? entry.contexts : "global"
            callback := entry.HasOwnProp("callback") ? entry.callback : entry.HasOwnProp("action") ? entry.action : ""
            suspendExempt := entry.HasOwnProp("suspendExempt") ? !!entry.suspendExempt : QMK.CallbackIsSuspendExempt(callback)
            return { spec: entry.spec, contexts: contexts, callback: callback, suspendExempt: suspendExempt }
        }
        if !QMK.IsArrayLike(entry) || entry.Length < 2
            return false
        spec := entry[1]
        contexts := "global"
        callback := ""
        if (entry.Length == 2) {
            callback := entry[2]
        } else if (entry.Length == 3) {
            if QMK.RawValueLooksBool(entry[3]) {
                callback := entry[2]
            } else if QMK.IsCallable(entry[2]) {
                callback := entry[2]
            } else {
                contexts := entry[2]
                callback := entry[3]
            }
        } else {
            contexts := entry[2]
            callback := entry[3]
        }
        suspendExempt := entry.Length == 3 && QMK.RawValueLooksBool(entry[3]) ? !!entry[3] : entry.Length >= 4 ? !!entry[4] : QMK.CallbackIsSuspendExempt(callback)
        return { spec: spec, contexts: contexts, callback: callback, suspendExempt: suspendExempt }
    }
    static HotkeyCell(value) {
        if QMK.IsSendKeyDirectDescriptor(value)
            return { tag: 1, text: value.text, callbackId: -1, suspendExempt: false, boolCell: false, boolValue: false }
        if QMK.IsTapDescriptor(value) {
            action := value.action
            if QMK.IsSendKeyDirectDescriptor(action)
                return { tag: 4, text: action.text, callbackId: -1, suspendExempt: false, boolCell: false, boolValue: false }
            if QMK.IsCallable(action) {
                return { tag: 3, text: "", callbackId: QMK.RegisterRuntimeCallback(action), suspendExempt: QMK.CallbackIsSuspendExempt(action), boolCell: false, boolValue: false }
            }
            return { tag: 4, text: String(action), callbackId: -1, suspendExempt: false, boolCell: false, boolValue: false }
        }
        if QMK.IsCallable(value)
            return { tag: 2, text: "", callbackId: QMK.RegisterRuntimeCallback(value), suspendExempt: QMK.CallbackIsSuspendExempt(value), boolCell: false, boolValue: false }
        isBoolCell := !IsObject(value) && Type(value) != "String"
        return { tag: 1, text: QMK.IsArrayLike(value) ? QMK.ContextText(value) : String(value), callbackId: -1, suspendExempt: false, boolCell: isBoolCell, boolValue: isBoolCell ? !!value : false }
    }
    static HotkeyCellFlags(cell) {
        flags := cell.suspendExempt ? 1 : 0
        if (cell.HasOwnProp("boolCell") && cell.boolCell)
            flags := flags | 2 | (cell.boolValue ? 4 : 0)
        return flags
    }
    static HotkeyCellsFromRow(entry) {
        cells := []
        if IsObject(entry) && entry.HasOwnProp("spec") {
            action := entry.HasOwnProp("callback") ? entry.callback : entry.HasOwnProp("action") ? entry.action : ""
            if IsObject(action) && !QMK.IsCallable(action) && !QMK.IsTapDescriptor(action) && !QMK.IsSendKeyDirectDescriptor(action)
                return false
            cells.Push(QMK.HotkeyCell(entry.spec))
            if entry.HasOwnProp("context")
                cells.Push(QMK.HotkeyCell(entry.context))
            else if entry.HasOwnProp("contexts")
                cells.Push(QMK.HotkeyCell(entry.contexts))
            else
                cells.Push(QMK.HotkeyCell("global"))
            cells.Push(QMK.HotkeyCell(action))
            if entry.HasOwnProp("suspendExempt")
                cells.Push(QMK.HotkeyCell(entry.suspendExempt))
        } else {
            if !QMK.IsArrayLike(entry)
                return false
            actionIndex := entry.Length == 2 ? 2 : entry.Length == 3 && QMK.RawValueLooksBool(entry[3]) ? 2 : entry.Length >= 3 ? 3 : 0
            if (actionIndex > 0 && IsObject(entry[actionIndex]) && !QMK.IsCallable(entry[actionIndex]) && !QMK.IsTapDescriptor(entry[actionIndex]) && !QMK.IsSendKeyDirectDescriptor(entry[actionIndex]))
                return false
            for value in entry
                cells.Push(QMK.HotkeyCell(value))
        }
        return cells.Length >= 2 ? cells : false
    }
    static RawValueLooksBool(value) {
        if IsObject(value)
            return false
        if (Type(value) != "String")
            return true
        value := StrLower(Trim(value))
        return value = "0" || value = "1" || value = "true" || value = "false" || value = "yes" || value = "no" || value = "on" || value = "off"
    }
    static LooksLikeModPrefix(value) {
        if IsObject(value)
            return false
        text := String(value)
        Loop Parse text {
            if !InStr("^!+#", A_LoopField)
                return false
        }
        return true
    }
    static LooksLikeChordSendRow(entry) {
        if !QMK.IsArrayLike(entry) || entry.Length < 5 || entry.Length > 8
            return false
        keyCount := entry.Length - 3
        if (keyCount < 2 || keyCount > 5)
            return false
        if !QMK.LooksLikeModPrefix(entry[entry.Length])
            return false
        if IsObject(entry[entry.Length - 1]) || QMK.IsCallable(entry[entry.Length - 1])
            return false
        Loop keyCount {
            if IsObject(entry[A_Index])
                return false
        }
        return true
    }
    static SetupObjectAction(entry) {
        if entry.HasOwnProp("callback")
            return entry.callback
        if entry.HasOwnProp("target")
            return entry.target
        if entry.HasOwnProp("action")
            return entry.action
        return ""
    }
    static SetupActionValueIsValid(action, allowTapDescriptor := false) {
        return !IsObject(action) || QMK.IsCallable(action) || QMK.IsSendKeyDirectDescriptor(action) || (allowTapDescriptor && QMK.IsTapDescriptor(action))
    }
    static SetupObjectActionIsValid(entry, allowTapDescriptor := false) {
        return QMK.SetupActionValueIsValid(QMK.SetupObjectAction(entry), allowTapDescriptor)
    }
    static SplitHotkeyRowsByTransport(entries) {
        nativeEntries := []
        ahkRows := []
        for entry in entries {
            row := QMK.NormalizeHotkeyRow(entry)
            if !row
                return false
            if QMK.TapDescriptorHasHold(row.callback) && !QMK.ZigHotkeySpecCompatible(row.spec)
                return false
            if QMK.ZigHotkeySpecCompatible(row.spec)
                nativeEntries.Push(entry)
            else
                ahkRows.Push(row)
        }
        return { nativeEntries: nativeEntries, ahkRows: ahkRows }
    }
    static HotkeyNativeControlKind(action) {
        if IsObject(action)
            return ""
        normalized := StrLower(StrReplace(StrReplace(String(action), "_", ""), "-", ""))
        switch normalized {
            case "panicexit", "qmkpanicexit", "nativepanicexit":
                return "panicExit"
            case "nativereload", "qmknativereload":
                return "nativeReload"
            default:
                return ""
        }
    }
    static ConfigureNativeControlHotkeyRows(entries) {
        normalRows := []
        for rowIndex, entry in entries {
            row := QMK.NormalizeHotkeyRow(entry)
            if !row
                QMK.ThrowSetupRowError("SetupHotkeys", rowIndex, "invalid hotkey row", entry)
            switch QMK.HotkeyNativeControlKind(row.callback) {
                case "panicExit":
                    QMK.SetupPanicExitHotkey(row.spec)
                case "nativeReload":
                    QMK.SetupNativeReloadHotkey(row.spec, false)
                default:
                    normalRows.Push(entry)
            }
        }
        return normalRows
    }
    static RegisterAhkHotkeyRows(rows) {
        for row in rows {
            if !QMK.SetupAhkHotkey(row.spec, row.contexts, row.callback)
                return false
        }
        return true
    }
    static SetupHotkeys(entries) {
        QMK.BeginSetup()
        try {
            entries := QMK.NormalizeSetupRows(entries)
            entries := QMK.ConfigureNativeControlHotkeyRows(entries)
            split := QMK.SplitHotkeyRowsByTransport(entries)
            if !split
                throw Error("QMK.SetupHotkeys failed while splitting native/AHK rows.")
            entries := split.nativeEntries
            nativeOk := entries.Length == 0 ? true : QMK.SetupHotkeysCompat(entries)
            return nativeOk && QMK.RegisterAhkHotkeyRows(split.ahkRows)
        } finally {
            QMK.EndSetup()
        }
    }
    static SetupHotkeysCompat(entries) {
        proc := QMK.Proc("QMK_SetupHotkeyEntries")
        rows := []
        totalTextChars := 0
        nativeCount := 0
        for rowIndex, entry in entries {
            row := QMK.NormalizeHotkeyRow(entry)
            if !row
                QMK.ThrowSetupRowError("SetupHotkeys", rowIndex, "invalid hotkey row", entry)
            contextText := QMK.ContextText(row.contexts)
            callback := row.callback
            directAction := QMK.IsSendKeyDirectDescriptor(callback)
            actionKind := QMK.IsTapDescriptor(callback) ? 1 : 0
            action := actionKind ? callback.action : directAction ? callback.text : callback
            holdCallback := actionKind ? callback.holdCallback : ""
            cleanupCallback := actionKind ? callback.cleanupCallback : ""
            thresholdMs := actionKind ? callback.thresholdMs : 0
            if QMK.IsSendKeyDirectDescriptor(action)
                action := action.text
            if IsObject(action) && !QMK.IsCallable(action)
                QMK.ThrowSetupRowError("SetupHotkeys", rowIndex, "action is an object but not callable", entry)
            isNative := !IsObject(action)
            nativeText := isNative ? String(action) : ""
            callbackId := -1
            holdCallbackId := QMK.RuntimeCallbackId(holdCallback)
            cleanupCallbackId := QMK.RuntimeCallbackId(cleanupCallback)
            suspendExempt := row.suspendExempt
            if isNative {
                nativeCount++
            } else {
                callbackId := QMK.RegisterRuntimeCallback(action)
                suspendExempt := suspendExempt || QMK.CallbackIsSuspendExempt(action)
            }
            suspendExempt := suspendExempt
                || QMK.CallbackIsSuspendExempt(holdCallback)
                || QMK.CallbackIsSuspendExempt(cleanupCallback)
            rows.Push({ spec: String(row.spec), context: contextText, actionText: nativeText, callbackId: callbackId, holdCallbackId: holdCallbackId, cleanupCallbackId: cleanupCallbackId, thresholdMs: Round(thresholdMs), suspendExempt: suspendExempt, isNative: isNative, actionKind: actionKind })
            totalTextChars += StrLen(row.spec) + StrLen(contextText) + (isNative ? StrLen(nativeText) + 1 : 0)
        }
        recordSize := 44
        recordBuf := Buffer(Max(1, rows.Length * recordSize), 0)
        textBuf := Buffer(Max(2, (totalTextChars + 1) * 2), 0)
        textOffset := 0
        for i, row in rows {
            off := (i - 1) * recordSize
            specLen := StrLen(row.spec)
            ctxLen := StrLen(row.context)
            actionLen := StrLen(row.actionText)
            NumPut("UInt", textOffset, recordBuf, off)
            NumPut("UShort", specLen, recordBuf, off + 4)
            if specLen > 0
                StrPut(row.spec, textBuf.Ptr + textOffset * 2, specLen + 1, "UTF-16")
            textOffset += specLen
            NumPut("UInt", textOffset, recordBuf, off + 8)
            NumPut("UShort", ctxLen, recordBuf, off + 12)
            if ctxLen > 0
                StrPut(row.context, textBuf.Ptr + textOffset * 2, ctxLen + 1, "UTF-16")
            textOffset += ctxLen
            NumPut("UInt", textOffset, recordBuf, off + 16)
            NumPut("UShort", actionLen, recordBuf, off + 20)
            if actionLen > 0
                StrPut(row.actionText, textBuf.Ptr + textOffset * 2, actionLen + 1, "UTF-16")
            textOffset += actionLen + (row.isNative ? 1 : 0)
            NumPut("Int", row.callbackId, recordBuf, off + 24)
            NumPut("UChar", row.suspendExempt ? 1 : 0, recordBuf, off + 28)
            NumPut("UChar", row.isNative ? 1 : 0, recordBuf, off + 29)
            NumPut("UChar", row.actionKind, recordBuf, off + 30)
            NumPut("Int", row.holdCallbackId, recordBuf, off + 32)
            NumPut("Int", row.cleanupCallbackId, recordBuf, off + 36)
            NumPut("Int", row.thresholdMs, recordBuf, off + 40)
        }
        loaded := DllCall(proc, "Ptr", recordBuf.Ptr, "UInt", rows.Length, "Ptr", textBuf.Ptr, "UInt", textOffset, "Int")
        if (loaded != rows.Length)
            QMK.ThrowSetupInstallError("SetupHotkeys", loaded, rows.Length, entries[loaded + 1])
        return true
    }
    static NoModifiers() {
        return DllCall(QMK.Proc("QMK_NoModifiersHeld"), "Int")
    }
    static Tap(tapAction, holdCallback := "", thresholdMs := 0, cleanupCallback := "") {
        if (A_ThisHotkey = "" && holdCallback = "" && thresholdMs = 0 && cleanupCallback = "")
            return QMKTapDescriptor(tapAction)
        if (A_ThisHotkey = "")
            return QMKTapDescriptor(tapAction, holdCallback, thresholdMs, cleanupCallback)
        key := StrReplace(StrReplace(StrReplace(StrReplace(A_ThisHotkey, "~", ""), " up", ""), "$", ""), "*", "")
        directThresholdMs := thresholdMs > 0 ? thresholdMs : 200
        isHold := !KeyWait(key, "T" . (Max(1, Round(directThresholdMs)) / 1000))
        KeyWait(key)

        if isHold {
            if (holdCallback != "")
                QMK.InvokeCallback(holdCallback)
            if (cleanupCallback != "")
                QMK.InvokeCallback(cleanupCallback)
        } else {
            if IsObject(tapAction)
                QMK.InvokeCallback(tapAction)
            else {
                if (Type(tapAction) != "String" || tapAction = "")
                    return
                vk := QMK.GetVK(tapAction)
                if (vk != 0)
                    DllCall(QMK.Proc("QMK_SendKeyDirectFromDLL"), "Int", vk, "Int", 0)
                else
                    SendEvent("{" . tapAction . "}")
            }
        }
    }
}

class QMKRuntimeControls extends QMKTextAndHotkeyAPIs {
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
        if !QMK.allowAhkKeyhooks
            return false
        Suspend(true)

        ; --- Physical modifiers: suppress in AHK and immediately hand every
        ;     down/up event to the same Zig QMK_ProcessKeyEvent path used by
        ;     regular keys.  Do NOT use ~ here: the fallback input layer owns
        ;     the physical stroke, and Zig decides what is emitted.
        if !QMK.registeredMods {
            static modHotkeys := [
                ["LCtrl", 0xA2], ["RCtrl", 0xA3],
                ["LAlt", 0xA4], ["RAlt", 0xA5],
                ["LShift", 0xA0], ["RShift", 0xA1],
                ["LWin", 0x5B], ["RWin", 0x5C],
            ]

            for entry in modHotkeys {
                key := entry[1]
                vk := entry[2]
                keyDown := ((resolvedVK) => (*) => QMK.OnKeyDown(resolvedVK))(vk)
                keyUp := ((resolvedVK) => (*) => QMK.OnKeyUp(resolvedVK))(vk)
                try {
                    Hotkey("$*" . key, keyDown, "I2")
                    Hotkey("$*" . key . " up", keyUp, "I2")
                }
            }
            QMK.registeredMods := true
        }

        ; --- Regular keys (InputLevel 2, suppressed via $*) ---
        for key in QMK.allKeys {
            if !QMK.registeredKeys.Has(key) {
                ; QMK_ProcessKeyEvent expects a numeric VK. Resolve the AHK key
                ; name once at registration time so the per-event fallback path
                ; stays numeric and does not perform a string->VK DLL lookup.
                vk := QMK.GetVK(key)
                if (vk == 0)
                    continue

                keyDown := ((resolvedVK) => (*) => QMK.OnKeyDown(resolvedVK))(vk)
                keyUp := ((resolvedVK) => (*) => QMK.OnKeyUp(resolvedVK))(vk)
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

        ; --- Physical modifiers ---
        if QMK.registeredMods {
            static modHotkeys := [
                "LCtrl", "RCtrl", "LAlt", "RAlt",
                "LShift", "RShift", "LWin", "RWin",
            ]
            for key in modHotkeys {
                try {
                    Hotkey("$*" . key, "Off")
                    Hotkey("$*" . key . " up", "Off")
                }
            }
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
        if tooltips {
            ToolTip("QMK Emergency Reset!")
            SetTimer(() => ToolTip(), -2000)
        }
        ; Install LL hook if requested â€” falls back silently if it fails
        ; if (QMK.userconfig.useLLHook) {
        ;     DllCall(QMK.Proc("QMK_InstallLLHook"))
        ;     }
    }

    static EmergencyExit() {
        if proc := QMK.ProcOptional("QMK_EmergencyExit")
            DllCall(proc)
        ExitApp()
    }

    static SetupPanicExitHotkey(hotkeySpec := "*#Escape") {
        if !DllCall(QMK.Proc("QMK_SetPanicExitHotkeyEntry"), "Str", String(hotkeySpec), "Int", 1, "Int")
            throw Error("QMK panic exit hotkey must be a native-loadable keyboard hotkey", , hotkeySpec)
        return true
    }

    static SetupNativeReloadHotkey(hotkeySpec := "*^+r", registerAhkFallback := true) {
        if !DllCall(QMK.Proc("QMK_SetNativeReloadHotkeyEntry"), "Str", String(hotkeySpec), "Int", 1, "Int")
            throw Error("QMK native reload hotkey must be a native-loadable keyboard hotkey", , hotkeySpec)
        if registerAhkFallback
            try Hotkey(String(hotkeySpec), (*) => QMK.NativeReload(), "I2")
        return true
    }

    static NativeReload() {
        static lastReloadTick := 0
        now := A_TickCount
        if (now - lastReloadTick < 750)
            return
        lastReloadTick := now
        QMK.EmergencyReset(false)
        ahkPath := A_AhkPath
        if InStr(ahkPath, "_UIA")
            ahkPath := StrReplace(ahkPath, "_UIA")
        Run('"' ahkPath '" "' A_ScriptFullPath '"', A_ScriptDir)
        ExitApp()
    }

    static Suspend(state?) {
        if IsSet(state) {
            value := state ? 1 : 0
            if proc := QMK.ProcOptional("QMK_SetRuntimeHotkeysSuspended")
                value := DllCall(proc, "Int", value, "Int")
        } else if proc := QMK.ProcOptional("QMK_ToggleRuntimeHotkeysSuspended") {
            value := DllCall(proc, "Int")
        } else {
            return false
        }
        Suspend(value ? true : false)
        ToolTip("QMK " (value ? "Suspended" : "Resumed"))
        SetTimer(() => ToolTip(), -900)
        return value
    }

    static IsSuspended() {
        return (proc := QMK.ProcOptional("QMK_GetRuntimeHotkeysSuspended")) ? DllCall(proc, "Int") : false
    }

}

/*

QMKInterception User API
========================

This is the part most scripts should use. The goal is to keep your AutoHotkey
code easy to read while Zig does the fast work: context matching, active-row
selection, suppression, native paste/send payloads, and key-gate rebuilds.

Contexts are plain strings. Use "global" for a fallback row, or use the same
strings you already use in AHK:

    "ahk_exe Code.exe"
    "ahk_class #32768"
    "youtube.com"
    "Some Window Title"

Most rows use this shape:

    key fields, context, action, optional mode/options

Use QMK.SendKeyDirect("...") when the action is just sending keys. That lets
the DLL send through the active QMK send path without bouncing back into AHK:

    QMK.SendKeyDirect("^{Left}")
    QMK.SendKeyDirect("{Enter}")
    QMK.SendKeyDirect("b", "^+")       ; Ctrl+Shift+B

For real startup blocks, prefer plural APIs. They send one batch into Zig so the
native side can rebuild once instead of once per shortcut:

    QMK.SetupModifiers([
        ["a", "Ctrl"],
        ["s", "Shift", "global"],
        { key: "CapsLock", modifier: "Ctrl", context: "ahk_exe Code.exe" }
    ])

    QMK.SetupHolds([
        ["e", "global", (*) => edge.activate(true)],
        { key: "f", context: "global", callback: (*) => globals.activaterun("ChatGPT") }
    ])

    QMK.SetupHotkeys([
        ["*#Escape", "global", "panicExit", true],
        ["*^+r", "global", "nativeReload", true],
        ["^Space", "global", (*) => globals.togglealwaysontop()],
        ["!h", "global", QMK.SendKeyDirect("{Left}")]
    ])

    QMK.SetupTaps([
        ["h", "Med School - Anki", QMK.SendKeyDirect("1")],
        ["j", "Med School - Anki", QMK.SendKeyDirect("2")],
        ["k", "Med School - Anki", QMK.SendKeyDirect("4")],
        ["l", "Med School - Anki", QMK.SendKeyDirect("{Enter}")],
        ["a", "Med School - Anki", QMK.SendKeyDirect("1"), (*) => anki.activate(true)]
    ])

    QMK.SetupTap("h", QMK.SendKeyDirect("1"))
    QMK.SetupTap("l", "Med School - Anki", QMK.SendKeyDirect("{Enter}"))
    QMK.SetupTap({ key: "CapsLock", context: "global", tap: QMK.SendKeyDirect("{Esc}") })

    QMK.SetupCombos([
        ["f", "u", "global", QMK.SendKeyDirect("{Browser_Back}")],
        ["a", "h", "global", QMK.SendKeyDirect("^{Left}")],
        ["a", ";", "global", QMK.SendKeyDirect("{Backspace}"), "instant"],
        { primary: "v", secondary: "m", context: "global", mode: "instant", callback: (*) => media.volume.mute() },
        { primary: "x", secondary: "c", context: "global", action: QMK.SendKeyDirect("c", "^") }
    ])

    QMK.SetupChords([
        ["a", "s", "l", "global", QMK.SendKeyDirect("^+{Right}")],
        ["a", "s", "d", "l", "global", (*) => VDA.GoRight()],
        { keys: ["a", "s", "d", "f", "o"], context: "global", callback: (*) => outlookdesktop.activate(true) }
    ])

    QMK.SetupDoubleTaps([
        ["LCtrl", "outlook.live.com", (*) => outlookdesktop.activate(true)]
    ])

    QMK.SetupTapHolds([
        ["Space", "global", 175, (*) => Send(" "), (*) => ShowMenuWithDigits(MenuMap["default"])],
        { key: "CapsLock", context: "global", thresholdMs: 175, tap: (*) => Send("{Esc}"), hold: (*) => ShowMenuWithDigits(MenuMap["default"]) }
    ])

    QMK.SetupHotstrings([
        [":*:addr", "global", "123 Example Street"],
        [":*:sig", "ahk_exe OUTLOOK.EXE", (*) => PasteEmailSignature()]
    ])

Callback versus native-send rule of thumb:

    (*) => SomeAhkFunction()       callback to AHK
    QMK.SendKeyDirect("...")       native send from Zig/DLL

Combos and chords can still take "instant" as the optional final flag when you
want them to fire as soon as QMK recognizes the key group. For native-send
actions, QMK.SendKeyDirect("...") is the preferred public syntax.

QMK.SetupTaps(...) is the family for 1:1 tap remaps. Use it when a single key
should send/call something on tap while still letting hold behavior fall back
through QMK. For simple key sends, use QMK.SendKeyDirect(...) in the tap row so
the send stays in the native QMK path.

QMK.Tap(...) remains available for one-off hotkey rows when you do not want to
make a separate tap family:

    QMK.SetupHotkeys([
        ["l", "Med School - Anki", QMK.Tap("{Enter}")]
    ])

Tap row shapes:

    [key, QMK.SendKeyDirect(tapAction)]
    [key, context, QMK.SendKeyDirect(tapAction)]
    [key, context, QMK.SendKeyDirect(tapAction), holdCallback]
    [key, context, QMK.SendKeyDirect(tapAction), holdCallback, thresholdMs]

The object shape is also supported:

    { key: "l", context: "Med School - Anki", tap: QMK.SendKeyDirect("{Enter}") }
    { key: "a", context: "Med School - Anki", tap: QMK.SendKeyDirect("1"), hold: (*) => anki.activate(true), thresholdMs: 175 }
    QMK.SetupTap({ key: "CapsLock", context: "global", tap: QMK.SendKeyDirect("{Esc}") })

If thresholdMs is omitted or 0, the core uses the configured hold timing where
applicable.

Suspension defaults to false for setup rows. Pass true as the final value, or
use a row property named suspendExempt, only for commands that should keep
working while QMK is suspended.

*/

class QMK extends QMKRuntimeControls {
    static __New() {
        QMK.Init()
    }
}
