class globals {

static activaterun(winTitle, url := "", skipsearch := false, skipLoop := false, showtooltips := false) {
    ; Set tooltip flag
    tabactivator.showtooltips := showtooltips

    ; Initialize cache system
    if (!tabactivator.HasOwnProp("tabindextracker")) {
        tabactivator.tabindextracker := Map()
    }
    if (!tabactivator.HasOwnProp("browseritemcache")) {
        tabactivator.browseritemcache := []
    }
    if (!tabactivator.HasOwnProp("cachebuilding")) {
        tabactivator.cachebuilding := false
    }
    if (!tabactivator.HasOwnProp("initialcachecomplete")) {
        tabactivator.initialcachecomplete := false
    }

    ; Handle skipLoop - just open new tab and return
    if (skipLoop) {
        if (url != "") {
            if (showtooltips) {
                ToolTip("Skip loop - running Run...")
                SetTimer () => ToolTip(), -1000
            }
            Run(url)
        }
        return
    }

    ; Check if Edge exists, if not activate it
    if (!WinExist("ahk_exe msedge.exe")) {
        if (showtooltips) {
            ToolTip("Edge not found - activating Edge...")
            SetTimer () => ToolTip(), -1000
        }
        Run(url)
        WinWaitActive("ahk_exe msedge.exe")

        ; Build initial cache for new Edge instance
        tabactivator.buildinitialcachewithotherbrowers(winTitle, url)
        return
    }

    ; Edge exists - check special case: already on matching tab with only 1 match
    if (tabactivator.initialcachecomplete && WinActive("ahk_exe msedge.exe")) {
        try {
            currentTitle := WinGetTitle("A")
            if (InStr(StrLower(currentTitle), StrLower(winTitle))) {
                matchingItems := tabactivator.findmatchesincache(winTitle)
                if (matchingItems.Length == 1) {
                        if (url != "") {
                            if (showtooltips) {
                                ToolTip("On matching tab with 1 match - creating new tab...")
                                SetTimer () => ToolTip(), -1000
                            }
                            Run(url)
                            tabactivator.waitfornewTabandcache(winTitle)
                            tabactivator.startbackgroundcacheupdate()
                        }
                        return
                    }
                }
        }
    }

    ; Edge exists - check if cache is built and handle rotation
    isEdgeActive := WinActive("ahk_exe msedge.exe")

    if (tabactivator.initialcachecomplete) {
        ; Cache exists, use rotation logic
        if (isEdgeActive) {
            tabactivator.handleedgeactivewithcache(winTitle, url, skipsearch)
        } else {
            tabactivator.handleedgeinactivewithcache(winTitle, url)
        }
    } else {
        ; Cache not built yet
        if (isEdgeActive) {
            tabactivator.handleedgeactivenocache(winTitle, url)
        } else {
            tabactivator.handleedgeinactivenocache(winTitle, url)
        }
    }
}
}

class tabactivator {
    ; Static properties for caching and tracking
    static tabindextracker := Map()
    static browseritemcache := []
    static cachebuilding := false
    static initialcachecomplete := false
    static cacheworkertimer := ""
    static showtooltips := false

    ; Build initial cache including other browsers when Edge is new
    static buildinitialcachewithotherbrowers(winTitle, url) {
        if (tabactivator.showtooltips) {
            ToolTip("Building initial cache with other browsers...")
            SetTimer () => ToolTip(), -1000
        }
        
        ; Initialize cache with other browser windows
        tabactivator.browseritemcache := []
        otherBrowserItems := tabactivator.addotherbrowserwindows()
        for item in otherBrowserItems {
            tabactivator.browseritemcache.Push(item)
            ; Assign initial tracker index if matching winTitle
            if (InStr(StrLower(item.title), StrLower(winTitle))) {
                tabactivator.tabindextracker[winTitle] := tabactivator.browseritemcache.Length
            }
        }

        ; Build Edge cache
        tabactivator.buildinitialedgecache(winTitle, url)
    }

    ; Add Chrome, Firefox, Zen windows to cache
    static addotherbrowserwindows() {
        if (tabactivator.showtooltips) {
            ToolTip("Adding other browser windows to cache...")
            SetTimer () => ToolTip(), -1000
        }

        browsers := ["chrome.exe", "firefox.exe", "zen.exe"]
        newItems := [] ; Temporary array to collect non-Edge windows

        for browser in browsers {
            hwnds := WinGetList("ahk_exe " . browser)
            ; Sort hwnds ascending for consistent order
            Loop (hwnds.Length - 1) {
                i := A_Index
                Loop (hwnds.Length - i) {
                    j := A_Index
                    if (hwnds[j] > hwnds[j + 1]) {
                        temp := hwnds[j]
                        hwnds[j] := hwnds[j + 1]
                        hwnds[j + 1] := temp
                    }
                }
            }
            for hwnd in hwnds {
                try {
                    title := WinGetTitle("ahk_id " . hwnd)
                    if (title != "" && title != "New Tab") {
                        newItems.Push({title: title, activator: hwnd, type: "window", browser: StrReplace(browser, ".exe", "")})
                    }
                } catch {
                    continue
                }
            }
        }
        return newItems
    }

    ; Build initial Edge cache (non-interruptible, progressive availability)
    ; Scans ALL Edge windows without activation
    static buildinitialedgecache(winTitle, url) {
        if (tabactivator.showtooltips) {
            ToolTip("Building initial Edge cache...")
            SetTimer () => ToolTip(), -1000
        }

        matchFound := false
        lowerPattern := StrLower(winTitle)

        edgeHwnds := WinGetList("ahk_exe msedge.exe")
        ; Sort edgeHwnds ascending for consistent order
        Loop (edgeHwnds.Length - 1) {
            i := A_Index
            Loop (edgeHwnds.Length - i) {
                j := A_Index
                if (edgeHwnds[j] > edgeHwnds[j + 1]) {
                    temp := edgeHwnds[j]
                    edgeHwnds[j] := edgeHwnds[j + 1]
                    edgeHwnds[j + 1] := temp
                }
            }
        }

        ; Loop through sorted Edge windows
        for hwnd in edgeHwnds {
            if (!WinExist("ahk_id " . hwnd)) {
                continue
            }

            try {
                edgeEl := UIA.ElementFromHandle(hwnd)
                ; tabbar := edgeEl.FindElement({LocalizedType:"region", ClassName:"EdgeTabStrip"}, 4, 1, 2)
                tabBar := edgeEl.FindElement({AutomationId:"view_25"}, 4, 1, 2)
                tabs := tabbar.FindAll({Type: "TabItem", ClassName:"EdgeTab"})

                Loop tabs.Length {
                    try {
                        tab := tabs[A_Index]
                        tabName := tab.GetCurrentPropertyValue("Name")
                        if (tabName != "" && tabName != "New Tab") {
                            tabRuntimeId := tab.GetRuntimeId()
                            tabactivator.browseritemcache.Push({title: tabName, hwnd: hwnd, type: "tab", browser: "edge", tabIndex: A_Index, runtimeId: tabRuntimeId})

                            ; Check if this tab matches our search - activate if found
                            if (!matchFound && InStr(StrLower(tabName), lowerPattern)) {
                                if (tabactivator.showtooltips) {
                                    ToolTip("Match found - activating tab...")
                                    SetTimer () => ToolTip(), -1000
                                }
                                WinActivate("ahk_id " . hwnd)
                                WinWaitActive("ahk_id " . hwnd, , 2)
                                tab.Select()
                                matchFound := true
                                tabactivator.tabindextracker[winTitle] := tabactivator.browseritemcache.Length
                            }
                        }
                    } catch {
                        continue
                    }
                }
            } 
        }

        ; If no match found and URL provided, create new tab
        if (!matchFound && url != "") {
            if (tabactivator.showtooltips) {
                ToolTip("No match found - creating new tab...")
                SetTimer () => ToolTip(), -1000
            }
            Run(url)
            ; Wait for new tab to be active, then add to cache
            tabactivator.waitfornewTabandcache(winTitle)
        }

        tabactivator.initialcachecomplete := true
        if (tabactivator.showtooltips) {
            ToolTip("Initial cache complete!")
            SetTimer () => ToolTip(), -1000
        }
    }

    static handleedgeactivewithcache(winTitle, url, skipsearch) {
        if (tabactivator.showtooltips) {
            ToolTip("Handling Edge active with cache...")
            SetTimer () => ToolTip(), -1000
        }

        matchingItems := tabactivator.findmatchesincache(winTitle)

        if (matchingItems.Length == 0) {
            ; No matches, create new tab
            if (url != "") {
                if (tabactivator.showtooltips) {
                    ToolTip("No matches - creating new tab...")
                    SetTimer () => ToolTip(), -1000
                }
                Run(url)
                tabactivator.waitfornewTabandcache(winTitle)
                tabactivator.startbackgroundcacheupdate()
            }
            return
        }

        if (skipsearch) {
            ; Just activate first match
            try {
                if (tabactivator.showtooltips) {
                    ToolTip("Activating first match (skip search)...")
                    SetTimer () => ToolTip(), -1000
                }
                tabactivator.activateitem(matchingItems[1])
                tabactivator.tabindextracker[winTitle] := 1
                if (tabactivator.shouldupdatecache(matchingItems[1])) {
                    tabactivator.startbackgroundcacheupdate()
                }
            } catch {
                ; Failed to activate - rebuild cache and try again
                if (tabactivator.showtooltips) {
                    ToolTip("Activation failed - rebuilding cache...")
                    SetTimer () => ToolTip(), -1000
                }
                tabactivator.rebuildfullcache()
                matchingItems := tabactivator.findmatchesincache(winTitle)
                if (matchingItems.Length == 0) {
                    ; Still no matches after rebuild, create new tab
                    if (url != "") {
                        if (tabactivator.showtooltips) {
                            ToolTip("Still no matches - creating new tab...")
                            SetTimer () => ToolTip(), -1000
                        }
                        Run(url)
                        tabactivator.waitfornewTabandcache(winTitle)
                    }
                } else {
                    ; Try first match again
                    try {
                        tabactivator.activateitem(matchingItems[1])
                        tabactivator.tabindextracker[winTitle] := 1
                    }
                }
            }
            return
        }

        ; Handle cycling logic
        currentMatchIndex := tabactivator.getcurrentmatchindex(matchingItems)

        ; Cycle through all matching items (tabs and windows)
        nextIndex := 1
        if (currentMatchIndex > 0) {
            ; On a matching item, move to next
            nextIndex := (currentMatchIndex >= matchingItems.Length) ? 1 : currentMatchIndex + 1
        } else if (tabactivator.tabindextracker.Has(winTitle)) {
            ; Not on a matching item, use previous index
            nextIndex := tabactivator.tabindextracker[winTitle] + 1
            if (nextIndex > matchingItems.Length || nextIndex < 1) {
                nextIndex := 1
            }
        }

        targetItem := matchingItems[nextIndex]
        try {
            if (tabactivator.showtooltips) {
                ToolTip("Cycling to match " . nextIndex . " of " . matchingItems.Length)
                SetTimer () => ToolTip(), -1000
            }
            tabactivator.activateitem(targetItem)
            tabactivator.tabindextracker[winTitle] := nextIndex
            if (tabactivator.shouldupdatecache(targetItem)) {
                tabactivator.startbackgroundcacheupdate()
            }
        } catch {
            ; Failed to activate - rebuild cache and try again
            if (tabactivator.showtooltips) {
                ToolTip("Activation failed - rebuilding cache...")
                SetTimer () => ToolTip(), -1000
            }
            tabactivator.rebuildfullcache()
            matchingItems := tabactivator.findmatchesincache(winTitle)
            if (matchingItems.Length == 0) {
                ; No matches after rebuild, create new tab
                if (url != "") {
                    if (tabactivator.showtooltips) {
                        ToolTip("No matches after rebuild - creating new tab...")
                        SetTimer () => ToolTip(), -1000
                    }
                    Run(url)
                    tabactivator.waitfornewTabandcache(winTitle)
                }
            } else {
                ; Try to activate first match
                try {
                    tabactivator.activateitem(matchingItems[1])
                    tabactivator.tabindextracker[winTitle] := 1
                }
            }
        }
    }

    static shouldupdatecache(targetItem) {
        currentHwnd := WinGetID("A")
        currentProcess := WinGetProcessName("ahk_id " . currentHwnd)

        ; Update cache when switching between Edge and non-Edge browsers
        if (targetItem.type == "tab" && currentProcess != "msedge.exe") {
            return true  ; Switching TO Edge
        }
        if (targetItem.type == "window" && currentProcess == "msedge.exe") {
            return true  ; Switching FROM Edge
        }

        return false  ; Staying within same browser type
    }

    static handleedgeinactivewithcache(winTitle, url) {
        if (tabactivator.showtooltips) {
            ToolTip("Handling Edge inactive with cache...")
            SetTimer () => ToolTip(), -1000
        }

        matchingItems := tabactivator.findmatchesincache(winTitle)

        if (matchingItems.Length == 0) {
            ; No matches, activate Edge and create new tab
            if (tabactivator.showtooltips) {
                ToolTip("No matches - activating Edge...")
                SetTimer () => ToolTip(), -1000
            }
            Run("ahk_exe msedge.exe")
            WinWaitActive("ahk_exe msedge.exe")
            if (url != "") {
                Run(url)
                tabactivator.waitfornewTabandcache(winTitle)
                tabactivator.startbackgroundcacheupdate()
            }
            return
        }

        ; Handle cycling logic
        currentMatchIndex := tabactivator.getcurrentmatchindex(matchingItems)

        ; Cycle through all matching items (tabs and windows)
        nextIndex := 1
        if (currentMatchIndex > 0) {
            ; On a matching item, move to next
            nextIndex := (currentMatchIndex >= matchingItems.Length) ? 1 : currentMatchIndex + 1
        } else if (tabactivator.tabindextracker.Has(winTitle)) {
            ; Not on a matching item, use previous index
            nextIndex := tabactivator.tabindextracker[winTitle] + 1
            if (nextIndex > matchingItems.Length || nextIndex < 1) {
                nextIndex := 1
            }
        }

        targetItem := matchingItems[nextIndex]
        if (targetItem.type == "tab") {
            WinActivate("ahk_id " . targetItem.hwnd)
            WinWaitActive("ahk_id " . targetItem.hwnd, , 2)
        }

        try {
            if (tabactivator.showtooltips) {
                ToolTip("Cycling to match " . nextIndex . " of " . matchingItems.Length)
                SetTimer () => ToolTip(), -1000
            }
            tabactivator.activateitem(targetItem)
            tabactivator.tabindextracker[winTitle] := nextIndex
            tabactivator.startbackgroundcacheupdate()
        } catch {
            ; Failed to activate - rebuild cache and try again
            if (tabactivator.showtooltips) {
                ToolTip("Activation failed - rebuilding cache...")
                SetTimer () => ToolTip(), -1000
            }
            tabactivator.rebuildfullcache()
            matchingItems := tabactivator.findmatchesincache(winTitle)
            if (matchingItems.Length == 0) {
                ; No matches after rebuild, activate Edge and create new tab
                if (tabactivator.showtooltips) {
                    ToolTip("No matches after rebuild - activating Edge...")
                    SetTimer () => ToolTip(), -1000
                }
                Run("ahk_exe msedge.exe")
                WinWaitActive("ahk_exe msedge.exe")
                if (url != "") {
                    Run(url)
                    tabactivator.waitfornewTabandcache(winTitle)
                }
            } else {
                ; Try to activate first match
                targetItem := matchingItems[1]
                if (targetItem.type == "tab") {
                    WinActivate("ahk_id " . targetItem.hwnd)
                    WinWaitActive("ahk_id " . targetItem.hwnd, , 2)
                }
                try {
                    tabactivator.activateitem(targetItem)
                    tabactivator.tabindextracker[winTitle] := 1
                }
            }
        }
    }

    ; Handle when Edge is active but no cache
    static handleedgeactivenocache(winTitle, url) {
        if (tabactivator.showtooltips) {
            ToolTip("Edge active - building initial cache...")
            SetTimer () => ToolTip(), -1000
        }
        tabactivator.buildinitialedgecache(winTitle, url)
    }

    ; Handle when Edge is inactive and no cache
    static handleedgeinactivenocache(winTitle, url) {
        if (tabactivator.showtooltips) {
            ToolTip("Edge inactive - activating and building cache...")
            SetTimer () => ToolTip(), -1000
        }
        Run("ahk_exe msedge.exe")
        WinWaitActive("ahk_exe msedge.exe")
        tabactivator.buildinitialcachewithotherbrowers(winTitle, url)
    }

    ; Wait for new tab to be active and add to cache
static waitfornewTabandcache(winTitle) {
    if (tabactivator.showtooltips) {
        ToolTip("Waiting for new tab...")
        SetTimer () => ToolTip(), -1000
    }

    Loop 50 {
        try {
            currentTitle := WinGetTitle("A")
            if (InStr(StrLower(currentTitle), StrLower(winTitle))) {
                ; Found new tab, get UIA element and add to cache
                if (tabactivator.showtooltips) {
                    ToolTip("New tab found - adding to cache...")
                    SetTimer () => ToolTip(), -1000
                }
                currentHwnd := WinGetID("A")
                WinWaitActive("ahk_id " . currentHwnd, , 2)
                edgeEl := UIA.ElementFromHandle(currentHwnd)
                ; tabbar := edgeEl.FindElement({LocalizedType:"region", ClassName:"EdgeTabStrip"}, 4, 1, 2)
                tabBar := edgeEl.FindElement({AutomationId:"view_25"}, 4, 1, 2)
                tabs := tabbar.FindAll({Type: "TabItem", ClassName:"EdgeTab"})
                currentActiveTab := tabactivator.getcurrentactiveedgetab(edgeEl)
                currentTabIndex := 0
                for i, tab in tabs {
                    if (tabactivator.arraysequal(tab.GetRuntimeId(), currentActiveTab.GetRuntimeId())) {
                        currentTabIndex := i
                        break
                    }
                }
                if (currentTabIndex) {
                    tabName := currentActiveTab.GetCurrentPropertyValue("Name")
                    tabRuntimeId := currentActiveTab.GetRuntimeId()
                    tabactivator.browseritemcache.Push({title: tabName, hwnd: currentHwnd, type: "tab", browser: "edge", tabIndex: currentTabIndex, runtimeId: tabRuntimeId})
                    tabactivator.tabindextracker[winTitle] := tabactivator.browseritemcache.Length
                }
                break
            }
        } 
        Sleep(100)
    }
}

    ; Find matches in cache
    static findmatchesincache(winTitle) {
        matchingItems := []

        for cachedItem in tabactivator.browseritemcache {
            if (InStr(StrLower(cachedItem.title), StrLower(winTitle))) {
                matchingItems.Push(cachedItem)
            }
        }

        return matchingItems
    }

    static activateitem(item) {
        if (item.type == "tab") {
            ; Check if window still exists
            if (!WinExist("ahk_id " . item.hwnd)) {
                throw Error("Window no longer exists")
            }

            ; Ensure the correct Edge window is active before attempting tab selection
            if (WinGetID("A") != item.hwnd) {
                WinActivate("ahk_id " . item.hwnd)
                if (!WinWaitActive("ahk_id " . item.hwnd, , 3)) {
                    throw Error("Failed to activate window")
                }
            }

            ; Proceed with tab selection - search by RuntimeId
            edgeEl := UIA.ElementFromHandle(item.hwnd)
            tabbar := edgeEl.FindElement({LocalizedType:"region", ClassName:"EdgeTabStrip"}, 4, 1, 2)
            tabs := tabbar.FindAll({Type: "TabItem", ClassName:"EdgeTab"})
            
            ; Find tab by matching RuntimeId
            tabFound := false
            Loop tabs.Length {
                try {
                    currentTab := tabs[A_Index]
                    currentRuntimeId := currentTab.GetRuntimeId()
                    if (tabactivator.arraysequal(currentRuntimeId, item.runtimeId)) {
                        currentTab.Select()
                        tabFound := true
                        break
                    }
                } catch {
                    continue
                }
            }
            
            if (!tabFound) {
                throw Error("Tab no longer exists")
            }
        } else {
            ; Check if other browser window still exists
            if (!WinExist("ahk_id " . item.activator)) {
                throw Error("Window no longer exists")
            }

            ; Other browser window - activate with retry
            Loop 3 {
                try {
                    WinActivate("ahk_id " . item.activator)
                    WinWaitActive("ahk_id " . item.activator, , 1)
                    break
                } catch {
                    if (A_Index < 3) {
                        Sleep(50)
                    } else {
                        throw Error("Failed to activate window")
                    }
                }
            }
        }
    }

    static getcurrentmatchindex(matchingItems) {
        currentHwnd := WinGetID("A")
        currentProcess := WinGetProcessName("ahk_id " . currentHwnd)

        if (currentProcess == "msedge.exe") {
            try {
                WinWaitActive("ahk_id " . currentHwnd, , 2)
                edgeEl := UIA.ElementFromHandle(currentHwnd)
                ; tabbar := edgeEl.FindElement({LocalizedType:"region", ClassName:"EdgeTabStrip"}, 4, 1, 2)
                tabBar := edgeEl.FindElement({AutomationId:"view_25"}, 4, 1, 2)
                tabs := tabbar.FindAll({Type: "TabItem", ClassName:"EdgeTab"})
                currentActiveTab := tabactivator.getcurrentactiveedgetab(edgeEl)
                if (!currentActiveTab)
                    return 0
                currentRuntimeId := currentActiveTab.GetRuntimeId()
                
                for i, item in matchingItems {
                    if (item.type == "tab" && item.hwnd == currentHwnd) {
                        try {
                            if (tabactivator.arraysequal(item.runtimeId, currentRuntimeId)) {
                                return i
                            }
                        }
                    }
                }
            }
        } else {
            ; Non-Edge browser - check if current hwnd matches a window item
            for i, item in matchingItems {
                if (item.type == "window" && item.activator == currentHwnd) {
                    return i
                }
            }
        }

        return 0
    }

    ; Get currently active tab in Edge
    static getcurrentactiveedgetab(edgeEl) {
        try {
            ; Edge uses SelectionItemIsSelected for active tabs
            return edgeEl.FindElement({Type: "TabItem", SelectionItemIsSelected: true}, 4, 1, 2)
        } catch {
            return ""
        }
    }

    ; Helper to compare arrays (for runtime IDs)
    static arraysequal(arr1, arr2) {
        if (arr1.Length != arr2.Length) {
            return false
        }
        for i, val in arr1 {
            if (val != arr2[i]) {
                return false
            }
        }
        return true
    }

    ; Start initial background cache (non-interruptible)
    static startinitialbackgroundcache() {
        if (tabactivator.cachebuilding)
            return

        if (tabactivator.showtooltips) {
            ToolTip("Starting initial background cache...")
            SetTimer () => ToolTip(), -1000
        }

        tabactivator.cachebuilding := true
        timerCallback := () => tabactivator.initialbackgroundcacheworker()
        tabactivator.cacheworkertimer := timerCallback
        SetTimer(timerCallback, -1)
    }

    ; Start background cache update (interruptible)
    static startbackgroundcacheupdate() {
        ; Don't interrupt initial cache building
        if (!tabactivator.initialcachecomplete)
            return

        ; Cancel existing background cache
        if (tabactivator.cacheworkertimer != "") {
            SetTimer(tabactivator.cacheworkertimer, 0)
            tabactivator.cacheworkertimer := ""
        }

        if (tabactivator.showtooltips) {
            ToolTip("Starting background cache update...")
            SetTimer () => ToolTip(), -1000
        }

        tabactivator.cachebuilding := true
        timerCallback := () => tabactivator.backgroundcacheworker()
        tabactivator.cacheworkertimer := timerCallback
        SetTimer(timerCallback, -1)
    }

    ; Initial background cache worker (non-interruptible)
    static initialbackgroundcacheworker() {
        try {
            if (tabactivator.showtooltips) {
                ToolTip("Building initial background cache...")
                SetTimer () => ToolTip(), -1000
            }

            ; Complete the initial cache build
            newCache := tabactivator.buildnewcache()
            if (newCache.Length > 0) {
                tabactivator.browseritemcache := newCache ; Atomic swap
                ; Update tabindextracker for all titles in cache
                for i, item in newCache {
                    if (tabactivator.tabindextracker.Has(item.title) && tabactivator.tabindextracker[item.title] == 0) {
                        tabactivator.tabindextracker[item.title] := i
                    }
                }
            }
            tabactivator.initialcachecomplete := true
            tabactivator.cachebuilding := false
            tabactivator.cacheworkertimer := ""

            if (tabactivator.showtooltips) {
                ToolTip("Initial background cache complete!")
                SetTimer () => ToolTip(), -1000
            }
        } catch {
            tabactivator.cachebuilding := false
            tabactivator.cacheworkertimer := ""
        }
    }

    ; Background cache worker (interruptible)
    static backgroundcacheworker() {
        try {
            ; Check if we should continue (not interrupted)
            if (tabactivator.cacheworkertimer == "")
                return

            if (tabactivator.showtooltips) {
                ToolTip("Updating background cache...")
                SetTimer () => ToolTip(), -1000
            }

            newCache := tabactivator.buildnewcache()

            ; Final check before atomic swap
            if (tabactivator.cacheworkertimer != "" && newCache.Length > 0) {
                tabactivator.browseritemcache := newCache ; Atomic swap
                ; Update tabindextracker for all titles in cache
                for i, item in newCache {
                    if (tabactivator.tabindextracker.Has(item.title) && tabactivator.tabindextracker[item.title] == 0) {
                        tabactivator.tabindextracker[item.title] := i
                    }
                }
            }

            tabactivator.cachebuilding := false
            tabactivator.cacheworkertimer := ""

            if (tabactivator.showtooltips) {
                ToolTip("Background cache update complete!")
                SetTimer () => ToolTip(), -1000
            }
        } catch {
            tabactivator.cachebuilding := false
            tabactivator.cacheworkertimer := ""
        }
    }

    ; Rebuild full cache
    static rebuildfullcache() {
        if (tabactivator.showtooltips) {
            ToolTip("Rebuilding full cache...")
            SetTimer () => ToolTip(), -1000
        }

        newCache := tabactivator.buildnewcache()
        if (newCache.Length > 0) {
            tabactivator.browseritemcache := newCache ; Atomic swap
            ; Update tabindextracker for all titles in cache
            for i, item in newCache {
                if (tabactivator.tabindextracker.Has(item.title) && tabactivator.tabindextracker[item.title] == 0) {
                    tabactivator.tabindextracker[item.title] := i
                }
            }
        }

        if (tabactivator.showtooltips) {
            ToolTip("Full cache rebuild complete!")
            SetTimer () => ToolTip(), -1000
        }
    }

static buildnewcache() {
    newCache := []

    ; Add other browser windows first
    otherBrowserItems := tabactivator.addotherbrowserwindows()
    for item in otherBrowserItems {
        newCache.Push(item)
    }

    ; Add Edge tabs from ALL Edge windows
    edgeHwnds := WinGetList("ahk_exe msedge.exe")
    ; Sort edgeHwnds ascending for consistent order
    Loop (edgeHwnds.Length - 1) {
        i := A_Index
        Loop (edgeHwnds.Length - i) {
            j := A_Index
            if (edgeHwnds[j] > edgeHwnds[j + 1]) {
                temp := edgeHwnds[j]
                edgeHwnds[j] := edgeHwnds[j + 1]
                edgeHwnds[j + 1] := temp
            }
        }
    }
    
    for hwnd in edgeHwnds {
        if (!WinExist("ahk_id " . hwnd)) {
            continue
        }

        try {
            edgeEl := UIA.ElementFromHandle(hwnd)
            tabbar := edgeEl.FindElement({LocalizedType:"region", ClassName:"EdgeTabStrip"}, 4, 1, 2)
            tabs := tabbar.FindAll({Type: "TabItem", ClassName:"EdgeTab"})
            Loop tabs.Length {
                try {
                    tab := tabs[A_Index]
                    tabName := tab.GetCurrentPropertyValue("Name")
                    ; Include tabs with "Loading..." or other temporary titles
                    if (tabName != "" && tabName != "New Tab") {
                        tabRuntimeId := tab.GetRuntimeId()
                        newCache.Push({title: tabName, hwnd: hwnd, type: "tab", browser: "edge", tabIndex: A_Index, runtimeId: tabRuntimeId})
                    }
                } catch {
                    continue
                }
            }
        } 
    }
    return newCache
}
}


