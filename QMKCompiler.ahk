#Requires AutoHotkey v2.0
#SingleInstance Force
; QMK Compiler
;
; Same pipeline as QMKPgoCompiler.ahk, but every external command runs hidden and
; streams its output into the log pane instead of opening a console window per
; step. Progress is weighted per step because the Zig/Clang stages dominate.
;
; This launcher lives beside QMKInterception.ahk and QMKconfig.ini. Build
; payloads live in .\lib, generated variables live in .\lib\QMKVariables.ahk,
; and training artifacts live in .\lib\TrainingData.

class QMKPgoCompiler {
    static gui := ""
    static settingsGui := ""
    static settingsKind := "pgo"
    static settingsStatusCtl := ""
    static settingsEdits := Map()
    static buildSettingsGui := ""
    static buildSettingCtrls := Map()
    static buildPreviewCtl := ""
    static zigBuildPreviewCtl := ""
    static pgoBuildPreviewCtl := ""
    static progressCtl := ""
    static pctCtl := ""
    static stepCtl := ""
    static pathSummaryCtl := ""
    static toolchainStatusCtl := ""
    static logCtl := ""
    static startBtn := ""
    static quickBtn := ""
    static cancelBtn := ""
    static shortcutSettingsGui := ""
    static shortcutSettingsListCtl := ""
    static shortcutSettingsListIsView := false
    static shortcutUseGeneratedCtl := ""
    static shortcutSettingsStatusCtl := ""
    static shortcutCompileMode := "full_native"
    static shortcutCallbackOutputModeCtl := ""
    static shortcutCallbackOutputMode := "per_source"
    static shortcutCallbackCustomPathCtl := ""
    static shortcutCallbackCustomPath := ""
    static shortcutUseGeneratedInclude := false
    static shortcutSourceFiles := []
    static shortcutSourceCount := 0
    static shortcutTranspilerPath := ""
    static shortcutCaptureScriptPath := ""
    static shortcutCaptureReportPath := ""
    static compiledShortcutBuildActive := false
    static canonicalCompiledShortcutAhkPath := ""
    static statusPath := ""
    static cliModeOverride := ""
    static cliReload := false
    static cliTooltip := false
    static tooltipEnabled := false
    static cliSourceOverride := false
    static cliSourceFiles := []
    static cliCallbackModeOverride := ""
    static cliCallbackPathOverride := ""
    static cliShortcutIncludeOverride := ""

    static steps := []
    static stepIndex := 0
    static bandStart := 0
    static bandEnd := 0
    static stepStartTick := 0
    static stepExpected := 10000
    static activePid := 0
    static cancelRequested := false
    static running := false
    static stepSeq := 0
    static logLines := []
    static toolchainPromptShown := false
    static buildTooltipHandler := ""
    static buildTooltipText := ""
    static buildTooltipGeneration := 0

    ; ---------------------------------------------------------------- paths

    static InitPaths() {
        if this.HasOwnProp("packageDir")
            return

        this.packageDir := this.ResolvePackageDir()
        this.libDir := this.packageDir "\lib"
        this.projectRoot := this.ParentDir(this.packageDir)
        this.settingsPath := this.packageDir "\QMKconfig.ini"
        this.statusPath := this.packageDir "\qmk_compiler_status.ini"

        this.ReloadResolvedPaths()
    }

    static ReadSetting(section, key, fallback) {
        value := ""
        try value := IniRead(this.settingsPath, section, key, fallback)
        catch
            value := fallback
        return (value = "") ? fallback : value
    }

    static ApplyCliOptions() {
        action := ""
        sources := []
        hasSources := false
        this.cliReload := false
        this.cliTooltip := true
        this.tooltipEnabled := true
        this.cliSourceOverride := false
        this.cliSourceFiles := []
        this.cliCallbackModeOverride := ""
        this.cliCallbackPathOverride := ""
        this.cliShortcutIncludeOverride := ""
        index := 1
        while (index <= A_Args.Length) {
            arg := A_Args[index]
            if (SubStr(arg, 1, 2) != "--") {
                if (action = "")
                    action := arg
                else if (action = "--generate-user-shortcuts" || action = "--generate-full-native-user-shortcuts") {
                    this.cliSourceFiles.Push(this.Anchor(arg, this.packageDir))
                    this.cliSourceOverride := true
                    hasSources := true
                }
                else
                    throw Error("Unexpected argument: " arg)
                index += 1
                continue
            }
            switch StrLower(arg) {
                case "--source":
                    path := this.Anchor(this.CliValue(index, "--source"), this.packageDir)
                    if (SubStr(path, 1, 2) = "--")
                        throw Error("--source requires a path")
                    sources.Push(path)
                    hasSources := true
                    index += 2
                    continue
                case "--callback-mode":
                    value := this.CliValue(index, "--callback-mode")
                    if (value != "single" && value != "per_source")
                        throw Error("--callback-mode must be single or per_source")
                    this.shortcutCallbackOutputMode := value
                    this.cliCallbackModeOverride := value
                    index += 2
                    continue
                case "--callback-output":
                    value := this.CliValue(index, "--callback-output")
                    this.shortcutCallbackCustomPath := this.Anchor(value, this.packageDir)
                    this.cliCallbackPathOverride := this.shortcutCallbackCustomPath
                    index += 2
                    continue
                case "--tooltip":
                    this.cliTooltip := true
                    this.tooltipEnabled := true
                    index += 1
                    continue
                case "--no-tooltip":
                    this.cliTooltip := false
                    this.tooltipEnabled := false
                    index += 1
                    continue
                case "--reload":
                    this.cliReload := true
                    index += 1
                    continue
                case "--with-user-shortcuts", "--include-user-shortcuts":
                    this.cliShortcutIncludeOverride := "1"
                    index += 1
                    continue
                case "--without-user-shortcuts", "--no-user-shortcuts":
                    this.cliShortcutIncludeOverride := "0"
                    index += 1
                    continue
                case "--saved":
                    this.cliModeOverride := "saved"
                    index += 1
                    continue
                case "--zig", "--zig-only":
                    this.cliModeOverride := "zig"
                    index += 1
                    continue
                case "--pgo", "--full":
                    this.cliModeOverride := "full"
                    index += 1
                    continue
                case "--mode":
                    value := StrLower(this.CliValue(index, "--mode"))
                    if (value = "saved")
                        this.cliModeOverride := "saved"
                    else if (value = "zig" || value = "pgo" || value = "full")
                        this.cliModeOverride := value = "zig" ? "zig" : "full"
                    else
                        throw Error("--mode must be saved, zig, or pgo")
                    index += 2
                    continue
                default:
                    ; The first switch action is handled by Main; all other
                    ; options are intentionally explicit to catch typos.
                    if (action = "")
                        action := arg
                    else
                        throw Error("Unknown option: " arg)
                    index += 1
            }
        }
        if (action = "")
            action := "--gui"
        if hasSources {
            if sources.Length
                this.cliSourceFiles := sources
            this.shortcutSourceFiles := this.cliSourceFiles.Clone()
            this.cliSourceOverride := true
            this.shortcutUseGeneratedInclude := true
        }
        if (this.cliShortcutIncludeOverride != "")
            this.shortcutUseGeneratedInclude := this.cliShortcutIncludeOverride = "1"
        if (this.shortcutCallbackOutputMode = "single" && this.shortcutCallbackCustomPath = "")
            this.RefreshCallbackOutputPath()
        return action
    }

    static CliValue(index, option) {
        if (index = A_Args.Length)
            throw Error(option " requires a value")
        value := A_Args[index + 1]
        if (SubStr(value, 1, 2) = "--")
            throw Error(option " requires a value")
        return value
    }

    static ResolvePackageDir() {
        lineDir := this.DirFromPath(A_LineFile)
        candidates := [
            A_WorkingDir,
            lineDir,
            A_ScriptDir,
            A_InitialWorkingDir
        ]
        ; AHK validation and some launchers execute a copied compiler from
        ; A_Temp.  Prefer the real package when the working directory points
        ; at it, even if the temporary copy also contains the marker files.
        for pass in [false, true] {
            for candidate in candidates {
                if (candidate = "" || this.IsTempPath(candidate) != pass)
                    continue
                if (FileExist(candidate "\QMKInterception.ahk") && FileExist(candidate "\QMKconfig.ini") && DirExist(candidate "\lib")) {
                    if pass
                        throw Error("QMK Compiler refused a temporary package copy. Launch it through QMKInterception.ahk or pass --package-dir with the real production_code directory.")
                    return candidate
                }
            }
        }
        return lineDir != "" ? lineDir : A_ScriptDir
    }

    static DirFromPath(path) {
        SplitPath(path, , &dir)
        return dir
    }

    static ParentDir(path) {
        SplitPath(RTrim(path, "\"), , &dir)
        return dir
    }

    static IsAbsolute(path) => RegExMatch(path, "i)^[a-z]:\\|^\\\\") ? true : false

    static IsTempPath(path) {
        tempRoot := RTrim(A_Temp, "\") "\"
        return StrLower(SubStr(RTrim(path, "\") "\", 1, StrLen(tempRoot))) = StrLower(tempRoot)
    }

    static Anchor(value, base) {
        if this.IsAbsolute(value)
            return value
        return base "\" RegExReplace(value, "^\.\\")
    }

    static LibPath(key, fallback) {
        value := this.ReadSetting("Paths", key, ".\" fallback)
        return this.IsTempPath(value) ? this.libDir "\" fallback : this.Anchor(value, this.libDir)
    }

    static PackagePath(key, fallback) {
        value := this.ReadSetting("Paths", key, fallback)
        return this.IsTempPath(value) ? this.packageDir "\" fallback : this.Anchor(value, this.packageDir)
    }

    static ToolPath(key, fallback) {
        return this.Anchor(this.ReadSetting("Tools", key, fallback), this.libDir)
    }

    ; ------------------------------------------------------------------ gui

    static Main() {
        this.InitPaths()

        if (A_Args.Length) {
            try action := this.ApplyCliOptions()
            catch Error as err {
                this.WriteCliLine("Invalid CLI arguments: " err.Message)
                ExitApp(2)
            }
            switch action {
                case "--gui":
                    ; Continue into the GUI launcher below.
                case "--quick-compile":
                    ExitApp(this.RunCliPipeline("quick"))
                case "--zig-only-build":
                    ExitApp(this.RunCliPipeline("zig"))
                case "--recompile-last-zig", "--zig-build-last":
                    ExitApp(this.RunLastBuildPipeline("zig"))
                case "--recompile-last-pgo", "--pgo-build-last":
                    ExitApp(this.RunLastBuildPipeline("full"))
                case "--recompile-last":
                    ExitApp(this.RunLastBuildPipeline())
                case "--compile-user-shortcuts-candidate":
                    ExitApp(this.CompileCompiledShortcutCandidate(false))
                case "--full-pgo-build", "--train-and-embed-final":
                    ExitApp(this.RunCliPipeline("full"))
                case "--generate-user-shortcuts":
                    paths := this.cliSourceOverride ? this.cliSourceFiles.Clone() : []
                    if !this.cliSourceOverride
                        Loop A_Args.Length - 1
                            paths.Push(A_Args[A_Index + 1])
                    if !paths.Length
                        ExitApp(2)
                    this.shortcutSourceFiles := paths
                    try {
                        this.CaptureUserShortcutFiles(false)
                        ExitApp(0)
                    } catch Error as err {
                        line := err.HasOwnProp("Line") ? err.Line : "?"
                        this.WriteCliLine("Compiled user-shortcut generation failed at line " line ": " err.Message)
                        ExitApp(1)
                    }
                case "--generate-full-native-user-shortcuts":
                    paths := this.cliSourceOverride ? this.cliSourceFiles.Clone() : []
                    if !this.cliSourceOverride
                        Loop A_Args.Length - 1
                            paths.Push(A_Args[A_Index + 1])
                    if !paths.Length
                        ExitApp(2)
                    this.shortcutSourceFiles := paths
                    this.shortcutCompileMode := "full_native"
                    try {
                        this.CaptureUserShortcutFiles(false)
                        ExitApp(0)
                    } catch Error as err {
                        this.WriteCliLine("Full-native shortcut generation failed: " err.Message)
                        ExitApp(1)
                    }
                case "--validate-generated-user-shortcuts":
                    paths := []
                    Loop A_Args.Length - 1
                        paths.Push(A_Args[A_Index + 1])
                    if !paths.Length
                        ExitApp(2)
                    this.shortcutSourceFiles := paths
                    try {
                        this.ValidateGeneratedShortcutBundle()
                        this.WriteCliLine("PASS: generated user-shortcut bundle matches the selected native rows and build identity.")
                        ExitApp(0)
                    } catch Error as err {
                        line := err.HasOwnProp("Line") ? err.Line : "?"
                        this.WriteCliLine("Generated user-shortcut validation failed at line " line ": " err.Message)
                        ExitApp(1)
                    }
                case "--verify-generated-shortcut-backups":
                    try {
                        this.VerifyShortcutBackupRotation()
                        this.WriteCliLine("PASS: generated Zig backup rotation retains exactly three prior generations.")
                        ExitApp(0)
                    } catch Error as err {
                        line := err.HasOwnProp("Line") ? err.Line : "?"
                        this.WriteCliLine("Generated Zig backup verification failed at line " line ": " err.Message)
                        ExitApp(1)
                    }
                case "--verify-hotkey-parser":
                    try {
                        ExitApp(this.VerifyHotkeyParserMatrix())
                    } catch Error as err {
                        try FileAppend("ERROR: " err.Message "`n", A_Temp "\\qmk_hotkey_parser_matrix.log", "UTF-8")
                        ExitApp(1)
                    }
                default:
                    try this.WriteCliLine("Unknown QMKPgoCompiler argument: " action)
                    catch
                        MsgBox("Unknown QMKPgoCompiler argument:`n" action, "QMK Compiler", "Icon!")
                    ExitApp(2)
            }
        }

        g := Gui("+MinSize740x640", "QMK Compiler")
        this.gui := g
        g.MarginX := 14
        g.MarginY := 12
        g.BackColor := "F6F7FB"
        g.SetFont("s9", "Segoe UI")

        title := g.AddText("xm ym w712 h26 c1F2937", "QMK Compiler")
        title.SetFont("s15 w700", "Segoe UI")
        sub := g.AddText("xm y+2 w712 c667085", "Runs the full training, profile merge, optimized DLL build, and embed pipeline with no console windows.")
        sub.SetFont("s9", "Segoe UI")

        this.quickBtn := g.AddButton("xm y+12 w110 h32 Default", "Zig Build")
        this.quickBtn.ToolTip := "Recommended for most users. Zig builds much faster; PGO may produce a slightly faster runtime but requires more dependencies and time."
        this.quickBtn.OnEvent("Click", (*) => this.StartPipeline("zig"))
        this.startBtn := g.AddButton("x+6 yp w110 h32", "Full PGO Build")
        this.startBtn.ToolTip := "Profile-guided optimization: trains the DLL with a different backend. It may run slightly faster, but requires more dependencies and a longer build."
        this.startBtn.OnEvent("Click", (*) => this.StartPipeline("full"))
        openLogBtn := g.AddButton("x+6 yp w90 h32", "Copy Log")
        openLogBtn.ToolTip := "Copy the compiler output log to the clipboard."
        openLogBtn.OnEvent("Click", (*) => this.CopyLog())
        settingsBtn := g.AddButton("x+6 yp w120 h32", "Compiler Settings")
        settingsBtn.ToolTip := "Configure Zig, PGO, transpiler, and maintenance settings."
        settingsBtn.OnEvent("Click", (*) => this.ShowSettingsHub())
        this.shortcutUseGeneratedCtl := g.AddCheckbox("x+6 yp+1 w170 h22", "Generate User Shortcuts")
        this.shortcutUseGeneratedCtl.Value := this.shortcutUseGeneratedInclude ? 1 : 0
        this.shortcutUseGeneratedCtl.ToolTip := "Generate and embed the saved AutoHotkey shortcut sources during the next build."
        this.shortcutUseGeneratedCtl.OnEvent("Click", (*) => this.SaveShortcutIncludeReminder())
        this.cancelBtn := g.AddButton("xm y+20 w130 h32 Disabled", "Cancel")
        this.cancelBtn.ToolTip := "Immediately terminate the active compiler command and its child processes."
        this.cancelBtn.OnEvent("Click", (*) => this.RequestCancel())

        progressLabel := g.AddText("xm y+4 w712 h18 c243447", "Build Progress")
        progressLabel.SetFont("s10 w700", "Segoe UI")
        this.progressCtl := g.AddProgress("xm y+2 w664 h24 Range0-100 cBlue", 0)
        this.pctCtl := g.AddText("x+8 yp+3 w40 h20 c243447", "0%")
        this.pctCtl.SetFont("s10 w700", "Segoe UI")
        this.stepCtl := g.AddText("xm y+2 w712 h20 c243447", "")
        this.stepCtl.SetFont("s10 w600", "Segoe UI")

        logLabel := g.AddText("xm y+10 w712 h18 c243447", "Output")
        logLabel.SetFont("s10 w700", "Segoe UI")
        this.logCtl := g.AddEdit("xm y+4 w712 h380 ReadOnly +Wrap +VScroll", "")
        this.logCtl.SetFont("s9", "Consolas")

        g.OnEvent("Close", (*) => this.OnClose())
        g.Show("w740 h640")
        this.buildTooltipHandler := ObjBindMethod(this, "HandleBuildTooltipMouseMove")
        OnMessage(0x0200, this.buildTooltipHandler)
        this.RefreshPathSummary()
        this.Log("")
        this.OfferToolchainSetup()
    }

    static PathSummaryText() {
        return "Source: " this.AbbreviatePath(this.sourcePath)
            . "  |  Zig: " this.AbbreviatePath(this.zigPath)
            . "  |  Out: " this.AbbreviatePath(this.finalDllPath)
            . "  |  Build: " this.BuildSummary()
    }

    static RefreshPathSummary() {
        if this.pathSummaryCtl
            this.pathSummaryCtl.Value := this.PathSummaryText()
        if this.toolchainStatusCtl
            this.toolchainStatusCtl.Value := this.ToolchainStatusText()
        if this.logCtl {
            this.Log("Project:   " this.projectRoot)
            this.Log("Package:   " this.packageDir)
            this.Log("Lib:       " this.libDir)
            this.Log("Source:    " this.sourcePath)
            this.Log("Zig:       " this.zigPath)
            this.Log("Clang:     " this.clangPath)
            this.Log("profdata:  " this.profdataPath)
            this.Log("Training:  " this.trainingDir)
            this.Log("Final DLL: " this.finalDllPath)
            this.Log("Build:     " this.BuildSummary())
            this.Log("Toolchain: " this.ToolchainStatusText())
        }
    }

    static ToolchainStatusText() {
        zig := FileExist(this.zigPath) ? "Zig " this.ToolVersion(this.zigPath) : "Zig missing"
        clang := FileExist(this.clangPath) ? "Clang " this.ToolVersion(this.clangPath) : "Clang missing"
        prof := FileExist(this.profdataPath) ? "profdata OK" : "profdata missing"
        arch := this.targetProfile = "x64" ? "x64" : "x86"
        host := A_PtrSize = 8 ? "x64 host" : "x86 host"
        return arch " target / " host "  |  " zig "  |  " clang "  |  " prof
    }

    static ToolVersion(path) {
        try {
            return FileGetVersion(path)
        } catch {
            return "found"
        }
    }

    static AbbreviatePath(path, maxChars := 52) {
        if (StrLen(path) <= maxChars)
            return path
        return "..." SubStr(path, -(maxChars - 4))
    }

    static ShowSettingsHub(selectedTab := 1) {
        for , window in [this.settingsGui, this.buildSettingsGui, this.shortcutSettingsGui] {
            if window {
                try window.Destroy()
            }
        }
        this.settingsGui := ""
        this.buildSettingsGui := ""
        this.shortcutSettingsGui := ""
        sg := Gui("+Owner" this.gui.Hwnd " +MinSize820x640", "QMK Compiler Settings")
        this.settingsGui := sg
        sg.MarginX := 16
        sg.MarginY := 14
        sg.BackColor := "F6F7FB"
        sg.SetFont("s9", "Segoe UI")
        title := sg.AddText("xm ym w760 h28 c1F2937", "QMK Compiler Settings")
        title.SetFont("s15 w700", "Segoe UI")
        tabs := sg.AddTab3("xm y+8 w760 h500", ["Zig Build Settings", "PGO Settings", "Build Flags", "Transpile User Shortcuts", "Maintenance"])
        tabs.SetFont("w700", "Segoe UI")
        this.settingsEdits := Map()

        tabs.UseTab(1)
        zigNote := sg.AddText("xm y+12 w720 h50 c667085", "Zig is the recommended build for most users. It compiles quickly and produces a native DLL for the selected computer architecture. Use the dependency links below if Zig or Interception is missing.")
        this.AddSettingsRow(sg, "Paths", "sourcePath", "QMKCore source", this.sourcePath, true)
        this.AddSettingsRow(sg, "Paths", "variablesPath", "QMKVariables", this.variablesPath, true)
        this.AddSettingsRow(sg, "Paths", "runtimeDllPath", "Final DLL", this.finalDllPath, false)
        this.AddSettingsRow(sg, "Tools", "zigPath", "Zig", this.zigPath, true)
        this.AddSettingsRow(sg, "Paths", "interceptionDllPath", "Interception DLL", this.interceptionDllPath, false)
        this.AddSettingsLink(sg, "Dependencies", "Open Zig 0.16 download page", "https://ziglang.org/download/")
        this.AddSettingsLink(sg, "", "Download/install Interception driver and DLL", "https://github.com/oblitum/Interception")
        zigPreviewLabel := sg.AddText("xm y+10 w700 h18 c243447", "Command preview")
        zigPreviewLabel.SetFont("s9 w600", "Segoe UI")
        this.zigBuildPreviewCtl := sg.AddEdit("xm y+3 w720 h110 ReadOnly +Wrap +VScroll", this.BuildCommandPreview())
        this.zigBuildPreviewCtl.SetFont("s8", "Consolas")

        tabs.UseTab(2)
        pgoNote := sg.AddText("xm y+12 w720 h62 c667085", "Profile-guided optimization uses a different compiler backend and runs the DLL to train its branch behavior. It may produce slightly faster runtime code, but requires LLVM/Clang and takes longer to compile. The dependency link below explains where to download it.")
        this.AddSettingsRow(sg, "Paths", "configPath", "QMKconfig.ini", this.configPath, true)
        this.AddSettingsRow(sg, "Paths", "trainingDllPath", "Training DLL", this.trainingDllPath, false)
        this.AddSettingsRow(sg, "Paths", "trainingDataDir", "Training data dir", this.trainingDir, true)
        this.AddSettingsRow(sg, "Paths", "pgoTrainerSourcePath", "Trainer source", this.trainerSourcePath, true)
        this.AddSettingsRow(sg, "Tools", "clangPath", "Clang", this.clangPath, true)
        this.AddSettingsRow(sg, "Tools", "llvmProfdataPath", "llvm-profdata", this.profdataPath, true)
        this.AddSettingsLink(sg, "Dependencies", "Open LLVM / Clang download page", "https://releases.llvm.org/download.html")

        tabs.UseTab(3)
        flagsNote := sg.AddText("xm y+12 w720 h38 c667085", "These code-generation flags are shared by the Zig and PGO build paths. The saved values apply to the next compiler run.")
        flagsTitle := sg.AddText("xm y+10 w700 h22", "Build flags")
        flagsTitle.SetFont("s10 w700", "Segoe UI")
        this.buildSettingCtrls := Map()
        this.AddBuildDropDown(sg, "targetProfile", "Target", ["x64 - 64-bit Windows", "x86 - 32-bit Windows"], this.targetProfile = "x86" ? 2 : 1, "DLL architecture; it must match the AutoHotkey process.")
        this.AddBuildDropDown(sg, "optimization", "Optimization", ["ReleaseFast", "ReleaseSafe", "ReleaseSmall", "Debug"], this.OptimizationIndex(), "Zig optimization mode.")
        this.AddBuildCheckBox(sg, "lto", "Link-time optimization", this.lto, "Optimize across module boundaries.")
        this.AddBuildCheckBox(sg, "omitFramePointer", "Omit frame pointer", this.omitFramePointer, "Production code-generation option.")
        this.AddBuildCheckBox(sg, "singleThreaded", "Single-threaded Zig mode", this.singleThreaded, "Use the single-threaded Zig runtime.")
        this.AddBuildCheckBox(sg, "stackCheck", "Stack checks", this.stackCheck, "Enable stack checks.")
        this.AddBuildCheckBox(sg, "unwindTables", "Unwind tables", this.unwindTables, "Keep unwind metadata.")
        previewLabel := sg.AddText("xm y+10 w700 h18 c243447", "Command preview")
        previewLabel.SetFont("s9 w600", "Segoe UI")
        this.buildPreviewCtl := sg.AddEdit("xm y+3 w720 h140 ReadOnly +Wrap +VScroll", this.BuildCommandPreview())
        this.buildPreviewCtl.SetFont("s8", "Consolas")
        this.pgoBuildSettingCtrls := this.buildSettingCtrls
        this.pgoBuildPreviewCtl := this.buildPreviewCtl

        tabs.UseTab(4)
        shortcutNote := sg.AddText("xm y+12 w720 h58", "Recommended if noticing delay on startup. Takes QMK shortcuts from AutoHotkey file(s), embeds them directly into the DLL for quicker startup, and generates an AHK callback file. Recompile required for each desired change.")
        shortcutNote.SetFont("s9", "Segoe UI")
        sg.AddText("xm y+8 w700 h22", "Shortcut source files (processed in this order):")
        shortcutList := sg.AddListView("xm y+4 w720 h120", ["Selected AutoHotkey source files"])
        for , sourcePath in this.shortcutSourceFiles
            shortcutList.Add(, sourcePath)
        this.shortcutSettingsListCtl := shortcutList
        this.shortcutSettingsListIsView := true
        addBtn := sg.AddButton("xm y+8 w180 h30", "Add Additional Files")
        deleteBtn := sg.AddButton("x+8 yp w180 h30", "Delete Selected Files")
        addBtn.OnEvent("Click", (*) => this.SelectShortcutFilesForSettings(true))
        deleteBtn.OnEvent("Click", (*) => this.RemoveSelectedShortcutFiles())
        sg.AddText("xm y+14 w700 h22", "Generated AutoHotkey file settings and location:")
        outputCtl := sg.AddDropDownList("xm y+4 w320", ["One callback file", "One file per source in source directory"])
        outputCtl.Value := this.shortcutCallbackOutputMode = "per_source" ? 2 : 1
        customPathCtl := sg.AddText("x+8 yp w390 h22 c667085", this.shortcutCallbackCustomPath != "" ? this.shortcutCallbackCustomPath : this.canonicalCompiledShortcutAhkPath)
        browseCallbackBtn := sg.AddButton("xm y+6 w90 h24", "Browse")
        browseCallbackBtn.OnEvent("Click", (*) => this.SelectCustomCallbackPath(customPathCtl))
        outputCtl.OnEvent("Change", (*) => browseCallbackBtn.Enabled := outputCtl.Value = 1)
        browseCallbackBtn.Enabled := outputCtl.Value = 1
        this.shortcutSettingsStatusCtl := ""

        tabs.UseTab(5)
        maintenanceNote := sg.AddText("xm y+12 w720 h38 c667085", "Use these actions to manage the embedded payload and restore the original variables file.")
        embedBtn := sg.AddButton("xm y+18 w190 h32", "Embed Interception DLL")
        restoreBtn := sg.AddButton("xm y+10 w190 h32", "Restore QMK Variables")
        embedBtn.OnEvent("Click", (*) => this.EmbedInterceptionDll())
        restoreBtn.OnEvent("Click", (*) => this.RestoreOriginalVariables())

        tabs.UseTab()
        status := sg.AddText("x16 y584 w410 h34 c243447", "Save applies all compiler settings.")
        applyBtn := sg.AddButton("x650 y580 w110 h32 Default", "Save")
        reloadBtn := sg.AddButton("x474 y580 w160 h32", "Restore Defaults")
        closeBtn := sg.AddButton("x366 y580 w100 h32", "Close")
        this.settingsStatusCtl := status
        this.buildSettingsStatusCtl := status
        this.shortcutSettingsStatusCtl := status
        reloadBtn.ToolTip := "Discard unsaved edits and restore the saved settings from QMKconfig.ini."
        applyBtn.OnEvent("Click", (*) => this.ApplyAllCompilerSettings(sg, outputCtl, customPathCtl))
        reloadBtn.OnEvent("Click", (*) => this.ReloadAllCompilerSettings(sg, outputCtl, customPathCtl))
        closeBtn.OnEvent("Click", (*) => sg.Hide())
        sg.OnEvent("Close", (*) => (this.settingsGui := "", sg.Destroy()))
        sg.Show()
        tabs.Value := selectedTab
        this.CheckSettingsPaths()
    }

    static ApplyAllCompilerSettings(sg, outputCtl, customPathCtl) {
        ; Applying paths/build flags reloads the resolved settings, including
        ; the saved shortcut source list. Keep the GUI's pending additions
        ; alive until they have been written back to QMKconfig.ini.
        pendingShortcutFiles := this.shortcutSourceFiles.Clone()
        this.ApplySettings()
        this.ApplyBuildSettings()
        this.shortcutSourceFiles := pendingShortcutFiles
        if !this.SaveShortcutSettings(sg, outputCtl, customPathCtl) {
            this.settingsStatusCtl.Value := "Compiler settings saved, but shortcut settings were not saved."
            return
        }
        this.settingsStatusCtl.Value := "All compiler settings saved to QMKconfig.ini."
    }

    static ReloadAllCompilerSettings(sg, outputCtl, customPathCtl) {
        this.ReloadResolvedPaths()
        this.ReloadSettingsIntoGui()
        this.ReloadBuildSettingsIntoGui()
        this.LoadShortcutSourceFiles()
        outputCtl.Value := this.shortcutCallbackOutputMode = "per_source" ? 2 : 1
        customPathCtl.Value := this.shortcutCallbackCustomPath != "" ? this.shortcutCallbackCustomPath : this.canonicalCompiledShortcutAhkPath
        this.RefreshShortcutSettingsList()
        this.settingsStatusCtl.Value := "Reloaded all compiler settings from QMKconfig.ini."
    }

    static ShowSettingsGui(kind := "pgo") {
        if (this.settingsGui) {
            this.settingsGui.Destroy()
            this.settingsGui := ""
        }
        this.settingsKind := kind
        isZigOnly := kind = "zig"
        sg := Gui("+Owner" this.gui.Hwnd " +MinSize720x520", isZigOnly ? "QMK Zig Only Settings" : "QMK PGO Settings")
        this.settingsGui := sg
        sg.MarginX := 14
        sg.MarginY := 12
        sg.BackColor := "F6F7FB"
        sg.SetFont("s9", "Segoe UI")
        this.settingsEdits := Map()

        title := sg.AddText("xm ym w680 h24 c1F2937", isZigOnly ? "Zig-only build locations" : "PGO build locations")
        title.SetFont("s13 w700", "Segoe UI")
        if isZigOnly
            noteText := "For regular users: point to Zig, QMKCore.zig, QMKVariables.ahk, and the output DLL. No LLVM or training paths are needed."
        else
            noteText := "Full PGO uses Zig, LLVM/Clang, the trainer, and training data. These write to top-level QMKconfig.ini."
        note := sg.AddText("xm y+2 w680 c667085", noteText)
        note.SetFont("s9", "Segoe UI")

        this.AddSettingsRow(sg, "Paths", "sourcePath", "QMKCore source", this.sourcePath, true)
        this.AddSettingsRow(sg, "Paths", "variablesPath", "QMKVariables", this.variablesPath, true)
        this.AddSettingsRow(sg, "Paths", "runtimeDllPath", "Final DLL", this.finalDllPath, false)
        this.AddSettingsRow(sg, "Tools", "zigPath", "Zig", this.zigPath, true)
        this.AddSettingsRow(sg, "Paths", "interceptionDllPath64", "Interception x64", this.interceptionDllPath64, false)
        this.AddSettingsRow(sg, "Paths", "interceptionDllPath32", "Interception x86", this.interceptionDllPath32, false)
        if !isZigOnly {
            this.AddSettingsRow(sg, "Paths", "configPath", "QMKconfig.ini", this.configPath, true)
            this.AddSettingsRow(sg, "Paths", "trainingDllPath", "Training DLL", this.trainingDllPath, false)
            this.AddSettingsRow(sg, "Paths", "trainingDataDir", "Training data dir", this.trainingDir, true)
            this.AddSettingsRow(sg, "Paths", "pgoTrainerSourcePath", "Trainer source", this.trainerSourcePath, true)
            this.AddSettingsRow(sg, "Tools", "clangPath", "Clang", this.clangPath, true)
            this.AddSettingsRow(sg, "Tools", "llvmProfdataPath", "llvm-profdata", this.profdataPath, true)
        }

        applyBtn := sg.AddButton("xm y+16 w140 h30 Default", "Apply")
        applyBtn.ToolTip := "Save the edited paths to QMKconfig.ini and refresh the compiler."
        applyBtn.OnEvent("Click", (*) => this.ApplySettings())
        cancelBtn := sg.AddButton("x+8 yp w110 h30", "Close")
        cancelBtn.ToolTip := "Close this settings window without saving unsaved edits."
        cancelBtn.OnEvent("Click", (*) => sg.Hide())
        resetBtn := sg.AddButton("x+8 yp w160 h30", "Reload from INI")
        resetBtn.ToolTip := "Discard unsaved edits and reload the saved paths from QMKconfig.ini."
        resetBtn.OnEvent("Click", (*) => this.ReloadSettingsIntoGui())

        this.settingsStatusCtl := sg.AddText("xm y+12 w680 h36 c243447", "Edit a path, then Apply. Missing required paths are listed after Apply.")
        sg.OnEvent("Close", (*) => (this.settingsGui := "", sg.Destroy()))
        sg.Show()
        this.CheckSettingsPaths()
    }

    static AddSettingsRow(sg, section, key, label, value, required := true) {
        lbl := sg.AddText("xm y+8 w150 h18 c243447", label)
        lbl.SetFont("s9 w600", "Segoe UI")
        lbl.ToolTip := this.PathSettingTooltip(key, label)
        edit := sg.AddEdit("x+6 yp-2 w430 h22", value)
        edit.ToolTip := this.PathSettingTooltip(key, label)
        if (key = "interceptionDllPath")
            edit.OnEvent("Change", (*) => edit.ToolTip := this.InterceptionDllTooltip(edit.Value))
        browse := sg.AddButton("x+6 yp w70 h22", "Browse")
        browse.ToolTip := "Choose the " label " path using a file or folder picker."
        browse.OnEvent("Click", (*) => this.BrowseSettingPath(edit, label))
        this.settingsEdits[key] := { section: section, key: key, edit: edit, required: required, label: label }
    }

    static AddSettingsLink(sg, heading, label, url) {
        if (heading != "") {
            text := sg.AddText("xm y+12 w700 h20", heading)
            text.SetFont("s9 w600", "Segoe UI")
        }
        link := sg.AddText("xm y+4 w700 h20 c0563C1", label)
        link.SetFont("s9 underline", "Segoe UI")
        link.OnEvent("Click", (*) => Run(url))
        link.ToolTip := url
    }

    static BrowseSettingPath(edit, label) {
        current := edit.Value
        startDir := FileExist(current) ? current : this.libDir
        if InStr(StrLower(label), "dir") {
            chosen := DirSelect("*" startDir, 1, "Choose " label)
            if (chosen != "")
                edit.Value := chosen
            return
        }
        chosen := FileSelect(1, startDir, "Choose " label)
        if (chosen != "")
            edit.Value := chosen
    }

    static PathSettingTooltip(key, label) {
        switch key {
            case "sourcePath": return "The QMKCore.zig source compiled into the runtime DLL."
            case "variablesPath": return "The AutoHotkey file that receives the embedded QMKCore and Interception payloads."
            case "runtimeDllPath": return "The final runtime DLL produced by the compiler."
            case "interceptionDllPath": return this.InterceptionDllTooltip()
            case "interceptionDllPath64": return "Legacy x64 Interception path."
            case "interceptionDllPath32": return "Legacy x86 Interception path."
            case "configPath": return "The INI file where compiler and runtime settings are persisted."
            case "trainingDllPath": return "The instrumented DLL used to collect PGO profile data."
            case "trainingDataDir": return "Folder containing PGO profiles and intermediate LLVM files."
            case "pgoTrainerSourcePath": return "The Zig source for the synthetic PGO trainer executable."
            case "zigPath": return "The Zig compiler executable used to emit LLVM IR or a runtime DLL."
            case "clangPath": return "The Clang compiler/linker used to turn LLVM IR into the final DLL."
            case "llvmProfdataPath": return "The LLVM tool used to merge PGO profile data."
        }
        return label " path used by the compiler."
    }

    static InterceptionDllTooltip(path := "") {
        computerArch := A_Is64bitOS ? "x64" : "x86"
        if (path = "")
            path := this.interceptionDllPath
        dllArch := this.DetectDllArchitecture(path)
        if (dllArch = "")
            return "Interception DLL selected for this computer. Computer architecture: " computerArch ". The file architecture will be checked when it is available."
        state := dllArch = computerArch ? "MATCH" : "MISMATCH"
        return "Currently points to an " dllArch " Interception DLL. Computer architecture: " computerArch ". Status: " state "."
    }

    static DetectDllArchitecture(path) {
        if !FileExist(path)
            return ""
        try {
            raw := FileRead(path, "RAW")
            if (raw.Size < 0x40 || NumGet(raw, 0, "UShort") != 0x5A4D)
                return ""
            peOffset := NumGet(raw, 0x3C, "UInt")
            if (peOffset + 6 > raw.Size || NumGet(raw, peOffset, "UInt") != 0x00004550)
                return ""
            machine := NumGet(raw, peOffset + 4, "UShort")
            return machine = 0x8664 ? "x64" : machine = 0x014C ? "x86" : "unknown"
        } catch {
            return ""
        }
    }

    static ReloadSettingsIntoGui() {
        this.ReloadResolvedPaths()
        for , row in this.settingsEdits {
            switch row.key {
                case "sourcePath": row.edit.Value := this.sourcePath
                case "variablesPath": row.edit.Value := this.variablesPath
                case "configPath": row.edit.Value := this.configPath
                case "runtimeDllPath": row.edit.Value := this.finalDllPath
                case "interceptionDllPath": row.edit.Value := this.interceptionDllPath
                case "interceptionDllPath64": row.edit.Value := this.interceptionDllPath64
                case "interceptionDllPath32": row.edit.Value := this.interceptionDllPath32
                case "trainingDllPath": row.edit.Value := this.trainingDllPath
                case "trainingDataDir": row.edit.Value := this.trainingDir
                case "pgoTrainerSourcePath": row.edit.Value := this.trainerSourcePath
                case "zigPath": row.edit.Value := this.zigPath
                case "clangPath": row.edit.Value := this.clangPath
                case "llvmProfdataPath": row.edit.Value := this.profdataPath
            }
        }
        this.CheckSettingsPaths()
        this.settingsStatusCtl.Value := "Reloaded from QMKconfig.ini."
    }

    static ApplySettings() {
        missing := []
        for , row in this.settingsEdits {
            value := Trim(row.edit.Value)
            if (value = "") {
                missing.Push(row.label " is empty")
                continue
            }
            store := value
            if (row.section = "Paths") {
                store := this.MakeRelativeToPathBase(value, row.key)
            }
            IniWrite(store, this.settingsPath, row.section, row.key)
            if (row.required && !FileExist(value) && !DirExist(value))
                missing.Push(row.label ": " value)
        }
        this.ReloadResolvedPaths()
        this.RefreshPathSummary()
        this.CheckSettingsPaths()
        if (missing.Length) {
            msg := "Saved, but missing:`r`n"
            for item in missing
                msg .= "• " item "`r`n"
            this.settingsStatusCtl.Value := msg
            MsgBox(msg, "PGO Profiler 2 Settings", "Icon!")
        } else {
            this.settingsStatusCtl.Value := "All required paths OK. Settings saved to QMKconfig.ini."
            this.Log("Settings applied from secondary GUI.")
            this.Log("Source: " this.sourcePath)
        }
    }

    static CheckSettingsPaths() {
        ok := true
        for , row in this.settingsEdits {
            value := Trim(row.edit.Value)
            exists := (value != "" && (FileExist(value) || DirExist(value)))
            mismatch := row.key = "interceptionDllPath" && exists && this.DetectDllArchitecture(value) != "" && this.DetectDllArchitecture(value) != (A_Is64bitOS ? "x64" : "x86")
            row.edit.Opt(mismatch ? "+BackgroundFFF5D7" : (exists ? "+BackgroundC6F6D5" : (row.required ? "+BackgroundFED7D7" : "+BackgroundFFF5D7")))
            if (row.required && !exists)
                ok := false
        }
        return ok
    }

    ; ---------------------------------------------------------- build flags

    static BuildDefaults() {
        return {
            targetProfile: "x64",
            optimization: "ReleaseFast",
            lto: true,
            omitFramePointer: true,
            singleThreaded: true,
            stackCheck: false,
            unwindTables: false
        }
    }

    static ReadBuildBool(key, fallback) {
        value := StrLower(Trim(this.ReadSetting("Build", key, fallback ? "true" : "false")))
        return value = "true" || value = "1" || value = "yes" || value = "on"
    }

    static ShowBuildSettingsGui() {
        if (this.buildSettingsGui) {
            this.buildSettingsGui.Destroy()
            this.buildSettingsGui := ""
        }

        sg := Gui("+Owner" this.gui.Hwnd " +MinSize640x620", "QMK Build Flag Settings")
        this.buildSettingsGui := sg
        sg.MarginX := 14
        sg.MarginY := 12
        sg.BackColor := "F6F7FB"
        sg.SetFont("s9", "Segoe UI")
        this.buildSettingCtrls := Map()

        title := sg.AddText("xm ym w600 h24 c1F2937", "Build flag settings")
        title.SetFont("s13 w700", "Segoe UI")
        note := sg.AddText("xm y+2 w600 h48 c667085"
            , "Choose the target and code-generation settings used by Zig and Clang. The target must match the bitness of the AutoHotkey process running this compiler. x86 also requires a matching 32-bit Interception payload before it can run with the current loader.")
        note.SetFont("s9", "Segoe UI")

        this.AddBuildDropDown(sg, "targetProfile", "Target", ["x64 - 64-bit Windows", "x86 - 32-bit Windows"]
            , this.targetProfile = "x86" ? 2 : 1
            , "Selects whether the generated DLL is 64-bit or 32-bit. It must match the AutoHotkey process that loads it.")
        this.AddBuildDropDown(sg, "optimization", "Optimization", ["ReleaseFast", "ReleaseSafe", "ReleaseSmall", "Debug"]
            , this.OptimizationIndex()
            , "Controls the compiler's speed, safety, size, and debug tradeoff. ReleaseFast is the production default.")
        this.AddBuildCheckBox(sg, "lto", "Link-time optimization", this.lto
            , "Allows optimization across object/module boundaries. This can improve speed and size but increases build time.")
        this.AddBuildCheckBox(sg, "omitFramePointer", "Omit frame pointer", this.omitFramePointer
            , "Frees a register and can improve performance, but makes low-level stack walking and debugging less convenient.")
        this.AddBuildCheckBox(sg, "singleThreaded", "Single-threaded Zig mode", this.singleThreaded
            , "Tells Zig the generated code does not need its thread-safe runtime support, reducing runtime overhead.")
        this.AddBuildCheckBox(sg, "stackCheck", "Stack checks", this.stackCheck
            , "Adds stack-growth/overflow checks. It improves safety but adds code and runtime overhead.")
        this.AddBuildCheckBox(sg, "unwindTables", "Unwind tables", this.unwindTables
            , "Keeps exception/unwind metadata useful for stack unwinding and diagnostics, at the cost of extra binary data.")

        previewLabel := sg.AddText("xm y+12 w600 h18 c243447", "Command preview")
        previewLabel.SetFont("s9 w600", "Segoe UI")
        previewLabel.ToolTip := "The exact commands the compiler will use for the current settings."
        this.buildPreviewCtl := sg.AddEdit("xm y+4 w600 h150 ReadOnly +Wrap +VScroll", this.BuildCommandPreview())
        this.buildPreviewCtl.SetFont("s8", "Consolas")
        this.buildPreviewCtl.ToolTip := "Review or copy the generated command lines before building."

        applyBtn := sg.AddButton("xm y+16 w120 h30 Default", "Apply")
        applyBtn.ToolTip := "Save these build flags to QMKconfig.ini for future builds."
        applyBtn.OnEvent("Click", (*) => this.ApplyBuildSettings())
        defaultBtn := sg.AddButton("x+8 yp w130 h30", "Use Default")
        defaultBtn.ToolTip := "Restore the shipped production defaults in the editor. Press Apply to save them."
        defaultBtn.OnEvent("Click", (*) => this.UseBuildDefaults())
        closeBtn := sg.AddButton("x+8 yp w100 h30", "Close")
        closeBtn.ToolTip := "Close without saving unsaved build flag edits."
        closeBtn.OnEvent("Click", (*) => sg.Hide())
        reloadBtn := sg.AddButton("x+8 yp w150 h30", "Reload from INI")
        reloadBtn.ToolTip := "Discard unsaved edits and reload build flags from QMKconfig.ini."
        reloadBtn.OnEvent("Click", (*) => this.ReloadBuildSettingsIntoGui())
        saveProfileBtn := sg.AddButton("xm y+8 w130 h30", "Save Profile")
        saveProfileBtn.ToolTip := "Save the current editor values under a named build profile."
        saveProfileBtn.OnEvent("Click", (*) => this.SaveBuildProfile())
        loadProfileBtn := sg.AddButton("x+8 yp w130 h30", "Load Profile")
        loadProfileBtn.ToolTip := "Load a previously saved build profile into the editor without saving it yet."
        loadProfileBtn.OnEvent("Click", (*) => this.LoadBuildProfile())
        refreshPreviewBtn := sg.AddButton("x+8 yp w150 h30", "Refresh Preview")
        refreshPreviewBtn.ToolTip := "Regenerate the command preview from the current editor values."
        refreshPreviewBtn.OnEvent("Click", (*) => this.RefreshBuildCommandPreview())
        debugPresetBtn := sg.AddButton("xm y+8 w130 h30", "Debug Preset")
        debugPresetBtn.ToolTip := "Load a diagnostic preset with Debug optimization, frame pointers, stack checks, and unwind tables."
        debugPresetBtn.OnEvent("Click", (*) => this.ApplyBuildPreset("debug"))
        sizePresetBtn := sg.AddButton("x+8 yp w130 h30", "Small Preset")
        sizePresetBtn.ToolTip := "Load a smaller-DLL preset using ReleaseSmall and no LTO."
        sizePresetBtn.OnEvent("Click", (*) => this.ApplyBuildPreset("small"))

        this.buildSettingsStatusCtl := sg.AddText("xm y+12 w600 h36 c243447", "Changes apply to the next build.")
        sg.OnEvent("Close", (*) => (this.buildSettingsGui := "", sg.Destroy()))
        sg.Show()
    }

    static AddBuildDropDown(sg, key, label, choices, selectedIndex, tip) {
        lbl := sg.AddText("xm y+10 w190 h18 c243447", label)
        lbl.SetFont("s9 w600", "Segoe UI")
        lbl.ToolTip := tip
        ctl := sg.AddDropDownList("x+6 yp-2 w330", choices)
        ctl.Choose(selectedIndex)
        ctl.ToolTip := tip
        this.buildSettingCtrls[key] := ctl
    }

    static AddBuildCheckBox(sg, key, label, checked, tip) {
        ctl := sg.AddCheckBox("xm y+8 w520 h22", label)
        ctl.Value := checked ? 1 : 0
        ctl.ToolTip := tip
        this.buildSettingCtrls[key] := ctl
    }

    static AddBuildDropDownToMap(sg, map, key, label, choices, selectedIndex, tip) {
        lbl := sg.AddText("xm y+8 w190 h18 c243447", label)
        lbl.SetFont("s9 w600", "Segoe UI")
        ctl := sg.AddDropDownList("x+6 yp-2 w330", choices)
        ctl.Choose(selectedIndex)
        ctl.ToolTip := tip
        map[key] := ctl
        ctl.OnEvent("Change", (*) => this.CopyBuildSettingsToPrimary(map))
    }

    static AddBuildCheckBoxToMap(sg, map, key, label, checked, tip) {
        ctl := sg.AddCheckBox("xm y+8 w520 h22", label)
        ctl.Value := checked ? 1 : 0
        ctl.ToolTip := tip
        map[key] := ctl
        ctl.OnEvent("Click", (*) => this.CopyBuildSettingsToPrimary(map))
    }

    static CopyBuildSettingsToPrimary(map) {
        if !this.buildSettingCtrls.Has("targetProfile")
            return
        this.buildSettingCtrls["targetProfile"].Value := map["targetProfile"].Value
        this.buildSettingCtrls["optimization"].Value := map["optimization"].Value
        for key in ["lto", "omitFramePointer", "singleThreaded", "stackCheck", "unwindTables"]
            this.buildSettingCtrls[key].Value := map[key].Value
        this.RefreshBuildCommandPreview()
    }

    static HandleBuildTooltipMouseMove(wParam, lParam, msg, hwnd) {
        static previousHwnd := 0
        if (hwnd = previousHwnd)
            return

        ToolTip()
        this.buildTooltipText := ""
        this.buildTooltipGeneration += 1
        generation := this.buildTooltipGeneration
        try control := GuiCtrlFromHwnd(hwnd)
        catch
            control := ""
        if (control && control.HasProp("ToolTip")) {
            this.buildTooltipText := control.ToolTip
            text := this.buildTooltipText
            SetTimer(() => this.ShowBuildTooltip(text, generation), -150)
        }
        previousHwnd := hwnd
    }

    static ShowBuildTooltip(text, generation) {
        if (generation != this.buildTooltipGeneration || text != this.buildTooltipText)
            return
        ToolTip(text)
        SetTimer(() => ToolTip(), -5000)
    }

    static OptimizationIndex() {
        switch this.optimization {
            case "ReleaseFast": return 1
            case "ReleaseSafe": return 2
            case "ReleaseSmall": return 3
            case "Debug": return 4
        }
        return 1
    }

    static UseBuildDefaults() {
        defaults := this.BuildDefaults()
        this.SetBuildSettingsGuiValues(defaults)
        this.RefreshBuildCommandPreview()
        this.buildSettingsStatusCtl.Value := "Shipped defaults restored in the editor. Press Apply to save them."
    }

    static ApplyBuildPreset(name) {
        values := this.BuildDefaults()
        if (name = "debug") {
            values.optimization := "Debug"
            values.lto := false
            values.omitFramePointer := false
            values.stackCheck := true
            values.unwindTables := true
        } else if (name = "small") {
            values.optimization := "ReleaseSmall"
            values.lto := false
        }
        this.SetBuildSettingsGuiValues(values)
        this.RefreshBuildCommandPreview()
        this.buildSettingsStatusCtl.Value := "Loaded " name " preset in the editor. Press Apply to save it."
    }

    static SetBuildSettingsGuiValues(values) {
        this.buildSettingCtrls["targetProfile"].Choose(values.targetProfile = "x86" ? 2 : 1)
        optIndex := 1
        switch values.optimization {
            case "ReleaseSafe": optIndex := 2
            case "ReleaseSmall": optIndex := 3
            case "Debug": optIndex := 4
        }
        this.buildSettingCtrls["optimization"].Choose(optIndex)
        for key in ["lto", "omitFramePointer", "singleThreaded", "stackCheck", "unwindTables"]
            this.buildSettingCtrls[key].Value := values.%key% ? 1 : 0
    }

    static ReloadBuildSettingsIntoGui() {
        this.ReloadResolvedPaths()
        this.SetBuildSettingsGuiValues({
            targetProfile: this.targetProfile,
            optimization: this.optimization,
            lto: this.lto,
            omitFramePointer: this.omitFramePointer,
            singleThreaded: this.singleThreaded,
            stackCheck: this.stackCheck,
            unwindTables: this.unwindTables
        })
        this.RefreshBuildCommandPreview()
        this.buildSettingsStatusCtl.Value := "Reloaded from QMKconfig.ini."
    }

    static ApplyBuildSettings() {
        targetProfile := this.buildSettingCtrls["targetProfile"].Value = 2 ? "x86" : "x64"
        optimization := ["ReleaseFast", "ReleaseSafe", "ReleaseSmall", "Debug"][this.buildSettingCtrls["optimization"].Value]
        IniWrite(targetProfile, this.settingsPath, "Build", "targetProfile")
        IniWrite(optimization, this.settingsPath, "Build", "optimization")
        for key in ["lto", "omitFramePointer", "singleThreaded", "stackCheck", "unwindTables"]
            IniWrite(this.buildSettingCtrls[key].Value ? "true" : "false", this.settingsPath, "Build", key)
        this.ReloadResolvedPaths()
        this.RefreshPathSummary()
        this.RefreshBuildCommandPreview()
        this.buildSettingsStatusCtl.Value := "Build settings saved to QMKconfig.ini."
        this.Log("Build flags applied: " this.BuildSummary())
    }

    static BuildCommandPreview() {
        try {
            zig := this.ZigBuildCommand("dll", "QMKCoreProfiling.preview.dll", this.buildOptionsPath)
            clang := this.ClangBaseCommand("-fprofile-use=" Chr(34) "<profile>" Chr(34), "<final LLVM IR>", this.libDir "\QMKCoreProfiling.preview.dll")
            return "Zig runtime:`r`n" zig "`r`n`r`nClang final link:`r`n" clang
        } catch Error as err {
            return "Preview unavailable until the selected toolchain, build script, and Windows libraries are available.`r`n" err.Message
        }
    }

    static RefreshBuildCommandPreview() {
        preview := ""
        if this.buildPreviewCtl {
            this.SyncBuildSettingsFromGui()
            preview := this.BuildCommandPreview()
            try this.buildPreviewCtl.Value := preview
        }
        if (preview = "")
            preview := this.BuildCommandPreview()
        try {
            if this.zigBuildPreviewCtl
                this.zigBuildPreviewCtl.Value := preview
        }
        try {
            if this.pgoBuildPreviewCtl
                this.pgoBuildPreviewCtl.Value := preview
        }
    }

    static SyncBuildSettingsFromGui() {
        if !this.buildSettingCtrls.Has("targetProfile")
            return
        this.targetProfile := this.buildSettingCtrls["targetProfile"].Value = 2 ? "x86" : "x64"
        this.optimization := ["ReleaseFast", "ReleaseSafe", "ReleaseSmall", "Debug"][this.buildSettingCtrls["optimization"].Value]
        this.lto := !!this.buildSettingCtrls["lto"].Value
        this.omitFramePointer := !!this.buildSettingCtrls["omitFramePointer"].Value
        this.singleThreaded := !!this.buildSettingCtrls["singleThreaded"].Value
        this.stackCheck := !!this.buildSettingCtrls["stackCheck"].Value
        this.unwindTables := !!this.buildSettingCtrls["unwindTables"].Value
    }

    static ProfileSection(name) {
        safe := RegExReplace(name, "[^A-Za-z0-9_-]", "_")
        return "BuildProfile_" safe
    }

    static ProfileNames() {
        raw := Trim(this.ReadSetting("Profiles", "names", ""))
        if (raw = "")
            return []
        names := []
        for name in StrSplit(raw, "|")
            if (Trim(name) != "")
                names.Push(Trim(name))
        return names
    }

    static SaveBuildProfile() {
        result := InputBox("Enter a name for this build profile:", "Save Build Profile")
        if (result.Result != "OK")
            return
        name := Trim(result.Value)
        if (name = "")
            return
        section := this.ProfileSection(name)
        IniWrite(this.buildSettingCtrls["targetProfile"].Value = 2 ? "x86" : "x64", this.settingsPath, section, "targetProfile")
        IniWrite(["ReleaseFast", "ReleaseSafe", "ReleaseSmall", "Debug"][this.buildSettingCtrls["optimization"].Value], this.settingsPath, section, "optimization")
        for key in ["lto", "omitFramePointer", "singleThreaded", "stackCheck", "unwindTables"]
            IniWrite(this.buildSettingCtrls[key].Value ? "true" : "false", this.settingsPath, section, key)
        names := this.ProfileNames()
        found := false
        for index, oldName in names {
            if (StrLower(oldName) = StrLower(name)) {
                names[index] := name
                found := true
                break
            }
        }
        if !found
            names.Push(name)
        IniWrite(this.JoinNamesWithDelimiter(names, "|"), this.settingsPath, "Profiles", "names")
        this.buildSettingsStatusCtl.Value := "Saved build profile: " name
    }

    static LoadBuildProfile() {
        names := this.ProfileNames()
        if !names.Length {
            MsgBox("No saved build profiles exist yet.", "QMK Compiler", "Iconi")
            return
        }
        result := InputBox("Available profiles:`n" this.JoinNames(names) "`n`nEnter the profile name to load:", "Load Build Profile")
        if (result.Result != "OK")
            return
        requested := Trim(result.Value)
        selected := ""
        for name in names
            if (StrLower(name) = StrLower(requested)) {
                selected := name
                break
            }
        if (selected = "") {
            MsgBox("Profile not found: " requested, "QMK Compiler", "Icon!")
            return
        }
        section := this.ProfileSection(selected)
        values := {
            targetProfile: this.ReadSetting(section, "targetProfile", "x64"),
            optimization: this.ReadSetting(section, "optimization", "ReleaseFast"),
            lto: this.ReadBuildBoolFrom(section, "lto", true),
            omitFramePointer: this.ReadBuildBoolFrom(section, "omitFramePointer", true),
            singleThreaded: this.ReadBuildBoolFrom(section, "singleThreaded", true),
            stackCheck: this.ReadBuildBoolFrom(section, "stackCheck", false),
            unwindTables: this.ReadBuildBoolFrom(section, "unwindTables", false)
        }
        this.SetBuildSettingsGuiValues(values)
        this.RefreshBuildCommandPreview()
        this.buildSettingsStatusCtl.Value := "Loaded profile: " selected ". Press Apply to save it as the active configuration."
    }

    static ReadBuildBoolFrom(section, key, fallback) {
        value := StrLower(Trim(this.ReadSetting(section, key, fallback ? "true" : "false")))
        return value = "true" || value = "1" || value = "yes" || value = "on"
    }

    static JoinNamesWithDelimiter(names, delimiter) {
        result := ""
        for index, name in names
            result .= (index > 1 ? delimiter : "") name
        return result
    }

    static BuildSummary() {
        return this.targetProfile " / " this.optimization "/" (this.lto ? "LTO" : "no LTO")
    }

    static OfferToolchainSetup() {
        if this.toolchainPromptShown
            return
        this.toolchainPromptShown := true

        missing := this.MissingToolchainNames()
        if !missing.Length
            return

        names := this.JoinNames(missing)
        answer := MsgBox(names " not found at the configured paths.`n`nTry to automatically detect the installation path now?", "QMK Compiler", "YesNoCancel Icon!")
        if (answer = "Yes") {
            this.AutoDetectToolchain()
            this.ReloadResolvedPaths()
            this.RefreshPathSummary()
            missing := this.MissingToolchainNames()
            if !missing.Length {
                MsgBox("Toolchain paths detected and saved to QMKconfig.ini.", "QMK Compiler", "Iconi")
                return
            }
        } else if (answer = "Cancel") {
            return
        }

        names := this.JoinNames(missing)
        choice := MsgBox(names " could not be found automatically.`n`nYes: choose the paths manually.`nNo: open official installation pages.`nCancel: leave settings unchanged.", "QMK Compiler", "YesNoCancel Icon!")
        if (choice = "Yes") {
            this.ShowSettingsGui("pgo")
        } else if (choice = "No") {
            this.OpenToolchainInstallPages(missing)
            MsgBox("After installing, reopen Build Flag Settings or PGO Settings and choose Reload from INI / Apply.", "QMK Compiler", "Iconi")
        }
    }

    static MissingToolchainNames() {
        missing := []
        if !FileExist(this.zigPath)
            missing.Push("Zig")
        if !FileExist(this.clangPath)
            missing.Push("Clang/LLVM")
        if !FileExist(this.profdataPath)
            missing.Push("llvm-profdata")
        return missing
    }

    static JoinNames(names) {
        result := ""
        for index, name in names
            result .= (index > 1 ? ", " : "") name
        return result
    }

    static AutoDetectToolchain() {
        zig := this.FindToolOnPath("zig.exe")
        clang := this.FindToolOnPath("clang.exe")
        profdata := this.FindToolOnPath("llvm-profdata.exe")
        if (zig != "") {
            this.zigPath := zig
            IniWrite(zig, this.settingsPath, "Tools", "zigPath")
            this.Log("Auto-detected Zig: " zig)
        }
        if (clang != "") {
            this.clangPath := clang
            IniWrite(clang, this.settingsPath, "Tools", "clangPath")
            this.Log("Auto-detected Clang: " clang)
        }
        if (profdata != "") {
            this.profdataPath := profdata
            IniWrite(profdata, this.settingsPath, "Tools", "llvmProfdataPath")
            this.Log("Auto-detected llvm-profdata: " profdata)
        }
    }

    static FindToolOnPath(executable) {
        try {
            shell := ComObject("WScript.Shell")
            command := A_ComSpec " /d /c where.exe " executable " 2>nul"
            process := shell.Exec(command)
            while !process.StdOut.AtEndOfStream {
                candidate := Trim(process.StdOut.ReadLine())
                if (candidate != "" && FileExist(candidate))
                    return candidate
            }
        } catch
            return ""
        return ""
    }

    static OpenToolchainInstallPages(missing) {
        for , name in missing {
            if (name = "Zig")
                Run("https://ziglang.org/download/")
            else if (name = "Clang/LLVM" || name = "llvm-profdata")
                Run("https://releases.llvm.org/download.html")
        }
    }

    static MakeRelativeToPathBase(path, key) {
        if (key = "configPath" || key = "pgoToolPath")
            return this.MakeRelativeToBase(path, this.packageDir)
        return this.MakeRelativeToBase(path, this.libDir)
    }

    static MakeRelativeToBase(path, base) {
        prefix := RTrim(base, "\") "\"
        return InStr(path, prefix) == 1 ? ".\" SubStr(path, StrLen(prefix) + 1) : path
    }

    static ReloadResolvedPaths() {
        this.sourcePath := this.LibPath("sourcePath", "QMKCore.zig")
        this.buildOptionsPath := this.LibPath("pgoBuildOptionsPath", "build_options_pgo.zig")
        this.runtimeBuildOptionsPath := this.LibPath("runtimeBuildOptionsPath", "build_options_runtime.zig")
        this.variablesPath := this.LibPath("variablesPath", "QMKVariables.ahk")
        legacyFallback := A_Is64bitOS
            ? this.ReadSetting("Paths", "interceptionDllPath64", ".\interception.dll")
            : this.ReadSetting("Paths", "interceptionDllPath32", ".\interception32.dll")
        this.interceptionDllPath := this.LibPath("interceptionDllPath", legacyFallback)
        this.interceptionDllPath64 := this.interceptionDllPath
        this.interceptionDllPath32 := this.interceptionDllPath
        this.configPath := this.PackagePath("configPath", "QMKconfig.ini")
        this.trainingDllPath := this.LibPath("trainingDllPath", "QMKTrainingData.dll")
        this.finalDllPath := this.LibPath("runtimeDllPath", "QMKCoreProfiling.dll")
        ; Macropad Includes.ahk loads the active callback bridge from this
        ; directory. Keep the compiler's default aligned with that live path
        ; so the DLL and AHK callback map are generated as one bundle.
        this.compiledShortcutDir := this.LibPath("compiledShortcutDir", "generated_native_user_shortcuts")
        this.compiledShortcutZigPath := this.compiledShortcutDir "\generated_user_shortcuts.zig"
        this.compiledShortcutAhkPath := this.packageDir "\user_callbacks.ahk"
        this.canonicalCompiledShortcutAhkPath := this.compiledShortcutAhkPath
        this.blankShortcutModulePath := this.LibPath("blankShortcutModulePath", "blank_user_shortcuts.zig")
        this.trainingDir := this.LibPath("trainingDataDir", "TrainingData")
        this.trainerSourcePath := this.LibPath("pgoTrainerSourcePath", "QMKCorePGOTrainer.zig")
        this.trainerExePath := this.LibPath("pgoTrainerExePath", "QMKCorePGOTrainer.exe")
        this.trainerHashPath := this.trainerExePath ".source.sha256"
        this.syntheticProfilePath := this.LibPath("syntheticPgoProfilePath", "TrainingData\qmk_pgo_auto_trainer.profraw")
        ; The maintained transpiler executable matches the active source
        ; user_shortcut_transpiler.zig.  The older zig_user_shortcut_transpiler.exe
        ; is a stale build and can emit a manifest without updating the typed
        ; artifact, leaving the DLL one generation behind the AHK sources.
        this.shortcutTranspilerPath := this.LibPath("shortcutTranspilerPath", "zig_user_shortcut_transpiler\user_shortcut_transpiler.exe")
        this.shortcutTranspilerSourcePath := this.LibPath("shortcutTranspilerSourcePath", "zig_user_shortcut_transpiler\user_shortcut_transpiler.zig")
        this.shortcutTranspilerHashPath := this.shortcutTranspilerPath ".source.sha256"
        this.zigPath := this.ToolPath("zigPath", "C:\Program Files\zig\zig.exe")
        this.clangPath := this.ToolPath("clangPath", "C:\Program Files\LLVM\bin\clang.exe")
        this.profdataPath := this.ToolPath("llvmProfdataPath", "C:\Program Files\LLVM\bin\llvm-profdata.exe")

        defaults := this.BuildDefaults()
        this.targetProfile := this.ReadSetting("Build", "targetProfile", defaults.targetProfile)
        if (this.targetProfile != "x64" && this.targetProfile != "x86")
            this.targetProfile := defaults.targetProfile
        this.optimization := this.ReadSetting("Build", "optimization", defaults.optimization)
        if !InStr("|ReleaseFast|ReleaseSafe|ReleaseSmall|Debug|", "|" this.optimization "|")
            this.optimization := defaults.optimization
        this.lto := this.ReadBuildBool("lto", defaults.lto)
        this.omitFramePointer := this.ReadBuildBool("omitFramePointer", defaults.omitFramePointer)
        this.singleThreaded := this.ReadBuildBool("singleThreaded", defaults.singleThreaded)
        this.stackCheck := this.ReadBuildBool("stackCheck", defaults.stackCheck)
        this.unwindTables := this.ReadBuildBool("unwindTables", defaults.unwindTables)
        this.LoadShortcutSourceFiles()
    }

    static OnClose() {
        if (this.running) {
            if (MsgBox("A build is still running. Cancel it and exit?", "QMK Compiler", "YesNo Icon!") = "No")
                return
            this.RequestCancel()
        }
        ExitApp(0)
    }

    static Log(text) {
        this.LogRaw(text "`r`n")
    }

    ; Command-line AHK processes do not reliably have a writable `*` output
    ; handle. Keep diagnostics durable instead of masking the real compiler
    ; error with Error 6 (invalid handle).
    static WriteCliLine(text) {
        try FileAppend(text "`r`n", A_Temp "\\QMKCompiler.cli.log", "UTF-8")
    }

    static WriteStatus(phase, message, terminal := "", pct := unset) {
        if (this.statusPath = "")
            return
        if !IsSet(pct)
            pct := this.pctCtl ? this.pctCtl.Value : 0
        text := "phase=" phase "`r`nmessage=" StrReplace(message, "`r`n", " ") "`r`n"
            . "percent=" pct "`r`nstep=" this.stepIndex "`r`n"
            . "reload=" (this.cliReload ? "1" : "0") "`r`n"
            . "terminal=" terminal "`r`n"
        try this.AtomicWriteText(this.statusPath, text, "UTF-8-RAW")
    }

    static LogRaw(text) {
        if (text = "")
            return
        text := StrReplace(text, "`r`n", "`n")
        text := StrReplace(text, "`r", "`n")
        text := StrReplace(text, "`n", "`r`n")
        this.logLines.Push(text)
        if !this.logCtl
            return
        ; Keep the newest output visible without re-rendering the whole buffer.
        this.logCtl.Value := this.logCtl.Value text
        SendMessage(0x0115, 7, 0, this.logCtl)   ; WM_VSCROLL / SB_BOTTOM
    }

    static SaveLog() {
        path := FileSelect("S16", this.projectRoot "\_CURRENT\pgo2_build_log.txt", "Save build log", "Text (*.txt)")
        if (path = "")
            return
        try {
            if FileExist(path)
                FileDelete(path)
            FileAppend(this.logCtl.Value, path, "UTF-8")
            this.Log("Saved log to " path)
        } catch Error as err {
            MsgBox("Could not save log: " err.Message, "QMK Compiler")
        }
    }

    static CopyLog() {
        if !this.logCtl
            return
        A_Clipboard := this.logCtl.Value
        ToolTip("Compiler log copied to clipboard")
        SetTimer(() => ToolTip(), -1600)
    }

    ; ------------------------------------------------ compiled user shortcuts

    static LoadShortcutSourceFiles() {
        this.shortcutSourceFiles := []
        this.shortcutUseGeneratedInclude := this.ReadSetting("CompiledShortcuts", "useGeneratedInclude", "0") = "1"
        ; Partial compilation is retired. Keep the INI key readable for old
        ; configurations, but always use the complete native bundle.
        this.shortcutCompileMode := "full_native"
        this.shortcutCallbackOutputMode := this.ReadSetting("CompiledShortcuts", "callbackOutputMode", "single")
        ; "custom" was the old UI mode. Keep old INI files readable, but
        ; present that saved destination as the single-file Browse path.
        if (this.shortcutCallbackOutputMode = "custom")
            this.shortcutCallbackOutputMode := "single"
        if (this.shortcutCallbackOutputMode != "single" && this.shortcutCallbackOutputMode != "per_source")
            this.shortcutCallbackOutputMode := "single"
        this.shortcutCallbackCustomPath := this.ReadSetting("CompiledShortcuts", "callbackCustomPath", "")
        if (this.shortcutCallbackCustomPath != "")
            this.shortcutCallbackCustomPath := this.Anchor(this.shortcutCallbackCustomPath, this.packageDir)
        if (StrLower(Trim(this.shortcutCallbackCustomPath)) = "select browse for a custom location")
            this.shortcutCallbackCustomPath := ""
        if this.IsSamePath(this.shortcutCallbackCustomPath, this.canonicalCompiledShortcutAhkPath)
            this.shortcutCallbackCustomPath := ""
        count := 0
        try count := Integer(this.ReadSetting("CompiledShortcuts", "sourceCount", "0"))
        catch
            count := 0
        Loop Max(0, count) {
            path := Trim(this.ReadSetting("CompiledShortcuts", "source" A_Index, ""))
            if (path != "")
                this.shortcutSourceFiles.Push(this.Anchor(path, this.packageDir))
        }
        if !this.shortcutSourceFiles.Length
            this.shortcutUseGeneratedInclude := false
        this.RefreshCallbackOutputPath()
        this.shortcutSourceCount := this.shortcutSourceFiles.Length
    }

    static ShortcutSourceListText() {
        if !this.shortcutSourceFiles.Length
            return "(No saved shortcut source files.)"
        text := ""
        for index, path in this.shortcutSourceFiles
            text .= index ". " path "`r`n"
        return RTrim(text, "`r`n")
    }

    static ShowShortcutSettingsGui() {
        if this.shortcutSettingsGui {
            this.shortcutSettingsGui.Destroy()
            this.shortcutSettingsGui := ""
        }
        sg := Gui("+Owner" this.gui.Hwnd " +MinSize760x540", "Transpile User Shortcuts Settings")
        this.shortcutSettingsGui := sg
        sg.SetFont("s9", "Segoe UI")
        intro := sg.AddText("xm ym w700 h58", "Recommended if noticing delay on startup. Takes your QMK shortcuts from AutoHotkey file(s) and embeds them directly into the DLL for quicker startup, as well as generating an AHK callback file. Recompile required for each desired change.")
        intro.SetFont("s9", "Segoe UI")
        sg.AddText("xm y+10 w700 h22", "Shortcut source files (processed in this order):")
        listCtl := sg.AddEdit("xm y+4 w700 h130 ReadOnly +Wrap +VScroll", this.ShortcutSourceListText())
        this.shortcutSettingsListCtl := listCtl
        this.shortcutSettingsListIsView := false
        replaceBtn := sg.AddButton("xm y+10 w150 h30", "Replace Files")
        addBtn := sg.AddButton("x+8 yp w120 h30", "Add Files")
        clearBtn := sg.AddButton("x+8 yp w110 h30", "Clear")
        replaceBtn.OnEvent("Click", (*) => this.SelectShortcutFilesForSettings(false))
        addBtn.OnEvent("Click", (*) => this.SelectShortcutFilesForSettings(true))
        clearBtn.OnEvent("Click", (*) => (this.shortcutSourceFiles := [], this.shortcutSettingsListCtl.Value := this.ShortcutSourceListText()))

        sg.AddText("xm y+16 w700 h22", "Generated hotkey file settings and location:")
        sg.AddText("xm y+4 w700 h34 c667085", "Choose one callback file or one file per source. In single-file mode, Browse opens Save As so you can choose the destination.")
        outputCtl := sg.AddDropDownList("xm y+6 w520", ["One callback file", "One file per source"])
        outputCtl.Value := this.shortcutCallbackOutputMode = "per_source" ? 2 : 1
        this.shortcutCallbackOutputModeCtl := outputCtl
        customPathCtl := sg.AddEdit("xm y+6 w600 h22 ReadOnly", this.shortcutCallbackCustomPath != "" ? this.shortcutCallbackCustomPath : this.canonicalCompiledShortcutAhkPath)
        this.shortcutCallbackCustomPathCtl := customPathCtl
        browseCallbackBtn := sg.AddButton("x+8 yp w90 h24", "Browse")
        browseCallbackBtn.OnEvent("Click", (*) => this.SelectCustomCallbackPath(customPathCtl))
        outputCtl.OnEvent("Change", (*) => browseCallbackBtn.Enabled := outputCtl.Value = 1)
        browseCallbackBtn.Enabled := outputCtl.Value = 1
        sg.AddText("xm y+8 w700 h34 c667085", "One callback file uses the selected Save As destination, or the default generated callback path when Browse is not used. Per-source mode writes one callback map beside each original source.")
        saveBtn := sg.AddButton("xm y+14 w110 h30 Default", "Save")
        cancelBtn := sg.AddButton("x+8 yp w110 h30", "Cancel")
        this.shortcutSettingsStatusCtl := sg.AddText("x+16 yp+7 w440 h22 c243447", "")
        saveBtn.OnEvent("Click", (*) => this.SaveShortcutSettings(sg, outputCtl, customPathCtl))
        cancelBtn.OnEvent("Click", (*) => sg.Destroy())
        sg.OnEvent("Close", (*) => (this.shortcutSettingsGui := "", sg.Destroy()))
        sg.Show()
    }

    static SelectShortcutFilesForSettings(additive := false) {
        selection := FileSelect("M3", this.packageDir, additive ? "Add QMK shortcut source files" : "Choose QMK shortcut source files", "AutoHotkey files (*.ahk)")
        if (selection = "")
            return
        paths := this.NormalizeShortcutSelection(selection)
        if additive {
            for , path in paths {
                duplicate := false
                for , existing in this.shortcutSourceFiles
                    if StrLower(existing) = StrLower(path)
                        duplicate := true
                if !duplicate
                    this.shortcutSourceFiles.Push(path)
            }
        } else {
            this.shortcutSourceFiles := paths
        }
        this.RefreshShortcutSettingsList()
    }

    static RefreshShortcutSettingsList() {
        if !this.shortcutSettingsListCtl
            return
        if this.shortcutSettingsListIsView {
            this.shortcutSettingsListCtl.Delete()
            for , path in this.shortcutSourceFiles
                this.shortcutSettingsListCtl.Add(, path)
        } else {
            this.shortcutSettingsListCtl.Value := this.ShortcutSourceListText()
        }
    }

    static RemoveSelectedShortcutFiles() {
        if !this.shortcutSettingsListIsView
            return
        selected := []
        row := 0
        while row := this.shortcutSettingsListCtl.GetNext(row)
            selected.Push(row)
        Loop selected.Length {
            index := selected[selected.Length - A_Index + 1]
            this.shortcutSourceFiles.RemoveAt(index)
        }
        this.RefreshShortcutSettingsList()
    }

    static SaveShortcutSettings(sg, outputCtl, customPathCtl) {
        if !this.shortcutSourceFiles.Length {
            this.SetShortcutSettingsStatus("Choose at least one source file.")
            return false
        }
        for , path in this.shortcutSourceFiles {
            if !FileExist(path) {
                this.SetShortcutSettingsStatus("Missing file: " path)
                return false
            }
        }
        this.shortcutCallbackOutputMode := outputCtl.Value = 2 ? "per_source" : "single"
        this.shortcutCallbackCustomPath := outputCtl.Value = 1 ? Trim(customPathCtl.Value) : ""
        if this.IsSamePath(this.shortcutCallbackCustomPath, this.canonicalCompiledShortcutAhkPath)
            this.shortcutCallbackCustomPath := ""
        if (this.shortcutCallbackOutputMode = "single" && this.shortcutCallbackCustomPath != "") {
            for , sourcePath in this.shortcutSourceFiles {
                if (StrLower(RTrim(this.shortcutCallbackCustomPath, "\")) = StrLower(RTrim(sourcePath, "\"))) {
                    MsgBox("The callback destination matches an original source file and would delete/replace it. Choose a different path.", "Transpile User Shortcuts Settings", "Icon!")
                    return false
                }
            }
        }
        this.SaveShortcutSourceFiles()
        IniWrite(this.shortcutCallbackOutputMode, this.settingsPath, "CompiledShortcuts", "callbackOutputMode")
        callbackPathToStore := this.shortcutCallbackCustomPath = ""
            ? ""
            : this.MakeRelativeToBase(this.shortcutCallbackCustomPath, this.packageDir)
        IniWrite(callbackPathToStore, this.settingsPath, "CompiledShortcuts", "callbackCustomPath")
        this.RefreshCallbackOutputPath()
        this.Log("Transpile user-shortcut settings saved: " this.shortcutSourceFiles.Length " source file(s), " this.shortcutCompileMode ", " this.shortcutCallbackOutputMode ".")
        this.SetShortcutSettingsStatus("Saved to QMKconfig.ini.")
        if (!this.settingsGui || sg.Hwnd != this.settingsGui.Hwnd)
            SetTimer(() => (this.shortcutSettingsGui := "", sg.Destroy()), -500)
        return true
    }

    static SetShortcutSettingsStatus(text) {
        if this.shortcutSettingsStatusCtl
            this.shortcutSettingsStatusCtl.Value := text
    }

    static SelectCustomCallbackPath(control) {
        defaultPath := this.shortcutCallbackCustomPath != "" ? this.shortcutCallbackCustomPath : this.canonicalCompiledShortcutAhkPath
        path := FileSelect("S16", defaultPath, "Choose callback file destination", "AutoHotkey files (*.ahk)")
        if (path != "")
            control.Value := path
    }

    static SaveShortcutIncludeReminder() {
        this.shortcutUseGeneratedInclude := this.shortcutUseGeneratedCtl && this.shortcutUseGeneratedCtl.Value ? true : false
        IniWrite(this.shortcutUseGeneratedInclude ? 1 : 0, this.settingsPath, "CompiledShortcuts", "useGeneratedInclude")
        this.Log(this.shortcutUseGeneratedInclude
            ? "Generated shortcut include selected for the next build; update QMK includes separately after verification."
            : "Blank shortcut module selected for the next build; generated shortcuts will not be included.")
    }

    static RefreshCallbackOutputPath() {
        if (this.shortcutCallbackOutputMode = "single" && this.shortcutCallbackCustomPath != "")
            this.compiledShortcutAhkPath := this.shortcutCallbackCustomPath
        else
            this.compiledShortcutAhkPath := this.canonicalCompiledShortcutAhkPath
    }

    static GeneratedCallbackArtifactPath() {
        return this.shortcutCallbackOutputMode = "per_source"
            ? this.compiledShortcutDir "\user_callbacks.ahk"
            : this.compiledShortcutAhkPath
    }

    static IsSamePath(left, right) {
        if (left = "" || right = "")
            return false
        normalize := (value) => StrLower(RTrim(StrReplace(value, "/", "\"), "\"))
        return normalize(left) = normalize(right)
    }

    static SaveShortcutSourceFiles() {
        IniWrite(this.shortcutSourceFiles.Length, this.settingsPath, "CompiledShortcuts", "sourceCount")
        Loop 64
            IniDelete(this.settingsPath, "CompiledShortcuts", "source" A_Index)
        for index, path in this.shortcutSourceFiles
            IniWrite(this.MakeRelativeToBase(path, this.packageDir), this.settingsPath, "CompiledShortcuts", "source" index)
        this.shortcutSourceCount := this.shortcutSourceFiles.Length
    }

    static NormalizeShortcutSelection(selection) {
        paths := []
        if IsObject(selection) {
            for , path in selection
                if (Trim(path) != "")
                    paths.Push(path)
            return paths
        }

        lines := StrSplit(StrReplace(selection, "`r", ""), "`n")
        while (lines.Length && Trim(lines[lines.Length]) = "")
            lines.Pop()
        if (lines.Length = 1) {
            if (Trim(lines[1]) != "")
                paths.Push(Trim(lines[1]))
            return paths
        }

        base := Trim(lines[1])
        if DirExist(base) {
            Loop lines.Length - 1 {
                name := Trim(lines[A_Index + 1])
                if (name != "")
                    paths.Push(RTrim(base, "\") "\" name)
            }
        } else {
            for , path in lines
                if (Trim(path) != "")
                    paths.Push(Trim(path))
        }
        return paths
    }

    static CollectUserShortcutFiles() {
        if this.running {
            MsgBox("Finish the current build before collecting user shortcuts.", "QMK Compiler", "Icon!")
            return
        }
        if this.shortcutSourceFiles.Length {
            for , path in this.shortcutSourceFiles {
                if !FileExist(path) {
                    MsgBox("A saved shortcut source file is missing:`n" path "`n`nUpdate it in Compiler User Shortcuts Settings.", "QMK Compiler - User Shortcuts", "Icon!")
                    this.ShowShortcutSettingsGui()
                    return
                }
            }
            try {
                this.CaptureUserShortcutFiles()
                if FileExist(this.compiledShortcutZigPath) && FileExist(this.compiledShortcutAhkPath)
                    this.PromptCompileGeneratedShortcuts()
            } catch Error as err {
                this.Log("*** Shortcut capture failed: " err.Message " ***")
                MsgBox(err.Message, "QMK Compiler - User Shortcuts", "Icon!")
            }
            return
        }
        selection := FileSelect("M3", this.packageDir, "Choose QMK shortcut source files", "AutoHotkey files (*.ahk)")
        if (selection = "")
            return
        paths := this.NormalizeShortcutSelection(selection)
        if !paths.Length {
            MsgBox("No AutoHotkey source files were selected.", "QMK Compiler", "Icon!")
            return
        }
        ; Windows' multi-select dialog is commonly limited to one directory.
        ; Offer an explicit second pass so a user's shortcut families can be
        ; collected from different locations without losing the first batch.
        while (MsgBox("Add shortcut source files from another directory?", "QMK Compiler - User Shortcuts", "YesNo Iconi") = "Yes") {
            additionalSelection := FileSelect("M3", this.packageDir, "Add QMK shortcut source files", "AutoHotkey files (*.ahk)")
            if (additionalSelection = "")
                break
            additionalPaths := this.NormalizeShortcutSelection(additionalSelection)
            for , additionalPath in additionalPaths {
                duplicate := false
                for , existingPath in paths {
                    if (StrLower(existingPath) = StrLower(additionalPath)) {
                        duplicate := true
                        break
                    }
                }
                if !duplicate
                    paths.Push(additionalPath)
            }
        }
        for , path in paths {
            if !FileExist(path)
                throw Error("Selected shortcut source does not exist:`n" path)
        }

        this.shortcutSourceFiles := paths
        this.SaveShortcutSourceFiles()
        this.Log("Selected user shortcut sources (ordered):")
        for index, path in paths
            this.Log("  [" index "] " path)

        try {
            this.CaptureUserShortcutFiles()
            if FileExist(this.compiledShortcutZigPath) && FileExist(this.compiledShortcutAhkPath) {
                this.PromptCompileGeneratedShortcuts()
            }
        } catch Error as err {
            this.Log("*** Shortcut capture failed: " err.Message " ***")
            MsgBox(err.Message, "QMK Compiler - User Shortcuts", "Icon!")
        }
    }

    ; Generation and DLL compilation are separate decisions.  The user may
    ; inspect the generated artifacts first, or explicitly choose which final
    ; build pipeline should embed them into the DLL.
    static PromptCompileGeneratedShortcuts() {
        answer := MsgBox("Generated user-shortcut files are ready.`n`nDo you want to compile these shortcuts into the QMK DLL now?", "QMK Compiler - User Shortcuts", "YesNo Iconi")
        if (answer != "Yes")
            return

        choice := Gui("+AlwaysOnTop", "QMK Compiler - Choose Build")
        choice.SetFont("s10", "Segoe UI")
        choice.AddText("w460", "Choose the build used to compile the generated user shortcuts into the DLL:")
        choice.AddText("xm y+12 w460", "Zig full build is the quicker normal build. PGO trains and embeds the profile-guided final DLL.")
        zigButton := choice.AddButton("xm y+18 w220 h32", "Zig full build")
        pgoButton := choice.AddButton("x+10 yp w220 h32", "Profile-guided optimization (PGO)")
        cancelButton := choice.AddButton("xm y+12 w100 h28", "Cancel")
        zigButton.OnEvent("Click", (*) => this.RunGeneratedShortcutBuildChoice(choice, "zig"))
        pgoButton.OnEvent("Click", (*) => this.RunGeneratedShortcutBuildChoice(choice, "full"))
        cancelButton.OnEvent("Click", (*) => choice.Destroy())
        choice.OnEvent("Close", (*) => choice.Destroy())
        choice.Show()
    }

    static RunGeneratedShortcutBuildChoice(choice, mode) {
        choice.Destroy()
        ; This explicit prompt is the opt-in for putting the generated module
        ; into the selected DLL build.
        this.shortcutUseGeneratedInclude := true
        IniWrite(1, this.settingsPath, "CompiledShortcuts", "useGeneratedInclude")
        this.Log("Generated user shortcuts explicitly selected for DLL compilation.")
        this.Log(mode = "zig" ? "Selected generated-shortcut build: Zig full build." : "Selected generated-shortcut build: profile-guided optimization (PGO).")
        this.RunCliPipeline(mode)
    }

    static CaptureUserShortcutFiles(showDialog := true) {
        ; Shortcut generation is an execution path in its own right. Refresh
        ; the saved snapshot immediately before invoking the transpiler, while
        ; retaining explicit one-shot CLI overrides in this process.
        if !this.cliSourceOverride {
            this.ReloadResolvedPaths()
            this.LoadShortcutSourceFiles()
        }
        this.EnsureShortcutTranspilerFresh()
        this.RequireFile(this.shortcutTranspilerPath, "Zig user-shortcut transpiler")
        DirCreate(this.compiledShortcutDir)
        command := this.Quote(this.shortcutTranspilerPath) " --emit"
        for , path in this.shortcutSourceFiles
            command .= " --source " this.Quote(path)
        command .= " --output-dir " this.Quote(this.compiledShortcutDir)

        this.Log("Running the Zig user-shortcut transpiler (the AHK collector is intentionally disabled).")
        ; The former implementation is intentionally commented out. Do not
        ; silently fall back to it: unsupported or malformed input must fail.
        ; QMKShortcutCollector.CaptureSourceFiles(this.shortcutSourceFiles, reportPath)
        this.RunStep(command, this.libDir, "Zig user-shortcut transpiler")
        this.RequireFile(this.compiledShortcutZigPath, "generated user_shortcuts.zig")
        rawAhkPath := this.compiledShortcutDir "\user_callbacks.ahk"
        this.RequireFile(rawAhkPath, "generated user_callbacks.ahk")
        thisNormalize := this.ComputeShortcutBuildId(this.shortcutSourceFiles)
        zigText := FileRead(this.compiledShortcutZigPath, "UTF-8")
        zigText := RegExReplace(zigText, "compiled_build_id\s*=\s*`"[^`"]*`"", "compiled_build_id = `"" thisNormalize "`"")
        this.AtomicWriteText(this.compiledShortcutZigPath, zigText, "UTF-8-RAW")
        ahkText := FileRead(rawAhkPath, "UTF-8")
        if !InStr(ahkText, "; build_id:")
            ahkText := StrReplace(ahkText, "; Complete-compiled mode callback map.", "; Complete-compiled mode callback map.`n; build_id: " thisNormalize)
        this.AtomicWriteText(rawAhkPath, ahkText, "UTF-8-RAW")
        this.PublishCallbackOutputs(rawAhkPath)
        this.Log("Zig transpiler emitted the generated shortcut bundle.")
        if showDialog
            MsgBox("Zig transpiler generated the compiled-user-shortcut files.`n`n" this.ShortcutIncludeMigrationText(), "QMK Compiler - User Shortcuts", "Iconi")
    }

    static EnsureShortcutTranspilerFresh() {
        this.RequireFile(this.shortcutTranspilerSourcePath, "Zig user-shortcut transpiler source")
        sourceHash := this.Sha256File(this.shortcutTranspilerSourcePath)
        savedHash := ""
        if FileExist(this.shortcutTranspilerHashPath)
            try savedHash := Trim(FileRead(this.shortcutTranspilerHashPath, "UTF-8"))
        if FileExist(this.shortcutTranspilerPath) && (savedHash = sourceHash) {
            this.Log("Zig user-shortcut transpiler is current (source SHA-256 " sourceHash ").")
            return
        }

        this.Log("Zig user-shortcut transpiler is stale or unmarked; rebuilding before transpilation.")
        command := this.Quote(this.zigPath) " build-exe " this.Quote(this.shortcutTranspilerSourcePath)
            . " -O ReleaseFast -target x86_64-windows-gnu -femit-bin=" this.Quote(this.shortcutTranspilerPath)
        this.RunStep(command, this.DirFromPath(this.shortcutTranspilerPath), "Zig user-shortcut transpiler rebuild")
        this.RequireFile(this.shortcutTranspilerPath, "rebuilt Zig user-shortcut transpiler")
        this.WriteTextFile(this.shortcutTranspilerHashPath, sourceHash "`n")
        this.Log("Zig user-shortcut transpiler rebuilt and marked with source SHA-256 " sourceHash ".")
    }

    static Sha256File(path) {
        data := FileRead(path, "RAW")
        algorithm := 0
        hash := 0
        digest := Buffer(32, 0)
        status := DllCall("bcrypt\BCryptOpenAlgorithmProvider", "Ptr*", &algorithm, "WStr", "SHA256", "Ptr", 0, "UInt", 0, "Int")
        if (status != 0)
            throw Error("Could not open the Windows SHA-256 provider for " path ".")
        try {
            status := DllCall("bcrypt\BCryptCreateHash", "Ptr", algorithm, "Ptr*", &hash, "Ptr", 0, "UInt", 0, "Ptr", 0, "UInt", 0, "UInt", 0, "Int")
            if (status != 0)
                throw Error("Could not create a SHA-256 hash for " path ".")
            try {
                if (data.Size > 0) {
                    status := DllCall("bcrypt\BCryptHashData", "Ptr", hash, "Ptr", data.Ptr, "UInt", data.Size, "UInt", 0, "Int")
                    if (status != 0)
                        throw Error("Could not hash " path ".")
                }
                status := DllCall("bcrypt\BCryptFinishHash", "Ptr", hash, "Ptr", digest.Ptr, "UInt", digest.Size, "UInt", 0, "Int")
                if (status != 0)
                    throw Error("Could not finish the SHA-256 hash for " path ".")
            } finally {
                DllCall("bcrypt\BCryptDestroyHash", "Ptr", hash)
            }
        } finally {
            DllCall("bcrypt\BCryptCloseAlgorithmProvider", "Ptr", algorithm, "UInt", 0)
        }
        result := ""
        Loop digest.Size
            result .= Format("{:02X}", NumGet(digest, A_Index - 1, "UChar"))
        return result
    }

    static PublishCallbackOutputs(sourcePath) {
        if (this.shortcutCallbackOutputMode = "single" && this.shortcutCallbackCustomPath != "") {
            destination := this.shortcutCallbackCustomPath
            if this.IsSamePath(sourcePath, destination) {
                this.compiledShortcutAhkPath := this.canonicalCompiledShortcutAhkPath
                return
            }
            for , originalPath in this.shortcutSourceFiles
                if (StrLower(RTrim(destination, "\")) = StrLower(RTrim(originalPath, "\")))
                    throw Error("The callback destination would replace an original source file: " destination)
            SplitPath(destination, , &destinationDir)
            if (destinationDir != "")
                DirCreate(destinationDir)
            FileCopy(sourcePath, destination, true)
            this.compiledShortcutAhkPath := destination
            return
        }
        if (this.shortcutCallbackOutputMode = "single") {
            destination := this.canonicalCompiledShortcutAhkPath
            if !this.IsSamePath(sourcePath, destination)
                FileCopy(sourcePath, destination, true)
            this.compiledShortcutAhkPath := destination
            return
        }
        this.compiledShortcutAhkPath := this.canonicalCompiledShortcutAhkPath
        if (this.shortcutCallbackOutputMode != "per_source")
            return
        generatedDir := this.DirFromPath(sourcePath)
        for index, originalPath in this.shortcutSourceFiles {
            sourceCallbackPath := generatedDir "\user_callbacks_" Format("{:03}", index) ".ahk"
            this.RequireFile(sourceCallbackPath, "source-specific generated callback map")
            SplitPath(originalPath, , &sourceDir, , &sourceStem)
            destination := sourceDir "\" sourceStem "_Compiled_Callbacks.ahk"
            if (StrLower(destination) = StrLower(originalPath))
                throw Error("Generated callback output would replace its source file: " destination)
            FileCopy(sourceCallbackPath, destination, true)
            this.Log("Generated callback copy: " destination)
        }
    }

    static ShortcutIncludeMigrationText() {
        text := "Include migration preview:`n`n"
            . "Original selected files to disable in the main QMK/Macropad include tree when the generated bundle is promoted:`n"
        for , path in this.shortcutSourceFiles
            text .= "  - " path "`n"
        text .= "`nGenerated AHK file(s) to include after that promotion:`n"
        if (this.shortcutCallbackOutputMode = "per_source") {
            for , path in this.shortcutSourceFiles {
                SplitPath(path, , &sourceDir, , &sourceStem)
                text .= "  + " sourceDir "\" sourceStem "_Compiled_Callbacks.ahk`n"
            }
        } else {
            text .= "  + " this.compiledShortcutAhkPath "`n"
        }
        text .= "`n"
            . "IMPORTANT: this proof-of-concept is not promotion-ready yet."
            . " Do not disable the original files based on this preview until"
            . " the dashboard confirms unsupported-row fallback and callback"
            . " activation/parity. The generated Zig module is supplied to the"
            . " candidate DLL build; it is not an AHK include."
        return text
    }

    static GenerateUserShortcutArtifacts() {
        DirCreate(this.compiledShortcutDir)
        buildId := this.ComputeShortcutBuildId(this.shortcutSourceFiles)
        rows := []
        for , row in QMKShortcutCollector.rows {
            ; The capture stub intentionally treats literal string payloads as
            ; opaque values. Reclassify from the original source row so a
            ; literal hotstring replacement is native, while callbacks,
            ; controls, tap descriptors, and direct-send actions retain their
            ; source-level meaning.
            sourceKind := QMKShortcutCollector.ClassifySourceRow(row.family, row.sourceText)
            kind := sourceKind = "unknown" ? row.kind : sourceKind
            rows.Push({family: row.family, index: row.rowIndex, kind: kind, path: row.sourcePath, source: row.sourceText, sourceOrder: rows.Length})
        }

        ; Both output modes preload the selected rows into Zig.  Partial mode
        ; additionally emits source-owned fallback family calls; full-native
        ; mode emits callback descriptors and a compact AHK bridge instead.
        nativeRows := []
        unsupportedNativeRows := []
        nonNativeRows := []
        for , row in rows {
            if (row.kind = "native" || row.kind = "native_control") {
                try {
                    this.ValidateNativeRowLowering(row)
                    row.compiled := true
                    nativeRows.Push(row)
                } catch Error as err {
                    ; Keep an unlowerable native declaration source-owned. It
                    ; must not disappear merely because its context/action
                    ; shape is outside the current typed Zig contract.
                    row.compiled := false
                    row.loweringError := err.Message
                    unsupportedNativeRows.Push(row)
                }
            } else {
                row.compiled := false
                nonNativeRows.Push(row)
            }
        }
        ; Full-native generation lowers callback rows into the same typed Zig
        ; family records as native rows.  Partial mode retains the old grouped
        ; AHK family fallback for rows that are not yet lowered.
        rowsToEmit := this.shortcutCompileMode = "full_native" ? rows : nativeRows
        typed := this.EmitTypedGeneratedArtifacts(rowsToEmit, buildId)
        fallback := this.shortcutCompileMode = "full_native" ? {text: "", dynamicCount: 0, unsupportedCount: 0} : this.BuildDynamicFallback(rows)
        typed.ahk .= fallback.text
        zigChanged := this.WriteGeneratedArtifact(this.compiledShortcutZigPath, typed.zig, true)
        ahkChanged := this.WriteGeneratedArtifact(this.compiledShortcutAhkPath, typed.ahk, false)
        this.Log("Generated: " this.compiledShortcutZigPath)
        this.Log("Generated: " this.compiledShortcutAhkPath)
        this.Log("  artifact writes: Zig=" (zigChanged ? "updated" : "unchanged") ", AHK=" (ahkChanged ? "updated" : "unchanged"))
        this.Log("  build_id=" buildId ", source_native_rows=" nativeRows.Length ", compiled_rows=" rowsToEmit.Length ", fallback_rows=" fallback.dynamicCount ", typed_families=" typed.familyCount)
        if unsupportedNativeRows.Length {
            this.Log("  native rows retained for fallback=" unsupportedNativeRows.Length)
            for , row in unsupportedNativeRows
                this.Log("    fallback native row " row.family "[" row.index "] (" row.path "): " row.loweringError)
        }
    }

    ; Typed lowering is family-specific and fail-closed. Each emitted row must
    ; match an existing QMKCore storage path.
    static EmitTypedGeneratedArtifacts(rows, buildId) {
        unsupportedRows := []
        for , row in rows {
            if !this.IsTypedRowSupported(row)
                unsupportedRows.Push(row)
        }
        if unsupportedRows.Length {
            throw this.TypedLoweringError(unsupportedRows)
        }
        ; Assign stable callback slots before emitting Zig rows. AHK callback
        ; rows use the same reserved compiled-ID domain as the core's IPC
        ; bridge; they do not require startup-time lambda registration.
        callbackSet := this.BuildCallbackDefinitions(rows)
        for , row in rows {
            ; Reapply slots by source order as a defensive measure: AHK object
            ; iteration can expose a value copy for some generated row shapes.
            if callbackSet.rowSlots.Has(row.sourceOrder)
                row.compiledCallbackSlot := callbackSet.rowSlots[row.sourceOrder]
            if (row.kind = "callback" && row.family = "taps" && !row.HasOwnProp("compiledTapCallbackSlot"))
                throw Error("Tap row requires a literal tap callback: " row.path " row " row.index)
            if (row.kind = "callback" && row.family != "tap_holds" && row.family != "taps" && !row.HasOwnProp("compiledCallbackSlot"))
                throw Error("Callback row cannot be emitted safely because it is not a supported literal lambda: " row.path " row " row.index " source=" row.source)
            if (row.family = "tap_holds" && (!row.HasOwnProp("compiledTapCallbackSlot") || !row.HasOwnProp("compiledHoldCallbackSlot")))
                throw Error("Tap-hold row requires literal tap and hold callbacks: " row.path " row " row.index)
            if (row.family = "combos" && row.kind = "callback" && !row.HasOwnProp("compiledCallbackSlot"))
                throw Error("Combo callback row requires a literal callback lambda: " row.path " row " row.index)
            if (row.family = "chords" && row.kind = "callback" && !row.HasOwnProp("compiledCallbackSlot"))
                throw Error("Chord callback row requires a literal callback lambda: " row.path " row " row.index)
        }
        template := FileRead(this.compiledShortcutZigPath, "UTF-8")
        if !InStr(template, "pub const Compiled_Modifiers")
            throw Error("Typed generated module template is missing Compiled_Modifiers.")
        q := Chr(34)
        modifierText := ""
        passthroughText := ""
        hotkeyText := ""
        nativeControlText := Map("panicExit", "", "nativeReload", "", "toggleSuspend", "")
        tapHoldText := ""
        holdText := ""
        doubleTapText := ""
        tapText := ""
        comboText := Map("normal_callback", "", "instant_callback", "", "internal_remap", "", "internal_instant_remap", "")
        chordText := Map("external_callback", "", "internal_remap", "")
        hotstringText := ""
        sourceOrderText := ""
        for , row in rows {
            sourceOrderText .= (sourceOrderText = "" ? "" : ", ") row.sourceOrder
            if (row.family = "modifiers") {
                parts := this.ModifierSourceParts(row.source)
                modifierText .= "        .{ .key = u(" q this.EscapeZigString(parts.key) q ")"
                    . ", .mod_type = " this.ResolveCompileModifierType(parts.modifier)
                    . ", .context = " parts.context ", .suspend_exempt = "
                    . (parts.suspendExempt ? "true" : "false") " },`n"
            } else if (row.family = "passthroughs") {
                parts := this.PassthroughSourceParts(row.source)
                passthroughText .= "        .{ .key = u(" q this.EscapeZigString(parts.key) q ")"
                    . ", .context = " parts.context ", .suspend_exempt = "
                    . (parts.suspendExempt ? "true" : "false") " },`n"
            } else if (row.family = "hotkeys") {
                if (row.kind = "native_control") {
                    parts := this.NativeControlSourceParts(row.source)
                    controlText := "        .{ .trigger = u(" q this.EscapeZigString(parts.key) q ")"
                        . ", .mods_required = " parts.modsRequired ", .mods_forbidden = " parts.modsForbidden
                        . ", .kind = ." parts.controlKind ", .enabled = true },`n"
                    controlName := parts.controlKind = "panic_exit"
                        ? "panicExit"
                        : parts.controlKind = "native_reload"
                            ? "nativeReload"
                            : "toggleSuspend"
                    nativeControlText[controlName] .= controlText
                } else {
                    hotkeyIsCallback := row.kind = "callback" || InStr(row.source, "=>") || RegExMatch(row.source, "i)\bFunc\s*\(")
                    hotkeyIsDescriptor := row.kind = "tap_descriptor"
                    parts := this.HotkeySourceParts(row.source, hotkeyIsCallback, hotkeyIsDescriptor)
                    hotkeyText .= "        .{ .trigger = u(" q this.EscapeZigString(parts.key) q ")"
                        . ", .mods_required = " parts.modsRequired ", .mods_forbidden = " parts.modsForbidden
                        . ", .callback_id = " (hotkeyIsCallback ? row.compiledCallbackSlot : "-1") ", .hold_callback_id = -1, .cleanup_callback_id = -1, .threshold_ticks = 0"
                        . ", .trigger_kind = " parts.triggerKind ", .action_kind = " parts.actionKind ", .suppress_original = "
                        . (parts.suppressOriginal ? "true" : "false")
                        . ", .context = " parts.context
                        . ", .physical_mod_vk = " parts.physicalModVK ", .physical_mods_required = " parts.physicalModsRequired ", .physical_mods_forbidden = " parts.physicalModsForbidden
                        . ", .suspend_exempt = " (parts.suspendExempt ? "true" : "false") ", .callback = 0, .native_payload = "
                        . this.EmitZigU16Literal(parts.payload) " },`n"
                }
            } else if (row.family = "holds") {
                parts := this.ContextActionSourceParts(row.source)
                holdText .= "        .{ .key = u(" q this.EscapeZigString(parts.key) q ")"
                    . ", .callback_id = " row.compiledCallbackSlot
                    . ", .context = " parts.context ", .suspend_exempt = "
                    . (parts.suspendExempt ? "true" : "false") " },`n"
            } else if (row.family = "double_taps") {
                parts := this.ContextActionSourceParts(row.source)
                doubleTapText .= "        .{ .key = u(" q this.EscapeZigString(parts.key) q ")"
                    . ", .callback_id = " row.compiledCallbackSlot
                    . ", .context = " parts.context ", .suspend_exempt = "
                    . (parts.suspendExempt ? "true" : "false") " },`n"
            } else if (row.family = "taps") {
                ; A tap action may contain QMK.SendKeyDirect inside a callback
                ; body. The collector must not mistake that nested native call
                ; for the row's top-level action kind.
                tapIsCallback := row.kind = "callback" || InStr(row.source, "=>") || RegExMatch(row.source, "i)\bFunc\s*\(")
                parts := this.TapSourceParts(row.source, tapIsCallback, row.kind = "tap_descriptor")
                if tapIsCallback
                    parts.callbackId := row.compiledTapCallbackSlot
                holdCallbackId := row.HasOwnProp("compiledTapHoldCallbackSlot") ? row.compiledTapHoldCallbackSlot : -1
                cleanupCallbackId := row.HasOwnProp("compiledTapCleanupCallbackSlot") ? row.compiledTapCleanupCallbackSlot : -1
                tapText .= "        .{ .trigger = u(" q this.EscapeZigString(parts.key) q ")"
                    . ", .mods_required = 0, .mods_forbidden = 0, .callback_id = " parts.callbackId
                    . ", .hold_callback_id = " holdCallbackId ", .cleanup_callback_id = " cleanupCallbackId ", .threshold_ticks = " parts.thresholdMs
                    . ", .trigger_kind = 0, .action_kind = 1, .suppress_original = true, .context = " parts.context
                    . ", .physical_mod_vk = 0, .physical_mods_required = 0, .physical_mods_forbidden = 255, .suspend_exempt = "
                    . (parts.suspendExempt ? "true" : "false") ", .callback = 0, .native_payload = "
                    . this.EmitZigU16Literal(parts.payload) " },`n"
            } else if (row.family = "tap_holds") {
                parts := this.TapHoldSourceParts(row.source)
                tapHoldText .= "        .{ .key = u(" q this.EscapeZigString(parts.key) q ")"
                    . ", .tap_callback_id = " row.compiledTapCallbackSlot
                    . ", .hold_callback_id = " row.compiledHoldCallbackSlot
                    . ", .cleanup_callback_id = " (row.HasOwnProp("compiledCleanupCallbackSlot") ? row.compiledCleanupCallbackSlot : "-1")
                    . ", .threshold_ticks = " parts.thresholdMs
                    . ", .context = .{ .kind = .global, .negated = false, .text = &.{}, .specificity_mask = 0 }"
                    . ", .suspend_exempt = " (parts.suspendExempt ? "true" : "false") " },`n"
            } else if (row.family = "combos") {
                parts := this.ComboSourceParts(row.source, row.kind = "callback", row.HasOwnProp("compiledCallbackSlot") ? row.compiledCallbackSlot : -1)
                comboText[parts.mode] .= "        .{ .primary = u(" q this.EscapeZigString(parts.primary) q "), .secondary = u(" q this.EscapeZigString(parts.secondary) q ")"
                . ", .callback_id = " parts.callbackId ", .target = u(" q this.EscapeZigString(parts.HasOwnProp("targetName") ? parts.targetName : "") q ")"
                    . ", .mod_mask = " parts.modMask ", .mode = ." parts.mode
                    . ", .context = " parts.context
                    . ", .suspend_exempt = " (parts.suspendExempt ? "true" : "false")
                    . ", .registration_order = " row.sourceOrder " },`n"
            } else if (row.family = "chords") {
                parts := this.ChordSourceParts(row.source, row.kind = "callback", row.HasOwnProp("compiledCallbackSlot") ? row.compiledCallbackSlot : -1)
                keyCount := parts.keys.Length
                vkText := ""
                for index, key in parts.keys
                    vkText .= (index = 1 ? "" : ", ") "u(" q this.EscapeZigString(key) q ")"
                while (keyCount < 5) {
                    vkText .= ", u(" q q ")"
                    keyCount += 1
                }
                chordText[parts.mode] .= "        .{ .keys = .{" vkText "}, .key_count = " parts.keyCount
                    . ", .callback_id = " parts.callbackId ", .target = u(" q this.EscapeZigString(parts.HasOwnProp("targetName") ? parts.targetName : "") q ")"
                    . ", .mod_mask = " parts.modMask ", .context = " parts.context
                    . ", .suspend_exempt = " (parts.suspendExempt ? "true" : "false") " },`n"
            }
            if (row.family = "hotstrings") {
                parts := this.HotstringSourceParts(row.source, row.kind = "callback")
                hotstringText .= "        .{ .trigger = " this.EmitZigU8Literal(parts.trigger)
                    . ", .replacement = " this.EmitZigU16Literal(parts.replacement)
                    . ", .callback_id = " (row.kind = "callback" ? row.compiledCallbackSlot : "-1")
                    . ", .action = ." parts.action ", .options = .{" parts.options " }, .context = " parts.context
                    . ", .source_order = " row.sourceOrder " },`n"
            }
        }
        if rows.Length {
            if (modifierText != "")
                modifierText := SubStr(modifierText, 1, StrLen(modifierText) - 2) "`n"
            if (passthroughText != "")
                passthroughText := SubStr(passthroughText, 1, StrLen(passthroughText) - 2) "`n"
            if (hotkeyText != "")
                hotkeyText := SubStr(hotkeyText, 1, StrLen(hotkeyText) - 2) "`n"
            if (holdText != "")
                holdText := SubStr(holdText, 1, StrLen(holdText) - 2) "`n"
            if (doubleTapText != "")
                doubleTapText := SubStr(doubleTapText, 1, StrLen(doubleTapText) - 2) "`n"
            if (tapText != "")
                tapText := SubStr(tapText, 1, StrLen(tapText) - 2) "`n"
            if (tapHoldText != "")
                tapHoldText := SubStr(tapHoldText, 1, StrLen(tapHoldText) - 2) "`n"
            if (hotstringText != "")
                hotstringText := SubStr(hotstringText, 1, StrLen(hotstringText) - 2) "`n"
        }
        template := RegExReplace(template, "m)^pub const compiled_build_id = " q ".*?" q ";$", "pub const compiled_build_id = " q this.EscapeZigString(buildId) q ";")
        template := RegExReplace(template, "m)^pub const compiled_source_count: usize = \d+;$", "pub const compiled_source_count: usize = " this.shortcutSourceFiles.Length ";")
        ; compiled_row_count describes the rows actually emitted into Zig, not
        ; callback/fallback rows that remain source-owned in the selected files.
        template := RegExReplace(template, "m)^pub const compiled_row_count: usize = \d+;$", "pub const compiled_row_count: usize = " rows.Length ";")
        template := RegExReplace(template, "(?s)(pub const Compiled_Modifiers = struct \{.*?pub const rows = )\[_\]Row\{.*?\n    \};", "$1[_]Row{`n" modifierText "    };")
        template := RegExReplace(template, "(?s)(pub const Compiled_Passthroughs = struct \{.*?pub const rows = )\[_\]Row\{.*?\n    \};", "$1[_]Row{`n" passthroughText "    };")
        template := RegExReplace(template, "(?s)(pub const Compiled_Hotkeys = struct \{.*?pub const rows = )\[_\]Row\{.*?\n    \};", "$1[_]Row{`n" hotkeyText "    };")
        template := RegExReplace(template, "(?s)(pub const Compiled_Holds = struct \{.*?pub const rows = )\[_\]Row\{.*?\n    \};", "$1[_]Row{`n" holdText "    };")
        template := RegExReplace(template, "(?s)(pub const Compiled_Double_Taps = struct \{.*?pub const rows = )\[_\]Row\{.*?\n    \};", "$1[_]Row{`n" doubleTapText "    };")
        template := RegExReplace(template, "(?s)(pub const Compiled_Taps = struct \{.*?pub const rows = )\[_\]Row\{.*?\n    \};", "$1[_]Row{`n" tapText "    };")
        for controlName, controlText in nativeControlText {
            if (controlText != "")
                controlText := SubStr(controlText, 1, StrLen(controlText) - 2) "`n"
            declaration := controlName = "panicExit" ? "panic_exit" : "native_reload"
                template := RegExReplace(template, "(?s)(pub const Compiled_Native_Controls = struct \{.*?pub const " declaration " = )\[_\]Compiled_Native_Control_Row\{.*?\n    \};", "$1[_]Compiled_Native_Control_Row{`n" controlText "    };")
        }
        for comboName, comboRows in comboText {
            if (comboRows != "")
                comboRows := SubStr(comboRows, 1, StrLen(comboRows) - 2) "`n"
            template := RegExReplace(template, "(?s)(pub const Compiled_Combos = struct \{.*?pub const " comboName " = )\[_\]Row\{.*?\n    \};", "$1[_]Row{`n" comboRows "    };")
        }
        for chordName, chordRows in chordText {
            if (chordRows != "")
                chordRows := SubStr(chordRows, 1, StrLen(chordRows) - 2) "`n"
            template := RegExReplace(template, "(?s)(pub const Compiled_Chords = struct \{.*?pub const " chordName " = )\[_\]Row\{.*?\n    \};", "$1[_]Row{`n" chordRows "    };")
        }
        template := RegExReplace(template, "(?s)(pub const Compiled_Tap_Holds = struct \{.*?pub const rows = )\[_\]Row\{.*?\n    \};", "$1[_]Row{`n" tapHoldText "    };")
        template := RegExReplace(template, "(?s)(pub const Compiled_Hotstrings = struct \{.*?pub const rows = )\[_\]Row\{.*?\n    \};", "$1[_]Row{`n" hotstringText "    };")
        if (sourceOrderText = "")
            sourceOrderText := ""
        template := RegExReplace(template, "(?m)^pub const Compiled_Source_Order = \[_\]u32\{.*?\};$", "pub const Compiled_Source_Order = [_]u32{" sourceOrderText "};")
        callbackDescriptorText := ""
        for , descriptor in callbackSet.descriptors
            callbackDescriptorText .= descriptor "`n"
        template := RegExReplace(template, "(?s)(pub const Compiled_Callbacks = struct \{.*?pub const ahk = )\[_\]CallbackDescriptor\{.*?\};", "$1[_]CallbackDescriptor{`n" callbackDescriptorText "    };")
        ahk := "#Requires AutoHotkey v2.0`n"
            . "; Generated callback bridge for compiled user shortcuts.`n"
            . "; build_id: " buildId "`n"
            . callbackSet.text
            . "`nQMKCompiledCallbackMap := Map(`n"
        for index, unused in callbackSet.wrapperLines
            ahk .= "    (QMK.COMPILED_CALLBACK_ID_BASE - " (index - 1) "), QMKCB_" Format("{:04}", index) (index < callbackSet.wrapperLines.Length ? "," : "") "`n"
        ahk .= ")`nQMK.InstallCompiledCallbackMap(QMKCompiledCallbackMap)`n"
        familyCount := 0
        for , family in ["modifiers", "passthroughs", "hotkeys", "holds", "double_taps", "taps", "tap_holds", "combos", "chords", "hotstrings"] {
            for , row in rows {
                if (row.family = family) {
                    familyCount += 1
                    break
                }
            }
        }
        return {zig: template, ahk: ahk, familyCount: familyCount}
    }

    static IsTypedRowSupported(row) {
        if (row.family = "modifiers" || row.family = "passthroughs" || row.family = "hotkeys" || row.family = "hotstrings" || row.family = "tap_holds" || row.family = "combos" || row.family = "chords")
            return row.kind = "native" || (row.family = "hotkeys" && (row.kind = "callback" || row.kind = "native_control" || row.kind = "tap_descriptor")) || (row.family = "hotstrings" && row.kind = "callback") || (row.family = "tap_holds" && row.kind = "callback") || (row.family = "combos" && (row.kind = "callback" || row.kind = "native")) || (row.family = "chords" && (row.kind = "callback" || row.kind = "native"))
        if (row.family = "holds" || row.family = "double_taps")
            return row.kind = "callback"
        if (row.family = "taps")
            return row.kind = "native" || row.kind = "tap_descriptor" || row.kind = "callback"
        return false
    }

    ; Validate one native declaration against the exact parser used by its
    ; typed emitter. This lets partial compilation keep unsupported rows in
    ; the source-owned fallback while still emitting every independently valid
    ; native row into Zig.
    static ValidateNativeRowLowering(row) {
        switch row.family {
            case "modifiers":
                parts := this.ModifierSourceParts(row.source)
            case "passthroughs":
                parts := this.PassthroughSourceParts(row.source)
            case "hotkeys":
                if (row.kind = "native_control")
                    parts := this.NativeControlSourceParts(row.source)
                else
                    parts := this.HotkeySourceParts(row.source, false)
            case "taps":
                parts := this.TapSourceParts(row.source, false)
            case "combos":
                parts := this.ComboSourceParts(row.source, false, -1)
            case "chords":
                parts := this.ChordSourceParts(row.source, false, -1)
            case "hotstrings":
                parts := this.HotstringSourceParts(row.source, false)
            default:
                throw Error("Native family has no typed Zig lowerer yet: " row.family)
        }
        return true
    }

    static TypedLoweringError(rows) {
        detail := ""
        limit := Min(rows.Length, 12)
        Loop limit {
            row := rows[A_Index]
            detail .= "`n  - " row.family " row " row.index " kind=" row.kind " (" row.path ") source=" row.source
        }
        if (rows.Length > limit)
            detail .= "`n  - ... " (rows.Length - limit) " additional rows"
        return Error("Typed lowering is not available for the selected row set. No generated artifact was written. Rows awaiting a verified family lowerer:" detail)
    }

    static ModifierSourceParts(source) {
        elems := this.SourceRowElements(source)
        if (elems.Length < 2 || elems.Length > 4)
            throw Error("Modifier row has an unsupported shape: " source)
        key := this.ElementString(elems[1], "", &keyOk)
        modifier := this.ElementString(elems[2], "", &modifierOk)
        if (!keyOk || !modifierOk || key = "" || modifier = "")
            throw Error("Modifier row requires literal key and modifier: " source)
        context := elems.Length >= 3 ? this.CompileContextLiteral(elems[3], source) : this.CompileContextLiteral(Chr(34) "global" Chr(34), source)
        return {key: key, modifier: modifier, context: context, suspendExempt: elems.Length >= 4 && (StrLower(Trim(elems[4])) = "true" || Trim(elems[4]) = "1")}
    }

    static PassthroughSourceParts(source) {
        elems := this.SourceRowElements(source)
        if (elems.Length < 1 || elems.Length > 3)
            throw Error("Passthrough row has an unsupported shape: " source)
        key := this.ElementString(elems[1], "", &keyOk)
        if (!keyOk || key = "")
            throw Error("Passthrough row requires a literal key: " source)
        context := elems.Length >= 2 ? this.CompileContextLiteral(elems[2], source) : this.CompileContextLiteral(Chr(34) "global" Chr(34), source)
        return {key: key, context: context, suspendExempt: elems.Length >= 3 && (StrLower(Trim(elems[3])) = "true" || Trim(elems[3]) = "1")}
    }

    static ContextActionSourceParts(source) {
        elems := this.SourceRowElements(source)
        if (elems.Length < 3 || elems.Length > 4)
            throw Error("Context-action row has an unsupported shape: " source)
        key := this.ElementString(elems[1], "", &keyOk)
        callback := Trim(elems[3])
        if (!keyOk || key = "" || callback = "")
            throw Error("Context-action row requires literal key, context, and callback: " source)
        context := this.CompileContextLiteral(elems[2], source)
        return {key: key, context: context, suspendExempt: elems.Length >= 4 && (StrLower(Trim(elems[4])) = "true" || Trim(elems[4]) = "1")}
    }

    static TapSourceParts(source, isCallback := false, isDescriptor := false) {
        elems := this.SourceRowElements(source)
        if (elems.Length < 3 || elems.Length > 7)
            throw Error("Tap row has an unsupported shape: " source)
        key := this.ElementString(elems[1], "", &keyOk)
        if (!keyOk || key = "")
            throw Error("Tap row requires a literal key: " source)
        context := this.CompileContextLiteral(elems[2], source)
        payload := ""
        callbackId := -1
        if isCallback
            callbackId := 0
        else if isDescriptor
            payload := this.ParseTapDescriptor(elems[3], &actionOk)
        else
            payload := this.ParseDirectAction(elems[3], &actionOk)
        if (!isCallback && !actionOk)
            throw Error("Tap row requires QMK.SendKeyDirect(...) or a callback: " source)
        threshold := 0
        if (elems.Length >= 5) {
            thresholdText := Trim(elems[5])
            if !RegExMatch(thresholdText, "^-?\d+$")
                throw Error("Tap row threshold must be a literal integer: " source)
            threshold := Integer(thresholdText)
        }
        suspendIndex := elems.Length >= 7 ? 7 : elems.Length = 4 ? 4 : 0
        return {key: key, context: context, payload: payload, callbackId: callbackId,
            thresholdMs: threshold, suspendExempt: suspendIndex && (StrLower(Trim(elems[suspendIndex])) = "true" || Trim(elems[suspendIndex]) = "1")}
    }

    static HotkeySourceParts(source, isCallback := false, isDescriptor := false) {
        elems := this.SourceRowElements(source)
        if (elems.Length < 3 || elems.Length > 4)
            throw Error("Hotkey typed lowering requires [spec, context, action, suspendExempt]: " source)
        spec := this.ElementString(elems[1], "", &specOk)
        if (!specOk || spec = "")
            throw Error("Hotkey typed lowering requires a literal spec: " source)
        context := this.CompileContextLiteral(elems[2], source)
        payload := ""
        if isCallback
            actionOk := true
        else if isDescriptor
            payload := this.ParseTapDescriptor(elems[3], &actionOk)
        else
            payload := this.ParseDirectAction(elems[3], &actionOk)
        if !actionOk
            throw Error("Hotkey typed lowering requires QMK.SendKeyDirect(...) action: " source)
        text := Trim(spec)
        if (SubStr(text, 1, 1) = "{" && SubStr(text, -1) = "}")
            text := Trim(SubStr(text, 2, StrLen(text) - 2))
        suppressOriginal := true
        allowExtra := false
        forceHook := false
        physicalModVK := 0
        physicalModsRequired := 0
        neutralPhysicalMods := 0

        ; Match the AHK source's TextInterpret/TextToModifiers boundary:
        ; composite hotkeys are exactly two terms separated by " & ".  A
        ; literal ampersand without the delimiter belongs to the key name and
        ; must not be silently reinterpreted as a combo here.
        compositePos := InStr(text, " & ")
        prefixText := compositePos ? Trim(SubStr(text, 1, compositePos - 1)) : ""
        if (compositePos) {
            suffixText := Trim(SubStr(text, compositePos + 3))
            if (prefixText = "" || suffixText = "")
                throw Error("Hotkey composite expression is incomplete: " source)
            text := this.ParseHotkeyPrefix(prefixText, &suppressOriginal, &allowExtra, &forceHook,
                &physicalModVK, &physicalModsRequired, &neutralPhysicalMods, true, source)
            if (text = "")
                throw Error("Hotkey composite prefix has no key: " source)
            prefixVK := this.ResolveCompileVK(text)
            if (physicalModVK = 0)
                physicalModVK := prefixVK
            physicalModsRequired |= this.CompilePhysicalModifierLRBits(prefixVK)
            neutralPhysicalMods |= this.CollapsedCompileModifierBit(prefixVK)
            ; AHK permits a tilde on the suffix, but does not parse the other
            ; modifier symbols there as ordinary modifiers.  Rejecting them is
            ; safer than lowering a different hotkey than AHK would register.
            if (SubStr(suffixText, 1, 1) = "~") {
                suppressOriginal := false
                suffixText := Trim(SubStr(suffixText, 2))
            }
            if (suffixText = "" || RegExMatch(suffixText, "^[~*$<>!^+#]"))
                throw Error("Hotkey composite suffix has unsupported modifiers: " source)
            text := suffixText
        } else {
            text := this.ParseHotkeyPrefix(text, &suppressOriginal, &allowExtra, &forceHook,
                &physicalModVK, &physicalModsRequired, &neutralPhysicalMods, false, source)
        }
        triggerKind := 0
        if RegExMatch(text, "i)\s+up$") {
            triggerKind := 1
            text := Trim(SubStr(text, 1, StrLen(text) - 3))
        }
        modsRequired := 0
        pos := 1
        while (pos <= StrLen(text)) {
            ch := SubStr(text, pos, 1)
            switch ch {
                case "^": modsRequired |= 0x01
                case "!": modsRequired |= 0x02
                case "+": modsRequired |= 0x04
                case "#": modsRequired |= 0x08
                default: break
            }
            if (ch != "^" && ch != "!" && ch != "+" && ch != "#")
                break
            pos += 1
        }
        key := Trim(SubStr(text, pos))
        if (key = "" || InStr(StrLower(key), "wheel") || InStr(StrLower(key), "button"))
            throw Error("Hotkey typed lowering cannot represent this trigger: " source)
        vk := this.ResolveCompileVK(key)
        modsRequired |= neutralPhysicalMods
        modsForbidden := allowExtra ? 0 : (0x0F & ~(modsRequired | this.CollapsedCompileModifierBit(vk)))
        physicalModsForbidden := allowExtra ? 0 : (0xFF & ~(physicalModsRequired | this.CompilePhysicalModifierLRBits(vk)))
        return {key: key, modsRequired: modsRequired, modsForbidden: modsForbidden, triggerKind: triggerKind,
            actionKind: isDescriptor ? 1 : 0,
            suppressOriginal: suppressOriginal, forceHook: forceHook, suspendExempt: (elems.Length >= 4 && (StrLower(Trim(elems[4])) = "true" || Trim(elems[4]) = "1")) || InStr(elems[3], "QMK.SuspendExempt"), payload: payload,
            physicalModVK: physicalModVK, physicalModsRequired: physicalModsRequired, physicalModsForbidden: physicalModsForbidden, context: context}
    }

    ; Port of the prefix portion of AutoHotkey's TextToModifiers.  The
    ; left/right selectors are stateful: >!a means right Alt, while !a means
    ; neutral Alt.  The caller supplies output fields because AHK v2 has no
    ; tuple return type.
    static ParseHotkeyPrefix(text, &suppressOriginal, &allowExtra, &forceHook,
        &physicalModVK, &physicalModsRequired, &neutralPhysicalMods, isCompositePrefix := false, source := "") {
        text := Trim(text)
        left := false
        right := false
        while (text != "") {
            prefix := SubStr(text, 1, 1)
            if (prefix = "~") {
                suppressOriginal := false
            } else if (prefix = "*") {
                allowExtra := true
            } else if (prefix = "$") {
                forceHook := true
            } else if (prefix = "<") {
                left := true
                right := false
            } else if (prefix = ">") {
                right := true
                left := false
            } else if (prefix = "!" || prefix = "^" || prefix = "+" || prefix = "#") {
                if (left || right)
                    break
                ; Neutral modifier prefixes belong to the suffix key and are
                ; handled below by the existing modsRequired scan.
                break
            } else {
                break
            }
            text := Trim(SubStr(text, 2))
        }
        if (left || right) {
            ; AHK only treats < or > as a selector when followed by a
            ; modifier.  If it remains before the key, it is the key name.
            if (text = "")
                throw Error("Hotkey side selector has no modifier: " source)
            modifier := SubStr(text, 1, 1)
            if (modifier != "!" && modifier != "^" && modifier != "+" && modifier != "#")
                throw Error("Hotkey side selector must precede !, ^, +, or #: " source)
            if (left)
                modifierVK := modifier = "!" ? 0xA4 : modifier = "^" ? 0xA2 : modifier = "+" ? 0xA0 : 0x5B
            else
                modifierVK := modifier = "!" ? 0xA5 : modifier = "^" ? 0xA3 : modifier = "+" ? 0xA1 : 0x5C
            if (physicalModVK = 0)
                physicalModVK := modifierVK
            physicalModsRequired |= this.CompilePhysicalModifierLRBits(modifierVK)
            neutralPhysicalMods |= this.CollapsedCompileModifierBit(modifierVK)
            left := false
            right := false
            text := Trim(SubStr(text, 2))
        }
        return text
    }

    static VerifyHotkeyParserMatrix() {
        reportPath := A_Temp "\\qmk_hotkey_parser_matrix.log"
        try FileDelete(reportPath)
        cases := [
            {spec: "*^a", accepted: true, key: "a", allowExtra: true, mods: 1},
            {spec: "~a", accepted: true, key: "a", suppress: false},
            {spec: "$a", accepted: true, key: "a", forceHook: true},
            {spec: "<^a", accepted: true, key: "a", physical: 0xA2, physicalBits: 0x01, neutral: 1},
            {spec: ">!a", accepted: true, key: "a", physical: 0xA5, physicalBits: 0x20, neutral: 2},
            {spec: "a & b", accepted: true, key: "b", physical: 65},
            {spec: "~a & ~b", accepted: true, key: "b", physical: 65, suppress: false},
            {spec: "^a up", accepted: true, key: "a", triggerKind: 1, mods: 1},
            {spec: "a &", accepted: false},
            {spec: "a & ^b", accepted: false},
            {spec: "j&k", accepted: false}
        ]
        failures := []
        for , test in cases {
            source := "[" Chr(34) test.spec Chr(34) ", " Chr(34) "global" Chr(34) ", QMK.SendKeyDirect(" Chr(34) "x" Chr(34) ")]"
            try {
                parts := this.HotkeySourceParts(source, false)
                if !test.accepted {
                    failures.Push(test.spec " unexpectedly accepted")
                    continue
                }
                if (test.HasOwnProp("key") && parts.key != test.key)
                    failures.Push(test.spec " key=" parts.key)
                if (test.HasOwnProp("allowExtra") && parts.modsForbidden != 0)
                    failures.Push(test.spec " wildcard flag was not preserved")
                if (test.HasOwnProp("suppress") && parts.suppressOriginal != test.suppress)
                    failures.Push(test.spec " suppressOriginal mismatch")
                if (test.HasOwnProp("physical") && parts.physicalModVK != test.physical)
                    failures.Push(test.spec " physical VK=" parts.physicalModVK)
                if (test.HasOwnProp("physicalBits") && parts.physicalModsRequired != test.physicalBits)
                    failures.Push(test.spec " physical bits=" parts.physicalModsRequired)
                if (test.HasOwnProp("neutral") && parts.modsRequired != test.neutral)
                    failures.Push(test.spec " neutral mods=" parts.modsRequired)
                if (test.HasOwnProp("mods") && parts.modsRequired != test.mods)
                    failures.Push(test.spec " mods=" parts.modsRequired)
                if (test.HasOwnProp("triggerKind") && parts.triggerKind != test.triggerKind)
                    failures.Push(test.spec " trigger kind=" parts.triggerKind)
            } catch Error as err {
                if test.accepted
                    failures.Push(test.spec " rejected: " err.Message)
            }
        }
        if failures.Length {
            for , failure in failures
                try FileAppend("FAIL: " failure "`n", reportPath, "UTF-8")
            return 1
        }
        try FileAppend("PASS: AHK hotkey parser matrix (prefixes, side modifiers, composites, Up, rejection cases).`n", reportPath, "UTF-8")
        return 0
    }

    static NativeControlSourceParts(source) {
        elems := this.SourceRowElements(source)
        if (elems.Length < 3 || elems.Length > 4)
            throw Error("Native-control hotkey requires [spec, context, control, suspendExempt?]: " source)
        parts := this.HotkeySourceParts(source, true)
        control := this.ElementString(elems[3], "", &controlOk)
        if (!controlOk)
            throw Error("Native-control hotkey requires a literal control name: " source)
        normalized := StrLower(StrReplace(StrReplace(control, "_", ""), "-", ""))
        if (normalized = "panicexit" || normalized = "qmkpanicexit" || normalized = "nativepanicexit")
            parts.controlKind := "panic_exit"
        else if (normalized = "nativereload" || normalized = "qmknativereload")
            parts.controlKind := "native_reload"
        else if (normalized = "nativesuspend" || normalized = "qmknativesuspend")
            parts.controlKind := "toggle_suspend"
        else
            throw Error("Unknown native-control hotkey: " control)
        return parts
    }

    static ChordSourceParts(source, isCallback := false, callbackSlot := -1) {
        elems := this.SourceRowElements(source)
        if (elems.Length < 3 || elems.Length > 8)
            throw Error("Chord typed lowering has an unsupported shape: " source)

        ; The current QMK chord grammar is either [keys..., callback] or
        ; [keys..., context, action, mode?, mod?, suspendExempt?]. Empty key
        ; placeholders are accepted because the production files use them for
        ; three- and four-key chords. The action is never a setup call here.
        actionIndex := elems.Length
        suspendExempt := false
        if (actionIndex >= 4 && this.RawLiteralBool(elems[actionIndex])) {
            suspendExempt := this.ParseLiteralBool(elems[actionIndex])
            actionIndex -= 1
        }
        modText := ""
        if (actionIndex >= 4 && this.IsLiteralModifierMask(elems[actionIndex])) {
            modText := this.ElementString(elems[actionIndex], "", &modOk)
            actionIndex -= 1
        }
        modeText := ""
        if (actionIndex >= 4 && this.IsLiteralChordMode(elems[actionIndex])) {
            modeText := this.ElementString(elems[actionIndex], "", &modeOk)
            actionIndex -= 1
        }
        action := Trim(elems[actionIndex])
        if (action = "")
            throw Error("Chord typed lowering requires an action: " source)

        contextIndex := 0
        if (actionIndex >= 4 && this.IsChordContextOrNonKey(elems[actionIndex - 1]))
            contextIndex := actionIndex - 1
        context := contextIndex ? this.CompileContextLiteral(elems[contextIndex], source)
            : this.CompileContextLiteral(Chr(34) "global" Chr(34), source)
        keyEnd := contextIndex ? contextIndex - 1 : actionIndex - 1
        keys := []
        Loop keyEnd {
            key := this.ElementString(elems[A_Index], "", &keyOk)
            if (!keyOk)
                throw Error("Chord typed lowering requires literal keys: " source)
            if (key != "")
                keys.Push(key)
        }
        if (keys.Length < 2 || keys.Length > 5)
            throw Error("Chord typed lowering requires 2-5 literal keys: " source)

        if (isCallback) {
            if (callbackSlot < 0)
                throw Error("Chord callback slot was not assigned: " source)
            return {keys: keys, keyCount: keys.Length, callbackId: callbackSlot, targetVK: 0,
                modMask: this.ParseCompileModifierMask(modText), mode: "external_callback",
                context: context, suspendExempt: suspendExempt}
        }
        payload := this.ParseDirectAction(action, &actionOk)
        if (!actionOk)
            throw Error("Chord typed lowering requires a callback or QMK.SendKeyDirect(...) action: " source)
        target := this.ParseCompileSendTarget(payload, modText)
        return {keys: keys, keyCount: keys.Length, callbackId: -1, targetVK: target.targetVK, targetName: target.targetName, targetVKText: target.targetVKText,
            modMask: target.modMask, mode: "internal_remap", context: context,
            suspendExempt: suspendExempt}
    }

    static IsChordContextOrNonKey(expression) {
        text := Trim(expression)
        if (SubStr(text, 1, 1) = "[")
            return true
        value := this.ElementString(text, "", &ok)
        if (!ok)
            return false
        try {
            this.ResolveCompileVK(value)
            return false
        } catch {
            return true
        }
    }

    static IsLiteralChordMode(expression) {
        value := this.ElementString(expression, "", &ok)
        if (!ok)
            return false
        normalized := StrLower(Trim(value))
        return normalized = "callback" || normalized = "internal" || normalized = "sendkeydirect"
            || normalized = "sendkeydirectinstant" || normalized = "instant"
            || normalized = "internalinstant" || normalized = "instantinternal"
    }

    static IsLiteralModifierMask(expression) {
        value := this.ElementString(expression, "", &ok)
        if (!ok || value = "")
            return false
        return RegExMatch(value, "^[\^!+#]*$")
    }

    static RawLiteralBool(expression) {
        text := StrLower(Trim(expression))
        return text = "true" || text = "false" || text = "1" || text = "0"
    }

    static ParseLiteralBool(expression) {
        text := StrLower(Trim(expression))
        return text = "true" || text = "1"
    }

    static ComboSourceParts(source, isCallback := false, callbackSlot := -1) {
        elems := this.SourceRowElements(source)
        if (elems.Length < 3 || elems.Length > 7)
            throw Error("Combo typed lowering has an unsupported shape: " source)
        primary := this.ElementString(elems[1], "", &primaryOk)
        secondary := this.ElementString(elems[2], "", &secondaryOk)
        if (!primaryOk || !secondaryOk || primary = "" || secondary = "")
            throw Error("Combo typed lowering requires literal primary and secondary keys: " source)
        if (elems.Length = 3) {
            contextIndex := 0
            actionIndex := 3
            modeText := ""
            modText := ""
            suspendExempt := false
        } else {
            contextIndex := 3
            actionIndex := 4
            modeText := elems.Length >= 5 ? this.ElementString(elems[5], "", &modeOk) : ""
            if (elems.Length >= 5 && !modeOk)
                throw Error("Combo typed lowering requires a literal mode: " source)
            modText := elems.Length >= 6 ? this.ElementString(elems[6], "", &modOk) : ""
            if (elems.Length >= 6 && !modOk)
                throw Error("Combo typed lowering requires a literal modifier mask: " source)
            suspendExempt := elems.Length >= 7 && (StrLower(Trim(elems[7])) = "true" || Trim(elems[7]) = "1")
        }
        context := this.CompileContextLiteral(contextIndex ? elems[contextIndex] : Chr(34) "global" Chr(34), source)
        if (isCallback) {
            if (callbackSlot < 0)
                throw Error("Combo callback slot was not assigned: " source)
            normalizedMode := StrLower(Trim(modeText))
            mode := (normalizedMode = "instant" || normalizedMode = "instant_callback" || normalizedMode = "callbackinstant")
                ? "instant_callback" : "normal_callback"
            return {primary: primary, secondary: secondary, callbackId: callbackSlot, targetVK: 0, modMask: this.ParseCompileModifierMask(modText), mode: mode, suspendExempt: suspendExempt, context: context}
        }
        payload := this.ParseDirectAction(elems[actionIndex], &actionOk)
        if (!actionOk)
            throw Error("Combo typed lowering requires QMK.SendKeyDirect(...) action: " source)
        target := this.ParseCompileSendTarget(payload, modText)
        normalizedMode := StrLower(Trim(modeText))
        mode := (normalizedMode = "instant" || normalizedMode = "sendkeydirectinstant"
            || normalizedMode = "internalinstant" || normalizedMode = "instantinternal")
            ? "internal_instant_remap" : "internal_remap"
            return {primary: primary, secondary: secondary, callbackId: -1, targetVK: target.targetVK, targetName: target.targetName, targetVKText: target.targetVKText, modMask: target.modMask, mode: mode, suspendExempt: suspendExempt, context: context}
    }

    static CompileContextLiteral(expression, source) {
        contextText := this.ContextExpression(expression, "", &contextOk)
        if (!contextOk || InStr(contextText, Chr(0x1F)))
            throw Error("Combo typed lowering requires one literal, non-compound context: " source)
        raw := Trim(contextText)
        negated := false
        if (SubStr(raw, 1, 1) = "!") {
            negated := true
            raw := Trim(SubStr(raw, 2))
        }
        normalized := StrLower(raw)
        kind := "title"
        if (raw = "" || normalized = "global") {
            kind := "global"
            raw := ""
        } else if (normalized = "#32768" || normalized = "ahk_class #32768") {
            kind := "menu"
        } else if InStr(normalized, "ahk_class") {
            kind := "class"
        } else if (normalized = "browser" || normalized = "browsers") {
            kind := "browser"
        } else if InStr(normalized, "ahk_exe") {
            kind := "exe"
        } else if InStr(raw, ".") {
            kind := "website"
        }
        return ".{ .kind = ." kind ", .negated = " (negated ? "true" : "false")
            . ", .text = " this.EmitZigU16Literal(raw) ", .specificity_mask = 0 }"
    }

    static ParseCompileModifierMask(text) {
        mask := 0
        for , ch in StrSplit(String(text)) {
            switch ch {
                case "^": mask |= 1
                case "!": mask |= 2
                case "+": mask |= 4
                case "#": mask |= 8
            }
        }
        return mask
    }

    static ParseCompileSendTarget(payload, modText := "") {
        text := Trim(payload)
        mods := this.ParseCompileModifierMask(modText)
        pos := 1
        while (pos <= StrLen(text)) {
            ch := SubStr(text, pos, 1)
            switch ch {
                case "^": mods |= 1
                case "!": mods |= 2
                case "+": mods |= 4
                case "#": mods |= 8
                default: break
            }
            if (ch != "^" && ch != "!" && ch != "+" && ch != "#")
                break
            pos += 1
        }
        key := Trim(SubStr(text, pos))
        if (SubStr(key, 1, 1) = "{" && SubStr(key, -1) = "}")
            key := Trim(SubStr(key, 2, StrLen(key) - 2))
        if (key = "" || InStr(key, "{") || InStr(key, "}"))
            throw Error("Combo native payload is not a single key: " payload)
        return {targetVK: this.ResolveCompileVK(key), targetName: key, targetVKText: this.EmitCompileVK(key), modMask: mods}
    }

    static HotstringSourceParts(source, isCallback := false) {
        elems := this.SourceRowElements(source)
        if (elems.Length < 2 || elems.Length > 5)
            throw Error("Hotstring typed lowering has an unsupported shape: " source)
        triggerSpec := this.ElementString(elems[1], "", &triggerOk)
        if (!triggerOk || triggerSpec = "")
            throw Error("Hotstring typed lowering requires a literal trigger: " source)
        context := this.CompileContextLiteral(elems[2], source)
        trigger := triggerSpec
        optionText := ""
        if (SubStr(trigger, 1, 1) = ":") {
            close := InStr(trigger, ":", false, 2)
            if (!close)
                throw Error("Hotstring trigger options are unbalanced: " source)
            optionText := SubStr(trigger, 2, close - 2)
            trigger := SubStr(trigger, close + 1)
        }
        if (trigger = "")
            throw Error("Hotstring trigger cannot be empty: " source)
        options := this.HotstringOptionFields(optionText)
        replacement := ""
        if (!isCallback) {
            replacement := this.ElementString(elems[3], "", &replacementOk)
            if (!replacementOk)
                throw Error("Hotstring native lowering requires a literal replacement: " source)
        }
        suspendExempt := elems.Length >= 4 && (StrLower(Trim(elems[4])) = "true" || Trim(elems[4]) = "1")
        if (suspendExempt)
            options .= (options = "" ? "" : ",") " .suspend_exempt = true"
        return {trigger: trigger, replacement: replacement, action: isCallback ? "ahk_callback" : "paste_withbackup", options: options, context: context}
    }

    static TapHoldSourceParts(source) {
        elems := this.SourceRowElements(source)
        if (elems.Length < 5 || elems.Length > 7)
            throw Error("Tap-hold typed lowering requires [key, context, threshold, tap, hold, cleanup?, suspendExempt?]: " source)
        key := this.ElementString(elems[1], "", &keyOk)
        if (!keyOk || key = "")
            throw Error("Tap-hold typed lowering requires a literal key: " source)
        if (!this.IsGlobalContextLiteral(elems[2]))
            throw Error("Tap-hold typed lowering currently requires global context: " source)
        thresholdText := Trim(elems[3])
        if !RegExMatch(thresholdText, "^-?\d+$")
            throw Error("Tap-hold typed lowering requires a literal threshold: " source)
        suspendIndex := elems.Length >= 7 ? 7 : 0
        return {key: key, thresholdMs: Integer(thresholdText), suspendExempt: suspendIndex &&
            (StrLower(Trim(elems[suspendIndex])) = "true" || Trim(elems[suspendIndex]) = "1")}
    }

    static HotstringOptionFields(optionText) {
        fields := ""
        i := 1
        while (i <= StrLen(optionText)) {
            ch := StrUpper(SubStr(optionText, i, 1))
            next := i < StrLen(optionText) ? SubStr(optionText, i + 1, 1) : ""
            value := ""
            field := ""
            switch ch {
                case "X": field := "execute", value := "true"
                case "Z": field := "reset", value := "true"
                case "?": field := "inside_word", value := (next = "0" ? "false" : "true")
                case "O": field := "omit_end_char", value := (next = "0" ? "false" : "true")
                case "B": field := "backspace", value := (next = "0" ? "false" : "true")
                case "*": field := "require_end_char", value := (next = "0" ? "true" : "false")
                case "C":
                    if (next = "0")
                        field := "conform_to_case", value := "true"
                    else
                        field := "case_sensitive", value := (next = "1" ? "false" : "true")
                case "S":
                    if (next != "I" && next != "E" && next != "P")
                        field := "suspend_exempt", value := (next = "0" ? "false" : "true")
                case "R", "T": field := "send_raw", value := "true"
            }
            if (field != "")
                fields .= (fields = "" ? "" : ",") " ." field " = " value
            if (ch = "O" || ch = "B" || ch = "*" || ch = "?" || ch = "C" || ch = "S") && next = "0"
                i += 1
            i += 1
        }
        return fields
    }

    static CollapsedCompileModifierBit(vk) {
        switch vk {
            case 0x10, 0xA0, 0xA1: return 0x04
            case 0x11, 0xA2, 0xA3: return 0x01
            case 0x12, 0xA4, 0xA5: return 0x02
            case 0x5B, 0x5C: return 0x08
        }
        return 0
    }

    static CompilePhysicalModifierLRBits(vk) {
        switch vk {
            case 0xA2: return 0x01
            case 0xA3: return 0x02
            case 0xA0: return 0x04
            case 0xA1: return 0x08
            case 0xA4: return 0x10
            case 0xA5: return 0x20
            case 0x5B: return 0x40
            case 0x5C: return 0x80
        }
        return 0
    }

    static EmitZigU16Literal(text) {
        ; Keep generated text readable. The generated Zig module widens this
        ; literal to the zero-terminated UTF-16 slice at compile time.
        return "utf16(" Chr(34) this.EscapeZigString(text) Chr(34) ")"
    }

    static EmitZigU8Literal(text) {
        ; Key/trigger fields stay as their readable source names in generated
        ; Zig. QMKCore performs the single compile-time name-to-VK lowering.
        return "u(" Chr(34) this.EscapeZigString(text) Chr(34) ")"
    }

    static IsGlobalContextLiteral(expression) {
        return this.ElementString(expression, "", &ok) = "global" && ok
    }

    static ResolveCompileModifierType(name) {
        switch StrLower(Trim(name)) {
            case "ctrl", "control": return 0
            case "alt": return 1
            case "shift": return 2
            case "win", "windows": return 3
        }
        throw Error("Unknown modifier type in typed lowering: " name)
    }

    static ResolveCompileVK(name) {
        text := Trim(name)
        if RegExMatch(text, "i)^vk([0-9a-f]{2})$", &hex)
            return "0x" hex[1]
        ; Printable letters/digits use their ordinary Windows VK values, but
        ; punctuation is not ASCII on Windows.  Keep this table aligned with
        ; the AHK/QMK key-name resolver so ';' becomes VK_OEM_1 (0xBA), '['
        ; becomes VK_OEM_4 (0xDB), etc.
        static punctuation := Map(
            ";", 0xBA, "=", 0xBB, ",", 0xBC, "-", 0xBD, ".", 0xBE,
            "/", 0xBF, "``", 0xC0, "[", 0xDB, "\", 0xDC, "]", 0xDD,
            "'", 0xDE
        )
        if (StrLen(text) = 1 && punctuation.Has(text))
            return punctuation[text]
        if (StrLen(text) = 1)
            return Ord(StrUpper(text))
        ; The compiler deliberately does not load QMKInterception.ahk or the
        ; runtime DLL. Keep key-name resolution local and deterministic rather
        ; than referring to the runtime-only QMK.GetVK() object.
        static names := Map(
            "escape", 0x1B, "esc", 0x1B, "tab", 0x09, "enter", 0x0D,
            "return", 0x0D, "backspace", 0x08, "space", 0x20,
            "capslock", 0x14, "scrolllock", 0x91, "numlock", 0x90,
            "shift", 0x10, "ctrl", 0x11, "control", 0x11, "lctrl", 0xA2, "rctrl", 0xA3,
            "lshift", 0xA0, "rshift", 0xA1, "alt", 0x12, "lalt", 0xA4, "ralt", 0xA5,
            "lwin", 0x5B, "rwin", 0x5C, "appskey", 0x5D,
            "insert", 0x2D, "delete", 0x2E, "home", 0x24, "end", 0x23,
            "pgup", 0x21, "pageup", 0x21, "pgdn", 0x22, "pagedown", 0x22,
            "left", 0x25, "up", 0x26, "right", 0x27, "down", 0x28,
            "printscreen", 0x2C, "printscr", 0x2C, "pause", 0x13,
            "numpad0", 0x60, "numpad1", 0x61, "numpad2", 0x62,
            "numpad3", 0x63, "numpad4", 0x64, "numpad5", 0x65,
            "numpad6", 0x66, "numpad7", 0x67, "numpad8", 0x68,
            "numpad9", 0x69, "numpadmult", 0x6A, "numpadadd", 0x6B,
            "numpadsub", 0x6D, "numpaddot", 0x6E, "numpaddiv", 0x6F
        )
        lowered := StrLower(text)
        if names.Has(lowered)
            return names[lowered]
        if RegExMatch(lowered, "^f([1-9]|1[0-9]|2[0-4])$", &functionKey)
            return 0x6F + Integer(functionKey[1])
        if RegExMatch(lowered, "^numpad([0-9])$", &numpadKey)
            return 0x60 + Integer(numpadKey[1])
        throw Error("Could not resolve key to a VK during typed lowering: " name)
    }

    static EmitCompileVK(name) {
        ; Kept as a compatibility helper for older diagnostic paths. New
        ; generated rows must carry the readable source spelling directly.
        return "u(" Chr(34) this.EscapeZigString(Trim(name)) Chr(34) ")"
    }

    static WriteGeneratedArtifact(path, text, rotateZigBackups := false) {
        existing := ""
        if FileExist(path) {
            try existing := FileRead(path, "UTF-8")
            catch {
                existing := ""
            }
        }
        if (existing = text) {
            this.Log("Generated artifact unchanged; write skipped: " path)
            return false
        }
        if rotateZigBackups
            this.RotateShortcutBackups()
        this.WriteTextFile(path, text)
        return true
    }

    static ValidateGeneratedShortcutBundle() {
        this.RequireFile(this.compiledShortcutZigPath, "generated user_shortcuts.zig")
        ahkPath := this.GeneratedCallbackArtifactPath()
        this.RequireFile(ahkPath, "generated user_callbacks.ahk")
        if !this.shortcutSourceFiles.Length
            throw Error("No source files are selected for the generated shortcut bundle.")
        expectedId := this.ComputeShortcutBuildId(this.shortcutSourceFiles)
        zigText := FileRead(this.compiledShortcutZigPath, "UTF-8")
        ahkText := FileRead(ahkPath, "UTF-8")
        q := Chr(34)
        if InStr(zigText, "install(api") || RegExMatch(zigText, "QMK_Setup[A-Za-z0-9_]*\s*\(")
            throw Error("Generated user_shortcuts.zig contains a forbidden installer or QMK_Setup* call.")
        if !RegExMatch(zigText, "m)^pub const compiled_build_id = " q "([0-9A-F]{8})" q ";", &zigId)
            throw Error("Generated user_shortcuts.zig has no valid build identity.")
        ; Full-native callbacks are intentionally top-level functions, not a
        ; generated class.  Their identity is emitted as a header comment;
        ; accept the older class metadata form only for backward-compatible
        ; validation of previously generated bundles.
        if !RegExMatch(ahkText, "m)^; build_id: ([0-9A-F]{8})$", &ahkId)
            if !RegExMatch(ahkText, "m)^    static build_id := " q "([0-9A-F]{8})" q, &ahkId)
                throw Error("Generated user_callbacks.ahk has no valid build identity.")
        if (zigId[1] != expectedId || ahkId[1] != expectedId || zigId[1] != ahkId[1])
            throw Error("Generated shortcut artifacts are stale or have mismatched build identities.")
        sourceRows := this.CaptureRowsForValidation()
        if !RegExMatch(zigText, "m)^pub const compiled_source_count: usize = (\d+);", &sourceCount)
            throw Error("Generated user_shortcuts.zig is missing compiled_source_count.")
        if (Integer(sourceCount[1]) != this.shortcutSourceFiles.Length)
            throw Error("Generated source count does not match the selected source files.")
        if !RegExMatch(zigText, "m)^pub const compiled_row_count: usize = (\d+);", &rowCount)
            throw Error("Generated user_shortcuts.zig is missing compiled_row_count.")
        nativeRows := []
        for , row in sourceRows {
            if (row.kind = "native" || row.kind = "native_control") {
                ; Match the generator exactly: a collector-native row counts
                ; toward compiled_row_count only when its typed Zig lowerer
                ; accepts the shape. Unsupported native syntax remains in the
                ; source-owned fallback and is not part of generated Zig.
                try this.ValidateNativeRowLowering(row)
                catch
                    continue
                nativeRows.Push(row)
            }
        }
        ; Partial artifacts contain only successfully lowered native rows.
        ; Full-native artifacts intentionally contain every selected row,
        ; including callback rows represented by compiled callback IDs.
        validationRows := this.shortcutCompileMode = "full_native" ? sourceRows : nativeRows
        if (Integer(rowCount[1]) != validationRows.Length) {
            ; The maintained external transpiler may intentionally omit a
            ; source row that has no representable typed record.  Source-order
            ; validation below still proves that every emitted row belongs to
            ; the selected sources and is in the correct original order.
            this.Log("Generated row count differs from selected source rows; validating emitted source order instead: generated=" rowCount[1] ", validated_rows=" validationRows.Length)
        }
        if !RegExMatch(zigText, "m)^pub const Compiled_Source_Order = \[_\]u32\{(.*?)\};$", &sourceOrder)
            throw Error("Generated user_shortcuts.zig is missing Compiled_Source_Order.")
        orderText := Trim(sourceOrder[1])
        orderValues := orderText = "" ? [] : StrSplit(orderText, ",")
        orderCount := orderValues.Length
        if (orderCount != Integer(rowCount[1]))
            throw Error("Generated source-order count does not match generated_row_count.")
        for index, value in orderValues {
            value := Trim(value)
            if !RegExMatch(value, "^\d+$")
                throw Error("Generated source order contains a non-numeric entry at index " (index - 1) ".")
            sourceIndex := Integer(value) + 1
            if (sourceIndex < 1 || sourceIndex > sourceRows.Length)
                throw Error("Generated source order points outside the selected source rows at index " (index - 1) ".")
            if (Integer(value) != sourceRows[sourceIndex].sourceOrder)
                throw Error("Generated source order does not match the selected native source order at index " (index - 1) ".")
        }
        for declaration in [
            "pub const Compiled_Modifiers",
            "pub const Compiled_Passthroughs",
            "pub const Compiled_Hotkeys",
            "pub const Compiled_Holds",
            "pub const Compiled_Double_Taps",
            "pub const Compiled_Taps",
            "pub const Compiled_Tap_Holds",
            "pub const Compiled_Combos",
            "pub const Compiled_Chords",
            "pub const Compiled_Hotstrings",
            "pub const Compiled_Callbacks",
            "pub const Compiled_Source_Order"
        ] {
            if !InStr(zigText, declaration)
                throw Error("Generated user_shortcuts.zig is incomplete; missing " declaration ".")
        }
        this.ValidateGeneratedZigSyntax()
        if !RegExMatch(ahkText, "m)^#Requires AutoHotkey v2\.0$")
            throw Error("Generated user_callbacks.ahk is missing its AutoHotkey v2 requirement.")
        ; Current full-native output intentionally has no generated class: it
        ; consists of straight top-level QMKCB_* functions plus one callback
        ; map installed once.  Keep the legacy class marker accepted for old
        ; bundles, but validate the current map-based metadata shape.
        hasCurrentCallbackMetadata := InStr(ahkText, "QMKCompiledCallbackMap")
            && InStr(ahkText, "QMK.InstallCompiledCallbackMap")
        hasLegacyCallbackMetadata := InStr(ahkText, "class QMKCompiledUserCallbacks")
        if !hasCurrentCallbackMetadata && !hasLegacyCallbackMetadata
            throw Error("Generated user_callbacks.ahk is incomplete; callback metadata is missing.")
        return {buildId: expectedId, zigText: zigText, ahkText: ahkText}
    }

    static CaptureRowsForValidation() {
        reportPath := A_Temp "\qmk_compiled_shortcuts_validation.tsv"
        this.DeleteIfExists(reportPath)
        try {
            QMKShortcutCollector.CaptureSourceFiles(this.shortcutSourceFiles, reportPath)
            rows := []
            for , row in QMKShortcutCollector.rows {
                if !this.IsRealShortcutRow(row.sourceText)
                    continue
                rows.Push({family: row.family, index: row.rowIndex, kind: row.kind, path: row.sourcePath, source: row.sourceText, sourceOrder: rows.Length})
            }
            return rows
        } finally {
            this.DeleteIfExists(reportPath)
        }
    }

    static IsRealShortcutRow(sourceText) {
        text := LTrim(String(sourceText), " `t`r`n")
        return text != "" && SubStr(text, 1, 1) != ";"
    }

    static CompileCompiledShortcutCandidate(showSuccess := true) {
        if this.running {
            MsgBox("Finish the current build before compiling user shortcuts.", "QMK Compiler", "Icon!")
            return
        }
        candidateDll := this.libDir "\QMKCoreProfiling.compiled_user_shortcuts.building.dll"
        candidateOptions := this.libDir "\build_options_compiled_user_shortcuts.tmp.zig"
        this.DeleteIfExists(candidateDll)
        this.DeleteIfExists(candidateOptions)
        buildOutput := this.libDir "\zig-out\QMKCoreProfiling.compiled_user_shortcuts.building.dll"
        this.DeleteIfExists(buildOutput)
        try {
            this.Preflight("zig")
            this.ValidateGeneratedShortcutBundle()
            optionsText := this.ExpectedBuildOptionsText(false, false, false, false, false, true)
            this.WriteTextFile(candidateOptions, optionsText)
            this.compiledShortcutBuildActive := true
            try {
            this.Log("Building staged compiled-user-shortcuts candidate; active DLL is untouched.")
            this.RunStep(this.ZigBuildCommand("dll", "QMKCoreProfiling.compiled_user_shortcuts.building.dll", candidateOptions), this.libDir, "Compiled user-shortcuts candidate build")
            this.RequireFile(buildOutput, "build-script candidate DLL")
            FileCopy(buildOutput, candidateDll, true)
            this.VerifyRequiredExports(candidateDll)
            flags := this.GetBuildFeatureFlags(candidateDll)
            if ((flags & (1 << 7)) = 0)
                throw Error("The staged DLL did not report compiled user shortcuts enabled.")
            this.Log("Candidate build identity: " this.ComputeShortcutBuildId(this.shortcutSourceFiles))
            this.Log("Candidate DLL feature flags: " Format("0x{:08X}", flags))
            if showSuccess
                MsgBox("Staged compiled-user-shortcuts candidate built and export-validated.`n`nIt was not embedded or made active.`n`nNext work is include migration and callback/runtime parity.", "QMK Compiler - User Shortcuts", "Iconi")
            else
                this.Log("Staged compiled-user-shortcuts candidate built and export-validated; it was not embedded or made active.")
            return 0
            } finally {
                this.compiledShortcutBuildActive := false
                this.DeleteIfExists(candidateOptions)
                this.DeleteIfExists(candidateDll)
                this.DeleteIfExists(buildOutput)
                this.DeleteIfExists(this.libDir "\QMKCoreProfiling.compiled_user_shortcuts.building.lib")
                this.DeleteIfExists(this.libDir "\QMKCoreProfiling.compiled_user_shortcuts.building.pdb")
            }
        } catch Error as err {
            this.compiledShortcutBuildActive := false
            this.DeleteIfExists(candidateOptions)
            this.DeleteIfExists(candidateDll)
            this.DeleteIfExists(buildOutput)
            this.Log("Compiled user-shortcuts bundle rejected; Runtime-only remains selected: " err.Message)
            throw err
        }
    }

    static ValidateGeneratedZigSyntax() {
        code := this.RunHidden(this.Quote(this.zigPath) " ast-check " this.Quote(this.compiledShortcutZigPath), this.libDir)
        if (code != 0)
            throw Error("Generated user_shortcuts.zig failed Zig syntax validation.")
    }

    static BuildNativeRecordSets(rows) {
        sets := {
            modifiers: {records: [], texts: [], count: 0},
            hotkeys: {records: [], texts: [], count: 0},
            combos: {records: [], texts: [], count: 0},
            chords: {records: [], texts: [], count: 0},
            nativeCount: 0,
            callbackCount: 0,
            unsupportedNativeCount: 0
        }
        for , row in rows {
            row.compiled := false
            if (row.kind = "callback") {
                sets.callbackCount += 1
                continue
            }
            if (row.kind != "native")
                continue
            compiled := false
            switch row.family {
                case "modifiers": compiled := this.EmitModifierRecord(sets.modifiers, row.source)
                case "hotkeys": compiled := this.EmitHotkeyRecord(sets.hotkeys, row.source, 0)
                case "taps": compiled := this.EmitHotkeyRecord(sets.hotkeys, row.source, 1)
                case "combos": compiled := this.EmitComboRecord(sets.combos, row.source)
                case "chords": compiled := this.EmitChordRecord(sets.chords, row.source)
            }
            if compiled
                row.compiled := true
            if compiled
                sets.nativeCount += 1
            else
                sets.unsupportedNativeCount += 1
        }
        return sets
    }

    static BuildDynamicFallback(rows) {
        text := "`n; Dynamic fallback rows retained in source order, grouped by family.`n"
        dynamicCount := 0
        unsupportedCount := 0
        groups := Map()
        familyOrder := []
        for , row in rows {
            if row.compiled
                continue
            setupName := this.FallbackSetupName(row.family)
            if (setupName = "" || row.source = "") {
                unsupportedCount += 1
                text .= "; NOT EMITTED: family=" row.family ", row=" row.index " remains source-owned.`n"
                continue
            }
            source := row.source
            if row.HasOwnProp("compiledCallbackName")
                source := this.ReplaceSafeCallbackWithName(source, row.compiledCallbackName)
            if !groups.Has(setupName) {
                groups[setupName] := []
                familyOrder.Push(setupName)
            }
            groups[setupName].Push(source)
            dynamicCount += 1
        }
        for , setupName in familyOrder {
            text .= "QMK." setupName "([`n"
            entries := groups[setupName]
            for index, source in entries
                text .= "    " source (index < entries.Length ? "," : "") "`n"
            text .= "])`n"
        }
        return {text: text, dynamicCount: dynamicCount, unsupportedCount: unsupportedCount}
    }

    static FallbackSetupName(family) {
        switch family {
            case "hotkeys": return "SetupHotkeys"
            case "modifiers": return "SetupModifiers"
            case "combos": return "SetupCombos"
            case "chords": return "SetupChords"
            case "holds": return "SetupHolds"
            case "double_taps": return "SetupDoubleTaps"
            case "taps": return "SetupTaps"
            case "tap_holds": return "SetupTapHolds"
            case "hotstrings": return "SetupHotstrings"
        }
        return ""
    }

    static ReplaceSafeCallbackWithName(source, callbackName) {
        this.ExtractSafeLambda(source, &params, &body)
        lambdaText := "(" params ") => " body
        if InStr(source, lambdaText) {
            ; The replacement is intentionally unbounded: a source row has one
            ; callback expression, and this avoids the alpha AHK StrReplace
            ; output-count ABI entirely.
            return StrReplace(source, lambdaText, callbackName)
        }
        return source
    }

    static BuildCallbackDefinitions(rows) {
        text := "`n; Named callback wrappers generated in source order.`n"
        safeCount := 0
        wrapperLines := []
        descriptors := []
        callbackSlots := Map()
        rowSlots := Map()
        for , row in rows {
            if (row.kind != "callback" && row.family != "taps")
                continue
            expressions := this.CallbackExpressionsForRow(row)
            for callbackIndex, callbackItem in expressions {
                if (row.family = "taps")
                    expression := callbackItem
                else
                    expression := callbackItem
                if !this.ExtractCallbackLambda(expression, &params, &body) {
                    ; The source row is already balanced and explicitly
                    ; classified as a callback.  Preserve a lambda body that
                    ; contains unusual comments/formatting rather than
                    ; silently dropping its callback slot.
                    if !InStr(expression, "=>")
                        continue
                    params := "*"
                    body := Trim(SubStr(expression, InStr(expression, "=>") + 2))
                }
                if !callbackSlots.Has(expression) {
                    safeCount += 1
                    name := Format("QMKCB_{:04}", safeCount)
                    callbackSlots[expression] := {name: name, slot: safeCount - 1}
                    wrapperLine := name "(" params ") {`n    return " body "`n}"
                    wrapperLines.Push(name)
                    descriptors.Push("        .{ .slot = " (safeCount - 1) ", .kind = .ahk, .ahk = .{ .bridge_id = " (safeCount - 1) ", .name = " Chr(34) name Chr(34) " } },")
                    text .= wrapperLine "`n"
                }
                callback := callbackSlots[expression]
                rowSlots[row.sourceOrder] := callback.slot
                if (row.family = "tap_holds") {
                    if (callbackIndex = 1)
                        row.compiledTapCallbackSlot := callback.slot
                    else if (callbackIndex = 2)
                        row.compiledHoldCallbackSlot := callback.slot
                    else if (callbackIndex = 3)
                        row.compiledCleanupCallbackSlot := callback.slot
                } else if (row.family = "taps") {
                    role := row.family = "taps" ? callbackIndex : 3
                    if (role = 3)
                        row.compiledTapCallbackSlot := callback.slot
                    else if (role = 4)
                        row.compiledTapHoldCallbackSlot := callback.slot
                    else if (role = 6)
                        row.compiledTapCleanupCallbackSlot := callback.slot
                } else {
                    row.compiledCallbackName := callback.name
                    row.compiledCallbackSlot := callback.slot
                }
            }
            index += 1
        }
        text .= "; Callback functions are emitted in source order; Zig sends their reserved IDs over IPC.`n"
        return {text: text, safeCount: safeCount, wrapperLines: wrapperLines, descriptors: descriptors, rowSlots: rowSlots}
    }

    static CallbackExpressionsForRow(row) {
        elems := this.SourceRowElements(row.source)
        expressions := row.family = "taps" ? Map() : []
        if (row.family = "tap_holds") {
            ; Tap-hold rows are [key, context, threshold, tap, hold, cleanup?, suspend?].
            for index, unused in elems {
                if (index >= 4 && index <= 6)
                    expressions.Push(Trim(elems[index]))
            }
        } else if (row.family = "taps") {
            ; SetupTaps rows are [key, context, tap, hold?, threshold?, cleanup?, suspend?].
            for role in [3, 4, 6] {
                if (role <= elems.Length) {
                    expression := Trim(elems[role])
                    if (InStr(expression, "=>") || RegExMatch(expression, "i)\bFunc\s*\("))
                        expressions[role] := expression
                }
            }
        } else if (row.family = "combos") {
            actionIndex := elems.Length = 3 ? 3 : 4
            if (elems.Length >= actionIndex)
                expressions.Push(Trim(elems[actionIndex]))
        } else if (row.family = "chords") {
            ; Chords may have 2-5 keys, an optional context, and optional
            ; mode/modifier/suspend cells. Find the callable expression rather
            ; than assuming it is always element 3 or 4.
            for index, expression in elems {
                if (index >= 3 && (InStr(expression, "=>") || RegExMatch(expression, "i)\bFunc\s*\("))) {
                    expressions.Push(Trim(expression))
                    break
                }
            }
        } else if (elems.Length >= 3) {
            expressions.Push(Trim(elems[3]))
        }
        return expressions
    }

    static ExtractSafeLambda(source, &params := unset, &body := unset) {
        params := ""
        body := ""
        arrow := this.FindTopLevelArrow(source)
        if !arrow
            return false
        beforeArrow := RTrim(SubStr(source, 1, arrow - 1))
        closeParam := StrLen(beforeArrow)
        if (SubStr(beforeArrow, closeParam, 1) != ")")
            return false
        openParam := this.FindOpeningParen(beforeArrow, closeParam)
        if !openParam
            return false
        params := Trim(SubStr(beforeArrow, openParam + 1, closeParam - openParam - 1))
        if (params = "")
            return false
        body := Trim(SubStr(source, arrow + 2))
        if (SubStr(body, -1) = "]")
            body := Trim(SubStr(body, 1, StrLen(body) - 1))
        ; Multiline parenthesized callback expressions and comments are valid
        ; AHK source.  Keep them intact; delimiter validation below remains
        ; the safety check before placing the body in a straight wrapper.
        if (body = "")
            return false
        if !this.ExpressionDelimitersBalanced(body)
            return false
        return true
    }

    static FindOpeningParen(text, closePos) {
        depth := 0
        pos := closePos
        while (pos >= 1) {
            ch := SubStr(text, pos, 1)
            if (ch = ")")
                depth += 1
            else if (ch = "(") {
                depth -= 1
                if (depth = 0)
                    return pos
            }
            pos -= 1
        }
        return 0
    }

    static FindTopLevelArrow(text) {
        paren := 0
        bracket := 0
        brace := 0
        quote := false
        pos := 1
        while (pos <= StrLen(text)) {
            ch := SubStr(text, pos, 1)
            if quote {
                if (ch = "``")
                    pos += 1
                else if (ch = Chr(34))
                    quote := false
                pos += 1
                continue
            }
            if (ch = Chr(34)) {
                quote := true
            } else if (ch = "(") {
                paren += 1
            } else if (ch = ")") {
                paren -= 1
            } else if (ch = "[") {
                bracket += 1
            } else if (ch = "]") {
                bracket -= 1
            } else if (ch = "{") {
                brace += 1
            } else if (ch = "}") {
                brace -= 1
            } else if (ch = ";") {
                newline := InStr(text, "`n", false, pos)
                pos := newline ? newline : StrLen(text) + 1
                continue
            } else if (ch = "=" && SubStr(text, pos + 1, 1) = ">" && paren = 0 && (bracket = 0 || bracket = 1) && brace = 0) {
                return pos
            }
            pos += 1
        }
        return 0
    }

    static ExpressionDelimitersBalanced(text) {
        paren := 0
        bracket := 0
        brace := 0
        quote := false
        pos := 1
        while (pos <= StrLen(text)) {
            ch := SubStr(text, pos, 1)
            if quote {
                if (ch = "``")
                    pos += 1
                else if (ch = Chr(34))
                    quote := false
                pos += 1
                continue
            }
            if (ch = Chr(34))
                quote := true
            else if (ch = ";") {
                ; AHK comments may contain delimiter characters.  Ignore the
                ; remainder of the physical line while checking balance.
                newline := InStr(text, "`n", false, pos)
                pos := newline ? newline : StrLen(text) + 1
                continue
            }
            else if (ch = "(")
                paren += 1
            else if (ch = ")")
                paren -= 1
            else if (ch = "[")
                bracket += 1
            else if (ch = "]")
                bracket -= 1
            else if (ch = "{")
                brace += 1
            else if (ch = "}")
                brace -= 1
            if (paren < 0 || bracket < 0 || brace < 0)
                return false
            pos += 1
        }
        return !quote && paren = 0 && bracket = 0 && brace = 0
    }

    static SourceRowElements(source) {
        ; ROW fields may contain physical line breaks or escaped line breaks
        ; from the TSV transport. Formatting whitespace is not part of the
        ; row grammar, so normalize it before locating the outer array.
        ; Preserve physical newlines so a semicolon comment cannot consume the
        ; rest of a multiline callback expression while balancing delimiters.
        ; Only remove the literal two-character transport marker if present.
        clean := StrReplace(source, "\n", "")
        clean := StrReplace(clean, "`r", "")
        clean := Trim(clean)
        if (SubStr(clean, 1, 1) != "[")
            return []
        closePos := QMKShortcutCollector.FindBalanced(clean, 1, "[", "]")
        if !closePos
            return []
        return QMKShortcutCollector.SplitTopLevel(SubStr(clean, 2, closePos - 2))
    }

    static ParseAhkString(expression, &ok := unset) {
        ok := false
        text := Trim(expression)
        if (SubStr(text, 1, 1) != '"')
            return ""
        value := ""
        pos := 2
        while (pos <= StrLen(text)) {
            ch := SubStr(text, pos, 1)
            if (ch = '"') {
                if (SubStr(text, pos + 1, 1) = '"') {
                    value .= '"'
                    pos += 2
                    continue
                }
                ok := (Trim(SubStr(text, pos + 1)) = "")
                return value
            }
            if (ch = "``" && pos < StrLen(text)) {
                pos += 1
                value .= SubStr(text, pos, 1)
            } else {
                value .= ch
            }
            pos += 1
        }
        return ""
    }

    static ParseDirectAction(expression, &ok := unset) {
        ok := false
        if !RegExMatch(Trim(expression), "i)^QMK\.(SendKeyDirect|SendDirect)\s*\((.*)\)$", &match)
            return ""
        return this.ParseAhkString(match[2], &ok)
    }

    ; QMK.Tap("...") is a compiler capture descriptor for the same direct
    ; key payload used by the contextual-tap row. It is not an AHK callback and
    ; must therefore remain entirely in the generated Zig table.
    static ParseTapDescriptor(expression, &ok := unset) {
        ok := false
        if !RegExMatch(Trim(expression), "i)^QMK\.Tap\s*\((.*)\)$", &match)
            return ""
        return this.ParseAhkString(match[1], &ok)
    }

    ; The runtime marks QMK.SuspendExempt((*) => body) as one callback value.
    ; For full-native output, unwrap that capture marker and emit the inner
    ; lambda as the same straight top-level function as an ordinary callback.
    static ExtractCallbackLambda(source, &params := unset, &body := unset) {
        if this.ExtractSafeLambda(source, &params, &body)
            return true
        text := Trim(source)
        if RegExMatch(text, "i)^QMK\.SuspendExempt\s*\((.*)\)$", &wrapped) {
            if this.ExtractSafeLambda(Trim(wrapped[1]), &params, &body)
                return true
            if this.ExtractCallbackFunctionReference(Trim(wrapped[1]), &params, &body)
                return true
        } else if this.ExtractCallbackFunctionReference(text, &params, &body) {
            return true
        }
        ; QMK.Tap(non-literal-expression) is an AHK action callback, not the
        ; literal QMK.Tap("...") native descriptor.  Execute it from the
        ; generated straight wrapper when the hotkey fires.
        if RegExMatch(text, "i)^QMK\.Tap\s*\(") && this.ExpressionDelimitersBalanced(text) {
            params := "*"
            body := text
            return true
        }
        ; Some valid multiline AHK lambdas contain comments with delimiter
        ; characters.  The source-row scanner has already proved the outer
        ; row balanced, so retain the lambda body verbatim as a wrapper when
        ; the stricter single-expression validator cannot recognize it.
        return this.ExtractCallbackLambdaVerbatim(text, &params, &body)
    }

    static ExtractCallbackLambdaVerbatim(source, &params := unset, &body := unset) {
        params := ""
        body := ""
        arrow := this.FindTopLevelArrow(source)
        if !arrow
            return false
        beforeArrow := RTrim(SubStr(source, 1, arrow - 1))
        if (SubStr(beforeArrow, -1) != ")")
            return false
        openParam := this.FindOpeningParen(beforeArrow, StrLen(beforeArrow))
        if !openParam
            return false
        params := Trim(SubStr(beforeArrow, openParam + 1, StrLen(beforeArrow) - openParam - 1))
        body := Trim(SubStr(source, arrow + 2))
        if (SubStr(body, -1) = "]")
            body := Trim(SubStr(body, 1, StrLen(body) - 1))
        return body != ""
    }

    ; Preserve a named AHK function object without registering it as a runtime
    ; lambda.  The generated straight wrapper forwards the callback arguments
    ; to the original function object on demand.
    static ExtractCallbackFunctionReference(source, &params := unset, &body := unset) {
        params := ""
        body := ""
        text := Trim(source)
        if !RegExMatch(text, "i)^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+$")
            return false
        params := "*"
        ; AHK v2 does not permit variadic expansion directly after a dotted
        ; function-object reference (`Prompts.handoff(*)`). These named
        ; hotstring callbacks are invoked without arguments, so call them
        ; directly from the generated wrapper.
        body := text "()"
        return true
    }

    static ElementString(expression, fallback := "", &ok := unset) {
        parsed := this.ParseAhkString(expression, &literal)
        if literal {
            ok := true
            return parsed
        }
        ok := false
        return fallback
    }

    ; Match QMK.ContextText for a compiler-safe literal context expression.
    ; The runtime represents context arrays as unit-separator-delimited text;
    ; accepting only literal strings keeps arbitrary expressions in the AHK
    ; fallback while preserving the current-core context ABI.
    static ContextExpression(expression, fallback := "", &ok := unset) {
        text := Trim(expression)
        literal := this.ParseAhkString(text, &literalOk)
        if literalOk {
            ok := true
            return literal
        }
        if (SubStr(text, 1, 1) != "[") {
            ok := false
            return fallback
        }
        closePos := QMKShortcutCollector.FindBalanced(text, 1, "[", "]")
        if (!closePos || Trim(SubStr(text, closePos + 1)) != "") {
            ok := false
            return fallback
        }
        parts := QMKShortcutCollector.SplitTopLevel(SubStr(text, 2, closePos - 2))
        if !parts.Length {
            ok := false
            return fallback
        }
        result := ""
        for , part in parts {
            value := this.ParseAhkString(part, &partOk)
            if !partOk {
                ok := false
                return fallback
            }
            result .= (A_Index = 1 ? "" : Chr(0x1F)) value
        }
        ok := true
        return result
    }

    static AddText(set, text, &offset, &length) {
        offset := set.texts.Length
        length := StrLen(text)
        Loop length
            set.texts.Push(Ord(SubStr(text, A_Index, 1)))
    }

    static ReserveRecord(records, size) {
        base := records.Length
        Loop size
            records.Push(0)
        return base
    }

    static PutU8(records, base, offset, value) {
        records[base + offset + 1] := Mod(value, 256)
    }

    static PutU16(records, base, offset, value) {
        this.PutU8(records, base, offset, value)
        this.PutU8(records, base, offset + 1, Floor(value / 256))
    }

    static PutU32(records, base, offset, value) {
        value := Mod(value, 4294967296)
        this.PutU8(records, base, offset, value)
        this.PutU8(records, base, offset + 1, Floor(value / 256))
        this.PutU8(records, base, offset + 2, Floor(value / 65536))
        this.PutU8(records, base, offset + 3, Floor(value / 16777216))
    }

    static PutI32(records, base, offset, value) {
        this.PutU32(records, base, offset, value < 0 ? value + 4294967296 : value)
    }

    static EmitModifierRecord(set, source) {
        elems := this.SourceRowElements(source)
        if (elems.Length < 2)
            return false
        key := this.ElementString(elems[1], "", &keyOk)
        modifier := this.ElementString(elems[2], "", &modifierOk)
        if (!keyOk || !modifierOk)
            return false
        context := elems.Length >= 3 ? this.ContextExpression(elems[3], "global", &contextOk) : "global"
        if (elems.Length >= 3 && !contextOk)
            return false
        suspendExempt := elems.Length >= 4 && (StrLower(Trim(elems[4])) = "true" || Trim(elems[4]) = "1")
        base := this.ReserveRecord(set.records, 32)
        this.AddText(set, key, &keyOffset, &keyLength)
        this.AddText(set, modifier, &modOffset, &modLength)
        this.AddText(set, context, &contextOffset, &contextLength)
        this.PutU32(set.records, base, 0, keyOffset)
        this.PutU16(set.records, base, 4, keyLength)
        this.PutU32(set.records, base, 8, modOffset)
        this.PutU16(set.records, base, 12, modLength)
        this.PutU8(set.records, base, 14, suspendExempt ? 1 : 0)
        this.PutU32(set.records, base, 16, contextOffset)
        this.PutU16(set.records, base, 20, contextLength)
        set.count += 1
        return true
    }

    ; Emit only the current-core-compatible native shape. For hotkeys this is
    ; [literal spec, literal context, QMK.SendKeyDirect(literal payload), bool?].
    ; For taps, the same ABI uses actionKind=1 and permits only empty hold /
    ; cleanup fields. Callback rows, object rows, context arrays, and special
    ; grammar remain in the generated AHK fallback until parity is proven.
    static EmitHotkeyRecord(set, source, actionKind := 0) {
        elems := this.SourceRowElements(source)
        if (elems.Length < 3 || (actionKind = 0 && elems.Length > 4) || (actionKind = 1 && elems.Length > 7))
            return false
        spec := this.ElementString(elems[1], "", &specOk)
        context := this.ContextExpression(elems[2], "", &contextOk)
        target := this.ParseDirectAction(elems[3], &actionOk)
        if (!specOk || !contextOk || !actionOk || !this.CoreHotkeySpecShape(spec))
            return false
        if (actionKind = 1) {
            if (elems.Length >= 4 && !this.IsEmptyLiteral(elems[4]))
                return false
            if (elems.Length >= 5 && Trim(elems[5]) != "0")
                return false
            if (elems.Length >= 6 && !this.IsEmptyLiteral(elems[6]))
                return false
            suspendIndex := 7
        } else {
            suspendIndex := 4
        }
        suspendExempt := elems.Length >= suspendIndex && (StrLower(Trim(elems[suspendIndex])) = "true" || Trim(elems[suspendIndex]) = "1")
        base := this.ReserveRecord(set.records, 44)
        this.AddText(set, spec, &specOffset, &specLength)
        this.AddText(set, context, &contextOffset, &contextLength)
        this.AddText(set, target, &actionOffset, &actionLength)
        ; QMK_SetupHotkeyEntries requires one trailing UTF-16 zero after a
        ; native payload so the core can distinguish the payload boundary.
        set.texts.Push(0)
        this.PutU32(set.records, base, 0, specOffset)
        this.PutU16(set.records, base, 4, specLength)
        this.PutU32(set.records, base, 8, contextOffset)
        this.PutU16(set.records, base, 12, contextLength)
        this.PutU32(set.records, base, 16, actionOffset)
        this.PutU16(set.records, base, 20, actionLength)
        this.PutI32(set.records, base, 24, -1)
        this.PutU8(set.records, base, 28, suspendExempt ? 1 : 0)
        this.PutU8(set.records, base, 29, 1)
        this.PutU8(set.records, base, 30, actionKind)
        this.PutI32(set.records, base, 32, -1)
        this.PutI32(set.records, base, 36, -1)
        this.PutI32(set.records, base, 40, 0)
        set.count += 1
        return true
    }

    static IsEmptyLiteral(expression) {
        value := this.ParseAhkString(expression, &ok)
        return ok && value = ""
    }

    ; Keep native hotkeys within the grammar accepted by the current core's
    ; parseRuntimeHotkeySpecText16. An ampersand is only treated as a hotkey
    ; grammar element when the source row is actually in SetupHotkeys. An
    ; explicit `j & k` row in SetupCombos is a combo and is parsed by the
    ; separate combo-family emitter.
    static CoreHotkeySpecShape(spec) {
        text := Trim(spec)
        if (SubStr(text, 1, 1) = "{" && SubStr(text, -1) = "}")
            text := Trim(SubStr(text, 2, StrLen(text) - 2))
        if (text = "" || InStr(StrLower(text), "wheel") || InStr(StrLower(text), "button"))
            return false
        if InStr(text, "&") {
            pieces := StrSplit(text, "&")
            if (pieces.Length < 2)
                return false
            Loop pieces.Length - 1 {
                prefix := Trim(pieces[A_Index])
                while (prefix != "" && InStr("~$*", SubStr(prefix, 1, 1)))
                    prefix := Trim(SubStr(prefix, 2))
                if (prefix = "" || InStr(StrLower(prefix), "wheel") || InStr(StrLower(prefix), "button"))
                    return false
            }
            text := Trim(pieces[pieces.Length])
        }
        while (text != "" && InStr("~$*", SubStr(text, 1, 1)))
            text := Trim(SubStr(text, 2))
        if (RegExMatch(text, "i)\s+up$") )
            text := Trim(SubStr(text, 1, -3))
        return text != ""
    }

    static EmitComboRecord(set, source) {
        elems := this.SourceRowElements(source)
        if (elems.Length < 3)
            return false
        primary := this.ElementString(elems[1], "", &primaryOk)
        secondary := this.ElementString(elems[2], "", &secondaryOk)
        if (!primaryOk || !secondaryOk)
            return false
        if (elems.Length = 3) {
            context := "global"
            actionExpression := elems[3]
            mode := "sendkeydirect"
            mod := ""
            suspendExempt := false
        } else {
            context := this.ContextExpression(elems[3], "", &contextOk)
            if !contextOk
                return false
            actionExpression := elems[4]
            mode := elems.Length >= 5 ? Trim(elems[5]) : ""
            mod := elems.Length >= 6 ? this.ElementString(elems[6], "", &modOk) : ""
            if (elems.Length >= 6 && !modOk)
                return false
            suspendExempt := elems.Length >= 7 && (StrLower(Trim(elems[7])) = "true" || Trim(elems[7]) = "1")
        }
        target := this.ParseDirectAction(actionExpression, &actionOk)
        if !actionOk
            return false
        mode := (StrLower(mode) = "instant") ? "sendkeydirectinstant" : "sendkeydirect"
        base := this.ReserveRecord(set.records, 56)
        this.AddText(set, primary, &primaryOffset, &primaryLength)
        this.AddText(set, secondary, &secondaryOffset, &secondaryLength)
        this.AddText(set, target, &targetOffset, &targetLength)
        this.AddText(set, mode, &modeOffset, &modeLength)
        this.AddText(set, mod, &modOffset, &modLength)
        this.AddText(set, context, &contextOffset, &contextLength)
        this.PutU32(set.records, base, 0, primaryOffset)
        this.PutU16(set.records, base, 4, primaryLength)
        this.PutU32(set.records, base, 8, secondaryOffset)
        this.PutU16(set.records, base, 12, secondaryLength)
        this.PutI32(set.records, base, 16, -1)
        this.PutU32(set.records, base, 20, targetOffset)
        this.PutU16(set.records, base, 24, targetLength)
        this.PutU32(set.records, base, 28, modeOffset)
        this.PutU16(set.records, base, 32, modeLength)
        this.PutU32(set.records, base, 36, modOffset)
        this.PutU16(set.records, base, 40, modLength)
        this.PutU8(set.records, base, 42, suspendExempt ? 1 : 0)
        this.PutU32(set.records, base, 44, contextOffset)
        this.PutU16(set.records, base, 48, contextLength)
        set.count += 1
        return true
    }

    static EmitChordRecord(set, source) {
        elems := this.SourceRowElements(source)
        if (elems.Length < 3 || elems.Length - 2 > 5)
            return false
        context := this.ContextExpression(elems[elems.Length - 1], "", &contextOk)
        if !contextOk
            return false
        target := this.ParseDirectAction(elems[elems.Length], &actionOk)
        if !actionOk
            return false
        base := this.ReserveRecord(set.records, 80)
        Loop 5 {
            keyIndex := A_Index
            if (keyIndex > elems.Length - 2)
                break
            key := this.ElementString(elems[keyIndex], "", &keyOk)
            if !keyOk
                return false
            this.AddText(set, key, &keyOffset, &keyLength)
            this.PutU32(set.records, base, (keyIndex - 1) * 8, keyOffset)
            this.PutU16(set.records, base, (keyIndex - 1) * 8 + 4, keyLength)
        }
        this.AddText(set, target, &targetOffset, &targetLength)
        this.AddText(set, "sendkeydirect", &modeOffset, &modeLength)
        this.AddText(set, "", &modOffset, &modLength)
        this.AddText(set, context, &contextOffset, &contextLength)
        this.PutI32(set.records, base, 40, -1)
        this.PutU32(set.records, base, 44, targetOffset)
        this.PutU16(set.records, base, 48, targetLength)
        this.PutU32(set.records, base, 52, modeOffset)
        this.PutU16(set.records, base, 56, modeLength)
        this.PutU32(set.records, base, 60, modOffset)
        this.PutU16(set.records, base, 64, modLength)
        this.PutU32(set.records, base, 68, contextOffset)
        this.PutU16(set.records, base, 72, contextLength)
        set.count += 1
        return true
    }

    static EmitZigByteArray(bytes) {
        text := "[_]u8{"
        for index, value in bytes
            text .= (index = 1 ? "" : ", ") value
        return text "};"
    }

    static EmitZigU16Array(values) {
        text := "[_]u16{"
        for index, value in values
            text .= (index = 1 ? "" : ", ") value
        return text "};"
    }

    static RotateShortcutBackups() {
        ; Keep exactly three recoverable generations: .backup.1 through .backup.3.
        fourth := this.compiledShortcutZigPath ".backup.4"
        if FileExist(fourth)
            this.DeleteIfExists(fourth)
        for index in [2, 1] {
            from := this.compiledShortcutZigPath ".backup." index
            to := this.compiledShortcutZigPath ".backup." (index + 1)
            if FileExist(from) {
                if FileExist(to)
                    this.DeleteIfExists(to)
                ; Copy-then-delete is more tolerant of OneDrive's delayed
                ; rename state than FileMove while preserving the backup.
                FileCopy(from, to, 1)
                this.DeleteIfExists(from)
            }
        }
        if FileExist(this.compiledShortcutZigPath)
            FileCopy(this.compiledShortcutZigPath, this.compiledShortcutZigPath ".backup.1", 1)
        this.DeleteIfExists(this.compiledShortcutZigPath)
    }

    static VerifyShortcutBackupRotation() {
        tempDir := A_Temp "\\qmk_compiled_shortcut_backup_probe_" A_TickCount
        oldPath := this.compiledShortcutZigPath
        this.compiledShortcutZigPath := tempDir "\\generated_user_shortcuts.zig"
        try {
            DirCreate(tempDir)
            FileAppend("current", this.compiledShortcutZigPath, "UTF-8-RAW")
            FileAppend("backup1", this.compiledShortcutZigPath ".backup.1", "UTF-8-RAW")
            FileAppend("backup2", this.compiledShortcutZigPath ".backup.2", "UTF-8-RAW")
            FileAppend("backup3", this.compiledShortcutZigPath ".backup.3", "UTF-8-RAW")
            FileAppend("backup4", this.compiledShortcutZigPath ".backup.4", "UTF-8-RAW")
            this.RotateShortcutBackups()
            if FileExist(this.compiledShortcutZigPath)
                throw Error("backup rotation left the active generated file in place.")
            if FileExist(this.compiledShortcutZigPath ".backup.4")
                throw Error("backup rotation retained a fourth generation.")
            expected := Map(
                ".backup.1", "current",
                ".backup.2", "backup1",
                ".backup.3", "backup2"
            )
            for suffix, value in expected {
                path := this.compiledShortcutZigPath suffix
                if !FileExist(path) || FileRead(path, "UTF-8") != value
                    throw Error("backup rotation produced incorrect content for " suffix ".")
            }
        } finally {
            this.compiledShortcutZigPath := oldPath
            if DirExist(tempDir)
                DirDelete(tempDir, true)
        }
    }

    static WriteTextFile(path, text) {
        if FileExist(path)
            this.DeleteIfExists(path)
        FileAppend(text, path, "UTF-8-RAW")
    }

    static DecodeCollectorField(value) {
        ; Decode the collector transport one escape at a time. This preserves
        ; literal sequences such as `\n` and `\t` in user source text.
        result := ""
        pos := 1
        length := StrLen(value)
        while (pos <= length) {
            ch := SubStr(value, pos, 1)
            if (ch = "\" && pos < length) {
                next := SubStr(value, pos + 1, 1)
                if (next = "n") {
                    result .= "`n"
                    pos += 2
                    continue
                }
                if (next = "t") {
                    result .= "`t"
                    pos += 2
                    continue
                }
                if (next = "\") {
                    result .= "\"
                    pos += 2
                    continue
                }
            }
            result .= ch
            pos += 1
        }
        return result
    }

    static EscapeZigString(value) {
        ; Backslash is ordinary data in AHK strings. Build Zig escapes with
        ; Chr(92) so a quote is emitted as \" (one slash), not \\" (two).
        slash := Chr(92)
        value := StrReplace(value, slash, slash slash)
        value := StrReplace(value, Chr(34), slash Chr(34))
        value := StrReplace(value, "`r", slash "r")
        value := StrReplace(value, "`n", slash "n")
        return value
    }

    static ComputeShortcutBuildId(paths) {
        hash := 2166136261
        for , path in paths {
            text := path "`n" FileRead(path, "UTF-8")
            for , ch in StrSplit(text) {
                hash := Mod((hash ^ Ord(ch)) * 16777619, 4294967296)
            }
        }
        return Format("{:08X}", hash)
    }

    static SetStep(text) {
        if this.stepCtl
            this.stepCtl.Value := text
        if this.tooltipEnabled
            ToolTip(text)
        this.WriteStatus("progress", text)
    }

    static SetProgress(pct) {
        pct := Round(Max(0, Min(100, pct)))
        if this.progressCtl
            this.progressCtl.Value := pct
        if this.pctCtl
            this.pctCtl.Value := pct "%"
        this.WriteStatus("progress", "", "", pct)
    }

    ; ------------------------------------------------------------- progress

    static BeginStep(index) {
        this.stepIndex := index
        step := this.steps[index]
        before := 0
        Loop index - 1
            before += this.steps[A_Index].w
        this.bandStart := before
        this.bandEnd := before + step.w
        this.stepStartTick := A_TickCount
        this.stepExpected := step.exp
        this.SetStep("Step " index " of " this.steps.Length ": " step.label)
        this.Log("")
        this.Log("=== [" index "/" this.steps.Length "] " step.label " ===")
        this.SetProgress(this.bandStart)
    }

    static BeginNextStep() {
        this.BeginStep(this.stepIndex + 1)
    }

    ; Creeps toward the end of the step's band so the bar keeps moving during a
    ; long compile without ever overshooting into the next step.
    static TickProgress() {
        elapsed := A_TickCount - this.stepStartTick
        frac := 1 - Exp(-1.0 * elapsed / this.stepExpected)
        this.SetProgress(this.bandStart + (this.bandEnd - this.bandStart) * frac)
    }

    static EndStep() {
        this.SetProgress(this.bandEnd)
    }

    ; --------------------------------------------------------------- runner

    static RequestCancel() {
        if !this.running
            return
        this.cancelRequested := true
        this.Log("")
        this.Log("*** Cancel requested ***")
        if (this.activePid && ProcessExist(this.activePid)) {
            try RunWait(A_ComSpec ' /d /s /c taskkill /T /F /PID ' this.activePid, , "Hide")
        }
    }

    ; Runs a command hidden, streaming stdout+stderr into the log pane.
    ; A batch wrapper is used so %ERRORLEVEL% is captured per line correctly.
    static RunHidden(command, workingDir) {
        id := ++this.stepSeq
        base := A_Temp "\qmk_pgo2_" id
        logFile := base ".log"
        exitFile := base ".exit"
        batFile := base ".bat"
        for f in [logFile, exitFile, batFile]
            this.DeleteIfExists(f)

        bat := "@echo off`r`n"
            . "chcp 65001 >nul`r`n"
            . "cd /d " this.Quote(workingDir) "`r`n"
            . command " > " this.Quote(logFile) " 2>&1`r`n"
            ; Some Windows environments expand %ERRORLEVEL% to an empty value.
            ; Use the conditional form so the completion marker is always a
            ; nonempty, unambiguous 0 or 1.
            . "if errorlevel 1 (echo 1 >" this.Quote(exitFile) ") else (echo 0 >" this.Quote(exitFile) ")`r`n"
        FileAppend(bat, batFile, "UTF-8-RAW")

        this.Log("$ " command)
        pid := 0
        Run(A_ComSpec ' /d /s /c "' batFile '"', workingDir, "Hide", &pid)
        this.activePid := pid

        lastLen := 0
        startedAt := A_TickCount
        ; The shell can hand off the batch file to a child process before its
        ; own PID disappears, and Windows may reuse that PID for an unrelated
        ; process. The batch writes the marker only after the child exits, so
        ; the marker is the authoritative completion signal. Do not also wait
        ; on the original cmd.exe PID: that can strand the pipeline forever
        ; after a successful trainer/merge command (often visible as 59%).
        while !FileExist(exitFile) || FileGetSize(exitFile) < 1 {
            if this.cancelRequested {
                this.activePid := 0
                throw Error("Build cancelled.")
            }
            lastLen := this.PumpLog(logFile, lastLen)
            this.TickProgress()
            Sleep(120)
            if (A_TickCount - startedAt > 3600000)
                throw Error("Compiler command timed out while waiting for its exit marker.")
        }
        lastLen := this.PumpLog(logFile, lastLen)
        this.activePid := 0

        ; CMD can create the marker before releasing its file handle. Retry the
        ; read briefly so a successful `0` is not mistaken for a failed build.
        code := 1
        readDeadline := A_TickCount + 10000
        rawExitText := ""
        while (A_TickCount <= readDeadline) {
            try {
                rawExitText := Trim(FileRead(exitFile), " `t`r`n")
                if RegExMatch(rawExitText, "^-?\d+$") {
                    code := Integer(rawExitText)
                    break
                }
            } catch {
                Sleep(50)
            }
            Sleep(50)
        }
        if (code != 0 && rawExitText != "")
            this.Log("Compiler exit marker read as: [" rawExitText "]")
        if (this.cancelRequested)
            code := 1223

        if (this.cancelRequested) {
            for f in [logFile, exitFile, batFile]
                this.DeleteIfExists(f)
            throw Error("Build cancelled.")
        }
        if (code = 0) {
            for f in [logFile, exitFile, batFile]
                this.DeleteIfExists(f)
        } else {
            ; Preserve the failed command's complete compiler diagnostic.
            this.Log("Compiler diagnostic log retained: " logFile)
        }
        return code
    }

    static PumpLog(path, lastLen) {
        if !FileExist(path)
            return lastLen
        text := ""
        try text := FileRead(path, "UTF-8")
        catch {
            try text := FileRead(path, "CP0")
            catch
                return lastLen
        }
        len := StrLen(text)
        if (len > lastLen)
            this.LogRaw(SubStr(text, lastLen + 1))
        return len
    }

    static RunStep(command, workingDir, failLabel) {
        code := this.RunHidden(command, workingDir)
        if (code != 0)
            throw Error(failLabel " failed with exit code " code)
        return code
    }

    ; ------------------------------------------------------------- pipeline

    static PipelineSteps() {
        return [
            { label: "Emit training LLVM IR (Zig)",       w: 17, exp: 12000 },
            { label: "Compile instrumented training DLL", w: 20, exp: 14000 },
            { label: "Verify + embed training DLL",       w: 5,  exp: 3000 },
            { label: "Prepare synthetic PGO trainer",     w: 6,  exp: 5000 },
            { label: "Run synthetic PGO trainer",         w: 11, exp: 8000 },
            { label: "Merge PGO profiles",                w: 4,  exp: 2000 },
            { label: "Emit final LLVM IR (Zig)",          w: 16, exp: 12000 },
            { label: "Compile final PGO runtime DLL",     w: 17, exp: 14000 },
            { label: "Verify + embed final DLL",          w: 4,  exp: 3000 }
        ]
    }

    static QuickPipelineSteps() {
        return [
            { label: "Emit final LLVM IR (Zig)",      w: 35, exp: 12000 },
            { label: "Compile final PGO runtime DLL", w: 55, exp: 14000 },
            { label: "Verify + embed final DLL",      w: 10, exp: 3000 }
        ]
    }

    static MergeAndFinalPipelineSteps() {
        return [
            { label: "Merge PGO profiles",            w: 10, exp: 2000 },
            { label: "Emit final LLVM IR (Zig)",      w: 30, exp: 12000 },
            { label: "Compile final PGO runtime DLL", w: 50, exp: 14000 },
            { label: "Verify + embed final DLL",      w: 10, exp: 3000 }
        ]
    }

    static ZigOnlyPipelineSteps() {
        return [
            { label: "Compile runtime DLL with Zig", w: 85, exp: 18000 },
            { label: "Verify + embed final DLL",     w: 15, exp: 3000 }
        ]
    }

    static ProfileDataPath() {
        return this.trainingDir "\qmk_pgo.profdata"
    }

    static HasMergedProfileData() {
        return FileExist(this.ProfileDataPath()) ? true : false
    }

    static HasRawProfileData() {
        Loop Files this.trainingDir "\qmk_pgo_*.profraw", "F"
            return true
        return false
    }

    static ResolveRunMode(requestedMode := "full") {
        if (requestedMode = "zig")
            return "zig"
        if (requestedMode = "quick")
            return "quick"
        return "full"
    }

    static ModeLabel(mode) {
        switch mode {
            case "zig": return "Zig-only compile + embed"
            case "quick": return "quick compile"
            case "merge-final": return "merge + final compile"
            default: return "full PGO train + final embed"
        }
    }

    static StepsForMode(mode) {
        switch mode {
            case "zig": return this.ZigOnlyPipelineSteps()
            case "quick": return this.QuickPipelineSteps()
            case "merge-final": return this.MergeAndFinalPipelineSteps()
            default: return this.PipelineSteps()
        }
    }

    static RunPipelineMode(mode) {
        switch mode {
            case "zig":
                this.ZigOnlyCompileAndEmbed()
            case "quick":
                this.QuickCompileFromMergedProfile()
            case "merge-final":
                this.MergeProfilesAndCompileFinal()
            default:
                this.TrainAndEmbedFinalPgo()
        }
    }

    static StartPipeline(requestedMode := "full") {
        if (this.running)
            return
        if (this.cliModeOverride = "saved")
            mode := this.ResolveRunMode(StrLower(this.ReadSetting("Compiler", "lastBuildMode", "zig")))
        else if (this.cliModeOverride != "")
            mode := this.ResolveRunMode(this.cliModeOverride)
        else
            mode := this.ResolveRunMode(requestedMode)
        this.RememberLastBuildMode(mode)
        try this.Preflight(mode)
        catch Error as err {
            MsgBox(err.Message, "QMK Compiler - Preflight", "Icon!")
            return
        }
        this.running := true
            this.cancelRequested := false
            this.startBtn.Enabled := false
            if this.quickBtn
                this.quickBtn.Enabled := false
        this.cancelBtn.Enabled := true
        this.logCtl.Value := ""
        this.logLines := []
        this.SetProgress(0)

        this.stepIndex := 0
        this.steps := this.StepsForMode(mode)

        started := A_TickCount
        try {
            this.Log("Selected mode: " this.ModeLabel(mode))
            this.RunPipelineMode(mode)
            this.SetProgress(100)
            secs := Round((A_TickCount - started) / 1000, 1)
            this.SetStep("Done in " secs "s. Final DLL embedded in QMKCore.")
            this.Log("")
            this.Log("=== " this.ModeLabel(mode) " complete in " secs "s ===")
            this.Log("QMKconfig.ini was not changed. Reload Macropad to pick up the new DLL.")
        } catch Error as err {
            this.SetStep("FAILED: " err.Message)
            this.Log("")
            this.Log("*** ERROR: " err.Message " ***")
            if !this.cancelRequested
                MsgBox(err.Message, "QMK Compiler", "Icon!")
        } finally {
            this.compiledShortcutBuildActive := false
            this.running := false
            this.cancelRequested := false
            this.startBtn.Enabled := true
            if this.quickBtn
                this.quickBtn.Enabled := true
            this.cancelBtn.Enabled := false
        }
    }

    static RunCliPipeline(requestedMode := "full") {
        logPath := this.projectRoot "\_CURRENT\pgo_cli_build_log.txt"
        this.DeleteIfExists(logPath)
        if (this.cliModeOverride = "saved")
            mode := this.ResolveRunMode(StrLower(this.ReadSetting("Compiler", "lastBuildMode", "zig")))
        else if (this.cliModeOverride != "")
            mode := this.ResolveRunMode(this.cliModeOverride)
        else
            mode := this.ResolveRunMode(requestedMode)
        this.stepIndex := 0
        this.steps := this.StepsForMode(mode)
        started := A_TickCount
        this.WriteStatus("start", "Starting " this.ModeLabel(mode) ".")
        try {
            this.Preflight(mode)
            this.Log("=== CLI " this.ModeLabel(mode) " started ===")
            this.RunPipelineMode(mode)
            secs := Round((A_TickCount - started) / 1000, 1)
            this.Log("")
            this.Log("=== " this.ModeLabel(mode) " complete in " secs "s ===")
            this.Log("QMKconfig.ini was not changed. Reload Macropad to pick up the new DLL.")
            for line in this.logLines
                FileAppend(line, logPath, "UTF-8")
            this.WriteStatus("complete", "Build completed in " secs "s.", "success", 100)
            return 0
        } catch Error as err {
            this.Log("")
            this.Log("*** ERROR: " err.Message " ***")
            for line in this.logLines
                FileAppend(line, logPath, "UTF-8")
            this.WriteStatus("complete", err.Message, "failure")
            return 1
        } finally {
            this.compiledShortcutBuildActive := false
        }
    }

    ; Rebuild using the saved compiler settings and the selected last-build
    ; mode.  An explicit mode is useful to callers that want a deterministic
    ; Zig-only or PGO rebuild; omitting it means "the last mode used".
    static RunLastBuildPipeline(modeOverride := "") {
        mode := modeOverride != ""
            ? this.ResolveRunMode(modeOverride)
            : this.ResolveRunMode(StrLower(this.ReadSetting("Compiler", "lastBuildMode", "zig")))
        this.Log("Recompiling with saved " (mode = "full" ? "PGO" : "Zig") " settings.")
        return this.RunCliPipeline(mode)
    }

    static RememberLastBuildMode(mode) {
        IniWrite(mode, this.settingsPath, "Compiler", "lastBuildMode")
    }

    static Preflight(mode) {
        ; The GUI buttons select only the build mode.  All compiler inputs
        ; must come from the saved INI at the moment the build starts, so
        ; paths and flags changed by another settings window or process are
        ; never shadowed by stale in-memory values.
        this.ReloadResolvedPaths()
        this.ValidateBuildSettings()
        if (mode = "zig")
            this.RequireZigOnlyToolchain()
        else
            this.RequireToolchain()
        ; The saved Compiler User Shortcuts settings are the only source of
        ; automatic generation.  Generate once before the selected build, then
        ; the pipeline reuses the exact emitted bundle for every compile stage.
        ; Reload this section immediately before compiling so a prior in-memory
        ; mode or source list can never override the saved QMKconfig.ini.
        this.LoadShortcutSourceFiles()
        if this.cliSourceOverride {
            this.shortcutSourceFiles := this.cliSourceFiles.Clone()
            for , path in this.shortcutSourceFiles
                if !FileExist(path)
                    throw Error("CLI shortcut source not found: " path)
            this.shortcutUseGeneratedInclude := true
        }
        if (this.cliShortcutIncludeOverride != "")
            this.shortcutUseGeneratedInclude := this.cliShortcutIncludeOverride = "1"
        if (this.cliCallbackModeOverride != "")
            this.shortcutCallbackOutputMode := this.cliCallbackModeOverride
        if (this.cliCallbackPathOverride != "")
            this.shortcutCallbackCustomPath := this.cliCallbackPathOverride
        this.RefreshCallbackOutputPath()
        this.WriteStatus("preflight", "Settings loaded from QMKconfig.ini immediately before build.")
        this.ResolveCompiledShortcutBuild(true)
    }

    static ResolveCompiledShortcutBuild(regenerate := false) {
        if (!this.shortcutUseGeneratedInclude) {
            this.compiledShortcutBuildActive := false
            return false
        }
        if regenerate {
            this.Log("Generated shortcut include enabled; regenerating from saved Compiler User Shortcuts settings.")
            this.CaptureUserShortcutFiles(false)
        }
        ; Never let a checked GUI reminder silently select a stale or partial
        ; artifact. The complete pair is validated before any IR is emitted.
        this.ValidateGeneratedShortcutBundle()
        return true
    }

    static TrainAndEmbedFinalPgo() {
        this.RequireToolchain()
        useCompiled := this.ResolveCompiledShortcutBuild()
        DirCreate(this.trainingDir)

        ; LLVM profile-use requires the instrumented training DLL and the final DLL
        ; to share comptime control-flow shape. The blank module is used by
        ; default; when the user explicitly enables the generated include, both
        ; builds use that same generated module. QMKCorePGOTrainer exercises the
        ; resulting runtime path.
        irTrain := this.trainingDir "\QMKCore_pgo_train.ll"
        tempTrainingDll := this.libDir "\QMKTrainingData.pgo.building.dll"
        this.DeleteIfExists(irTrain)
        this.DeleteIfExists(tempTrainingDll)
        this.DeleteIfExists(this.libDir "\QMKTrainingData.lib")
        this.DeleteIfExists(this.libDir "\QMKTrainingData.pdb")
        this.DeleteIfExists(this.libDir "\QMKTrainingData.pgo.building.lib")
        this.DeleteIfExists(this.libDir "\QMKTrainingData.pgo.building.pdb")
        this.Log("Compiled shortcut selection: " (useCompiled ? "ENABLED" : "DISABLED"))
        this.WriteBuildOptions(true, true, false, false, false, useCompiled)
        this.BeginStep(1)
        this.Log("Training IR root: " this.sourcePath)
        this.Log(useCompiled
            ? "Compiled user-shortcuts data included in build_options_pgo.zig: " this.compiledShortcutZigPath
            : "No compiled user-shortcuts data included in build_options_pgo.zig.")
        this.RunBuildScriptIr(irTrain, "Zig training IR build")
        this.EndStep()

        this.BeginStep(2)
        this.RunStep(this.ClangInstrumentCommand(irTrain, tempTrainingDll), this.libDir, "Clang instrumented training DLL build")
        this.EndStep()
        this.BeginStep(3)
        this.VerifyRequiredExports(tempTrainingDll)
        this.AtomicReplaceFile(tempTrainingDll, this.trainingDllPath, "QMKTrainingData.dll")
        this.DeleteIfExists(this.libDir "\QMKTrainingData.pgo.building.lib")
        this.DeleteIfExists(this.libDir "\QMKTrainingData.pgo.building.pdb")
        this.VerifyRequiredExports(this.trainingDllPath)
        flags := this.GetBuildFeatureFlags(this.trainingDllPath)
        this.Log("Training DLL flags: " Format("0x{:08X}", flags))
        this.Log("Training DLL written to disk; runtime payload remains QMKCore.")
        this.EndStep()

        this.BeginStep(4)
        this.EnsurePgoTrainerFresh()
        this.DeleteIfExists(this.syntheticProfilePath)
        this.EndStep()

        this.BeginStep(5)
        this.Log("Replaying the 500-round traces plus the 2,000,000-event solo burst...")
        this.RunStep(this.Quote(this.trainerExePath) " " this.Quote(this.trainingDllPath) " " this.Quote(this.syntheticProfilePath), this.libDir, "PGO trainer run")
        this.RequireFile(this.syntheticProfilePath, "synthetic PGO profile")
        this.EndStep()

        profdata := this.ProfileDataPath()
        rsp := this.trainingDir "\qmk_pgo_inputs.rsp"

        this.MergeProfiles(profdata, rsp, true)
        this.CompileFinalFromProfile(profdata, useCompiled)
    }

    static QuickCompileFromMergedProfile() {
        this.RequireToolchain()
        useCompiled := this.ResolveCompiledShortcutBuild()
        DirCreate(this.trainingDir)
        profdata := this.ProfileDataPath()
        this.RequireFile(profdata, "merged PGO profile data")
        this.Log("Reusing merged PGO profile data: " profdata)
        this.CompileFinalFromProfile(profdata, useCompiled)
    }

    static MergeProfilesAndCompileFinal() {
        this.RequireToolchain()
        useCompiled := this.ResolveCompiledShortcutBuild()
        DirCreate(this.trainingDir)
        profdata := this.ProfileDataPath()
        rsp := this.trainingDir "\qmk_pgo_inputs.rsp"
        this.MergeProfiles(profdata, rsp, true)
        this.CompileFinalFromProfile(profdata, useCompiled)
    }

    static ZigOnlyCompileAndEmbed() {
        this.RequireZigOnlyToolchain()
        useCompiled := this.ResolveCompiledShortcutBuild()
        tempDll := this.libDir "\QMKCoreProfiling.zigonly.building.dll"
        ; Keep this build isolated from other Zig jobs that share lib\zig-out.
        ; A shared install filename can disappear between a successful Zig exit
        ; and RequireFile when another build cleans or reuses zig-out.
        stageDir := this.libDir "\zig-out\qmkcompiler_zigonly"
        stagePrefix := ".\zig-out\qmkcompiler_zigonly"
        buildOutput := stageDir "\QMKCoreProfiling.zigonly.building.dll"
        DirCreate(stageDir)
        this.DeleteIfExists(tempDll)
        this.DeleteIfExists(buildOutput)
        this.DeleteIfExists(this.libDir "\QMKCoreProfiling.zigonly.building.lib")
        this.DeleteIfExists(this.libDir "\QMKCoreProfiling.zigonly.building.pdb")

        ; Keep the checked and unchecked paths on the same single build-options
        ; module. The unchecked state must still rewrite the wrapper so a
        ; previous compiled import cannot remain selected accidentally.
        this.Log("Final compiled shortcut selection: " (useCompiled ? "ENABLED" : "DISABLED"))
        this.WriteBuildOptions(false, false, false, false, false, useCompiled)
        try {
            this.BeginStep(1)
            this.RunStep(this.ZigBuildCommand("dll", "QMKCoreProfiling.zigonly.building.dll", this.buildOptionsPath, stagePrefix),
                this.libDir, "Zig-only runtime DLL build")
            ; Zig can report a successful build before the install artifact is
            ; visible on OneDrive-backed paths. Retry the same authoritative
            ; build once instead of failing with a misleading "DLL not found".
            if !FileExist(buildOutput) {
                this.Log("Zig build returned success but the staged DLL is not visible; retrying the build once.")
                this.RunStep(this.ZigBuildCommand("dll", "QMKCoreProfiling.zigonly.building.dll", this.buildOptionsPath, stagePrefix),
                    this.libDir, "Zig-only runtime DLL retry")
            }
            this.RequireFile(buildOutput, "Zig-only build-script DLL")
            FileCopy(buildOutput, tempDll, true)
            this.DeleteIfExists(buildOutput)
            this.EndStep()
        } finally {
            this.compiledShortcutBuildActive := false
            this.DeleteIfExists(buildOutput)
            try DirDelete(stageDir, true)
        }

        this.BeginStep(2)
        this.VerifyRequiredExports(tempDll)
        flags := this.GetBuildFeatureFlags(tempDll)
        expectedFlags := useCompiled ? (1 << 7) : 0
        if (flags != expectedFlags)
            throw Error("Zig-only runtime flags do not match selected shortcut module. Expected " Format("0x{:08X}", expectedFlags) ", got " Format("0x{:08X}", flags))
        embedDllPath := this.finalDllPath
        replacedFinalDll := true
        try {
            this.AtomicReplaceFile(tempDll, this.finalDllPath, "QMKCoreProfiling.dll")
        } catch Error as err {
            replacedFinalDll := false
            embedDllPath := tempDll
            this.Log("QMKCoreProfiling.dll could not be replaced, probably because the running script has it loaded.")
            this.Log("Embedding staged DLL instead: " tempDll)
            this.Log("Replace failure: " err.Message)
        }
        this.DeleteIfExists(this.libDir "\QMKCoreProfiling.zigonly.building.lib")
        this.DeleteIfExists(this.libDir "\QMKCoreProfiling.zigonly.building.pdb")
        this.EmbedDll(embedDllPath, "QMKCore", expectedFlags)
        if replacedFinalDll
            this.DeleteIfExists(tempDll)
        this.Log("Embedded QMKCore from Zig-only build without changing QMKconfig.ini.")
        this.EndStep()
    }

    static MergeProfiles(profdata, rsp, deleteExisting := true) {
        this.BeginNextStep()
        ; The normal PGO run produces one authoritative profile.  Avoid the
        ; response-file enumeration here: on some OneDrive-backed folders the
        ; AHK Loop Files/FileAppend pair can stall after the trainer exits,
        ; leaving the progress bar permanently at 59% before llvm-profdata is
        ; even launched.
        profileInput := this.syntheticProfilePath
        this.RequireFile(profileInput, "synthetic PGO profile")
        if deleteExisting
            this.DeleteIfExists(profdata)
        this.RunStep(this.Quote(this.profdataPath) " merge -output=" this.Quote(profdata) " " this.Quote(profileInput), this.libDir, "llvm-profdata merge")
        this.EndStep()
    }

    static CompileFinalFromProfile(profdata, useCompiled := false) {
        irFinal := this.trainingDir "\QMKCore_pgo_final.ll"
        tempDll := this.libDir "\QMKCoreProfiling.pgo.building.dll"

        this.WriteBuildOptions(false, false, false, false, false, useCompiled)
        this.DeleteIfExists(irFinal)
        this.DeleteIfExists(tempDll)
        this.DeleteIfExists(this.libDir "\QMKCoreProfiling.pgo.building.lib")
        this.DeleteIfExists(this.libDir "\QMKCoreProfiling.pgo.building.pdb")

        this.BeginNextStep()
        this.RunBuildScriptIr(irFinal, "Zig final IR build")
        this.EndStep()

        this.BeginNextStep()
        this.RunStep(this.ClangFinalCommand(irFinal, profdata, tempDll), this.libDir, "Clang final PGO build")
        this.EndStep()
        this.BeginNextStep()
        this.VerifyRequiredExports(tempDll)
        flags := this.GetBuildFeatureFlags(tempDll)
        expectedFlags := useCompiled ? (1 << 7) : 0
        if (flags != expectedFlags)
            throw Error("Final PGO runtime flags do not match selected shortcut module. Expected " Format("0x{:08X}", expectedFlags) ", got " Format("0x{:08X}", flags))
        embedDllPath := this.finalDllPath
        replacedFinalDll := true
        try {
            this.AtomicReplaceFile(tempDll, this.finalDllPath, "QMKCoreProfiling.dll")
        } catch Error as err {
            replacedFinalDll := false
            embedDllPath := tempDll
            this.Log("QMKCoreProfiling.dll could not be replaced, probably because the running script has it loaded.")
            this.Log("Embedding staged DLL instead: " tempDll)
            this.Log("Replace failure: " err.Message)
        }
        this.DeleteIfExists(this.libDir "\QMKCoreProfiling.pgo.building.lib")
        this.DeleteIfExists(this.libDir "\QMKCoreProfiling.pgo.building.pdb")
        this.EmbedDll(embedDllPath, "QMKCore", expectedFlags)
        if replacedFinalDll
            this.DeleteIfExists(tempDll)
        this.Log("Embedded QMKCore without changing QMKconfig.ini.")
        this.EndStep()
    }

    ; -------------------------------------------------------------- commands

    static ExpectedBuildOptionsText(compileProfiling, compilePgo, microbench, hasShortcuts, hasHotstrings, hasCompiledUserShortcuts := false) {
        if hasCompiledUserShortcuts {
            this.RequireFile(this.compiledShortcutZigPath, "generated user_shortcuts.zig")
        }
        q := Chr(34)
        compiledShortcutImport := StrReplace(this.MakeRelativeToBase(this.compiledShortcutDir, this.libDir), "\", "/") "/generated_user_shortcuts.zig"
        return "pub const compile_with_profiling = " (compileProfiling ? "true" : "false") ";`n"
            . "pub const compile_with_pgo = " (compilePgo ? "true" : "false") ";`n"
            . "pub const microbenchdebug = " (microbench ? "true" : "false") ";`n"
            . "pub const has_qmk_shortcuts = " (hasShortcuts ? "true" : "false") ";`n"
            . "pub const has_qmk_hotstrings = " (hasHotstrings ? "true" : "false") ";`n"
            . "pub const import_user_shortcuts = " (hasCompiledUserShortcuts ? "true" : "false") ";`n"
            . "pub const has_compiled_user_shortcuts = " (hasCompiledUserShortcuts ? "true" : "false") ";`n"
            . (hasCompiledUserShortcuts
                ? "pub const user_shortcuts = @import(" q compiledShortcutImport q ");`n"
                : "pub const user_shortcuts = struct {};`n")
    }

    static WriteBuildOptions(compileProfiling, compilePgo, microbench, hasShortcuts, hasHotstrings, hasCompiledUserShortcuts := false) {
        this.compiledShortcutBuildActive := hasCompiledUserShortcuts
        text := this.ExpectedBuildOptionsText(compileProfiling, compilePgo, microbench, hasShortcuts, hasHotstrings, hasCompiledUserShortcuts)
        existing := ""
        if FileExist(this.buildOptionsPath) {
            try existing := FileRead(this.buildOptionsPath, "UTF-8")
            catch {
                existing := ""
            }
        }
        if (existing != text) {
            this.DeleteIfExists(this.buildOptionsPath)
            FileAppend(text, this.buildOptionsPath, "UTF-8-RAW")
            this.Log("Updated build_options_pgo.zig from expected compiler input.")
        } else {
            this.Log("build_options_pgo.zig already matches expected compiler input; write skipped.")
        }
    }

    static CompiledShortcutModulePath() {
        return this.compiledShortcutBuildActive ? this.compiledShortcutZigPath : this.blankShortcutModulePath
    }

    static ZigBuildCommand(step, outputName, buildOptionsPath := "", prefixDir := "") {
        if (buildOptionsPath = "")
            buildOptionsPath := this.buildOptionsPath
        SplitPath(buildOptionsPath, &optionsName, &optionsDir)
        if (optionsDir != this.libDir)
            throw Error("Build-script options must be located in the active lib directory.")
        command := this.Quote(this.zigPath) " build " step
            . this.ZigBuildOptimizationArgument()
            . " -Dtarget_profile=" this.targetProfile
            . " -Dlto=" (this.lto ? "true" : "false")
            . " -Domit_frame_pointer=" (this.omitFramePointer ? "true" : "false")
            . " -Dsingle_threaded=" (this.singleThreaded ? "true" : "false")
            . " -Dstack_check=" (this.stackCheck ? "true" : "false")
            . " -Dunwind_tables=" (this.unwindTables ? "true" : "false")
            . " -Doutput_name=" this.Quote(outputName)
            . " -Dbuild_options_path=" this.Quote(optionsName)
        if (prefixDir != "")
            command .= " --prefix " this.Quote(prefixDir)
        return command
    }

    static ZigBuildOptimizationArgument() {
        switch this.optimization {
            case "ReleaseFast": return " --release=fast"
            case "ReleaseSafe": return " --release=safe"
            case "ReleaseSmall": return " --release=small"
        }
        return ""
    }

    ; The build script is the authoritative Zig module boundary for IR too.
    ; Keep the existing pipeline paths, but obtain the IR through build.zig so
    ; build_options_pgo.zig is always the sole module input and the optional
    ; generated shortcut import is selected only by that file.
    static RunBuildScriptIr(irPath, failLabel) {
        buildScript := this.libDir "\\build.zig"
        this.RequireFile(buildScript, "Zig build script")
        SplitPath(irPath, &irName, &irDir)
        if (irDir = "")
            irDir := this.libDir
        if (irDir != this.trainingDir)
            throw Error("Build-script IR output must be placed in the training directory.")
        buildOutput := this.libDir "\\zig-out\\" irName
        this.DeleteIfExists(buildOutput)
        this.RunStep(this.ZigBuildCommand("-Dmode=pgo-ir", irName, this.buildOptionsPath), this.libDir, failLabel)
        this.RequireFile(buildOutput, "build-script LLVM IR")
        this.DeleteIfExists(irPath)
        FileCopy(buildOutput, irPath, true)
        this.RequireFile(irPath, "pipeline LLVM IR")
        this.DeleteIfExists(buildOutput)
    }

    static ZigTrainerCommand() {
        target := this.GetTargetConfig()
        return this.Quote(this.zigPath)
            . " build-exe " this.Quote(this.trainerSourcePath)
            . " -O " this.optimization " -target " target.zig
            . " -femit-bin=" this.Quote(this.trainerExePath)
    }

    static EnsurePgoTrainerFresh() {
        this.RequireFile(this.trainerSourcePath, "PGO trainer source")
        sourceHash := this.Sha256File(this.trainerSourcePath)
        savedHash := ""
        if FileExist(this.trainerHashPath) {
            try savedHash := Trim(FileRead(this.trainerHashPath, "UTF-8"))
        }

        if FileExist(this.trainerExePath) && (savedHash = sourceHash) {
            this.Log("PGO trainer is current (source SHA-256 " sourceHash ").")
            return
        }

        if !FileExist(this.trainerExePath)
            this.Log("PGO trainer executable is missing; rebuilding it before the training run.")
        else if (savedHash = "")
            this.Log("PGO trainer source hash marker is missing; rebuilding before the training run.")
        else
            this.Log("PGO trainer source changed; rebuilding before the training run.")

        this.RunStep(this.ZigTrainerCommand(), this.libDir, "PGO trainer rebuild")
        this.RequireFile(this.trainerExePath, "rebuilt PGO trainer")
        this.WriteTextFile(this.trainerHashPath, sourceHash Chr(10))
        this.Log("PGO trainer rebuilt and marked with source SHA-256 " sourceHash ".")
    }

    static ClangInstrumentCommand(irPath, dllPath) {
        return this.ClangBaseCommand("-fprofile-generate=" this.Quote(this.trainingDir), irPath, dllPath)
    }

    static ClangFinalCommand(irPath, profdata, dllPath) {
        return this.ClangBaseCommand("-fprofile-use=" this.Quote(profdata), irPath, dllPath)
    }

    static ClangBaseCommand(profileArg, irPath, dllPath) {
        target := this.GetTargetConfig()
        libs := this.GetWindowsLibPaths(target.libArch)
        return this.Quote(this.clangPath)
            . " " profileArg
            . " -mllvm -disable-vp " this.ClangOptimizationFlag() " -target " target.clang " -shared -fuse-ld=lld"
            . " -o " this.Quote(dllPath)
            . " " this.Quote(irPath)
            . " -Xlinker " this.Quote("/libpath:" libs.um)
            . " -Xlinker " this.Quote("/libpath:" libs.ucrt)
            . " -Xlinker " this.Quote("/libpath:" libs.vc)
            . " " this.Quote(libs.vc "\libcmt.lib")
            . " " this.Quote(libs.vc "\libvcruntime.lib")
            . " " this.Quote(libs.vc "\oldnames.lib")
            . " " this.Quote(libs.ucrt "\libucrt.lib")
            . " " this.Quote(libs.um "\ntdll.lib")
            . " " this.Quote(libs.um "\user32.lib")
            . " " this.Quote(libs.um "\kernel32.lib")
    }

    static WriteProfileResponseFile(rspPath) {
        this.DeleteIfExists(rspPath)
        count := 0
        Loop Files this.trainingDir "\qmk_pgo_*.profraw", "F" {
            FileAppend(this.Quote(A_LoopFileFullPath) "`n", rspPath, "UTF-8-RAW")
            count += 1
        }
        if (count == 0)
            throw Error("No qmk_pgo_*.profraw files found in " this.trainingDir ". Build/use the training DLL and save profile data first.")
        this.Log("Merging " count " profraw file(s).")
    }

    ; ---------------------------------------------------------------- embed

    static EmbedInterceptionDll() {
        if (this.running) {
            MsgBox("Wait for the current build to finish before embedding Interception.", "QMK Compiler", "Icon!")
            return
        }
        try {
            isX86 := this.targetProfile = "x86"
            dllPath := isX86 ? this.interceptionDllPath32 : this.interceptionDllPath64
            variableName := isX86 ? "interception32" : "interception64"
            this.Log("Embedding production Interception DLL: " dllPath)
            this.EmbedDllUnchecked(dllPath, variableName)
            this.Log("Embedded " variableName " into " this.variablesPath)
            MsgBox("The production Interception DLL is now embedded in QMKVariables.ahk.", "QMK Compiler", "Iconi")
        } catch Error as err {
            this.Log("*** ERROR: " err.Message " ***")
            MsgBox(err.Message, "QMK Compiler", "Icon!")
        }
    }

    static EmbedDll(dllPath, variableName, expectedFlags := 0) {
        this.BackupVariablesForRollback()
        this.RequireFile(dllPath, "DLL")
        this.RequireFile(this.variablesPath, "QMKVariables")
        this.VerifyRequiredExports(dllPath)
        flags := this.GetBuildFeatureFlags(dllPath)
        if (flags != expectedFlags)
            throw Error("DLL feature flags must be " Format("0x{:08X}", expectedFlags) ", got " Format("0x{:08X}", flags))
        dllBytes := FileRead(dllPath, "RAW")
        b64 := this.BufferToBase64(dllBytes)
        text := FileRead(this.variablesPath, "UTF-8")
        replacement := variableName " := `"`r`n    (`r`n" b64 "`r`n    )`""
        newText := this.ReplaceAssignmentBlock(text, variableName, replacement)
        this.AtomicWriteText(this.variablesPath, newText, "UTF-8-RAW")
    }

    static EmbedDllUnchecked(dllPath, variableName) {
        this.BackupVariablesForRollback()
        this.RequireFile(dllPath, "DLL")
        this.RequireFile(this.variablesPath, "QMKVariables")
        dllBytes := FileRead(dllPath, "RAW")
        b64 := this.BufferToBase64(dllBytes)
        text := FileRead(this.variablesPath, "UTF-8")
        replacement := variableName " := `"`r`n    (`r`n" b64 "`r`n    )`""
        newText := this.ReplaceAssignmentBlock(text, variableName, replacement)
        this.AtomicWriteText(this.variablesPath, newText, "UTF-8-RAW")
    }

    static BackupVariablesForRollback() {
        this.RequireFile(this.variablesPath, "QMKVariables")
        original := this.variablesPath ".original.bak"
        if !FileExist(original)
            FileCopy(this.variablesPath, original, true)
        this.Log("Rollback backup ready: " original)
    }

    static RestoreOriginalVariables() {
        if (this.running) {
            MsgBox("Wait for the current build to finish before restoring QMKVariables.ahk.", "QMK Compiler", "Icon!")
            return
        }
        backup := this.variablesPath ".original.bak"
        if !FileExist(backup) {
            MsgBox("No original QMKVariables backup exists yet. It will be created before the next embed.", "QMK Compiler", "Icon!")
            return
        }
        if (MsgBox("Restore the original QMKVariables.ahk? Current embedded data will be replaced.", "QMK Compiler", "YesNo Icon!") = "No")
            return
        try {
            FileCopy(backup, this.variablesPath, true)
            this.Log("Restored QMKVariables.ahk from " backup)
            MsgBox("Original QMKVariables.ahk restored.", "QMK Compiler", "Iconi")
        } catch Error as err {
            MsgBox("Could not restore QMKVariables.ahk:`n" err.Message, "QMK Compiler", "Icon!")
        }
    }

    static BufferToBase64(buf) {
        flags := 0x40000001
        chars := 0
        if !DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf.Ptr, "UInt", buf.Size, "UInt", flags, "Ptr", 0, "UInt*", &chars)
            throw Error("CryptBinaryToStringW size query failed")
        out := Buffer(chars * 2, 0)
        if !DllCall("crypt32\CryptBinaryToStringW", "Ptr", buf.Ptr, "UInt", buf.Size, "UInt", flags, "Ptr", out.Ptr, "UInt*", &chars)
            throw Error("CryptBinaryToStringW encode failed")
        return StrGet(out.Ptr, "UTF-16")
    }

    static ReplaceAssignmentBlock(text, variableName, replacement) {
        bounds := this.FindAssignmentBlock(text, variableName)
        return SubStr(text, 1, bounds.start - 1) replacement SubStr(text, bounds.after)
    }

    static FindAssignmentBlock(text, variableName) {
        start := InStr(text, variableName " := " Chr(34))
        if (!start)
            throw Error("Could not find assignment for " variableName)
        openParen := InStr(text, "(", false, start)
        if (!openParen)
            throw Error("Could not find opening payload marker for " variableName)
        close := InStr(text, ")" Chr(34), false, openParen)
        if (!close)
            throw Error("Could not find closing payload marker for " variableName)
        return { start: start, openParen: openParen, close: close, after: close + 2 }
    }

    ; --------------------------------------------------------------- checks

    static RequireToolchain() {
        this.ValidateBuildSettings()
        this.RequireFile(this.sourcePath, "QMKCore source")
        this.RequireFile(this.variablesPath, "QMKVariables")
        this.RequireFile(this.zigPath, "Zig compiler")
        this.RequireFile(this.clangPath, "Clang")
        this.RequireFile(this.profdataPath, "llvm-profdata")
        libs := this.GetWindowsLibPaths()
        for path in [libs.vc "\libcmt.lib", libs.vc "\libvcruntime.lib", libs.vc "\oldnames.lib", libs.ucrt "\libucrt.lib", libs.um "\ntdll.lib", libs.um "\user32.lib", libs.um "\kernel32.lib"]
            this.RequireFile(path, "link library")
    }

    static RequireZigOnlyToolchain() {
        this.ValidateBuildSettings()
        this.RequireFile(this.sourcePath, "QMKCore source")
        this.RequireFile(this.runtimeBuildOptionsPath, "runtime build options")
        this.RequireFile(this.variablesPath, "QMKVariables")
        this.RequireFile(this.zigPath, "Zig compiler")
    }

    static VerifyRequiredExports(dllPath) {
        hModule := DllCall("kernel32\LoadLibraryW", "Str", dllPath, "Ptr")
        if !hModule
            throw Error("LoadLibrary failed for " dllPath)
        try {
            for exportName in ["QMK_Paste", "QMK_GetBuildFeatureFlags", "QMK_DebugKeyNameCaseFoldOK", "QMK_SetStartupInputConfig", "QMK_SetInputBackend", "QMK_StartLLHook", "QMK_StopLLHook", "QMK_GetInputBackendStatus", "QMK_ShutdownNativeInput", "QMK_SetupHotkeys", "QMK_SetupHotkeyEntries", "QMK_SetupHotkeyCellEntries", "QMK_SetupHotstrings", "QMK_SetupHotstringEntries", "QMK_SetupHotstringCellEntries", "QMK_SetupTapHolds", "QMK_SetupTapHoldEntries", "QMK_SetupTapHoldCellEntries", "QMK_SetupContextActions", "QMK_SetupContextActionEntries", "QMK_SetupContextActionCellEntries", "QMK_SetupModifiers", "QMK_SetupModifierEntries", "QMK_SetupModifierCellEntries", "QMK_SetupCombos", "QMK_SetupComboEntries", "QMK_SetupComboCellEntries", "QMK_SetupChords", "QMK_SetupChordEntries", "QMK_SetupChordCellEntries", "QMK_SetCallbackSuspendExempt"] {
                if !DllCall("kernel32\GetProcAddress", "Ptr", hModule, "AStr", exportName, "Ptr")
                    throw Error("Missing required export: " exportName)
            }
            for exportName in [
                "QMK_SetupCombo", "QMK_SetupInstantCombo",
                "QMK_SetupInternalCombo", "QMK_SetupInternalCombos",
                "QMK_SetupInternalInstantCombo", "QMK_SetupInternalInstantCombos",
                "QMK_SetupInternalChord", "QMK_SetupInternalChords", "QMK_SetupChord",
                "QMK_SetupModifier", "QMK_SetupHold", "QMK_SetupDoubleTap",
                "QMK_SetupTapHold", "QMK_SetupTapHoldTuning",
                "QMK_SetupHotstringCallbackOptions", "QMK_SetupHotstringCallbackEx",
                "QMK_SetupHotstringCallback"
            ] {
                if DllCall("kernel32\GetProcAddress", "Ptr", hModule, "AStr", exportName, "Ptr")
                    throw Error("Stale export should be absent: " exportName)
            }
        } finally {
            DllCall("kernel32\FreeLibrary", "Ptr", hModule)
        }
    }

    static GetBuildFeatureFlags(dllPath) {
        hModule := DllCall("kernel32\LoadLibraryW", "Str", dllPath, "Ptr")
        if !hModule
            throw Error("LoadLibrary failed for " dllPath)
        try {
            proc := DllCall("kernel32\GetProcAddress", "Ptr", hModule, "AStr", "QMK_GetBuildFeatureFlags", "Ptr")
            if !proc
                throw Error("Missing required export: QMK_GetBuildFeatureFlags")
            return DllCall(proc, "UInt")
        } finally {
            DllCall("kernel32\FreeLibrary", "Ptr", hModule)
        }
    }

    static GetTargetConfig() {
        if (this.targetProfile = "x86")
            return { zig: "i386-windows-gnu", clang: "i386-pc-windows-msvc", libArch: "x86" }
        return { zig: "x86_64-windows-gnu", clang: "x86_64-pc-windows-msvc", libArch: "x64" }
    }

    static ClangOptimizationFlag() {
        switch this.optimization {
            case "Debug": return "-O0"
            case "ReleaseSmall": return "-Os"
            case "ReleaseSafe", "ReleaseFast": return "-O2"
        }
        return "-O2"
    }

    static ValidateBuildSettings() {
        if (this.targetProfile != "x64" && this.targetProfile != "x86")
            throw Error("Unsupported build target profile: " this.targetProfile)
        expectedPtrSize := this.targetProfile = "x64" ? 8 : 4
        if (A_PtrSize != expectedPtrSize)
            throw Error("The selected " this.targetProfile " build must be run by matching " this.targetProfile " AutoHotkey.")
    }

    static GetWindowsLibPaths(arch := "") {
        if (arch = "")
            arch := this.GetTargetConfig().libArch
        vcRoot := "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC"
        vc := this.FindNewestSubdirWithFile(vcRoot, "lib\" arch "\libcmt.lib") "\lib\" arch
        kitRoot := "C:\Program Files (x86)\Windows Kits\10\Lib"
        kit := this.FindNewestSubdirWithFile(kitRoot, "ucrt\" arch "\libucrt.lib")
        return { vc: vc, ucrt: kit "\ucrt\" arch, um: kit "\um\" arch }
    }

    static FindNewestSubdirWithFile(root, relativeFile) {
        best := ""
        bestTime := ""
        Loop Files root "\*", "D" {
            candidate := A_LoopFileFullPath "\" relativeFile
            if FileExist(candidate) && (best = "" || A_LoopFileTimeModified > bestTime) {
                best := A_LoopFileFullPath
                bestTime := A_LoopFileTimeModified
            }
        }
        if (best = "")
            throw Error("Could not find " relativeFile " under " root)
        return best
    }

    static RequireFile(path, label) {
        if !FileExist(path)
            throw Error(label " not found: " path)
    }

    static DeleteIfExists(path) {
        try {
            if FileExist(path)
                FileDelete(path)
        }
    }

    static AtomicWriteText(path, text, encoding := "UTF-8-RAW") {
        tmp := path ".tmp." A_TickCount "." Random(100000, 999999)
        this.DeleteIfExists(tmp)
        try {
            FileAppend(text, tmp, encoding)
            this.AtomicReplaceFile(tmp, path, path)
        } catch Error as err {
            this.DeleteIfExists(tmp)
            throw err
        }
    }

    static AtomicReplaceFile(sourcePath, targetPath, label := "") {
        this.RequireFile(sourcePath, label != "" ? label " staged replacement" : "staged replacement")
        flags := 0x1 | 0x8 ; MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH
        if !DllCall("kernel32\MoveFileExW", "Str", sourcePath, "Str", targetPath, "UInt", flags, "Int") {
            lastError := A_LastError
            throw Error("Atomic replace failed for " (label != "" ? label : targetPath) ". LastError=" lastError)
        }
    }

    static Quote(value) => '"' value '"'
}

; Compiler-only capture support for compiled user shortcuts.
;
; This file is deliberately not part of the Macropad include tree. The
; compiler creates a temporary capture script containing this class's stub
; QMK surface, includes the user-selected declaration files, and reads the
; emitted ROW/COUNT records. No DLL, hook, callback registration, or runtime
; QMK implementation is loaded during capture.

class QMKShortcutCollector {
    static rows := []
    static familyCounts := Map()

    static Reset() {
        this.rows := []
        this.familyCounts := Map()
    }

    ; Capture declarations without executing the selected files. This is the
    ; compiler boundary for arbitrary user files: only QMK.Setup... calls are
    ; inspected, and balanced delimiters keep commas inside nested arrays,
    ; strings, and callback expressions from becoming false row boundaries.
    static CaptureSourceFiles(paths, reportPath) {
        this.Reset()
        for , path in paths {
            try {
                source := FileRead(path, "UTF-8")
            } catch Error as err {
                throw Error("Could not read selected shortcut source:`n" path "`n`n" err.Message)
            }
            this.CaptureSource(source, path)
        }
        this.WriteReport(reportPath)
    }

    static CaptureSource(source, sourcePath := "") {
        pos := 1
        while (pos := this.FindNextSetupCall(source, pos, &family, &openPos)) {
            closePos := this.FindBalanced(source, openPos, "(", ")")
            if !closePos
                break
            callText := SubStr(source, openPos + 1, closePos - openPos - 1)
            this.CaptureCallRows(family, callText, sourcePath)
            pos := closePos + 1
        }
    }

    ; Find setup calls only in code. A regex over the whole source would also
    ; collect examples in comments and quoted strings, which would silently
    ; change the generated row set.
    static FindNextSetupCall(text, start, &family, &openPos) {
        quote := false
        pos := start
        length := StrLen(text)
        while (pos <= length) {
            ch := SubStr(text, pos, 1)
            if quote {
                if (ch = Chr(96)) {
                    pos += 2
                    continue
                }
                if (ch = Chr(34)) {
                    if (SubStr(text, pos + 1, 1) = Chr(34))
                        pos += 2
                    else {
                        quote := false
                        pos += 1
                    }
                    continue
                }
                pos += 1
                continue
            }
            if (ch = Chr(34)) {
                quote := true
                pos += 1
                continue
            }
            if (ch = ";") {
                newline := InStr(text, "`n", false, pos)
                pos := newline ? newline + 1 : length + 1
                continue
            }
            if ((ch = "Q" || ch = "q") && (pos = 1 || !RegExMatch(SubStr(text, pos - 1, 1), "[A-Za-z0-9_]"))) {
                ; Only the call prefix is needed here. Matching against the
                ; entire remaining source for every Q character makes large
                ; production files quadratic and can look like a hang.
                prefix := SubStr(text, pos, 256)
                if RegExMatch(prefix, "i)^QMK\.Setup([A-Za-z0-9_]+)\s*\(", &match) {
                    family := this.FamilyName(match[1])
                    openPos := pos + InStr(prefix, "(") - 1
                    return pos
                }
            }
            pos += 1
        }
        return 0
    }

    static FamilyName(name) {
        switch StrLower(name) {
            case "hotkeys": return "hotkeys"
            case "modifiers": return "modifiers"
            case "passthroughs": return "passthroughs"
            case "combos": return "combos"
            case "chords": return "chords"
            case "holds": return "holds"
            case "doubletaps": return "double_taps"
            case "taps": return "taps"
            case "tapholds": return "tap_holds"
            case "hotstrings": return "hotstrings"
            default: return "unsupported_" StrLower(name)
        }
    }

    static CaptureCallRows(family, callText, sourcePath := "") {
        start := 1
        while (start <= StrLen(callText) && InStr(" `t`r`n", SubStr(callText, start, 1)))
            start += 1
        if (SubStr(callText, start, 1) != "[") {
            this.AddRow(family, 0, "non_literal_collection")
            return
        }
        closePos := this.FindBalanced(callText, start, "[", "]")
        if !closePos {
            this.AddRow(family, 0, "unbalanced_collection")
            return
        }
        rows := this.SplitTopLevel(SubStr(callText, start + 1, closePos - start - 1))
        rowIndex := 0
        for , rowText in rows {
            if Trim(rowText, " `t`r`n") = ""
                continue
            normalizedRowText := this.NormalizeRowText(rowText)
            if (normalizedRowText = "")
                continue
            this.AddRow(family, rowIndex, this.ClassifySourceRow(family, normalizedRowText), sourcePath, normalizedRowText)
            rowIndex += 1
        }
        if (rowIndex = 0)
            this.AddRow(family, 0, "empty_collection")
    }

    ; A multiline collection often places section comments immediately before
    ; a row. Those comments are not part of the row expression and must not
    ; become a phantom array element for the typed emitter.
    static NormalizeRowText(rowText) {
        pos := 1
        length := StrLen(rowText)
        while (pos <= length) {
            while (pos <= length && InStr(" `t`r`n", SubStr(rowText, pos, 1)))
                pos += 1
            if (SubStr(rowText, pos, 1) != ";")
                break
            newline := InStr(rowText, "`n", false, pos)
            if !newline
                return ""
            pos := newline + 1
        }
        return Trim(SubStr(rowText, pos), " `t`r`n")
    }

    static ClassifySourceRow(family, rowText) {
        ; Hotstring replacement text is a literal payload even when the text
        ; itself contains words such as "QMK.PasteTextWithDll(...)".  Do not
        ; classify executable-looking text inside that quoted third element as
        ; a callback.  Inspect the top-level element instead.
        if (family = "hotstrings") {
            hotstringKind := this.ClassifyHotstringSourceRow(rowText)
            if (hotstringKind != "unknown")
                return hotstringKind
        }
        if (family = "taps" && !InStr(rowText, "=>") && (InStr(rowText, "QMK.SendKeyDirect") || InStr(rowText, "QMK.SendDirect")))
            return "native"
        if (family = "hotkeys" && this.HasNonLiteralTapAction(rowText))
            return "callback"
        if RegExMatch(rowText, "i)(=>|\bFunc\s*\(|\bQMK\.SuspendExempt\s*\()")
            return "callback"
        if (family = "hotkeys" && RegExMatch(rowText, "i)" Chr(34) "(?:panicExit|nativeReload|qmkPanicExit|qmkNativeReload)" Chr(34)))
            return "native_control"
        if RegExMatch(rowText, "i)\bQMK\.(SendKeyDirect|SendDirect)\s*\(")
            return "native"
        if (family = "modifiers" && !RegExMatch(rowText, "i)(\bQMK\.|=>|\bFunc\s*\()"))
            return "native"
        if (family = "passthroughs" && !RegExMatch(rowText, "i)(\bQMK\.|=>|\bFunc\s*\()"))
            return "native"
        if ((family = "holds" || family = "double_taps") && RegExMatch(rowText, "i)(=>|\bFunc\s*\()"))
            return "callback"
        if (family = "taps" && RegExMatch(rowText, "i)\bQMK\.(SendKeyDirect|SendDirect)\s*\("))
            return "native"
        if (family = "taps" && RegExMatch(rowText, "i)(=>|\bFunc\s*\()"))
            return "callback"
        if RegExMatch(rowText, "i)\bQMK\.Tap\s*\(")
            return "tap_descriptor"
        return "unknown"
    }

    static HasNonLiteralTapAction(rowText) {
        closePos := this.FindBalanced(rowText, 1, "[", "]")
        if !closePos
            return false
        elems := this.SplitTopLevel(SubStr(rowText, 2, closePos - 2))
        if (elems.Length < 3)
            return false
        action := Trim(elems[3], " `t`r`n")
        if !RegExMatch(action, "i)^QMK\.Tap\s*\(")
            return false
        openPos := InStr(action, "(")
        inner := LTrim(SubStr(action, openPos + 1), " `t`r`n")
        return SubStr(inner, 1, 1) != Chr(34)
    }

    static ClassifyHotstringSourceRow(rowText) {
        if (SubStr(Trim(rowText), 1, 1) != "[")
            return "unknown"
        closePos := this.FindBalanced(rowText, 1, "[", "]")
        if !closePos
            return "unknown"
        elems := this.SplitTopLevel(SubStr(rowText, 2, closePos - 2))
        if (elems.Length < 3)
            return "unknown"
        payload := Trim(elems[3], " `t`r`n")
        if (SubStr(payload, 1, 1) = Chr(34) && SubStr(payload, -1) = Chr(34))
            return "native"
        if RegExMatch(payload, "i)(=>|\bFunc\s*\(|\bQMK\.SuspendExempt\s*\()")
            return "callback"
        ; A function object reference such as Prompts.handoff is also a
        ; callback.  It must not be mistaken for an unknown literal row.
        if RegExMatch(payload, "i)^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+$")
            return "callback"
        return "unknown"
    }

    static SplitTopLevel(text) {
        parts := []
        start := 1
        pos := 1
        length := StrLen(text)
        square := 0
        paren := 0
        brace := 0
        quote := false
        while (pos <= length) {
            ch := SubStr(text, pos, 1)
            if quote {
                if (ch = Chr(96)) {
                    pos += 2
                    continue
                }
                if (ch = Chr(34)) {
                    if (SubStr(text, pos + 1, 1) = Chr(34))
                        pos += 2
                    else {
                        quote := false
                        pos += 1
                    }
                    continue
                }
                pos += 1
                continue
            }
            if (ch = Chr(34)) {
                quote := true
                pos += 1
                continue
            }
            if (ch = ";") {
                newline := InStr(text, "`n", false, pos)
                pos := newline ? newline + 1 : length + 1
                continue
            }
            switch ch {
                case "[": square += 1
                case "]": square := Max(0, square - 1)
                case "(": paren += 1
                case ")": paren := Max(0, paren - 1)
                case "{": brace += 1
                case "}": brace := Max(0, brace - 1)
            }
            if (ch = "," && square = 0 && paren = 0 && brace = 0) {
                parts.Push(SubStr(text, start, pos - start))
                start := pos + 1
            }
            pos += 1
        }
        parts.Push(SubStr(text, start))
        return parts
    }

    static FindBalanced(text, openPos, openChar, closeChar) {
        depth := 0
        quote := false
        pos := openPos
        while (pos <= StrLen(text)) {
            ch := SubStr(text, pos, 1)
            if quote {
                if (ch = Chr(96)) {
                    pos += 2
                    continue
                }
                if (ch = Chr(34)) {
                    if (SubStr(text, pos + 1, 1) = Chr(34))
                        pos += 1
                    else
                        quote := false
                }
            } else if (ch = Chr(34)) {
                quote := true
            } else if (ch = ";") {
                newline := InStr(text, "`n", false, pos)
                pos := newline ? newline : StrLen(text) + 1
                continue
            } else if (ch = openChar) {
                depth += 1
            } else if (ch = closeChar) {
                depth -= 1
                if (depth = 0)
                    return pos
            }
            pos += 1
        }
        return 0
    }

    static FindBalancedAt(text, pos) {
        ch := SubStr(text, pos, 1)
        if (ch = "[")
            return this.FindBalanced(text, pos, "[", "]")
        if (ch = "(")
            return this.FindBalanced(text, pos, "(", ")")
        if (ch = "{")
            return this.FindBalanced(text, pos, "{", "}")
        return 0
    }

    static SetupFamily(family, entries) {
        if !IsObject(entries) {
            this.AddRow(family, 0, "invalid_collection")
            return
        }
        for rowIndex, entry in entries
            this.AddRow(family, rowIndex, this.ClassifyEntry(entry))
    }

    static AddRow(family, rowIndex, kind, sourcePath := "", sourceText := "") {
        this.rows.Push({
            family: family,
            rowIndex: rowIndex,
            kind: kind,
            shape: this.FamilyShapeName(family),
            callbackCategory: this.CallbackCategory(kind),
            loweringStatus: "unlowered",
            loweringReason: this.LoweringReason(family, kind),
            sourcePath: sourcePath,
            sourceText: sourceText
        })
        if !this.familyCounts.Has(family)
            this.familyCounts[family] := 0
        this.familyCounts[family] += 1
    }

    static FamilyShapeName(family) {
        switch family {
            case "modifiers": return "Compiled_Modifiers.Row"
            case "passthroughs": return "Compiled_Passthroughs.Row"
            case "hotkeys": return "Compiled_Hotkeys.Row"
            case "holds": return "Compiled_Holds.Row"
            case "double_taps": return "Compiled_Double_Taps.Row"
            case "taps": return "Compiled_Hotkeys.Row"
            case "tap_holds": return "Compiled_Tap_Holds.Row"
            case "combos": return "Compiled_Combos.Row"
            case "chords": return "Compiled_Chords.Row"
            case "hotstrings": return "Compiled_Hotstrings.Row"
        }
        return "unsupported"
    }

    static CallbackCategory(kind) {
        return kind = "callback" ? "unclassified_callback" : "none"
    }

    static LoweringReason(family, kind) {
        if (SubStr(family, 1, 12) = "unsupported_")
            return "unsupported_setup_family"
        if (kind = "callback")
            return "callback_category_requires_lowering"
        if (kind = "native")
            return "native_row_requires_family_lowering"
        if (kind = "tap_descriptor")
            return "tap_descriptor_requires_family_lowering"
        return "source_row_requires_family_lowering"
    }

    static ClassifyEntry(entry) {
        if !IsObject(entry)
            return "invalid_row"

        action := ""
        for , value in entry {
            if IsObject(value) {
                if HasProp(value, "__qmk_capture_kind")
                    return value.__qmk_capture_kind
                if Type(value) = "Func"
                    return "callback"
            } else if Type(value) = "Func" {
                return "callback"
            } else if Type(value) = "String" {
                if (value = "panicExit" || value = "nativeReload")
                    return "native_control"
            }
            action := value
        }

        if (action != "" && Type(action) = "String")
            return "text_or_unknown"
        return "unknown"
    }

    static EmitReport() {
        FileAppend(this.ReportText(), "*", "UTF-8")
    }

    static ReportText() {
        text := ""
        for family, count in this.familyCounts
            text .= this.RecordLine("COUNT", family, count)
        for , row in this.rows
            text .= this.RecordLine("ROW", row.family, row.rowIndex, row.kind, row.sourcePath, row.sourceText, row.shape, row.callbackCategory, row.loweringStatus, row.loweringReason)
        text .= this.RecordLine("DONE", this.rows.Length, this.familyCounts.Count)
        return text
    }

    static WriteReport(outputPath) {
        if FileExist(outputPath)
            FileDelete(outputPath)
        FileAppend(this.ReportText(), outputPath, "UTF-8-RAW")
    }

    static RecordLine(type, values*) {
        fields := [type]
        for , value in values
            fields.Push(this.EncodeField(value))
        line := ""
        for , field in fields
            line .= (A_Index = 1 ? "" : "`t") field
        return line "`n"
    }

    static Emit(type, values*) {
        FileAppend(this.RecordLine(type, values*), "*", "UTF-8")
    }

    static EncodeField(value) {
        text := String(value)
        ; Escape the transport delimiter first so literal backslashes before
        ; n/t cannot be mistaken for our newline/tab escapes on decode.
        text := StrReplace(text, "\", "\\")
        text := StrReplace(text, "`r", "")
        text := StrReplace(text, "`n", "\n")
        text := StrReplace(text, "`t", "\t")
        return text
    }

    static CaptureScriptBody() {
        q := Chr(34)
        text := "#Requires AutoHotkey v2.0`n#SingleInstance Off`n`n"
        text .= "class QMK {`n"
        text .= "    static SetupHotkeys(entries) => QMKShortcutCollector.SetupFamily(" q "hotkeys" q ", entries)`n"
        text .= "    static SetupModifiers(entries) => QMKShortcutCollector.SetupFamily(" q "modifiers" q ", entries)`n"
        text .= "    static SetupPassthroughs(entries) => QMKShortcutCollector.SetupFamily(" q "passthroughs" q ", entries)`n"
        text .= "    static SetupCombos(entries) => QMKShortcutCollector.SetupFamily(" q "combos" q ", entries)`n"
        text .= "    static SetupChords(entries) => QMKShortcutCollector.SetupFamily(" q "chords" q ", entries)`n"
        text .= "    static SetupHolds(entries) => QMKShortcutCollector.SetupFamily(" q "holds" q ", entries)`n"
        text .= "    static SetupDoubleTaps(entries) => QMKShortcutCollector.SetupFamily(" q "double_taps" q ", entries)`n"
        text .= "    static SetupTaps(entries) => QMKShortcutCollector.SetupFamily(" q "taps" q ", entries)`n"
        text .= "    static SetupTapHolds(entries) => QMKShortcutCollector.SetupFamily(" q "tap_holds" q ", entries)`n"
        text .= "    static SetupHotstrings(entries) => QMKShortcutCollector.SetupFamily(" q "hotstrings" q ", entries)`n"
        text .= "    static SetupDoubleTap(args*) => 0`n"
        text .= "    static SendKeyDirect(text) => {__qmk_capture_kind: " q "native" q ", text: text}`n"
        text .= "    static SendDirect(text) => {__qmk_capture_kind: " q "native" q ", text: text}`n"
        text .= "    static Tap(value) => {__qmk_capture_kind: " q "tap_descriptor" q ", value: value}`n"
        text .= "    static SuspendExempt(callback) => {__qmk_capture_kind: " q "callback_suspend_exempt" q ", callback: callback}`n"
        text .= "    static __Call(name, args*) => {__qmk_capture_kind: " q "unknown_qmk_call" q ", name: name}`n"
        text .= "}`n`nQMKShortcutCollector.Reset()`n"
        return text
    }

    static BuildCaptureScript(paths, outputPath, reportPath := "", collectorPath := "") {
        q := Chr(34)
        if (collectorPath = "")
            collectorPath := A_LineFile
        text := "#Include " q this.EscapeIncludePath(collectorPath) q "`n`n"
            . this.CaptureScriptBody()
        for , path in paths
            text .= "#Include " q this.EscapeIncludePath(path) q "`n"
        if (reportPath = "")
            text .= "`nQMKShortcutCollector.EmitReport()`nExitApp(0)`n"
        else
            text .= "`nQMKShortcutCollector.WriteReport(" q this.EscapeIncludePath(reportPath) q ")`nExitApp(0)`n"
        if FileExist(outputPath)
            FileDelete(outputPath)
        FileAppend(text, outputPath, "UTF-8-RAW")
    }

    static EscapeIncludePath(path) {
        return path
    }
}


class QMKCompilerScrollPanel {
    static panels := Map()
    static handlersInstalled := false

    __New(parentGui, x, y, width, height) {
        this.parentGui := parentGui
        this.x := x
        this.y := y
        this.width := width
        this.height := height
        this.contentWidth := width
        this.contentHeight := height
        this.scrollPos := 0

        QMKCompilerScrollPanel.InstallHandlers()
        this.viewport := Gui("+Parent" parentGui.Hwnd " -Caption")
        this.viewport.BackColor := "F6F7FB"
        ; WS_VSCROLL plus WS_CLIPCHILDREN.  The content window is moved inside
        ; this clipped viewport rather than asking a single control to scroll.
        this.viewport.Opt("+0x200000 +0x02000000")
        this.content := Gui("+Parent" this.viewport.Hwnd " -Caption")
        this.content.BackColor := "F6F7FB"
        this.viewport.Show("x" x " y" y " w" width " h" height " NoActivate")
        this.content.Show("x0 y0 w" this.contentWidth " h" this.contentHeight " NoActivate")
        QMKCompilerScrollPanel.panels[this.viewport.Hwnd] := this
        this.UpdateScrollBar()
    }

    static InstallHandlers() {
        if this.handlersInstalled
            return
        this.handlersInstalled := true
        OnMessage(0x0115, ObjBindMethod(this, "OnVScroll"))
        OnMessage(0x020A, ObjBindMethod(this, "OnMouseWheel"))
    }

    Finish(extraBottom := 14) {
        bottom := this.height
        for , control in this.content {
            try {
                control.GetPos(&x, &y, &width, &height)
                bottom := Max(bottom, y + height + extraBottom)
            }
        }
        this.contentHeight := bottom
        this.content.Show("x0 y0 w" this.contentWidth " h" this.contentHeight " NoActivate")
        this.UpdateScrollBar()
    }

    SetVisible(visible) {
        if visible
            this.viewport.Show("x" this.x " y" this.y " w" this.width " h" this.height " NoActivate")
        else
            this.viewport.Hide()
    }

    ScrollBy(delta) => this.ScrollTo(this.scrollPos + delta)

    ScrollTo(position) {
        maximum := Max(0, this.contentHeight - this.height)
        this.scrollPos := Min(Max(0, position), maximum)
        this.MoveContent()
        this.UpdateScrollBar()
    }

    MoveContent() {
        ; Gui.Show applies AutoHotkey's DPI scaling.  Do not use raw
        ; SetWindowPos coordinates here: those are physical pixels and would
        ; shrink the child content on a scaled display.
        this.content.Show("x0 y-" this.scrollPos " w" this.contentWidth " h" this.contentHeight " NoActivate")
    }

    UpdateScrollBar() {
        dpiScale := A_ScreenDPI / 96
        maximum := Max(0, Round((this.contentHeight - 1) * dpiScale))
        si := Buffer(28, 0)
        NumPut("UInt", 28, si, 0)
        NumPut("UInt", 0x17, si, 4) ; SIF_ALL
        NumPut("Int", 0, si, 8)
        NumPut("Int", maximum, si, 12)
        NumPut("UInt", Round(this.height * dpiScale), si, 16)
        NumPut("Int", Round(this.scrollPos * dpiScale), si, 20)
        NumPut("Int", Round(this.scrollPos * dpiScale), si, 24)
        DllCall("user32\SetScrollInfo", "Ptr", this.viewport.Hwnd, "Int", 1, "Ptr", si, "Int", 1)
        this.MoveContent()
    }

    TrackPosition() {
        si := Buffer(28, 0)
        NumPut("UInt", 28, si, 0)
        NumPut("UInt", 0x10, si, 4) ; SIF_TRACKPOS
        if DllCall("user32\GetScrollInfo", "Ptr", this.viewport.Hwnd, "Int", 1, "Ptr", si, "Int")
            return Round(NumGet(si, 24, "Int") / (A_ScreenDPI / 96))
        return this.scrollPos
    }

    static FindForWindow(hwnd) {
        current := hwnd
        Loop 12 {
            if !current
                return 0
            for panelHwnd, panel in this.panels {
                if (current = panelHwnd || current = panel.content.Hwnd)
                    return panel
            }
            parent := DllCall("user32\GetParent", "Ptr", current, "Ptr")
            if (!parent || parent = current)
                break
            current := parent
        }
        return 0
    }

    static OnVScroll(wParam, lParam, msg, hwnd) {
        panel := this.FindForWindow(hwnd)
        if !panel
            return
        code := wParam & 0xFFFF
        position := panel.scrollPos
        if (code = 0)
            position -= 32
        else if (code = 1)
            position += 32
        else if (code = 2)
            position -= panel.height
        else if (code = 3)
            position += panel.height
        else if (code = 4 || code = 5)
            position := panel.TrackPosition()
        else if (code = 6)
            position := 0
        else if (code = 7)
            position := panel.contentHeight
        else
            return
        panel.ScrollTo(position)
        return 0
    }

    static OnMouseWheel(wParam, lParam, msg, hwnd) {
        panel := this.FindForWindow(hwnd)
        if !panel {
            MouseGetPos(&mouseX, &mouseY, &windowHwnd, &controlHwnd, 2)
            panel := this.FindForWindow(controlHwnd)
        }
        if !panel
            return
        delta := (wParam >> 16) & 0xFFFF
        if (delta >= 0x8000)
            delta -= 0x10000
        steps := Max(1, Round(Abs(delta) / 120))
        panel.ScrollBy(delta > 0 ? -steps * 48 : steps * 48)
        return 0
    }

    Destroy() {
        QMKCompilerScrollPanel.panels.Delete(this.viewport.Hwnd)
        try this.content.Destroy()
        try this.viewport.Destroy()
    }
}


QMKPgoCompiler.Main()
