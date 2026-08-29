#Requires AutoHotkey v2.0

#SingleInstance Force

/*
================================================================================
                              MM CLASS TUTORIAL
================================================================================

BASIC USAGE:
Create instance: mm := MM

// Move window to monitor with predefined position
mm.MoveToMonitor("Notepad", "Ultrawide", "lefthalf")
mm.MoveToMonitor("Chrome", "4K", "rightthird")

CUSTOM POSITIONING:
// Use object with x, y properties (0.0 to 1.0 = percentage of monitor)
mm.MoveToMonitor("Terminal", "Surface", {x: 0.65, y: 0.065})
// x: 0.65 = 65% from left edge of monitor
// y: 0.065 = 6.5% from top edge of monitor
// Omit w/h to keep current window size, or add them:
mm.MoveToMonitor("App", "4K", {x: 0.5, y: 0.2, w: 0.8, h: 0.6})
// w: 0.8 = 80% of monitor width
// h: 0.6 = 60% of monitor height

TIMER SUPPORT (non-blocking):
// Add timeout parameter (milliseconds) to prevent hanging
mm.MoveToMonitor("Window", "4K", "lefthalf", "relative", 3, 5000)
// Will timeout after 5 seconds if window doesn't respond

SNAP FUNCTIONS:
mm.SnapLeft("A")        // Snap active window to left half - i use this a lot
mm.SnapRight("Notepad") // Snap specific window to right half

1. SETUP - Configure your monitors in the MonitorMap:
   - Add your monitor names with their aspect ratios
   - The class will automatically match to closest aspect ratio (including portrait)
   - Tolerance determines how close the match needs to be

   Example:
   static MonitorMap := Map(
       "Ultrawide", {aspectRatio: 2.39, tolerance: 0.1},
       "4K", {aspectRatio: 1.78, tolerance: 0.1},
       "Surface", {aspectRatio: 1.5, tolerance: 0.1}
   )

2. POSITION PRESETS:
   Halves: "lefthalf", "righthalf", "middlehalf", "tophalf", "bottomhalf"
   Thirds: "leftthird", "middlethird", "rightthird", "lefttwothirds", "righttwothirds"
   Quarters: "topleft", "topright", "bottomleft", "bottomright"
   Special: "fullscreen", "center", "current"

3. MONITOR COUNT CHECKING:
   if (mm.MonitorCount() == 3) {
       // Code for 3 monitor setup
   } else if (mm.MonitorCount() == 2) {
       // Code for 2 monitor setup
   } else {
       // Code for single monitor
   }

4. WINDOW IDENTIFIERS:
   - "A" = Active window
   - "Window Title" = Exact window title
   - "ahk_exe notepad.exe" = By executable
   - "ahk_class ClassName" = By window class
   - WindowHandle = Numeric window handle

5. EXAMPLES:
   // Quick setup for different monitor configs
   if (mm.MonitorCount() == 3) {
       mm.MoveToMonitor("Chrome", "Ultrawide", "lefthalf")
       mm.MoveToMonitor("Notepad", "4K", "righthalf")
       mm.MoveToMonitor("Calculator", "Surface", "center")
   }

   // Hotkeys
   F1::mm.MoveToMonitor("A", "Ultrawide", "lefthalf")
   F2::mm.SnapLeft("A")

================================================================================
*/

class mm {
    ; Monitor configuration - User customizable
    ; Note: No need for separate portrait entries - class automatically checks both orientations
    static MonitorMap := Map(
        "Ultrawide", { aspectRatio: 2.39, tolerance: 0.01 },
        "4K", { aspectRatio: 1.78, tolerance: 0.011 },
        "Surface", { aspectRatio: 1.5, tolerance: 0.01 },
        "iPad", { aspectRatio: 1.33, tolerance: 0.01 },
        "1440", { aspectRatio: 1.77, tolerance: 0.01 },
    )

    ; Position presets
    static PositionMap := Map(
        ; Halves
        "lefthalf", { x: 0, y: 0, w: 0.5, h: 1.0 },
        "righthalf", { x: 0.5, y: 0, w: 0.5, h: 1.0 },
        "middlehalf", { x: 0.25, y: 0, w: 0.5, h: 1.0 },
        "tophalf", { x: 0, y: 0, w: 1.0, h: 0.5 },
        "bottomhalf", { x: 0, y: 0.5, w: 1.0, h: 0.5 },
        ; Thirds
        "leftthird", { x: 0, y: 0, w: 0.333, h: 1.0 },
        "middlethird", { x: 0.333, y: 0, w: 0.334, h: 1.0 },
        "rightthird", { x: 0.666, y: 0, w: 0.334, h: 1.0 },
        "lefttwothirds", { x: 0, y: 0, w: 0.666, h: 1.0 },
        "righttwothirds", { x: 0.333, y: 0, w: 0.667, h: 1.0 },
        ; Quarters
        "topleft", { x: 0, y: 0, w: 0.5, h: 0.5 },
        "topright", { x: 0.5, y: 0, w: 0.5, h: 0.5 },
        "bottomleft", { x: 0, y: 0.5, w: 0.5, h: 0.5 },
        "bottomright", { x: 0.5, y: 0.5, w: 0.5, h: 0.5 },
        ; Special
        "fullscreen", { x: 0, y: 0, w: 1.0, h: 1.0 },
        "center", { x: -1, y: -1, w: -1, h: -1 } ; Special flag for centering
    )

    ; Cache for monitor information - Only updated on reload
    static MonitorCache := Map()
    static MonitorsCached := false
    static PendingOperations := Map() ; Track operations with timeouts

    ; Initialize and cache monitor information - Only once per reload
    static InitializeMonitors() {
        try {
            ; Only cache once per script reload
            if (this.MonitorsCached)
                return true

            this.MonitorCache.Clear()
            monitorCount := MonitorGetCount()

            Loop monitorCount {
                MonitorGet(A_Index, &left, &top, &right, &bottom)
                MonitorGetWorkArea(A_Index, &workLeft, &workTop, &workRight, &workBottom)

                width := right - left
                height := bottom - top
                aspectRatio := width / height

                this.MonitorCache[A_Index] := {
                    index: A_Index,
                    left: left, top: top, right: right, bottom: bottom,
                    workLeft: workLeft, workTop: workTop, workRight: workRight, workBottom: workBottom,
                    width: width, height: height,
                    aspectRatio: aspectRatio,
                    workWidth: workRight - workLeft,
                    workHeight: workBottom - workTop
                }
            }

            this.MonitorsCached := true
            return true
        } catch as err {
            return false
        }
    }

    ; Find monitor by aspect ratio matching (checks both orientations automatically)
    static FindMonitorByName(monitorName) {
        try {
            if (!this.InitializeMonitors())
                return 0

            if (!this.MonitorMap.Has(monitorName))
                return 0

            targetConfig := this.MonitorMap[monitorName]
            targetRatio := targetConfig.aspectRatio
            tolerance := targetConfig.tolerance

            ; Create array of all target ratios to check (original + inverse)
            targetRatios := [targetRatio, 1 / targetRatio]

            bestMatch := 0
            bestDifference := 999999

            ; Check all monitors against all target ratios
            for index, monitor in this.MonitorCache {
                monitorRatios := [monitor.aspectRatio, 1 / monitor.aspectRatio]

                for targetRatio in targetRatios {
                    for monitorRatio in monitorRatios {
                        difference := Abs(monitorRatio - targetRatio)
                        if (difference <= tolerance && difference < bestDifference) {
                            bestMatch := index
                            bestDifference := difference
                        }
                    }
                }
            }

            return bestMatch
        } catch as err {
            return 0
        }
    }

    ; Get monitor count for conditional logic
    static MonitorCount() {
        try {
            return MonitorGetCount()
        } catch as err {
            return 1
        }
    }

    ; Get window handle from various identifier types
    static GetWindowHandle(windowIdentifier) {
        try {
            if (windowIdentifier = "A") {
                ; Try WinGetID first, fallback to WinExist if it fails
                try {
                    return WinGetID("A")
                } catch {
                    return WinExist("A")
                }
            } else if (IsInteger(windowIdentifier)) {
                return windowIdentifier
            } else if (InStr(windowIdentifier, "ahk_")) {
                return WinExist(windowIdentifier)
            } else {
                return WinExist(windowIdentifier)
            }
        } catch as err {
            return 0
        }
    }

    ; Get current monitor of a window
    static GetCurrentMonitor(windowHandle) {
        try {
            if (!this.InitializeMonitors())
                return 1

            WinGetPos(&x, &y, &w, &h, "ahk_id " windowHandle)
            centerX := x + w / 2
            centerY := y + h / 2

            for index, monitor in this.MonitorCache {
                if (centerX >= monitor.left && centerX < monitor.right &&
                    centerY >= monitor.top && centerY < monitor.bottom) {
                    return index
                }
            }
        } catch as err {
            ; Continue to return default
        }
        return 1 ; Default to primary monitor
    }

    ; Parse position parameter into coordinates
    static ParsePosition(position, monitor) {
        try {
            If (Type(position) = "String") {
                if (this.PositionMap.Has(position)) {
                    preset := this.PositionMap[position]
                    if (position = "center") {
                        return { mode: "center" }
                    }
                    return {
                        x: monitor.workLeft + preset.x * monitor.workWidth,
                        y: monitor.workTop + preset.y * monitor.workHeight,
                        w: preset.w * monitor.workWidth,
                        h: preset.h * monitor.workHeight,
                        mode: "absolute"
                    }
                }
            } else if (IsObject(position)) {
                ; Handle object with x, y properties
                result := { mode: "relative" }
                if (position.HasOwnProp("x"))
                    result.x := position.x
                if (position.HasOwnProp("y"))
                    result.y := position.y
                if (position.HasOwnProp("w"))
                    result.w := position.w
                if (position.HasOwnProp("h"))
                    result.h := position.h
                return result
            }
        } catch as err {
            ; Continue to return default
        }

        return { mode: "current" } ; Keep current relative position
    }

    ; Create unique operation ID for timeout tracking
    static CreateOperationId() {
        return A_TickCount . "_" . Random(1000, 9999)
    }

    ; Cleanup expired operations
    static CleanupOperations() {
        try {
            currentTime := A_TickCount
            toRemove := []

            for opId, opData in this.PendingOperations {
                if (currentTime - opData.startTime > opData.timeout) {
                    toRemove.Push(opId)
                }
            }

            for opId in toRemove {
                this.PendingOperations.Delete(opId)
            }
        } catch as err {
            ; Silent cleanup failure
        }
    }

    ; Main move to monitor function with timer support
    static MoveToMonitor(windowIdentifier, monitorName, position := "current", sizeMode := "relative", retryCount := 3, timeout := 5000) {
        ; Clean up old operations
        this.CleanupOperations()

        ; If timeout specified, use timer
        if (timeout > 0) {
            opId := this.CreateOperationId()
            this.PendingOperations[opId] := {
                startTime: A_TickCount,
                timeout: timeout,
                completed: false
            }

            ; Use SetTimer for non-blocking operation
            timerFunc := () => this._ExecuteTimedOperation(opId, windowIdentifier, monitorName, position, sizeMode, retryCount)
            SetTimer(timerFunc, -1) ; Run once immediately
            return opId ; Return operation ID for tracking
        } else {
            ; Blocking operation
            return this._MoveToMonitorInternal(windowIdentifier, monitorName, position, sizeMode, retryCount)
        }
    }

    ; Execute timed operation for MoveToMonitor
    static _ExecuteTimedOperation(opId, windowIdentifier, monitorName, position, sizeMode, retryCount) {
        try {
            result := this._MoveToMonitorInternal(windowIdentifier, monitorName, position, sizeMode, retryCount)
            if (this.PendingOperations.Has(opId)) {
                this.PendingOperations[opId].completed := true
                this.PendingOperations[opId].result := result
            }
        } catch as err {
            if (this.PendingOperations.Has(opId)) {
                this.PendingOperations[opId].completed := true
                this.PendingOperations[opId].result := false
                this.PendingOperations[opId].error := err.message
            }
        }
    }

    ; Internal move function
    static _MoveToMonitorInternal(windowIdentifier, monitorName, position := "current", sizeMode := "relative", retryCount := 3) {
        try {
            ; Get window handle
            windowHandle := this.GetWindowHandle(windowIdentifier)
            if (!windowHandle || !WinExist("ahk_id " windowHandle)) {
                return false
            }

            ; Find target monitor
            targetMonitorIndex := this.FindMonitorByName(monitorName)
            if (!targetMonitorIndex) {
                return false
            }

            ; Get monitor info
            if (!this.InitializeMonitors()) {
                return false
            }

            targetMonitor := this.MonitorCache[targetMonitorIndex]
            currentMonitorIndex := this.GetCurrentMonitor(windowHandle)

            ; If already on target monitor and position is "current", do nothing
            if (currentMonitorIndex = targetMonitorIndex && position = "current") {
                return true
            }

            ; Get current window state and position
            WinGetPos(&currentX, &currentY, &currentW, &currentH, "ahk_id " windowHandle)
            winState := WinGetMinMax("ahk_id " windowHandle)
            wasMaximized := (winState = 1)

            ; Only restore and maximize if it is needed (e.g., if fullscreen is requested)
            if (position = "fullscreen" && !wasMaximized) {
                WinRestore("ahk_id " windowHandle)
                Sleep(100)
                WinMaximize("ahk_id " windowHandle)
            }

            ; Parse position
            posData := this.ParsePosition(position, targetMonitor)

            ; Calculate new position and size
            newX := 0, newY := 0, newW := currentW, newH := currentH

            switch posData.mode {
                case "absolute":
                    newX := posData.x
                    newY := posData.y
                    newW := posData.w
                    newH := posData.h

                case "relative":
                    ; Handle relative positioning
                    if (posData.HasOwnProp("x")) {
                        newX := targetMonitor.workLeft + posData.x * targetMonitor.workWidth
                    } else {
                        ; Keep relative position from current monitor
                        currentMonitor := this.MonitorCache[currentMonitorIndex]
                        relativeX := (currentX - currentMonitor.workLeft) / currentMonitor.workWidth
                        newX := targetMonitor.workLeft + relativeX * targetMonitor.workWidth
                    }

                    if (posData.HasOwnProp("y")) {
                        newY := targetMonitor.workTop + posData.y * targetMonitor.workHeight
                    } else {
                        ; Keep relative position from current monitor
                        currentMonitor := this.MonitorCache[currentMonitorIndex]
                        relativeY := (currentY - currentMonitor.workTop) / currentMonitor.workHeight
                        newY := targetMonitor.workTop + relativeY * targetMonitor.workHeight
                    }

                    if (posData.HasOwnProp("w"))
                        newW := posData.w * targetMonitor.workWidth
                    if (posData.HasOwnProp("h"))
                        newH := posData.h * targetMonitor.workHeight

                case "center":
                    newX := targetMonitor.workLeft + (targetMonitor.workWidth - currentW) / 2
                    newY := targetMonitor.workTop + (targetMonitor.workHeight - currentH) / 2

                case "current":
                    ; Keep relative position
                    currentMonitor := this.MonitorCache[currentMonitorIndex]
                    relativeX := (currentX - currentMonitor.workLeft) / currentMonitor.workWidth
                    relativeY := (currentY - currentMonitor.workTop) / currentMonitor.workHeight
                    newX := targetMonitor.workLeft + relativeX * targetMonitor.workWidth
                    newY := targetMonitor.workTop + relativeY * targetMonitor.workHeight
            }

            ; Ensure window fits within target monitor
            newW := Min(newW, targetMonitor.workWidth)
            newH := Min(newH, targetMonitor.workHeight)
            newX := Max(targetMonitor.workLeft, Min(newX, targetMonitor.workRight - newW))
            newY := Max(targetMonitor.workTop, Min(newY, targetMonitor.workBottom - newH))

            ; Move window with retry logic
            success := false
            Loop retryCount {
                try {
                    WinMove(newX, newY, newW, newH, "ahk_id " windowHandle)
                    Sleep(50)

                    ; Verify the move worked
                    WinGetPos(&verifyX, &verifyY, , , "ahk_id " windowHandle)
                    if (Abs(verifyX - newX) < 10 && Abs(verifyY - newY) < 10) {
                        success := true
                        break
                    }
                } catch as err {
                    Sleep(100 * A_Index) ; Exponential backoff
                }
            }

            ; Restore maximized state if needed
            if (wasMaximized && success) {
                Sleep(100)
                WinMaximize("ahk_id " windowHandle)
            }

            ; Activate and bring to front
            WinActivate("ahk_id " windowHandle)
            WinShow("ahk_id " windowHandle)

            return success

        } catch as err {
            return false
        }
    }

    ; Check operation status (for timed operations)
    static GetOperationStatus(operationId) {
        try {
            if (!this.PendingOperations.Has(operationId)) {
                return { status: "not_found" }
            }

            opData := this.PendingOperations[operationId]
            currentTime := A_TickCount

            if (opData.completed) {
                result := {
                    status: "completed",
                    success: opData.result,
                    duration: currentTime - opData.startTime
                }
                if (opData.HasOwnProp("error")) {
                    result.error := opData.error
                }
                return result
            } else if (currentTime - opData.startTime > opData.timeout) {
                return {
                    status: "timeout",
                    duration: currentTime - opData.startTime
                }
            } else {
                return {
                    status: "running",
                    elapsed: currentTime - opData.startTime,
                    timeout: opData.timeout
                }
            }
        } catch as err {
            return { status: "error", error: err.message }
        }
    }

    ; Snap to left half of current monitor
    static SnapLeft(windowIdentifier := "A", timeout := 5000) {
        if (timeout > 0) {
            opId := this.CreateOperationId()
            this.PendingOperations[opId] := {
                startTime: A_TickCount,
                timeout: timeout,
                completed: false
            }

            timerFunc := () => this._ExecuteSnapLeft(opId, windowIdentifier)
            SetTimer(timerFunc, -1)
            return opId
        }

        ; Blocking version
        try {
            windowHandle := this.GetWindowHandle(windowIdentifier)
            if (!windowHandle || !WinExist("ahk_id " windowHandle)) {
                return false
            }

            if (!this.InitializeMonitors()) {
                return false
            }

            currentMonitorIndex := this.GetCurrentMonitor(windowHandle)
            monitor := this.MonitorCache[currentMonitorIndex]

            winState := WinGetMinMax("ahk_id " windowHandle)
            if (winState = 1)
                WinRestore("ahk_id " windowHandle)

            newX := monitor.workLeft
            newY := monitor.workTop
            newW := monitor.workWidth // 2
            newH := monitor.workHeight

            WinMove(newX, newY, newW, newH, "ahk_id " windowHandle)
            WinActivate("ahk_id " windowHandle)
            WinShow("ahk_id " windowHandle)

            return true
        } catch as err {
            return false
        }
    }

    ; Execute timed operation for SnapLeft
    static _ExecuteSnapLeft(opId, windowIdentifier) {
        try {
            result := this.SnapLeft(windowIdentifier, 0) ; Call blocking version
            if (this.PendingOperations.Has(opId)) {
                this.PendingOperations[opId].completed := true
                this.PendingOperations[opId].result := result
            }
        } catch as err {
            if (this.PendingOperations.Has(opId)) {
                this.PendingOperations[opId].completed := true
                this.PendingOperations[opId].result := false
                this.PendingOperations[opId].error := err.message
            }
        }
    }

    ; Snap to right half of current monitor
    static SnapRight(windowIdentifier := "A", timeout := 5000) {
        if (timeout > 0) {
            opId := this.CreateOperationId()
            this.PendingOperations[opId] := {
                startTime: A_TickCount,
                timeout: timeout,
                completed: false
            }

            timerFunc := () => this._ExecuteSnapRight(opId, windowIdentifier)
            SetTimer(timerFunc, -1)
            return opId
        }

        ; Blocking version
        try {
            windowHandle := this.GetWindowHandle(windowIdentifier)
            if (!windowHandle || !WinExist("ahk_id " windowHandle)) {
                return false
            }

            if (!this.InitializeMonitors()) {
                return false
            }

            currentMonitorIndex := this.GetCurrentMonitor(windowHandle)
            monitor := this.MonitorCache[currentMonitorIndex]

            winState := WinGetMinMax("ahk_id " windowHandle)
            if (winState = 1)
                WinRestore("ahk_id " windowHandle)

            newX := monitor.workLeft + monitor.workWidth // 2
            newY := monitor.workTop
            newW := monitor.workWidth // 2
            newH := monitor.workHeight

            WinMove(newX, newY, newW, newH, "ahk_id " windowHandle)
            WinActivate("ahk_id " windowHandle)
            WinShow("ahk_id " windowHandle)

            return true
        } catch as err {
            return false
        }
    }

    ; Execute timed operation for SnapRight
    static _ExecuteSnapRight(opId, windowIdentifier) {
        try {
            result := this.SnapRight(windowIdentifier, 0) ; Call blocking version
            if (this.PendingOperations.Has(opId)) {
                this.PendingOperations[opId].completed := true
                this.PendingOperations[opId].result := result
            }
        } catch as err {
            if (this.PendingOperations.Has(opId)) {
                this.PendingOperations[opId].completed := true
                this.PendingOperations[opId].result := false
                this.PendingOperations[opId].error := err.message
            }
        }
    }


    ; Execute timed operation for ThrowRight
    static _ExecuteThrowRight(opId, windowIdentifier) {
        try {
            result := this.ThrowRight(windowIdentifier, 0) ; Call blocking version
            if (this.PendingOperations.Has(opId)) {
                this.PendingOperations[opId].completed := true
                this.PendingOperations[opId].result := result
            }
        } catch as err {
            if (this.PendingOperations.Has(opId)) {
                this.PendingOperations[opId].completed := true
                this.PendingOperations[opId].result := false
                this.PendingOperations[opId].error := err.message
            }
        }
    }

    static ThrowRight(windowIdentifier := "A", timeout := 5000) {
    if (timeout > 0) {
        opId := this.CreateOperationId()
        this.PendingOperations[opId] := {
            startTime: A_TickCount,
            timeout: timeout,
            completed: false
        }

        timerFunc := () => this._ExecuteThrowRight(opId, windowIdentifier)
        SetTimer(timerFunc, -1)
        return opId
    }

    ; Blocking version - simple index cycling
    try {
        windowHandle := this.GetWindowHandle(windowIdentifier)
        if (!windowHandle || !WinExist("ahk_id " windowHandle)) {
            return false
        }

        if (!this.InitializeMonitors()) {
            return false
        }

        currentMonitorIndex := this.GetCurrentMonitor(windowHandle)
        currentMonitor := this.MonitorCache[currentMonitorIndex]
        monitorCount := this.MonitorCache.Count
        
        if (monitorCount <= 1) {
            return false
        }

        ; Simple cycling: just go to next index
        targetIndex := currentMonitorIndex + 1
        if (targetIndex > monitorCount) {
            targetIndex := 1
        }

        targetMonitor := this.MonitorCache[targetIndex]

        ; Get current window position and state
        WinGetPos(&currentX, &currentY, &currentW, &currentH, "ahk_id " windowHandle)
        winState := WinGetMinMax("ahk_id " windowHandle)
        wasMaximized := (winState = 1)

        ; Restore if maximized
        if (wasMaximized) {
            WinRestore("ahk_id " windowHandle)
            Sleep(100)
            WinGetPos(&currentX, &currentY, &currentW, &currentH, "ahk_id " windowHandle)
        }

        ; Calculate relative position from current monitor
        relativeX := (currentX - currentMonitor.workLeft) / currentMonitor.workWidth
        relativeY := (currentY - currentMonitor.workTop) / currentMonitor.workHeight

        ; Apply to target monitor
        newX := targetMonitor.workLeft + relativeX * targetMonitor.workWidth
        newY := targetMonitor.workTop + relativeY * targetMonitor.workHeight

        ; Ensure window fits within target monitor
        newW := Min(currentW, targetMonitor.workWidth)
        newH := Min(currentH, targetMonitor.workHeight)
        newX := Max(targetMonitor.workLeft, Min(newX, targetMonitor.workRight - newW))
        newY := Max(targetMonitor.workTop, Min(newY, targetMonitor.workBottom - newH))

        ; Move window with retry logic
        success := false
        Loop 3 {
            try {
                WinMove(newX, newY, newW, newH, "ahk_id " windowHandle)
                Sleep(50)

                ; Verify the move worked
                WinGetPos(&verifyX, &verifyY, , , "ahk_id " windowHandle)
                if (Abs(verifyX - newX) < 10 && Abs(verifyY - newY) < 10) {
                    success := true
                    break
                }
            } catch as err {
                Sleep(100 * A_Index)
            }
        }

        ; Restore maximized state if needed
        if (wasMaximized && success) {
            Sleep(100)
            WinMaximize("ahk_id " windowHandle)
        }

        ; SURFACE AUTO-MAXIMIZE (easily removable block)
        if (success && this._IsSurfaceVertical(targetIndex)) {
            Sleep(200)
            WinMaximize("ahk_id " windowHandle)
        }

        ; Activate and bring to front
        if (success) {
            WinActivate("ahk_id " windowHandle)
            WinShow("ahk_id " windowHandle)
        }

        return success

    } catch as err {
        return false
    }
}

static ThrowLeft(windowIdentifier := "A", timeout := 5000) {
    if (timeout > 0) {
        opId := this.CreateOperationId()
        this.PendingOperations[opId] := {
            startTime: A_TickCount,
            timeout: timeout,
            completed: false
        }

        timerFunc := () => this._ExecuteThrowLeft(opId, windowIdentifier)
        SetTimer(timerFunc, -1)
        return opId
    }

    ; Blocking version - simple index cycling
    try {
        windowHandle := this.GetWindowHandle(windowIdentifier)
        if (!windowHandle || !WinExist("ahk_id " windowHandle)) {
            return false
        }

        if (!this.InitializeMonitors()) {
            return false
        }

        currentMonitorIndex := this.GetCurrentMonitor(windowHandle)
        currentMonitor := this.MonitorCache[currentMonitorIndex]
        monitorCount := this.MonitorCache.Count
        
        if (monitorCount <= 1) {
            return false
        }

        ; Simple cycling: just go to previous index
        targetIndex := currentMonitorIndex - 1
        if (targetIndex < 1) {
            targetIndex := monitorCount
        }

        targetMonitor := this.MonitorCache[targetIndex]

        ; Get current window position and state
        WinGetPos(&currentX, &currentY, &currentW, &currentH, "ahk_id " windowHandle)
        winState := WinGetMinMax("ahk_id " windowHandle)
        wasMaximized := (winState = 1)

        ; Restore if maximized
        if (wasMaximized) {
            WinRestore("ahk_id " windowHandle)
            Sleep(100)
            WinGetPos(&currentX, &currentY, &currentW, &currentH, "ahk_id " windowHandle)
        }

        ; Calculate relative position from current monitor
        relativeX := (currentX - currentMonitor.workLeft) / currentMonitor.workWidth
        relativeY := (currentY - currentMonitor.workTop) / currentMonitor.workHeight

        ; Apply to target monitor
        newX := targetMonitor.workLeft + relativeX * targetMonitor.workWidth
        newY := targetMonitor.workTop + relativeY * targetMonitor.workHeight

        ; Ensure window fits within target monitor
        newW := Min(currentW, targetMonitor.workWidth)
        newH := Min(currentH, targetMonitor.workHeight)
        newX := Max(targetMonitor.workLeft, Min(newX, targetMonitor.workRight - newW))
        newY := Max(targetMonitor.workTop, Min(newY, targetMonitor.workBottom - newH))

        ; Move window with retry logic
        success := false
        Loop 3 {
            try {
                WinMove(newX, newY, newW, newH, "ahk_id " windowHandle)
                Sleep(50)

                ; Verify the move worked
                WinGetPos(&verifyX, &verifyY, , , "ahk_id " windowHandle)
                if (Abs(verifyX - newX) < 10 && Abs(verifyY - newY) < 10) {
                    success := true
                    break
                }
            } catch as err {
                Sleep(100 * A_Index)
            }
        }

        ; Restore maximized state if needed
        if (wasMaximized && success) {
            Sleep(100)
            WinMaximize("ahk_id " windowHandle)
        }

        ; SURFACE AUTO-MAXIMIZE (easily removable block)
        if (success && this._IsSurfaceVertical(targetIndex)) {
            Sleep(200)
            WinMaximize("ahk_id " windowHandle)
        }

        ; Activate and bring to front
        if (success) {
            WinActivate("ahk_id " windowHandle)
            WinShow("ahk_id " windowHandle)
        }

        return success

    } catch as err {
        return false
    }
}

    ; ; Direct throw functions - more reliable approach
    ; ; Throw window to monitor on the right
    ; static ThrowRight(windowIdentifier := "A", timeout := 5000) {
    ;     if (timeout > 0) {
    ;         opId := this.CreateOperationId()
    ;         this.PendingOperations[opId] := {
    ;             startTime: A_TickCount,
    ;             timeout: timeout,
    ;             completed: false
    ;         }

    ;         timerFunc := () => this._ExecuteThrowRight(opId, windowIdentifier)
    ;         SetTimer(timerFunc, -1)
    ;         return opId
    ;     }

    ;     ; Blocking version - direct approach
    ;     try {
    ;         windowHandle := this.GetWindowHandle(windowIdentifier)
    ;         if (!windowHandle || !WinExist("ahk_id " windowHandle)) {
    ;             return false
    ;         }

    ;         if (!this.InitializeMonitors()) {
    ;             return false
    ;         }

    ;         currentMonitorIndex := this.GetCurrentMonitor(windowHandle)
    ;         currentMonitor := this.MonitorCache[currentMonitorIndex]

    ;         ; Find monitor to the right or cycle to next
    ;         targetIndex := 0
    ;         closestDistance := 999999

    ;         for index, monitor in this.MonitorCache {
    ;             if (index != currentMonitorIndex && monitor.left > currentMonitor.right) {
    ;                 distance := monitor.left - currentMonitor.right
    ;                 if (distance < closestDistance) {
    ;                     closestDistance := distance
    ;                     targetIndex := index
    ;                 }
    ;             }
    ;         }

    ;         if (!targetIndex) {
    ;             monitorCount := this.MonitorCache.Count
    ;             if (monitorCount <= 1) {
    ;                 return false
    ;             }
    ;             targetIndex := currentMonitorIndex + 1
    ;             if (targetIndex > monitorCount) {
    ;                 targetIndex := 1
    ;             }
    ;         }

    ;         ; DIRECT MOVE - bypassing MoveToMonitor complexity
    ;         targetMonitor := this.MonitorCache[targetIndex]

    ;         ; Get current window position and state
    ;         WinGetPos(&currentX, &currentY, &currentW, &currentH, "ahk_id " windowHandle)
    ;         winState := WinGetMinMax("ahk_id " windowHandle)
    ;         wasMaximized := (winState = 1)

    ;         ; Restore if maximized
    ;         if (wasMaximized) {
    ;             WinRestore("ahk_id " windowHandle)
    ;             Sleep(100)
    ;             ; Get new size after restore
    ;             WinGetPos(&currentX, &currentY, &currentW, &currentH, "ahk_id " windowHandle)
    ;         }

    ;         ; Calculate relative position from current monitor
    ;         relativeX := (currentX - currentMonitor.workLeft) / currentMonitor.workWidth
    ;         relativeY := (currentY - currentMonitor.workTop) / currentMonitor.workHeight

    ;         ; Apply to target monitor
    ;         newX := targetMonitor.workLeft + relativeX * targetMonitor.workWidth
    ;         newY := targetMonitor.workTop + relativeY * targetMonitor.workHeight

    ;         ; Ensure window fits within target monitor
    ;         newW := Min(currentW, targetMonitor.workWidth)
    ;         newH := Min(currentH, targetMonitor.workHeight)
    ;         newX := Max(targetMonitor.workLeft, Min(newX, targetMonitor.workRight - newW))
    ;         newY := Max(targetMonitor.workTop, Min(newY, targetMonitor.workBottom - newH))

    ;         ; Move window with retry logic
    ;         success := false
    ;         Loop 3 {
    ;             try {
    ;                 WinMove(newX, newY, newW, newH, "ahk_id " windowHandle)
    ;                 Sleep(50)

    ;                 ; Verify the move worked
    ;                 WinGetPos(&verifyX, &verifyY, , , "ahk_id " windowHandle)
    ;                 if (Abs(verifyX - newX) < 10 && Abs(verifyY - newY) < 10) {
    ;                     success := true
    ;                     break
    ;                 }
    ;             } catch as err {
    ;                 Sleep(100 * A_Index)
    ;             }
    ;         }

    ;         ; Restore maximized state if needed
    ;         if (wasMaximized && success) {
    ;             Sleep(100)
    ;             WinMaximize("ahk_id " windowHandle)
    ;         }

    ;         ; SURFACE AUTO-MAXIMIZE (easily removable block)
    ;         ; ================================================
    ;         if (success && this._IsSurfaceVertical(targetIndex)) {
    ;             Sleep(200) ; Wait for move to complete
    ;             WinMaximize("ahk_id " windowHandle)
    ;         }
    ;         ; ================================================

    ;         ; Activate and bring to front
    ;         if (success) {
    ;             WinActivate("ahk_id " windowHandle)
    ;             WinShow("ahk_id " windowHandle)
    ;         }

    ;         return success

    ;     } catch as err {
    ;         return false
    ;     }
    ; }

    ; ; Throw window to monitor on the left
    ; static ThrowLeft(windowIdentifier := "A", timeout := 5000) {
    ;     if (timeout > 0) {
    ;         opId := this.CreateOperationId()
    ;         this.PendingOperations[opId] := {
    ;             startTime: A_TickCount,
    ;             timeout: timeout,
    ;             completed: false
    ;         }

    ;         timerFunc := () => this._ExecuteThrowLeft(opId, windowIdentifier)
    ;         SetTimer(timerFunc, -1)
    ;         return opId
    ;     }

    ;     ; Blocking version - direct approach
    ;     try {
    ;         windowHandle := this.GetWindowHandle(windowIdentifier)
    ;         if (!windowHandle || !WinExist("ahk_id " windowHandle)) {
    ;             return false
    ;         }

    ;         if (!this.InitializeMonitors()) {
    ;             return false
    ;         }

    ;         currentMonitorIndex := this.GetCurrentMonitor(windowHandle)
    ;         currentMonitor := this.MonitorCache[currentMonitorIndex]

    ;         ; Find monitor to the left or cycle to previous
    ;         targetIndex := 0
    ;         closestDistance := 999999

    ;         for index, monitor in this.MonitorCache {
    ;             if (index != currentMonitorIndex && monitor.right < currentMonitor.left) {
    ;                 distance := currentMonitor.left - monitor.right
    ;                 if (distance < closestDistance) {
    ;                     closestDistance := distance
    ;                     targetIndex := index
    ;                 }
    ;             }
    ;         }

    ;         if (!targetIndex) {
    ;             monitorCount := this.MonitorCache.Count
    ;             if (monitorCount <= 1) {
    ;                 return false
    ;             }
    ;             targetIndex := currentMonitorIndex - 1
    ;             if (targetIndex < 1) {
    ;                 targetIndex := monitorCount
    ;             }
    ;         }

    ;         ; DIRECT MOVE - bypassing MoveToMonitor complexity
    ;         targetMonitor := this.MonitorCache[targetIndex]

    ;         ; Get current window position and state
    ;         WinGetPos(&currentX, &currentY, &currentW, &currentH, "ahk_id " windowHandle)
    ;         winState := WinGetMinMax("ahk_id " windowHandle)
    ;         wasMaximized := (winState = 1)

    ;         ; Restore if maximized
    ;         if (wasMaximized) {
    ;             WinRestore("ahk_id " windowHandle)
    ;             Sleep(100)
    ;             ; Get new size after restore
    ;             WinGetPos(&currentX, &currentY, &currentW, &currentH, "ahk_id " windowHandle)
    ;         }

    ;         ; Calculate relative position from current monitor
    ;         relativeX := (currentX - currentMonitor.workLeft) / currentMonitor.workWidth
    ;         relativeY := (currentY - currentMonitor.workTop) / currentMonitor.workHeight

    ;         ; Apply to target monitor
    ;         newX := targetMonitor.workLeft + relativeX * targetMonitor.workWidth
    ;         newY := targetMonitor.workTop + relativeY * targetMonitor.workHeight

    ;         ; Ensure window fits within target monitor
    ;         newW := Min(currentW, targetMonitor.workWidth)
    ;         newH := Min(currentH, targetMonitor.workHeight)
    ;         newX := Max(targetMonitor.workLeft, Min(newX, targetMonitor.workRight - newW))
    ;         newY := Max(targetMonitor.workTop, Min(newY, targetMonitor.workBottom - newH))

    ;         ; Move window with retry logic
    ;         success := false
    ;         Loop 3 {
    ;             try {
    ;                 WinMove(newX, newY, newW, newH, "ahk_id " windowHandle)
    ;                 Sleep(50)

    ;                 ; Verify the move worked
    ;                 WinGetPos(&verifyX, &verifyY, , , "ahk_id " windowHandle)
    ;                 if (Abs(verifyX - newX) < 10 && Abs(verifyY - newY) < 10) {
    ;                     success := true
    ;                     break
    ;                 }
    ;             } catch as err {
    ;                 Sleep(100 * A_Index)
    ;             }
    ;         }

    ;         ; Restore maximized state if needed
    ;         if (wasMaximized && success) {
    ;             Sleep(100)
    ;             WinMaximize("ahk_id " windowHandle)
    ;         }

    ;         ; SURFACE AUTO-MAXIMIZE (easily removable block)
    ;         ; ================================================
    ;         if (success && this._IsSurfaceVertical(targetIndex)) {
    ;             Sleep(200) ; Wait for move to complete
    ;             WinMaximize("ahk_id " windowHandle)
    ;         }
    ;         ; ================================================

    ;         ; Activate and bring to front
    ;         if (success) {
    ;             WinActivate("ahk_id " windowHandle)
    ;             WinShow("ahk_id " windowHandle)
    ;         }

    ;         return success

    ;     } catch as err {
    ;         return false
    ;     }
    ; }

    ; Execute timed operation for ThrowLeft
    static _ExecuteThrowLeft(opId, windowIdentifier) {
        try {
            result := this.ThrowLeft(windowIdentifier, 0) ; Call blocking version
            if (this.PendingOperations.Has(opId)) {
                this.PendingOperations[opId].completed := true
                this.PendingOperations[opId].result := result
            }
        } catch as err {
            if (this.PendingOperations.Has(opId)) {
                this.PendingOperations[opId].completed := true
                this.PendingOperations[opId].result := false
                this.PendingOperations[opId].error := err.message
            }
        }
    }

    ; SnapThrowLeft - Snap to left half, or throw to left monitor if already snapped left
    static SnapThrowLeft(windowIdentifier := "A", timeout := 5000) {
        if (timeout > 0) {
            opId := this.CreateOperationId()
            this.PendingOperations[opId] := {
                startTime: A_TickCount,
                timeout: timeout,
                completed: false
            }

            timerFunc := () => this._ExecuteSnapThrowLeft(opId, windowIdentifier)
            SetTimer(timerFunc, -1)
            return opId
        }

        ; Blocking version
        try {
            windowHandle := this.GetWindowHandle(windowIdentifier)
            if (!windowHandle || !WinExist("ahk_id " windowHandle)) {
                return false
            }

            if (!this.InitializeMonitors()) {
                return false
            }

            currentMonitorIndex := this.GetCurrentMonitor(windowHandle)
            monitor := this.MonitorCache[currentMonitorIndex]

            ; Get current window position
            WinGetPos(&currentX, &currentY, &currentW, &currentH, "ahk_id " windowHandle)

            ; Check if window is already snapped to left half
            leftHalfX := monitor.workLeft
            leftHalfW := monitor.workWidth // 2

            ; Consider it "snapped left" if it's close to left half position and size
            isSnappedLeft := (Abs(currentX - leftHalfX) < 20 &&
                Abs(currentW - leftHalfW) < 20 &&
                currentY <= monitor.workTop + 20 &&
                currentH >= monitor.workHeight - 40)

            if (isSnappedLeft) {
                ; Already snapped left, throw to left monitor
                return this.ThrowLeft(windowHandle, 0)
            } else {
                ; Not snapped left, snap to left half
                return this.SnapLeft(windowHandle, 0)
            }

        } catch as err {
            return false
        }
    }

    ; Execute timed operation for SnapThrowLeft
    static _ExecuteSnapThrowLeft(opId, windowIdentifier) {
        try {
            result := this.SnapThrowLeft(windowIdentifier, 0) ; Call blocking version
            if (this.PendingOperations.Has(opId)) {
                this.PendingOperations[opId].completed := true
                this.PendingOperations[opId].result := result
            }
        } catch as err {
            if (this.PendingOperations.Has(opId)) {
                this.PendingOperations[opId].completed := true
                this.PendingOperations[opId].result := false
                this.PendingOperations[opId].error := err.message
            }
        }
    }

    ; SnapThrowRight - Snap to right half, or throw to right monitor if already snapped right
    static SnapThrowRight(windowIdentifier := "A", timeout := 5000) {
        if (timeout > 0) {
            opId := this.CreateOperationId()
            this.PendingOperations[opId] := {
                startTime: A_TickCount,
                timeout: timeout,
                completed: false
            }

            timerFunc := () => this._ExecuteSnapThrowRight(opId, windowIdentifier)
            SetTimer(timerFunc, -1)
            return opId
        }

        ; Blocking version
        try {
            windowHandle := this.GetWindowHandle(windowIdentifier)
            if (!windowHandle || !WinExist("ahk_id " windowHandle)) {
                return false
            }

            if (!this.InitializeMonitors()) {
                return false
            }

            currentMonitorIndex := this.GetCurrentMonitor(windowHandle)
            monitor := this.MonitorCache[currentMonitorIndex]

            ; Get current window position
            WinGetPos(&currentX, &currentY, &currentW, &currentH, "ahk_id " windowHandle)

            ; Check if window is already snapped to right half
            rightHalfX := monitor.workLeft + monitor.workWidth // 2
            rightHalfW := monitor.workWidth // 2

            ; Consider it "snapped right" if it's close to right half position and size
            isSnappedRight := (Abs(currentX - rightHalfX) < 20 &&
                Abs(currentW - rightHalfW) < 20 &&
                currentY <= monitor.workTop + 20 &&
                currentH >= monitor.workHeight - 40)

            if (isSnappedRight) {
                ; Already snapped right, throw to right monitor
                return this.ThrowRight(windowHandle, 0)
            } else {
                ; Not snapped right, snap to right half
                return this.SnapRight(windowHandle, 0)
            }

        } catch as err {
            return false
        }
    }

    ; Execute timed operation for SnapThrowRight
    static _ExecuteSnapThrowRight(opId, windowIdentifier) {
        try {
            result := this.SnapThrowRight(windowIdentifier, 0) ; Call blocking version
            if (this.PendingOperations.Has(opId)) {
                this.PendingOperations[opId].completed := true
                this.PendingOperations[opId].result := result
            }
        } catch as err {
            if (this.PendingOperations.Has(opId)) {
                this.PendingOperations[opId].completed := true
                this.PendingOperations[opId].result := false
                this.PendingOperations[opId].error := err.message
            }
        }
    }

    ; Helper method to check if monitor is Surface in vertical mode (easily removable)
    static _IsSurfaceVertical(monitorIndex) {
        try {
            if (!this.MonitorCache.Has(monitorIndex))
                return false

            monitor := this.MonitorCache[monitorIndex]

            ; Check if it matches Surface aspect ratio (1.5) in vertical mode
            ; Vertical mode means height > width, so aspectRatio < 1
            if (monitor.aspectRatio < 1) {
                invertedRatio := 1 / monitor.aspectRatio
                surfaceConfig := this.MonitorMap["Surface"]
                difference := Abs(invertedRatio - surfaceConfig.aspectRatio)
                return (difference <= surfaceConfig.tolerance)
            }

            return false
        } catch as err {
            return false
        }
    }


    ; GESTURE METHODS
    ; ===============




    ; Gesture UR - Up-Right: Maximize or Enter Fullscreen
    static GestureUR(windowIdentifier := "A") {
        try {
            windowHandle := this.GetWindowHandle(windowIdentifier)
            if (!windowHandle || !WinExist("ahk_id " windowHandle)) {
                return false
            }

            minMax := WinGetMinMax("ahk_id " windowHandle)
            isFullscreen := this.IsWindowFullscreen(windowHandle)

            if (minMax = 0) {
                WinMaximize("ahk_id " windowHandle)
            } else if (minMax = 1 && !isFullscreen) {
                Send("{F11}")
            }
            ; If already fullscreen (minMax = 1 and isFullscreen), do nothing

            return true
        } catch as err {
            return false
        }
    }

    static TryMax(windowIdentifier := "A") {
        try {
            windowHandle := this.GetWindowHandle(windowIdentifier)
            if (!windowHandle || !WinExist("ahk_id " windowHandle)) {
                return false
            }
            WinMaximize("ahk_id " windowHandle)
            return true
        } catch as err {
            return false
        }
    }

    ; Gesture DL - Down-Left: Exit Fullscreen or Restore
    static GestureDL(windowIdentifier := "A") {
        try {
            windowHandle := this.GetWindowHandle(windowIdentifier)
            if (!windowHandle || !WinExist("ahk_id " windowHandle)) {
                return false
            }

            minMax := WinGetMinMax("ahk_id " windowHandle)
            isFullscreen := this.IsWindowFullscreen(windowHandle)

            if (minMax = 1 && isFullscreen) {
                Send("{F11}")
            } else if (minMax = 1 && !isFullscreen) {
                WinRestore("ahk_id " windowHandle)
            }
            ; If normal window (minMax = 0), do nothing

            return true
        } catch as err {
            return false
        }
    }

    ; Gesture DR - Down-Right: Minimize Window
    static GestureDR(windowIdentifier := "A") {
        try {
            windowHandle := this.GetWindowHandle(windowIdentifier)
            if (!windowHandle || !WinExist("ahk_id " windowHandle)) {
                return false
            }
        ; if you want to have certain programs just be hidden instead of closed, edit here
            ; if WinActive("ahk_exe PhoneExperienceHost.exe") ||  WinActive("ahk_class Chrome_WidgetWin_1 ahk_exe msedge.exe") || Winactive("ahk_exe zen.exe") || WinActive("Med School - Anki ahk_exe Anki.exe") || WinActive("ahk_class Chrome_WidgetWin_1 ahk_exe Spotify.exe") || WinActive('Phone Link') || WinActive("Checklist:") || WinActive("Task List")
            ; {
            ;     try WinHide("A")
            ;     return true
            ; }
            ; else
            {

                WinMinimize("ahk_id " windowHandle)
                return true
            }
        } catch as err {
            return false
        }
    }

    ; Gesture UL - Up-Left: Close Window
    static GestureUL(windowIdentifier := "A") {
        try {
            windowHandle := this.GetWindowHandle(windowIdentifier)
            if (!windowHandle || !WinExist("ahk_id " windowHandle)) {
                return false
            }
            if  WinActive("ahk_class Chrome_WidgetWin_1 ahk_exe msedge.exe") 
            {
            try
            {
            browserEl := UIA.ElementFromHandle(WinActive("ahk_exe msedge.exe"))
            browserEl.FindElement({LocalizedType:"button", Name:"Close", AutomationId:"view_1051"}).Click()
            }

            }
try
            {

                WinClose("ahk_id " windowHandle)
                return true
            }
        } catch as err {
            return false
        }
    }

    static GestureULDR(windowIdentifier := "A") {
        try {
            windowHandle := this.GetWindowHandle(windowIdentifier)
            if (!windowHandle || !WinExist("ahk_id " windowHandle)) {
                return false
            }
            
            WinClose("ahk_id " windowHandle)
            return true
        }
    }

    ; Gesture D - Down: Resize Window to 90% Height, Centered
    static GestureD(windowIdentifier := "A") {
        try {
            windowHandle := this.GetWindowHandle(windowIdentifier)
            if (!windowHandle || !WinExist("ahk_id " windowHandle)) {
                return false
            }

            if (!this.InitializeMonitors()) {
                return false
            }

            currentMonitorIndex := this.GetCurrentMonitor(windowHandle)
            monitor := this.MonitorCache[currentMonitorIndex]

            ; Restore if maximized
            if (WinGetMinMax("ahk_id " windowHandle) = 1) {
                WinRestore("ahk_id " windowHandle)
                Sleep(100)
            }

            targetHeight := monitor.workHeight * 0.9
            targetWidth := Min(targetHeight * 1.7, monitor.workWidth)
            newX := monitor.workLeft + (monitor.workWidth - targetWidth) / 2
            newY := monitor.workTop + (monitor.workHeight - targetHeight) / 2

            WinMove(newX, newY, targetWidth, targetHeight, "ahk_id " windowHandle)
            WinActivate("ahk_id " windowHandle)
            WinShow("ahk_id " windowHandle)

            return true
        } catch as err {
            return false
        }
    }

    ; Gesture U - Up: Context-Sensitive Actions
    static GestureU(windowIdentifier := "A") {
        try {
            windowHandle := this.GetWindowHandle(windowIdentifier)
            if (!windowHandle || !WinExist("ahk_id " windowHandle)) {
                return false
            }

            ; Get window process name
            processName := WinGetProcessName("ahk_id " windowHandle)

            ; Define process-to-action mapping
            actionMap := Map(
                "chrome.exe", "^w",
                "msedge.exe", "^w",
                "zen.exe", "^w",
                "firefox.exe", "^w",
                "thorium.exe", "^w",
                "floorp.exe", "^w",
                "ONENOTE.EXE", "^!{h}"
            )

            ; Get action, default to empty string for unknown processes
            action := actionMap.Get(processName, "")
            Send(action)

            ; Return true if process is in map, false otherwise
            return actionMap.Has(processName)
        } catch as err {
            return false
        }
    }

    ; Helper method to detect fullscreen windows
    static IsWindowFullscreen(windowHandle) {
        try {
            ; Get window position and size
            WinGetPos(&x, &y, &width, &height, "ahk_id " windowHandle)

            ; Get monitor info for the window
            currentMonitorIndex := this.GetCurrentMonitor(windowHandle)
            if (!this.MonitorCache.Has(currentMonitorIndex)) {
                return false
            }

            monitor := this.MonitorCache[currentMonitorIndex]

            ; Check if window covers entire monitor (including taskbar area)
            return (x <= monitor.left &&
                y <= monitor.top &&
                width >= monitor.width &&
                height >= monitor.height)
        } catch as err {
            return false
        }
    }


}


; BASIC USAGE:
; mm.MoveToMonitor("Notepad", "Ultrawide", "lefthalf")
; mm.MoveToMonitor("Chrome", "4K", "rightthird")
; mm.MoveToMonitor("A", "Surface", "fullscreen")

; CUSTOM POSITIONING:
; mm.MoveToMonitor("Terminal", "Ultrawide", {x: 0.65, y: 0.065})
; mm.MoveToMonitor("App", "4K", {x: 0.5, y: 0.2, w: 0.8, h: 0.6})

; TIMER SUPPORT (non-blocking with 5 second timeout):
; opId := mm.MoveToMonitor("Window", "4K", "lefthalf", "relative", 3, 5000)
; ; Check status later:
; status := mm.GetOperationStatus(opId)

; SNAP FUNCTIONS:
; mm.SnapLeft("A")
; mm.SnapRight("Notepad")
; ; With timeout:
; opId := mm.SnapLeft("A", 3000)

; Hotkey examples (uncomment to use):
; F1::mm.MoveToMonitor("A", "Ultrawide", "lefthalf")
; F2::mm.MoveToMonitor("A", "4K", "righthalf")e
; F3::mm.SnapLeft("A")
; F4::mm.SnapRight("A")
; F5::{
;     opId := mm.MoveToMonitor("A", "Ultrawide", "center", "relative", 3, 2000)
;     ; Could check status later if needed
; }
