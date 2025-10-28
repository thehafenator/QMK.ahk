#Requires AutoHotkey v2.0
#SingleInstance Force


; ProcessSetPriority("High")  ; Turn this on if noticing delay to prioritize the script Options: Low, BelowNormal, Normal, AboveNormal, High, Realtime. Realtime can make things unstable.
; Additional options you can try to turn on if running on an older piece of hardware. I haven't had issues though with this script with my computer's settings at near zero, but here in case. It is fairly lightweight
; SetKeyDelay(-1, 0)
; SetDefaultMouseSpeed(0)
; SetMouseDelay(0)
; SetControlDelay(-1)
; SetWinDelay(-1)
; SetControlDelay(-1)
; A_HotkeyInterval := 2000 
; A_MaxHotkeysPerInterval := 200


class QMK {
    ; User configuration section
    static userconfig := {
        timingMode: "accurate", ; "accurate" or "fast". I reccommend "accurate", which will be more reliable under heavy system load or in energy saver mode. 'Fast' uses A_tickcount, but can be slightly innacurate
        holdThreshold: 150, ; default 150-200 ms. Shorter means that 'setupholds', and other methods with this logic will work sooner, but may cause accidental triggering if too short
        maxBufferSize: 50, ; maximum amount of keys that can exist in the buffer at once. Default is 50 for a higher cieling, but most people won't ever have more than 4-5 keys at a time
        comboQuietPeriod: 150, ; for normal combo keys, this is the amount of time in ms that are needed before a combo will work. Avoids combos triggering when normally. Default 150, lower if needed  typing
        modifierThreshold: 200, ; When 'stacking' modifiers, this is the number of milliseconds a modifier must be pressed within last most recent one. Default 200, but increase as needed
        maxHoldTime: 1000, ; Threshold in ms for maximumhold time in ms. Default is 1000 ms, or 1 second. Keys held past this time are marked to either be supressed (if maxholdsupresskeys is true, which is the default), or marked to tap once lifted up (maxholdsupresses keys false), meaning the keys will type out one at a time upon release past the threshold. 
        maxholdsupresseskeys: true,   ; If true, keys held past maxHoldTime are suppressed (will not be sent. Usefull for when you press keys that will trigger an action that you don't want to do.  (not tapped)
    }

    ; Core data structures
    static keyBuffer := Map()
    static keyOrder := []
    static holdCallbacks := Map()
    static comboCallbacks := Map()
    static instantComboCallbacks := Map()
    static comboPrimaries := Map()
    static instantComboPrimaries := Map()
    static activeTimers := Map()
    static needsState := Map()
    static registeredKeys := Map()
    static lastKeyTime := 0
    static isTypingMode := false

    ; Homerow modifier structures
    static modifierKeys := Map()
    static activeModifiers := Map()
    static sameModifierKeys := Map()

    ; Modifier tracking
    static modifierBitmask := 0
    static modifierMap := Map(
        "CapsLock", 1, "Ctrl", 2, "Alt", 4, "LWin", 8,
        "RWin", 16, "Shift", 32, "RShift", 64
    )
    static modifierSet := Map()

    ; Context priority constants
    static CONTEXT_MENU := 1
    static CONTEXT_URL := 2
    static CONTEXT_TITLE := 3
    static CONTEXT_CLASS := 4
    static CONTEXT_BROWSER := 5
    static CONTEXT_EXE := 6
    static CONTEXT_GLOBAL := 7

    static allKeys := ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
        "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
        "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
        "Enter", "Backspace", "Delete", "Space", "Tab",
        ";", "'", ",", ".", "/", "[", "]", "\", "-", "=",
        "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"] ; add more keys here if the order you press them is important/you want to add shortcuts to them

    static browsers := [ ; hold keys can have specific contexts that they work in. For example, QMK.SetupHold("a", ["global"], (*) => myfunction()). Add more browsers here if needed
        "ahk_class Chrome_WidgetWin_1 ahk_exe chrome.exe",
        "ahk_class Chrome_WidgetWin_1 ahk_exe msedge.exe",
        "ahk_class MozillaWindowClass ahk_exe firefox.exe",
        "ahk_class Chrome_WidgetWin_1 ahk_exe thorium.exe",
        "ahk_class Chrome_WidgetWin_1 ahk_exe floorp.exe"
    ]

    static freq := 0

    static __New() { ; upon load, this method will load all user defined hotkeys/settings into memory for use.
        for modKey in this.modifierKeys
            this.modifierSet[modKey] := true
        DllCall("QueryPerformanceFrequency", "Int64*", &freq := 0)
        this.freq := freq
        this.RegisterAllKeys()
        cfg := this.userconfig
        this.holdThreshold := cfg.holdThreshold
        this.maxHoldTime := cfg.maxHoldTime
        this.maxBufferSize := cfg.maxBufferSize
        this.comboQuietPeriod := cfg.comboQuietPeriod
        this.modifierThreshold := cfg.modifierThreshold
    }

    ; ============================================================================
    ; TIMING
    ; ============================================================================

    static GetTime() { ; tracks time to microsecond for accuracy by default.
        if (this.userconfig.timingMode == "accurate") {
            DllCall("QueryPerformanceCounter", "Int64*", &counter := 0)
            return (counter / this.freq) * 1000
        } else {
            return A_TickCount
        }
    }

    ; ============================================================================
    ; MAIN KEY HANDLERS
    ; ============================================================================
; For each key that is pressed down, it must go through 3 main methods - bufferkeydown, bufferkeyup, and process queue to determine if the key(s) already down and currently being pressed/released are normal typing, instantcombos, combos, modifiers, partnermodifiers (two keys both with the same modifier), for the appropriate action to occur. The order of these three methods is important for functionality. These functions have gone through over 70 changes to fine tune all desired functionality, so feel free to tweak if you want to add functionality, but know even small changes could break funcionatliy elsewhere.  
  
static BufferKeyDown(key) { 
    if (this.keyBuffer.Has(key) && !this.keyBuffer[key].isReleased) {
        return  ; Ignore repeat down events
    }

    currentTime := this.GetTime()

    ; Check if we're in quiet period (typing burst)
    inQuietPeriod := (currentTime - this.lastKeyTime) < this.comboQuietPeriod
    this.lastKeyTime := currentTime

    ; UP STAGE 1: Traditional modifiers bypass - when pressing a normal modier (such as the left physical control button), these shortcuts work fast and also clear the buffer. Press a traditional modifier if your buffer ever gets stuck
    if (this.modifierSet.Has(key)) {
        if (this.modifierMap.Has(key)) {
            this.modifierBitmask |= this.modifierMap[key]
            this.ClearBuffer()
        }
        return
    }

    ; UP STAGE 2: Traditional modifiers active - bypass buffering
    if (this.modifierBitmask > 0) {
        for bufferedKey, data in this.keyBuffer
            data.modifierPressed := true
        SendLevel 2
        SendEvent("{" . key . "}")
        return
    }

    ; Count unreleased modifiers for combo blocking
    unreleasedModifierCount := 0
    for buffKey, buffData in this.keyBuffer {
        if (buffData.isModifier && !buffData.isReleased) {
            unreleasedModifierCount++
        }
    }

    ; UP STAGE 2.5: Check INSTANT combos first (always, even during quiet period)
    for buffKey, buffData in this.keyBuffer {
        if (buffData.isReleased)
            continue

        comboId := buffKey . "_" . key
        if (this.instantComboCallbacks.Has(comboId)) {
            this.TriggerInstantCombo(buffKey, key)
            return
        }
    }

    ; UP STAGE 2.6: Check if primary is in combo repeat mode - allows a combo like QMK.SetupCombo("a", "g", (*) => Send("!{Tab}")) to press the a key first hold it down, then press 'g' repeatedly.
    if (unreleasedModifierCount < 2) {
        for buffKey, buffData in this.keyBuffer {
            if (!buffData.inComboRepeatMode || buffData.isReleased)
                continue

            comboId := buffKey . "_" . key
            if (this.comboCallbacks.Has(comboId)) {
                ; Primary still held in combo mode, secondary is being repeated
                this.TriggerComboImmediate(buffKey, key) ; logic to trigger callback supported here
                return
            }
        }
    }

    ; UP STAGE 2.65: Check for regular combos BEFORE quiet period buffering
    hasRegisteredCombo := false
    if (unreleasedModifierCount < 2) {
        for buffKey, buffData in this.keyBuffer {
            if (buffData.isReleased || buffData.hasInterferingKeys)
                continue

            comboId := buffKey . "_" . key
            if (this.comboCallbacks.Has(comboId)) {
                hasRegisteredCombo := true
                break
            }
        }
    }

    ; NEW STAGE 2.66: Check for regular combos with unreleased keys during quiet period
    if (hasRegisteredCombo) {
        for buffKey, buffData in this.keyBuffer {
            if (buffData.isReleased)
                continue

            comboId := buffKey . "_" . key
            if (!this.comboCallbacks.Has(comboId))
                continue

            ; Found combo - buffer secondary and set timer
            this.keyBuffer[key] := {
                downTime: currentTime,
                hasInterferingKeys: false,
                isReleased: false,
                comboTriggered: false,
                modifierPressed: false,
                isModifier: false,
                modifierActivated: false,
                modifierTriggered: false,
                inComboRepeatMode: false,
                action: "",
                sameModTimerId: "",
                inQuietPeriod: inQuietPeriod
            }
            this.keyOrder.Push(key)

            elapsed := currentTime - buffData.downTime

            if (elapsed >= this.holdThreshold) {
                timeSinceLastKey := currentTime - this.lastKeyTime
                if (timeSinceLastKey >= this.comboQuietPeriod) {
                    this.TriggerComboImmediate(buffKey, key)
                    return
                }
                delay := this.comboQuietPeriod
            } else {
                delay := this.holdThreshold - elapsed + this.comboQuietPeriod
            }

            timerFunc := ObjBindMethod(this, "TriggerComboWithQuietCheck", buffKey, key, currentTime)
            timerId := buffKey . "_" . key
            this.activeTimers[timerId] := timerFunc
            SetTimer(timerFunc, -delay)

            return
        }
    }

    ; UP STAGE 2.7: If in quiet period, ALWAYS buffer (typing takes priority unless intentional chord or registered combo). Useful for typing normal words. For example, the word 'please' often has keyboard rolls and homerow keys that are modifiers. This checks that if we are typing, we mark those as tap
    if (inQuietPeriod && !hasRegisteredCombo) {
        ; Check for non-modifier keys in buffer (indicates typing)
        hasNonModifierKeys := false
        for buffKey, buffData in this.keyBuffer {
            if (!buffData.isModifier) {
                hasNonModifierKeys := true
                break
            }
        }

        ; Set typing mode if non-modifier key pressed during quiet period
        if (!this.modifierKeys.Has(key)) {
            this.isTypingMode := true
        }

        ; Calculate clean unreleased modifier count (skip contaminated)
        cleanUnreleasedModCount := 0
        for buffKey, buffData in this.keyBuffer {
            if (buffData.isModifier && !buffData.isReleased && !buffData.hasInterferingKeys) {
                cleanUnreleasedModCount++
            }
        }

        ; Check if this is an intentional multi-mod chord
        isIntentionalChord := (cleanUnreleasedModCount >= 2 && !hasNonModifierKeys && !this.isTypingMode)

        if (isIntentionalChord) {
            ; Check if new key is same-mod partner
            isSameModPartner := false
            if (this.modifierKeys.Has(key)) {
                newModName := this.modifierKeys[key]
                for buffKey, buffData in this.keyBuffer {
                    if (buffData.isModifier && !buffData.isReleased && this.modifierKeys[buffKey] == newModName) {
                        isSameModPartner := true
                        break
                    }
                }
            }

            ; If NOT a modifier OR is same-mod partner, activate all clean mods and send
            if (!this.modifierKeys.Has(key) || isSameModPartner) { ; this line either doesn't trigger the full 'ash' or the 'sh' or 'ah' for shift h or ^h timers are still going, because pressing ash (h non-modifier) does not trigger full
                for buffKey, buffData in this.keyBuffer {
                    if (buffData.isModifier && !buffData.isReleased && !buffData.modifierActivated && !buffData.hasInterferingKeys) {
                        ; Cancel any pending timers for this modifier
                        for timerId, timerFunc in this.activeTimers.Clone() {
                            if (InStr(timerId, buffKey . "_")) {
                                SetTimer(timerFunc, 0)
                                this.activeTimers.Delete(timerId)
                            }
                        }

                        this.activeModifiers[buffKey] := true
                        buffData.modifierActivated := true
                    }
                }

                this.SendModifiedKey(key)

                for buffKey, buffData in this.keyBuffer {
                    if (buffData.isModifier && !buffData.isReleased) {
                        buffData.modifierTriggered := true
                    }
                }

                return
            }
        }

        ; Determine if we should contaminate (force taps)
        shouldContaminate := hasNonModifierKeys || !this.modifierKeys.Has(key) || this.isTypingMode

        if (shouldContaminate) {
            ; Cancel ALL active timers - we're in typing mode
            for timerId, timerFunc in this.activeTimers.Clone() {
                SetTimer(timerFunc, 0)
                this.activeTimers.Delete(timerId)
            }

            ; Contaminate all existing keys AND clear their timer references
            for bufferedKey, data in this.keyBuffer {
                data.hasInterferingKeys := true
                data.sameModTimerId := ""  ; Clear timer references
            }
        }

        isHomerowModifier := this.modifierKeys.Has(key)

        this.keyBuffer[key] := {
            downTime: currentTime,
            hasInterferingKeys: shouldContaminate,
            isReleased: false,
            comboTriggered: false,
            modifierPressed: false,
            isModifier: isHomerowModifier,
            modifierActivated: false,
            modifierTriggered: false,
            inComboRepeatMode: false,
            action: "",
            sameModTimerId: "",
            inQuietPeriod: inQuietPeriod
        }

        this.keyOrder.Push(key)

        if (this.keyOrder.Length > this.maxBufferSize) {
            oldKey := this.keyOrder.RemoveAt(1)
            if (this.keyBuffer.Has(oldKey))
                this.keyBuffer.Delete(oldKey)
        }
        return  ; ALWAYS return during quiet period
    }



    ; UP STAGE 3: Check active homerow modifiers - Allows us to press multiple keys that are modifiers and 'stack' them instantly for quick sending other keys
    activeModifierCount := 0
    for modKey, _ in this.activeModifiers {
        activeModifierCount++
    }

    ; UP STAGE 3.5: Check for instant combos with any unreleased key
    unreleasedCount := 0
    for buffKey, buffData in this.keyBuffer {
        if (!buffData.isReleased) {
            unreleasedCount++
        }
    }
    if (unreleasedCount == 1) {
        for buffKey, buffData in this.keyBuffer {
            if (buffData.isReleased)
                continue

            comboId := buffKey . "_" . key
            if (this.instantComboCallbacks.Has(comboId)) {
                this.TriggerInstantCombo(buffKey, key)
                return
            }
        }
    }

    ; UP STAGE 3.75: Check for multiple unreleased modifiers past threshold ; 
    unreleasedModsPastThreshold := []
    for buffKey, buffData in this.keyBuffer {
        if (!buffData.isModifier || buffData.isReleased)
            continue

        elapsed := currentTime - buffData.downTime
        if (elapsed >= this.holdThreshold) {
            unreleasedModsPastThreshold.Push(buffKey)
        }
    }

    ; If we have 2+ modifiers past threshold, activate them all and send modified key
    if (unreleasedModsPastThreshold.Length >= 2) {
        for modKey in unreleasedModsPastThreshold {
            if (!this.activeModifiers.Has(modKey)) {
                this.activeModifiers[modKey] := true
                this.keyBuffer[modKey].modifierActivated := true
            }
        }

        this.SendModifiedKey(key)

        for modKey in unreleasedModsPastThreshold {
            this.keyBuffer[modKey].modifierTriggered := true
        }

        return
    }

    ; UP STAGE 4: Active homerow modifiers present
    if (activeModifierCount > 0) {
        ; Check instant combos FIRST (before modifier stacking) but only for single modifier
        if (activeModifierCount == 1) {
            for modKey, _ in this.activeModifiers {
                comboId := modKey . "_" . key
                if (this.instantComboCallbacks.Has(comboId)) {
                    if (this.keyBuffer.Has(modKey) && !this.keyBuffer[modKey].isReleased) {
                        this.TriggerInstantCombo(modKey, key)
                        return
                    }
                }
            }
        }

        ; Check regular combos (Combo Supremacy) but only for single modifier
        if (activeModifierCount == 1) {
            for modKey, _ in this.activeModifiers {
                comboId := modKey . "_" . key
                if (this.comboCallbacks.Has(comboId)) {
                    if (this.keyBuffer.Has(modKey) && !this.keyBuffer[modKey].isReleased) {
                        this.TriggerComboImmediate(modKey, key)
                        return
                    }
                }
            }
        }

        ; New key is also a modifier - check for combo FIRST before stacking
        if (this.modifierKeys.Has(key)) {
            ; Check if there's a combo registered with any active modifier
            for modKey, _ in this.activeModifiers {
                comboId := modKey . "_" . key
                if (this.comboCallbacks.Has(comboId)) {
                    if (this.keyBuffer.Has(modKey) && !this.keyBuffer[modKey].isReleased) {
                        this.TriggerComboImmediate(modKey, key)
                        return
                    }
                }
            }

            ; No combo - proceed with stacking logic
            newModType := this.modifierKeys[key]
            modTypeAlreadyActive := false
            for modKey, _ in this.activeModifiers {
                if (this.modifierKeys[modKey] == newModType) {
                    modTypeAlreadyActive := true
                    break
                }
            }
            if (modTypeAlreadyActive) {
                this.SendModifiedKey(key)
                for modKey, _ in this.activeModifiers {
                    if (this.keyBuffer.Has(modKey)) {
                        this.keyBuffer[modKey].modifierTriggered := true
                    }
                }
                return
            }
            this.activeModifiers[key] := true
            if (this.keyBuffer.Has(key)) {
                this.keyBuffer[key].isModifier := true
                this.keyBuffer[key].modifierActivated := true
            } else {
                this.keyBuffer[key] := {
                    downTime: currentTime,
                    hasInterferingKeys: false,
                    isReleased: false,
                    comboTriggered: false,
                    modifierPressed: false,
                    isModifier: true,
                    modifierActivated: true,
                    modifierTriggered: false,
                    inComboRepeatMode: false,
                    action: "",
                    sameModTimerId: "",
                    inQuietPeriod: inQuietPeriod
                }
                this.keyOrder.Push(key)
            }
            return
        }

        ; Multiple modifiers OR regular key with modifiers
        if (activeModifierCount > 1) {
            this.SendModifiedKey(key)
            for modKey, _ in this.activeModifiers {
                if (this.keyBuffer.Has(modKey)) {
                    this.keyBuffer[modKey].modifierTriggered := true
                }
            }
            return
        }

        ; No combo - send as modified key
        this.SendModifiedKey(key)
        for modKey, _ in this.activeModifiers {
            if (this.keyBuffer.Has(modKey)) {
                this.keyBuffer[modKey].modifierTriggered := true
            }
        }
        return
    }

    ; UP STAGE 5: Check for held keys past threshold (Fast path for modifiers/combos)
    if (unreleasedModifierCount < 2) {
        for buffKey, buffData in this.keyBuffer {
            if (buffData.isReleased)
                continue

            elapsed := currentTime - buffData.downTime
            if (elapsed < this.holdThreshold)
                continue

            ; Check instant combos FIRST
            comboId := buffKey . "_" . key
            if (this.instantComboCallbacks.Has(comboId)) {
                this.TriggerInstantCombo(buffKey, key)
                return
            }

            ; Modifier past threshold - check for combo FIRST (before modifier activation)
            if (buffData.isModifier) {
                if (this.comboCallbacks.Has(comboId)) {
                    this.TriggerComboImmediate(buffKey, key)
                    return
                }

                ; No combo found - if new key is NOT a modifier, activate modifier and send modified key
                if (!this.modifierKeys.Has(key)) {
                    this.activeModifiers[buffKey] := true
                    buffData.modifierActivated := true
                    this.SendModifiedKey(key)
                    buffData.modifierTriggered := true
                    return
                }
            }

            ; Check for regular combo with any held key
            if (this.comboCallbacks.Has(comboId)) {
                this.TriggerComboImmediate(buffKey, key)
                return
            }
        }
    }

    ; ; UP STAGE 6: Check for same-modifier keys (before multi-modifier detection)
    ; if (this.modifierKeys.Has(key)) {
    ;     newModName := this.modifierKeys[key]

    ;     ; FIRST: Check if 2+ other modifiers already unreleased (multi-mod takes priority)
    ;     ; If 2+ mods down and new key is same-mod partner, treat as modifier and send immediately
    ;     if (unreleasedModifierCount >= 2) {
    ;         for buffKey, buffData in this.keyBuffer {
    ;             if (!buffData.isModifier || buffData.isReleased)
    ;                 continue

    ;             buffModName := this.modifierKeys[buffKey]
    ;             if (buffModName == newModName) {
    ;                 ; Found same-mod partner - cancel timers and activate ALL unreleased mods
    ;                 for modKey, modData in this.keyBuffer {
    ;                     if (modData.isModifier && !modData.isReleased) {
    ;                         ; Cancel any pending timers for this modifier
    ;                         for timerId, timerFunc in this.activeTimers.Clone() {
    ;                             if (InStr(timerId, modKey . "_")) {
    ;                                 SetTimer(timerFunc, 0)
    ;                                 this.activeTimers.Delete(timerId)
    ;                             }
    ;                         }

    ;                         this.activeModifiers[modKey] := true
    ;                         modData.modifierActivated := true
    ;                         modData.modifierTriggered := true
    ;                     }
    ;                 }
    ;                 this.SendModifiedKey(key)
    ;                 return
    ;             }
    ;         }
    ;     }
    ;     ; If 2+ mods down, skip same-mod logic (treat as normal key or stack)
    ;     if (unreleasedModifierCount < 2) {
    ;         for buffKey, buffData in this.keyBuffer {
    ;             if (!buffData.isModifier || buffData.isReleased || buffData.modifierActivated)
    ;                 continue

    ;             buffModName := this.modifierKeys[buffKey]
    ;             if (buffModName != newModName)
    ;                 continue

    ;             timeDiff := currentTime - buffData.downTime

    ;             ; Within threshold - set up for fast typing or modifier behavior
    ;             if (timeDiff < this.holdThreshold) {
    ;                 ; Contaminate primary to prevent hold
    ;                 buffData.hasInterferingKeys := true

    ;                 ; Buffer new key as non-modifier
    ;                 this.keyBuffer[key] := {
    ;                     downTime: currentTime,
    ;                     hasInterferingKeys: false,
    ;                     isReleased: false,
    ;                     comboTriggered: false,
    ;                     modifierPressed: false,
    ;                     isModifier: false,
    ;                     modifierActivated: false,
    ;                     modifierTriggered: false,
    ;                     inComboRepeatMode: false,
    ;                     action: "",
    ;                     sameModTimerId: "",
    ;                     sameModPartner: buffKey,
    ;                     inQuietPeriod: inQuietPeriod
    ;                 }
    ;                 this.keyOrder.Push(key)

    ;                 ; Set timer on first key for threshold check
    ;                 remaining := this.holdThreshold - timeDiff
    ;                 timerFunc := ObjBindMethod(this, "SameModifierThreshold", buffKey, key)
    ;                 timerId := buffKey . "_sameMod_" . key
    ;                 buffData.sameModTimerId := timerId
    ;                 this.activeTimers[timerId] := timerFunc
    ;                 SetTimer(timerFunc, -remaining)
    ;                 return
    ;             }

    ;             ; Past threshold - activate as modifier and send modified key
    ;             this.activeModifiers[buffKey] := true
    ;             buffData.modifierActivated := true
    ;             this.SendModifiedKey(key)
    ;             buffData.modifierTriggered := true
    ;             return
    ;         }
    ;     }
    ; }

    ; UP STAGE 6: Check for same-modifier keys (before multi-modifier detection)
if (this.modifierKeys.Has(key)) {
    newModName := this.modifierKeys[key]

    ; FIRST: Check if 2+ other modifiers already unreleased (multi-mod takes priority)
    ; If 2+ mods down and new key is same-mod partner, treat as modifier and send immediately
    if (unreleasedModifierCount >= 2) {
        for buffKey, buffData in this.keyBuffer {
            if (!buffData.isModifier || buffData.isReleased)
                continue

            buffModName := this.modifierKeys[buffKey]
            if (buffModName == newModName) {
                ; Found same-mod partner - cancel timers and activate ALL unreleased mods
                for modKey, modData in this.keyBuffer {
                    if (modData.isModifier && !modData.isReleased) {
                        ; Cancel any pending timers for this modifier
                        for timerId, timerFunc in this.activeTimers.Clone() {
                            if (InStr(timerId, modKey . "_")) {
                                SetTimer(timerFunc, 0)
                                this.activeTimers.Delete(timerId)
                            }
                        }

                        this.activeModifiers[modKey] := true
                        modData.modifierActivated := true
                        modData.modifierTriggered := true
                    }
                }
                this.SendModifiedKey(key)
                return
            }
        }
    }
    ; If 2+ mods down, skip same-mod logic (treat as normal key or stack)
    if (unreleasedModifierCount < 2) {
        for buffKey, buffData in this.keyBuffer {
            if (!buffData.isModifier || buffData.isReleased || buffData.modifierActivated)
                continue

            buffModName := this.modifierKeys[buffKey]
            if (buffModName != newModName)
                continue

            timeDiff := currentTime - buffData.downTime

            ; Within threshold - set up for fast typing or modifier behavior
            if (timeDiff < this.holdThreshold) {
                this.keyBuffer[key] := {
                    downTime: currentTime,
                    hasInterferingKeys: false,
                    isReleased: false,
                    comboTriggered: false,
                    modifierPressed: false,
                    isModifier: true, ; Treat as modifier
                    modifierActivated: false,
                    modifierTriggered: false,
                    inComboRepeatMode: false,
                    action: "",
                    sameModTimerId: "",
                    sameModPartner: buffKey,
                    inQuietPeriod: inQuietPeriod
                }
                this.keyOrder.Push(key)
                remaining := this.holdThreshold - timeDiff
                timerFunc := ObjBindMethod(this, "SameModifierThreshold", buffKey, key)
                timerId := buffKey . "_sameMod_" . key
                buffData.sameModTimerId := timerId
                this.activeTimers[timerId] := timerFunc
                SetTimer(timerFunc, -remaining)
                return
            }

            ; Past threshold - activate as modifier and send modified key
            this.activeModifiers[buffKey] := true
            buffData.modifierActivated := true
            this.SendModifiedKey(key)
            buffData.modifierTriggered := true
            return
        }
    }
}

    ; UP STAGE 7: Check for instant combos with unreleased keys
    for buffKey, buffData in this.keyBuffer {
        if (buffData.isReleased)
            continue

        comboId := buffKey . "_" . key
        if (this.instantComboCallbacks.Has(comboId)) {
            this.TriggerInstantCombo(buffKey, key)
            return
        }
    }

    ; UP STAGE 8: Normal buffering
    for bufferedKey, data in this.keyBuffer {
        data.hasInterferingKeys := true
    }

    isHomerowModifier := this.modifierKeys.Has(key)

    this.keyBuffer[key] := {
        downTime: currentTime,
        hasInterferingKeys: false,
        isReleased: false,
        comboTriggered: false,
        modifierPressed: false,
        isModifier: isHomerowModifier,
        modifierActivated: false,
        modifierTriggered: false,
        inComboRepeatMode: false,
        action: "",
        sameModTimerId: "",
        inQuietPeriod: inQuietPeriod
    }

    this.keyOrder.Push(key)

    if (this.keyOrder.Length > this.maxBufferSize) {
        oldKey := this.keyOrder.RemoveAt(1)
        if (this.keyBuffer.Has(oldKey))
            this.keyBuffer.Delete(oldKey)
    }
}

; Some timing decisions are based on when keys are released, as seen here
static BufferKeyUp(key) { 
    currentTime := this.GetTime()

    ; DOWN STAGE 1: Traditional modifier handling
    if (this.modifierSet.Has(key)) {
        if (this.modifierMap.Has(key))
            this.modifierBitmask &= ~this.modifierMap[key]
        return
    }

    if (this.modifierBitmask > 0 || !this.keyBuffer.Has(key))
        return

    keyData := this.keyBuffer[key]
    keyData.isReleased := true
    keyData.releaseTime := currentTime

    duration := currentTime - keyData.downTime

    ; Remove from active modifiers
    if (this.activeModifiers.Has(key)) {
        this.activeModifiers.Delete(key)
    }

    ; Cancel any retro timers for this key as primary
    for timerId, timerFunc in this.activeTimers.Clone() {
        parts := StrSplit(timerId, "_")
        if (parts.Length >= 3 && parts[1] == key && (parts[2] == "retroMod" || parts[2] == "retroCombo")) {
            SetTimer(timerFunc, 0)
            this.activeTimers.Delete(timerId)
        }
    }

; DOWN STAGE 1.4: PROACTIVE single-mod handling (one mod pressed quickly, then non-mod or different-type mod)
if (duration < this.holdThreshold) {
    ; Check for exactly 1 unreleased modifier pressed quickly before this key
    singleMod := ""
    for buffKey, buffData in this.keyBuffer {
        if (!buffData.isModifier || buffData.isReleased)
            continue
        
        ; Mod must have been pressed before the released key
        if (buffData.downTime >= keyData.downTime)
            continue
        
        ; Check if mod was pressed quickly
        timeFromModToKey := keyData.downTime - buffData.downTime
        if (timeFromModToKey < this.holdThreshold) {
            if (singleMod != "") {
                singleMod := ""  ; More than one mod, skip single-mod logic
                break
            }
            singleMod := buffKey
        }
    }

    if (singleMod != "") {
        ; Check if released key is non-modifier OR different-type modifier
        isNonModifier := !this.modifierKeys.Has(key)
        isDifferentTypeMod := false
        
        if (this.modifierKeys.Has(key)) {
            modType := this.modifierKeys[singleMod]
            releasedModType := this.modifierKeys[key]
            if (modType != releasedModType) {
                isDifferentTypeMod := true
            }
        }
        
        if (isNonModifier || isDifferentTypeMod) {
            ; NEW: Check if combo registered - if yes, skip proactive and let timer handle
            comboId := singleMod . "_" . key
            if (this.comboCallbacks.Has(comboId) || this.instantComboCallbacks.Has(comboId)) {
                return  ; Skip proactive activation to prioritize combo
            }

            ; Cancel any pending timers
            for timerId, timerFunc in this.activeTimers.Clone() {
                if (InStr(timerId, singleMod . "_")) {
                    SetTimer(timerFunc, 0)
                    this.activeTimers.Delete(timerId)
                }
            }

            ; Activate the single mod
            if (!this.activeModifiers.Has(singleMod)) {
                this.activeModifiers[singleMod] := true
                this.keyBuffer[singleMod].modifierActivated := true
            }
            this.keyBuffer[singleMod].modifierTriggered := true
            this.keyBuffer[singleMod].action := "modifier_used"

            ; Send modified key
            this.SendModifiedKey(key)

            ; Clean up
            this.keyBuffer.Delete(key)
            Loop this.keyOrder.Length {
                if (this.keyOrder[A_Index] == key) {
                    this.keyOrder.RemoveAt(A_Index)
                    break
                }
            }
            return
        }
    }
}

; DOWN STAGE 1.5: PROACTIVE multi-mod handling
if (duration < this.holdThreshold) {  ; ← Remove the && !keyData.isModifier check
    ; Collect unreleased modifiers that were pressed quickly BEFORE this key
    quickMods := []
    for buffKey, buffData in this.keyBuffer {
        if (!buffData.isModifier || buffData.isReleased)
            continue
        
        ; Mod must have been pressed before the released key
        if (buffData.downTime >= keyData.downTime)
            continue
        
        ; Check if mod was pressed quickly (within threshold of when IT went down, not now)
        timeFromModToKey := keyData.downTime - buffData.downTime
        if (timeFromModToKey < this.holdThreshold) {
            quickMods.Push(buffKey)
        }
    }

    ; If 2+ mods found, check if released key is non-modifier OR partner-mod
    if (quickMods.Length >= 2) {
        isNonModifier := !this.modifierKeys.Has(key)
        isPartnerMod := false
        
        if (this.modifierKeys.Has(key)) {
            releasedModType := this.modifierKeys[key]
            ; Check if any quick mod is same type (partner)
            for modKey in quickMods {
                if (this.modifierKeys[modKey] == releasedModType) {
                    isPartnerMod := true
                    break
                }
            }
        }
        
        isNonPartnerMod := false
        if (this.modifierKeys.Has(key) && !isPartnerMod) {
            isNonPartnerMod := true
        }
        
        if (isNonModifier || isPartnerMod || isNonPartnerMod) {
            ; Verify mods were pressed quickly relative to EACH OTHER
            allQuickTogether := true
            for i, modKey1 in quickMods {
                for j, modKey2 in quickMods {
                    if (i >= j)
                        continue
                    timeBetweenMods := Abs(this.keyBuffer[modKey1].downTime - this.keyBuffer[modKey2].downTime)
                    if (timeBetweenMods >= this.holdThreshold) {
                        allQuickTogether := false
                        break 2
                    }
                }
            }

            if (allQuickTogether) {
                ; Cancel any pending timers
                for modKey in quickMods {
                    for timerId, timerFunc in this.activeTimers.Clone() {
                        if (InStr(timerId, modKey . "_")) {
                            SetTimer(timerFunc, 0)
                            this.activeTimers.Delete(timerId)
                        }
                    }
                }

                ; Activate all quick mods
                for modKey in quickMods {
                    if (!this.activeModifiers.Has(modKey)) {
                        this.activeModifiers[modKey] := true
                        this.keyBuffer[modKey].modifierActivated := true
                    }
                    this.keyBuffer[modKey].modifierTriggered := true
                    this.keyBuffer[modKey].action := "modifier_used"
                }

                ; Send modified key
                this.SendModifiedKey(key)

                ; Clean up
                this.keyBuffer.Delete(key)
                Loop this.keyOrder.Length {
                    if (this.keyOrder[A_Index] == key) {
                        this.keyOrder.RemoveAt(A_Index)
                        break
                    }
                }
                return
            }
        }
    }
}

; DOWN STAGE 1.6: Multi-mod chord with any release timing
if (!keyData.isModifier || (keyData.isModifier && this.modifierKeys.Has(key))) {
    ; Collect ALL unreleased modifiers pressed before this key
    unreleasedMods := []
    for buffKey, buffData in this.keyBuffer {
        if (!buffData.isModifier || buffData.isReleased)
            continue
        
        if (buffData.downTime >= keyData.downTime)
            continue
        
        ; Skip if past maxHoldTime (will be suppressed)
        elapsed := currentTime - buffData.downTime
        if (elapsed > this.maxHoldTime)
            continue
            
        unreleasedMods.Push(buffKey)
    }
    
    ; If 2+ unreleased mods, activate and send
    if (unreleasedMods.Length >= 2) {
        ; Cancel any pending timers
        for modKey in unreleasedMods {
            for timerId, timerFunc in this.activeTimers.Clone() {
                if (InStr(timerId, modKey . "_")) {
                    SetTimer(timerFunc, 0)
                    this.activeTimers.Delete(timerId)
                }
            }
        }
        
        ; Activate all mods
        for modKey in unreleasedMods {
            if (!this.activeModifiers.Has(modKey)) {
                this.activeModifiers[modKey] := true
                this.keyBuffer[modKey].modifierActivated := true
            }
            this.keyBuffer[modKey].modifierTriggered := true
            this.keyBuffer[modKey].action := "modifier_used"
        }
        
        ; Send modified key
        this.SendModifiedKey(key)
        
        ; Clean up
        this.keyBuffer.Delete(key)
        Loop this.keyOrder.Length {
            if (this.keyOrder[A_Index] == key) {
                this.keyOrder.RemoveAt(A_Index)
                break
            }
        }
        return
    }
}

    ; DOWN STAGE 2: Handle same-modifier key release
    if (keyData.HasProp("sameModPartner") && keyData.sameModPartner != "") {
        partnerKey := keyData.sameModPartner
        if (this.keyBuffer.Has(partnerKey)) {
            partnerData := this.keyBuffer[partnerKey]

            ; Cancel the timer on partner
            if (partnerData.sameModTimerId != "" && this.activeTimers.Has(partnerData.sameModTimerId)) {
                SetTimer(this.activeTimers[partnerData.sameModTimerId], 0)
                this.activeTimers.Delete(partnerData.sameModTimerId)
                partnerData.sameModTimerId := ""
            }
        }
    }

    ; Check if there is an unreleased key that has this key as partner
    for buffKey, buffData in this.keyBuffer {
        if (buffData.HasProp("sameModPartner") && buffData.sameModPartner == key && !buffData.isReleased) {
            ; Cancel timer on this key (primary)
            if (keyData.sameModTimerId != "" && this.activeTimers.Has(keyData.sameModTimerId)) {
                SetTimer(this.activeTimers[keyData.sameModTimerId], 0)
                this.activeTimers.Delete(keyData.sameModTimerId)
                keyData.sameModTimerId := ""
            }
            break
        }
    }

; ; DOWN STAGE 3: Handle homerow modifier release
; if (keyData.isModifier) {
;     ; Check for quick tap while OTHER modifiers are held or quick stack handling
;     if (duration < this.holdThreshold) {
;         totalUnreleasedKeys := 1
;         otherModifiersHeld := []
;         thisModType := this.modifierKeys[key]

;         for buffKey, buffData in this.keyBuffer {
;             if (buffKey == key)
;                 continue
;             if (buffData.isReleased)
;                 continue

;             totalUnreleasedKeys++

;             if (buffData.isModifier && buffData.modifierActivated) {
;                 otherModifiersHeld.Push(buffKey)
;             }
;         }

;         if (otherModifiersHeld.Length > 0) {
;             if (totalUnreleasedKeys == 2 && otherModifiersHeld.Length == 1) {
;                 heldModKey := otherModifiersHeld[1]
;                 comboId := heldModKey . "_" . key

;                 if (this.comboCallbacks.Has(comboId) || this.instantComboCallbacks.Has(comboId)) {
;                     this.TriggerComboImmediate(heldModKey, key)
;                     return
;                 }
;             }

;             modString := ""
;             for modKey in otherModifiersHeld {
;                 modName := this.modifierKeys[modKey]
;                 switch modName {
;                     case "Ctrl": modString .= "^"
;                     case "Alt": modString .= "!"
;                     case "Shift": modString .= "+"
;                     case "Win": modString .= "#"
;                 }
;                 if (this.keyBuffer.Has(modKey)) {
;                     this.keyBuffer[modKey].modifierTriggered := true
;                 }
;             }

;             SendLevel 2
;             SendEvent(modString . "{" . key . "}")

;             this.keyBuffer.Delete(key)
;             Loop this.keyOrder.Length {
;                 if (this.keyOrder[A_Index] == key) {
;                     this.keyOrder.RemoveAt(A_Index)
;                     break
;                 }
;             }
;             return
;         }

;         ; Check for same type non-activated
;         for buffKey, buffData in this.keyBuffer {
;             if (buffKey == key)
;                 continue
;             if (buffData.isModifier && !buffData.isReleased && buffData.downTime < keyData.downTime) {
;                 if (this.modifierKeys[buffKey] != thisModType)
;                     continue

;                 timeSinceOtherMod := keyData.downTime - buffData.downTime
;                 if (timeSinceOtherMod < this.modifierThreshold) {
;                     if (!this.activeModifiers.Has(buffKey)) {
;                         this.activeModifiers[buffKey] := true
;                         buffData.modifierActivated := true
;                     }
;                     buffData.modifierTriggered := true

;                     modName := this.modifierKeys[buffKey]
;                     modString := ""
;                     switch modName {
;                         case "Ctrl": modString := "^"
;                         case "Alt": modString .= "!"
;                         case "Shift": modString .= "+"
;                         case "Win": modString := "#"
;                     }

;                     SendLevel 2
;                     SendEvent(modString . "{" . key . "}")

;                     this.keyBuffer.Delete(key)
;                     Loop this.keyOrder.Length {
;                         if (this.keyOrder[A_Index] == key) {
;                             this.keyOrder.RemoveAt(A_Index)
;                             break
;                         }
;                     }
;                     return
;                 }
;             }
;         }
;     }

;     ; Stacked check only if not already handled
;     if (duration < this.holdThreshold && keyData.modifierActivated && !keyData.modifierTriggered) {
;         ; Find other stacked modifiers that were activated with this one
;         stackedModifiers := []
;         for buffKey, buffData in this.keyBuffer {
;             if (buffKey == key)
;                 continue
;             if (buffData.isModifier && buffData.modifierActivated && !buffData.modifierTriggered && !buffData.isReleased) {
;                 ; Check if they were activated together (within threshold)
;                 timeDiff := Abs(buffData.downTime - keyData.downTime)
;                 if (timeDiff < this.modifierThreshold) {
;                     stackedModifiers.Push(buffKey)
;                 }
;             }
;         }

;         ; If we have stacked modifiers, we need to wait and see if they're also quick-released
;         if (stackedModifiers.Length > 0) {
;             ; Don't process yet - wait for the others to release
;             this.ProcessQueue()
;             return
;         }

;         ; No stacked modifiers waiting - this was a solo quick tap, send as tap
;         keyData.action := "tap"
;         this.ProcessQueue()
;         return
;     }

;     if (keyData.comboTriggered) {
;         keyData.action := "modifier_used"
;         this.ProcessQueue()
;         return
;     }

;     if (keyData.modifierTriggered) {
;         keyData.action := "modifier_used"
;         this.ProcessQueue()
;         return
;     }

;     if (keyData.modifierActivated && !keyData.modifierTriggered) {
;         this.ProcessQueue()
;         return
;     }

;     ; Force tap if key was pressed within comboQuietPeriod of previous key
;     if (keyData.inQuietPeriod && !keyData.modifierTriggered && !keyData.comboTriggered) {
;         keyData.action := "tap"
;         this.ProcessQueue()
;         return
;     }

;     if (keyData.hasInterferingKeys || duration < this.holdThreshold) {
;         keyData.action := "tap"
;         this.ProcessQueue()
;         return
;     }

;     if (duration > this.maxHoldTime) {
;         if (this.userconfig.maxholdsupresseskeys) {
;             keyData.action := "none"
;         } else {
;             keyData.action := "tap"
;         }
;         this.ProcessQueue()
;         return
;     }

;     ; NEW: Force tap during typing bursts or contamination (suppresses hold callback)
;     if (keyData.inQuietPeriod || keyData.hasInterferingKeys) {
;         keyData.action := "tap"
;         this.ProcessQueue()
;         return
;     }

;     ; Existing hold check (now only triggers outside bursts)
;     hotkeyId := key . "_hold"
;     if (this.holdCallbacks.Has(hotkeyId)) {
;         keyData.action := "hold"
;     } else {
;         keyData.action := "tap"
;     }
;     this.ProcessQueue()
;     return
; }

; DOWN STAGE 3: Handle homerow modifier release
if (keyData.isModifier) {
    ; Check for quick tap while OTHER modifiers are held or quick stack handling
    if (duration < this.holdThreshold) {
        totalUnreleasedKeys := 1
        otherModifiersHeld := []
        thisModType := this.modifierKeys[key]

        for buffKey, buffData in this.keyBuffer {
            if (buffKey == key)
                continue
            if (buffData.isReleased)
                continue

            totalUnreleasedKeys++

            if (buffData.isModifier && buffData.modifierActivated) {
                otherModifiersHeld.Push(buffKey)
            }
        }

        ; NEW: Check for unreleased non-partner modifiers past threshold (not yet activated)
        if (otherModifiersHeld.Length == 0) {
            for buffKey, buffData in this.keyBuffer {
                if (buffKey == key || buffData.isReleased || !buffData.isModifier)
                    continue
                
                ; Skip partner modifiers (same type)
                if (this.modifierKeys[buffKey] == thisModType)
                    continue
                
                elapsed := currentTime - buffData.downTime
                if (elapsed >= this.holdThreshold && !buffData.modifierActivated) {
                    ; Check if there's a registered combo - if yes, skip activation
                    comboId := buffKey . "_" . key
                    if (this.comboCallbacks.Has(comboId) || this.instantComboCallbacks.Has(comboId))
                        continue
                    
                    ; Activate the non-partner modifier retroactively
                    this.activeModifiers[buffKey] := true
                    buffData.modifierActivated := true
                    buffData.modifierTriggered := true
                    otherModifiersHeld.Push(buffKey)
                }
            }
        }

        if (otherModifiersHeld.Length > 0) {
            if (totalUnreleasedKeys == 2 && otherModifiersHeld.Length == 1) {
                heldModKey := otherModifiersHeld[1]
                comboId := heldModKey . "_" . key

                if (this.comboCallbacks.Has(comboId) || this.instantComboCallbacks.Has(comboId)) {
                    this.TriggerComboImmediate(heldModKey, key)
                    return
                }
            }

            modString := ""
            for modKey in otherModifiersHeld {
                modName := this.modifierKeys[modKey]
                switch modName {
                    case "Ctrl": modString .= "^"
                    case "Alt": modString .= "!"
                    case "Shift": modString .= "+"
                    case "Win": modString .= "#"
                }
                if (this.keyBuffer.Has(modKey)) {
                    this.keyBuffer[modKey].modifierTriggered := true
                }
            }

            SendLevel 2
            SendEvent(modString . "{" . key . "}")

            this.keyBuffer.Delete(key)
            Loop this.keyOrder.Length {
                if (this.keyOrder[A_Index] == key) {
                    this.keyOrder.RemoveAt(A_Index)
                    break
                }
            }
            return
        }

        ; Check for same type non-activated
        for buffKey, buffData in this.keyBuffer {
            if (buffKey == key)
                continue
            if (buffData.isModifier && !buffData.isReleased && buffData.downTime < keyData.downTime) {
                if (this.modifierKeys[buffKey] != thisModType)
                    continue

                timeSinceOtherMod := keyData.downTime - buffData.downTime
                if (timeSinceOtherMod < this.modifierThreshold) {
                    if (!this.activeModifiers.Has(buffKey)) {
                        this.activeModifiers[buffKey] := true
                        buffData.modifierActivated := true
                    }
                    buffData.modifierTriggered := true

                    modName := this.modifierKeys[buffKey]
                    modString := ""
                    switch modName {
                        case "Ctrl": modString := "^"
                        case "Alt": modString .= "!"
                        case "Shift": modString .= "+"
                        case "Win": modString := "#"
                    }

                    SendLevel 2
                    SendEvent(modString . "{" . key . "}")

                    this.keyBuffer.Delete(key)
                    Loop this.keyOrder.Length {
                        if (this.keyOrder[A_Index] == key) {
                            this.keyOrder.RemoveAt(A_Index)
                            break
                        }
                    }
                    return
                }
            }
        }
    }

    ; Stacked check only if not already handled
    if (duration < this.holdThreshold && keyData.modifierActivated && !keyData.modifierTriggered) {
        ; Find other stacked modifiers that were activated with this one
        stackedModifiers := []
        for buffKey, buffData in this.keyBuffer {
            if (buffKey == key)
                continue
            if (buffData.isModifier && buffData.modifierActivated && !buffData.modifierTriggered && !buffData.isReleased) {
                ; Check if they were activated together (within threshold)
                timeDiff := Abs(buffData.downTime - keyData.downTime)
                if (timeDiff < this.modifierThreshold) {
                    stackedModifiers.Push(buffKey)
                }
            }
        }

        ; If we have stacked modifiers, we need to wait and see if they're also quick-released
        if (stackedModifiers.Length > 0) {
            ; Don't process yet - wait for the others to release
            this.ProcessQueue()
            return
        }

        ; No stacked modifiers waiting - this was a solo quick tap, send as tap
        keyData.action := "tap"
        this.ProcessQueue()
        return
    }

    if (keyData.comboTriggered) {
        keyData.action := "modifier_used"
        this.ProcessQueue()
        return
    }

    if (keyData.modifierTriggered) {
        keyData.action := "modifier_used"
        this.ProcessQueue()
        return
    }

    if (keyData.modifierActivated && !keyData.modifierTriggered) {
        this.ProcessQueue()
        return
    }

    ; Force tap if key was pressed within comboQuietPeriod of previous key
    if (keyData.inQuietPeriod && !keyData.modifierTriggered && !keyData.comboTriggered) {
        keyData.action := "tap"
        this.ProcessQueue()
        return
    }

    if (keyData.hasInterferingKeys || duration < this.holdThreshold) {
        keyData.action := "tap"
        this.ProcessQueue()
        return
    }

    if (duration > this.maxHoldTime) {
        if (this.userconfig.maxholdsupresseskeys) {
            keyData.action := "none"
        } else {
            keyData.action := "tap"
        }
        this.ProcessQueue()
        return
    }

    ; NEW: Force tap during typing bursts or contamination (suppresses hold callback)
    if (keyData.inQuietPeriod || keyData.hasInterferingKeys) {
        keyData.action := "tap"
        this.ProcessQueue()
        return
    }

    ; Existing hold check (now only triggers outside bursts)
    hotkeyId := key . "_hold"
    if (this.holdCallbacks.Has(hotkeyId)) {
        keyData.action := "hold"
    } else {
        keyData.action := "tap"
    }
    this.ProcessQueue()
    return
}

    ; DOWN STAGE 4: Check for retroactive modifier activation
    if (!keyData.comboTriggered && !keyData.modifierPressed) {
        ; First pass: activate ALL eligible modifiers
        modsToActivate := []
        for buffKey, buffData in this.keyBuffer {
            if (!buffData.isModifier || buffData.isReleased)
                continue

            comboId := buffKey . "_" . key
            if (this.comboCallbacks.Has(comboId) || this.instantComboCallbacks.Has(comboId))
                continue

            elapsed := currentTime - buffData.downTime
            if (elapsed < this.holdThreshold)
                continue

            modsToActivate.Push(buffKey)
        }

        ; If any mods to activate, activate all then send once
        if (modsToActivate.Length > 0) {
            for modKey in modsToActivate {
                if (!this.activeModifiers.Has(modKey)) {
                    this.activeModifiers[modKey] := true
                    this.keyBuffer[modKey].modifierActivated := true
                }
                this.keyBuffer[modKey].modifierTriggered := true
            }

            this.SendModifiedKey(key)

            this.keyBuffer.Delete(key)
            Loop this.keyOrder.Length {
                if (this.keyOrder[A_Index] == key) {
                    this.keyOrder.RemoveAt(A_Index)
                    break
                }
            }
            return
        }
    }

    ; Set up retroactive timers (but ONLY if not contaminated by typing burst)
    if (!keyData.hasInterferingKeys) {
        unreleasedCount := 0
        for buffK, buffD in this.keyBuffer {
            if (!buffD.isReleased && buffK != key) {
                unreleasedCount++
            }
        }

        potentialComboPrimaries := []
        if (unreleasedCount == 1) {
            for buffKey, buffData in this.keyBuffer {
                if (buffData.isReleased || buffData.downTime >= keyData.downTime)
                    continue

                comboId := buffKey . "_" . key
                if (!this.comboCallbacks.Has(comboId) || this.instantComboCallbacks.Has(comboId))
                    continue

                elapsed := currentTime - buffData.downTime
                if (elapsed >= this.holdThreshold)
                    continue

                potentialComboPrimaries.Push({ key: buffKey, elapsed: elapsed })
            }
        }

        for pm in potentialComboPrimaries {
            remaining := this.holdThreshold - pm.elapsed
            timerFunc := ObjBindMethod(this, "RetroTriggerCombo", pm.key, key)
            timerId := pm.key . "_retroCombo_" . key
            this.activeTimers[timerId] := timerFunc
            SetTimer(timerFunc, -remaining)
        }

        potentialModifiers := []
        for buffKey, buffData in this.keyBuffer {
            if (!buffData.isModifier || buffData.isReleased || buffData.modifierActivated)
                continue

            comboId := buffKey . "_" . key
            if (this.comboCallbacks.Has(comboId) || this.instantComboCallbacks.Has(comboId))
                continue

            elapsed := currentTime - buffData.downTime
            if (elapsed >= this.holdThreshold)
                continue

            potentialModifiers.Push({ key: buffKey, elapsed: elapsed })
        }

        for pm in potentialModifiers {
            remaining := this.holdThreshold - pm.elapsed
            timerFunc := ObjBindMethod(this, "RetroActivateModifier", pm.key, key)
            timerId := pm.key . "_retroMod_" . key
            this.activeTimers[timerId] := timerFunc
            SetTimer(timerFunc, -remaining)
        }

        if (potentialComboPrimaries.Length > 0 || potentialModifiers.Length > 0) {
            this.ProcessQueue()
            return
        }
    }

    ; DOWN STAGE 5: Fast path for simple taps
    if (duration < this.holdThreshold && !keyData.hasInterferingKeys && !keyData.comboTriggered) {
        hotkeyId := key . "_hold"
        if (!this.holdCallbacks.Has(hotkeyId) && !this.comboPrimaries.Has(key) && !this.instantComboPrimaries.Has(key)) {
            keyData.action := "tap"

            for timerId, timerFunc in this.activeTimers.Clone() {
                parts := StrSplit(timerId, "_")
                if (parts.Length == 2 && parts[2] == key) {
                    SetTimer(timerFunc, 0)
                    this.activeTimers.Delete(timerId)
                }
            }

            this.ProcessQueue()
            return
        }
    }

    ; DOWN STAGE 6: Queue for processing
    this.ProcessQueue()
}

    ; ============================================================================
    ; PROCESS QUEUE
    ; ============================================================================
    static ProcessQueue() {
        while (this.keyOrder.Length > 0) {
            firstKey := this.keyOrder[1]

            if (!this.keyBuffer.Has(firstKey)) {
                this.keyOrder.RemoveAt(1)
                continue
            }

            keyData := this.keyBuffer[firstKey]

            if (!keyData.isReleased)
                break

            if (keyData.action == "") {
                ; Wait for unreleased stacked modifiers
                if (keyData.isModifier && keyData.modifierActivated && !keyData.modifierTriggered) {
                    hasOtherUnreleasedMods := false
                    for buffKey, buffData in this.keyBuffer {
                        if (buffKey != firstKey && buffData.isModifier && !buffData.isReleased && buffData.modifierActivated) {
                            hasOtherUnreleasedMods := true
                            break
                        }
                    }

                    if (hasOtherUnreleasedMods) {
                        break
                    }

                    ; Check if this modifier was part of a quick-released stack
                    wasQuickStack := false
                    stackedKeys := []
                    hasUnreleasedKeys := false

                    ; Check for unreleased keys first
                    for buffKey, buffData in this.keyBuffer {
                        if (!buffData.isReleased) {
                            hasUnreleasedKeys := true
                            break
                        }
                    }

                    if (keyData.releaseTime - keyData.downTime < this.holdThreshold) {
                        ; Look for other modifiers that were pressed together (within modifierThreshold)
                        for buffKey, buffData in this.keyBuffer {
                            if (buffKey == firstKey)
                                continue
                            if (!buffData.isModifier || !buffData.isReleased)
                                continue

                            timeDiff := Abs(buffData.downTime - keyData.downTime)
                            if (timeDiff < this.modifierThreshold) {
                                releaseDiff := Abs(buffData.releaseTime - keyData.releaseTime)
                                if (releaseDiff < this.holdThreshold && (buffData.releaseTime - buffData.downTime) < this.holdThreshold) {
                                    wasQuickStack := true
                                    stackedKeys.Push(buffKey)
                                }
                            }
                        }
                    }

                    anyModifierUsed := false
                    anyComboTriggered := false

                    for buffKey, buffData in this.keyBuffer {
                        if (buffData.isModifier && buffData.modifierActivated && buffData.modifierTriggered) {
                            anyModifierUsed := true
                            break
                        }
                        if (buffData.comboTriggered) {
                            anyComboTriggered := true
                            break
                        }
                    }

                    ; Only convert to tap if no unreleased keys remain
                    if (wasQuickStack && !anyModifierUsed && !anyComboTriggered && !hasUnreleasedKeys) {
                        keyData.action := "tap"
                    } else if (!anyModifierUsed && !anyComboTriggered && !keyData.modifierActivated) {
                        keyData.action := "tap"
                    } else {
                        keyData.action := "modifier_used"
                    }
                }

                ; Determine action for regular keys
                if (keyData.action == "" && !keyData.isModifier) {
                    needToWait := false
                    for buffKey, buffData in this.keyBuffer {
                        if (!buffData.isReleased && buffData.downTime < keyData.downTime) {
                            if ((buffData.isModifier && !buffData.modifierActivated) || this.comboCallbacks.Has(buffKey . "_" . firstKey) || this.instantComboCallbacks.Has(buffKey . "_" . firstKey)) {
                                needToWait := true
                                break
                            }
                        }
                    }

                    if (needToWait) {
                        break
                    }

                    duration := keyData.releaseTime - keyData.downTime

                    if (keyData.modifierPressed || duration > this.maxHoldTime) {
                        keyData.action := "none"
                    } else {
                        hotkeyId := firstKey . "_hold"
                        hasHold := this.holdCallbacks.Has(hotkeyId)

                        if (!hasHold && !keyData.hasInterferingKeys && duration < this.maxHoldTime) {
                            keyData.action := "tap"
                        } else {
                            keyData.action := (keyData.hasInterferingKeys || duration < this.holdThreshold || !hasHold)
                                ? "tap" : "hold"
                        }
                    }
                }
            }

            this.keyOrder.RemoveAt(1)
            this.keyBuffer.Delete(firstKey)

            if (keyData.comboTriggered || keyData.action == "modifier_used" || keyData.action == "none") {
                continue
            }

            if (keyData.action == "tap") {
                modifierPrefix := ""

                for buffKey, buffData in this.keyBuffer {
                    if (buffData.isModifier && buffData.modifierActivated && buffData.modifierTriggered) {
                        if (buffData.downTime < keyData.downTime) {
                            activationTime := buffData.downTime + this.modifierThreshold
                            if (activationTime <= keyData.downTime) {
                                modName := this.modifierKeys[buffKey]
                                switch modName {
                                    case "Ctrl": modifierPrefix .= "^"
                                    case "Alt": modifierPrefix .= "!"
                                    case "Shift": modifierPrefix .= "+"
                                    case "Win": modifierPrefix .= "#"
                                }
                            }
                        }
                    }
                }

                SendLevel 2
                if (modifierPrefix != "") {
                    SendEvent(modifierPrefix . "{" . firstKey . "}")
                } else {
                    SendEvent("{" . firstKey . "}")
                }
            } else if (keyData.action == "hold") {
                hotkeyId := firstKey . "_hold"
                callback := this.FindMatchingCallback(hotkeyId)
                if (callback != "") {
                    SetTimer(callback, -1)
                } else {
                    SendLevel 2
                    SendEvent("{" . firstKey . "}")
                }
            }
        }
    }

    static TriggerComboWithQuietCheck(primaryKey, secondaryKey, captureTime) {
        currentTime := this.GetTime()

        ; AUTO-CLEAR BUFFER
        if (currentTime - this.lastKeyTime >= this.comboQuietPeriod) {
            allReleased := true
            for buffKey, buffData in this.keyBuffer {
                if (!buffData.isReleased) {
                    allReleased := false
                    break
                }
            }

            if (allReleased && this.keyBuffer.Count > 0) {
                this.ProcessQueue()
                if (this.keyBuffer.Count > 0) {
                    this.ClearBuffer()
                }
                return
            }
        }

        if (!this.keyBuffer.Has(primaryKey) || this.keyBuffer[primaryKey].isReleased)
            return

        if (this.lastKeyTime > captureTime && this.lastKeyTime - captureTime > 50)
            return

        this.TriggerComboImmediate(primaryKey, secondaryKey)
    }

    static TriggerComboImmediate(primaryKey, secondaryKey) {
        if (!this.keyBuffer.Has(primaryKey) || this.keyBuffer[primaryKey].isReleased)
            return

        timerId := primaryKey . "_" . secondaryKey
        if (this.activeTimers.Has(timerId)) {
            SetTimer(this.activeTimers[timerId], 0)
            this.activeTimers.Delete(timerId)
        }

        if (this.keyBuffer.Has(primaryKey)) {
            this.keyBuffer[primaryKey].comboTriggered := true
            this.keyBuffer[primaryKey].inComboRepeatMode := true
        }

        if (this.keyBuffer.Has(secondaryKey)) {
            this.keyBuffer[secondaryKey].comboTriggered := true
            this.keyBuffer.Delete(secondaryKey)
            Loop this.keyOrder.Length {
                if (this.keyOrder[A_Index] == secondaryKey) {
                    this.keyOrder.RemoveAt(A_Index)
                    break
                }
            }
        }

        comboId := primaryKey . "_" . secondaryKey
        callback := ""
        if (this.comboCallbacks.Has(comboId)) {
            callback := this.comboCallbacks[comboId]
        } else if (this.instantComboCallbacks.Has(comboId)) {
            callback := this.instantComboCallbacks[comboId]
        }
        if (callback != "") {
            SetTimer((*) => (IsObject(callback) ? callback.Call() : callback()), -1)
        }

        if (this.instantComboCallbacks.Has(comboId) && this.keyBuffer.Has(primaryKey)) {
            primaryData := this.keyBuffer[primaryKey]
            if (primaryData.isModifier && !primaryData.modifierActivated) {
                primaryData.modifierActivated := true
                primaryData.modifierTriggered := true
                this.activeModifiers[primaryKey] := true
            }
        }
    }

    static TriggerInstantCombo(primaryKey, secondaryKey) {
        if (!this.keyBuffer.Has(primaryKey) || this.keyBuffer[primaryKey].isReleased)
            return

        if (this.keyBuffer.Has(primaryKey)) {
            this.keyBuffer[primaryKey].comboTriggered := true
            this.keyBuffer[primaryKey].inComboRepeatMode := true

            if (this.keyBuffer[primaryKey].isModifier) {
                this.keyBuffer[primaryKey].modifierActivated := true
                this.keyBuffer[primaryKey].modifierTriggered := true
                this.activeModifiers[primaryKey] := true
            }
        }

        if (!this.keyBuffer.Has(secondaryKey)) {
            this.keyBuffer[secondaryKey] := {
                downTime: this.GetTime(),
                hasInterferingKeys: false,
                isReleased: false,
                comboTriggered: true,
                modifierPressed: false,
                isModifier: false,
                modifierActivated: false,
                modifierTriggered: false,
                inComboRepeatMode: false,
                action: "none",
                sameModTimerId: ""
            }
            this.keyOrder.Push(secondaryKey)
        } else {
            this.keyBuffer[secondaryKey].comboTriggered := true
        }

        comboId := primaryKey . "_" . secondaryKey
        if (this.instantComboCallbacks.Has(comboId)) {
            callback := this.instantComboCallbacks[comboId]
            SetTimer((*) => (IsObject(callback) ? callback.Call() : callback()), -1)
        }
    }

    ; static SameModifierThreshold(primaryKey, secondaryKey) {
    ;     timerId := primaryKey . "_sameMod_" . secondaryKey
    ;     if (this.activeTimers.Has(timerId)) {
    ;         this.activeTimers.Delete(timerId)
    ;     }

    ;     if (!this.keyBuffer.Has(primaryKey) || this.keyBuffer[primaryKey].isReleased)
    ;         return

    ;     if (!this.keyBuffer.Has(secondaryKey) || this.keyBuffer[secondaryKey].isReleased)
    ;         return

    ;     this.activeModifiers[primaryKey] := true
    ;     primaryData := this.keyBuffer[primaryKey]
    ;     primaryData.modifierActivated := true
    ;     primaryData.modifierTriggered := true
    ;     primaryData.sameModTimerId := ""

    ;     this.SendModifiedKey(secondaryKey)

    ;     this.keyBuffer.Delete(secondaryKey)
    ;     Loop this.keyOrder.Length {
    ;         if (this.keyOrder[A_Index] == secondaryKey) {
    ;             this.keyOrder.RemoveAt(A_Index)
    ;             break
    ;         }
    ;     }

    ;     this.ProcessQueue()
    ; }

    static SameModifierThreshold(primaryKey, secondaryKey) {
    timerId := primaryKey . "_sameMod_" . secondaryKey
    if (this.activeTimers.Has(timerId)) {
        this.activeTimers.Delete(timerId)
    }
    if (!this.keyBuffer.Has(primaryKey) || this.keyBuffer[primaryKey].isReleased)
        return
    if (!this.keyBuffer.Has(secondaryKey) || this.keyBuffer[secondaryKey].isReleased)
        return
    this.activeModifiers[primaryKey] := true
    primaryData := this.keyBuffer[primaryKey]
    primaryData.modifierActivated := true
    primaryData.modifierTriggered := true
    primaryData.hasInterferingKeys := false ; Clear contamination
    primaryData.sameModTimerId := ""
    this.activeModifiers[secondaryKey] := true ; Keep secondary as modifier
    secondaryData := this.keyBuffer[secondaryKey]
    secondaryData.isModifier := true ; Override non-modifier
    secondaryData.modifierActivated := true
    secondaryData.modifierTriggered := true
    secondaryData.hasInterferingKeys := false ; Clear contamination
    this.SendModifiedKey(secondaryKey)
    ; Remove deletion of secondaryKey to keep it as modifier
    this.ProcessQueue()
}

    ; ============================================================================
    ; UTILITY METHODS
    ; ============================================================================

    static RegisterAllKeys() {
        for key in this.allKeys {
            if (!this.registeredKeys.Has(key)) {
                keyDown := ((k) => (*) => this.BufferKeyDown(k))(key)
                keyUp := ((k) => (*) => this.BufferKeyUp(k))(key)

                Hotkey(key, keyDown, "I2")
                Hotkey(key . " up", keyUp, "I2")
                this.registeredKeys[key] := true
            }
        }
    }

    static ClearBuffer() {
        for timerId, timerFunc in this.activeTimers {
            SetTimer(timerFunc, 0)
        }
        this.activeTimers := Map()

        this.keyBuffer := Map()
        this.keyOrder := []
        this.activeModifiers := Map()
    }

    static SetupModifier(key, modifierName) {
        this.modifierKeys[key] := modifierName

        if (!this.sameModifierKeys.Has(modifierName)) {
            this.sameModifierKeys[modifierName] := []
        }
        this.sameModifierKeys[modifierName].Push(key)
    }

    static SetupHold(key, contexts, callback) {
        if (!IsObject(contexts) || contexts.Length == 0) {
            contexts := ["global"]
        }

        hotkeyId := key . "_hold"

        if (!this.holdCallbacks.Has(hotkeyId)) {
            this.holdCallbacks[hotkeyId] := []
            this.needsState[hotkeyId] := false
        }

        for ctx in contexts {
            contextInfo := this.ParseContext(ctx)
            this.holdCallbacks[hotkeyId].Push({
                context: ctx,
                callback: callback,
                priority: contextInfo.priority,
                contextType: contextInfo.type
            })
            if (contextInfo.priority != this.CONTEXT_GLOBAL) {
                this.needsState[hotkeyId] := true
            }
        }

        this.SortContexts(this.holdCallbacks[hotkeyId])
    }

    static SetupCombo(primaryKey, secondaryKey, callback) {
        comboId := primaryKey . "_" . secondaryKey
        this.comboCallbacks[comboId] := callback

        if (!this.comboPrimaries.Has(primaryKey)) {
            this.comboPrimaries[primaryKey] := []
        }
        this.comboPrimaries[primaryKey].Push(secondaryKey)
    }

    static SetupInstantCombo(primaryKey, secondaryKey, callback) {
        comboId := primaryKey . "_" . secondaryKey
        this.instantComboCallbacks[comboId] := callback

        if (!this.instantComboPrimaries.Has(primaryKey)) {
            this.instantComboPrimaries[primaryKey] := []
        }
        this.instantComboPrimaries[primaryKey].Push(secondaryKey)
    }

    static SendModifiedKey(key) {
        uniqueModNames := Map()
        for modKey, _ in this.activeModifiers {
            if (!this.modifierKeys.Has(modKey))
                continue
            modName := this.modifierKeys[modKey]
            uniqueModNames[modName] := true
        }

        modString := ""
        for modName, _ in uniqueModNames {
            switch modName {
                case "Ctrl": modString .= "^"
                case "Alt": modString .= "!"
                case "Shift": modString .= "+"
                case "Win": modString .= "#"
            }
        }

        SendLevel 2
        SendEvent(modString . "{" . key . "}")
    }

    static ParseContext(context) {
        lowerContext := StrLower(context)

        if (context == "#32768" || context == "ahk_class #32768")
            return { type: this.CONTEXT_MENU, priority: 1 }

        if (InStr(context, "."))
            return { type: this.CONTEXT_URL, priority: 2 }

        if (context != "" && lowerContext != "global" && lowerContext != "browser" && lowerContext != "browsers"
            && !InStr(context, "ahk_class") && !InStr(context, "ahk_exe") && !InStr(context, ".exe"))
            return { type: this.CONTEXT_TITLE, priority: 3 }

        if (InStr(context, "ahk_class"))
            return { type: this.CONTEXT_CLASS, priority: 4 }

        if (lowerContext == "browser" || lowerContext == "browsers")
            return { type: this.CONTEXT_BROWSER, priority: 5 }

        if (InStr(context, "ahk_exe") || InStr(context, ".exe"))
            return { type: this.CONTEXT_EXE, priority: 6 }

        if (context == "" || lowerContext == "global")
            return { type: this.CONTEXT_GLOBAL, priority: 7 }

        return { type: this.CONTEXT_TITLE, priority: 3 }
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
        if (!this.holdCallbacks.Has(hotkeyId))
            return ""

        callbacks := this.holdCallbacks[hotkeyId]
        if (callbacks.Length == 0)
            return ""

        if (!this.needsState[hotkeyId])
            return callbacks[1].callback

        state := {
            hasContextMenu: WinExist("ahk_class #32768") ? true : false,
            activeWin: "",
            activeClass: "",
            activeExe: "",
            currentUrl: ""
        }

        if (!state.hasContextMenu) {
            try {
                state.activeWin := WinGetTitle("A")
                state.activeClass := WinGetClass("A")
                state.activeExe := WinGetProcessName("A")
            }

            if IsSet(On) {
                try state.currentUrl := On.LastResult.url ? On.LastResult.url : ""
            }
        }

        for entry in callbacks {
            if (this.MatchesContext(entry.context, entry.contextType, state))
                return entry.callback
        }

        return ""
    }

    static MatchesContext(context, contextType, state) {
        if (contextType == this.CONTEXT_MENU && state.hasContextMenu)
            return true

        if (state.hasContextMenu)
            return false

        if (contextType == this.CONTEXT_URL)
            return this.IsBrowserActive() && InStr(state.currentUrl, context) > 0

        if (contextType == this.CONTEXT_TITLE)
            return InStr(state.activeWin, context) > 0

        if (contextType == this.CONTEXT_CLASS) {
            try return WinActive(context)
            return false
        }

        if (contextType == this.CONTEXT_BROWSER)
            return this.IsBrowserActive()

        if (contextType == this.CONTEXT_EXE) {
            try return WinActive(context)
            return false
        }

        if (contextType == this.CONTEXT_GLOBAL)
            return true

        return false
    }

    static IsBrowserActive() {
        for criteria in this.browsers {
            if (WinActive(criteria)) {
                return true
            }
        }
        return false
    }

    static EmergencyReset() {
        for timerId, timerFunc in this.activeTimers {
            SetTimer(timerFunc, 0)
        }

        this.keyBuffer := Map()
        this.keyOrder := []
        this.modifierBitmask := 0
        this.activeTimers := Map()
        this.activeModifiers := Map()
        this.lastKeyTime := 0
    }

    static RetroActivateModifier(primaryKey, secondaryKey) {
        currentTime := this.GetTime()

        timerId := primaryKey . "_retroMod_" . secondaryKey
        if (this.activeTimers.Has(timerId)) {
            this.activeTimers.Delete(timerId)
        }

        if (!this.keyBuffer.Has(primaryKey) || this.keyBuffer[primaryKey].isReleased || this.keyBuffer[primaryKey].modifierActivated || this.keyBuffer[primaryKey].modifierTriggered)
            return

        if (!this.keyBuffer.Has(secondaryKey) || !this.keyBuffer[secondaryKey].isReleased)
            return

        this.activeModifiers[primaryKey] := true
        primaryData := this.keyBuffer[primaryKey]
        primaryData.modifierActivated := true
        primaryData.modifierTriggered := true

        this.SendModifiedKey(secondaryKey)

        this.keyBuffer.Delete(secondaryKey)
        Loop this.keyOrder.Length {
            if (this.keyOrder[A_Index] == secondaryKey) {
                this.keyOrder.RemoveAt(A_Index)
                break
            }
        }

        this.ProcessQueue()
    }

    static RetroTriggerCombo(primaryKey, secondaryKey) {
        currentTime := this.GetTime()

        timerId := primaryKey . "_retroCombo_" . secondaryKey
        if (this.activeTimers.Has(timerId)) {
            this.activeTimers.Delete(timerId)
        }

        if (!this.keyBuffer.Has(primaryKey) || this.keyBuffer[primaryKey].isReleased || this.keyBuffer[primaryKey].comboTriggered || this.keyBuffer[primaryKey].modifierActivated)
            return

        if (!this.keyBuffer.Has(secondaryKey) || !this.keyBuffer[secondaryKey].isReleased)
            return

        this.keyBuffer[primaryKey].comboTriggered := true
        this.keyBuffer[primaryKey].inComboRepeatMode := true
        this.keyBuffer[secondaryKey].comboTriggered := true

        comboId := primaryKey . "_" . secondaryKey
        if (this.comboCallbacks.Has(comboId)) {
            callback := this.comboCallbacks[comboId]
            SetTimer((*) => (IsObject(callback) ? callback.Call() : callback()), -1)
        }

        this.keyBuffer.Delete(secondaryKey)
        Loop this.keyOrder.Length {
            if (this.keyOrder[A_Index] == secondaryKey) {
                this.keyOrder.RemoveAt(A_Index)
                break
            }
        }

        this.ProcessQueue()
    }
}
