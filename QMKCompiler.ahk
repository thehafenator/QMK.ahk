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
    static progressCtl := ""
    static pctCtl := ""
    static stepCtl := ""
    static pathSummaryCtl := ""
    static logCtl := ""
    static startBtn := ""
    static quickBtn := ""
    static cancelBtn := ""

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

    ; ---------------------------------------------------------------- paths

    static InitPaths() {
        if this.HasOwnProp("packageDir")
            return

        this.packageDir := this.ResolvePackageDir()
        this.libDir := this.packageDir "\lib"
        this.projectRoot := this.ParentDir(this.packageDir)
        this.settingsPath := this.packageDir "\QMKconfig.ini"

        this.ReloadResolvedPaths()
    }

    static ReadSetting(section, key, fallback) {
        value := ""
        try value := IniRead(this.settingsPath, section, key, fallback)
        catch
            value := fallback
        return (value = "") ? fallback : value
    }

    static ResolvePackageDir() {
        ; QMKCompiler.ahk lives in the package root. Resolve all package-relative
        ; paths from this script's current directory so the compiler is portable.
        packageDir := A_ScriptDir

        if (FileExist(packageDir "\QMKInterception.ahk")
            && FileExist(packageDir "\QMKconfig.ini")
            && DirExist(packageDir "\lib"))
            return packageDir

        ; A_LineFile is a safe fallback if this code is included from another script.
        lineDir := this.DirFromPath(A_LineFile)
        if (lineDir != ""
            && FileExist(lineDir "\QMKInterception.ahk")
            && FileExist(lineDir "\QMKconfig.ini")
            && DirExist(lineDir "\lib"))
            return lineDir

        ; Keep the current script directory as the base even if files are missing,
        ; so Settings shows the expected local paths instead of a machine-specific path.
        return packageDir
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

    static Anchor(value, base) {
        if this.IsAbsolute(value)
            return value
        return base "\" RegExReplace(value, "^\.\\")
    }

    static LibPath(key, fallback) {
        return this.Anchor(this.ReadSetting("Paths", key, ".\" fallback), this.libDir)
    }

    static PackagePath(key, fallback) {
        return this.Anchor(this.ReadSetting("Paths", key, fallback), this.packageDir)
    }

    static ToolPath(key, fallback) {
        return this.Anchor(this.ReadSetting("Tools", key, fallback), this.libDir)
    }

    ; ------------------------------------------------------------------ gui

    static Main() {
        this.InitPaths()

        if (A_Args.Length) {
            action := A_Args[1]
            switch action {
                case "--gui":
                    ; Continue into the GUI launcher below.
                case "--quick-compile":
                    ExitApp(this.RunCliPipeline("quick"))
                case "--zig-only-build":
                    ExitApp(this.RunCliPipeline("zig"))
                case "--full-pgo-build", "--train-and-embed-final":
                    ExitApp(this.RunCliPipeline("full"))
                default:
                    try FileAppend("Unknown QMKPgoCompiler argument: " action "`n", "*", "UTF-8")
                    catch
                        MsgBox("Unknown QMKPgoCompiler argument:`n" action, "QMK Compiler", "Icon!")
                    ExitApp(2)
            }
        }

        g := Gui("+MinSize900x640", "QMK Compiler")
        this.gui := g
        g.MarginX := 14
        g.MarginY := 12
        g.BackColor := "F6F7FB"
        g.SetFont("s9", "Segoe UI")

        title := g.AddText("xm ym w860 h26 c1F2937", "QMK Compiler")
        title.SetFont("s15 w700", "Segoe UI")
        sub := g.AddText("xm y+2 w860 c667085", "Runs the full training, profile merge, optimized DLL build, and embed pipeline with no console windows.")
        sub.SetFont("s9", "Segoe UI")

        this.startBtn := g.AddButton("xm y+12 w170 h32 Default", "Full PGO Build")
        this.startBtn.OnEvent("Click", (*) => this.StartPipeline("full"))
        this.quickBtn := g.AddButton("x+8 yp w130 h32", "Zig Build")
        this.quickBtn.OnEvent("Click", (*) => this.StartPipeline("zig"))
        this.cancelBtn := g.AddButton("x+8 yp w110 h32 Disabled", "Cancel")
        this.cancelBtn.OnEvent("Click", (*) => this.RequestCancel())
        settingsBtn := g.AddButton("x+8 yp w120 h32", "PGO Settings...")
        settingsBtn.OnEvent("Click", (*) => this.ShowSettingsGui("pgo"))
        zigSettingsBtn := g.AddButton("x+8 yp w140 h32", "Zig Build Settings...")
        zigSettingsBtn.OnEvent("Click", (*) => this.ShowSettingsGui("zig"))
        openLogBtn := g.AddButton("x+8 yp w130 h32", "Save Log...")
        openLogBtn.OnEvent("Click", (*) => this.SaveLog())

        this.pathSummaryCtl := g.AddText("xm y+10 w860 h18 c667085", this.PathSummaryText())
        this.pathSummaryCtl.SetFont("s9", "Segoe UI")

        this.stepCtl := g.AddText("xm y+14 w860 h20 c243447", "Idle. Full PGO Build runs the 9-step pipeline (slightly faster). Zig Only Build requires only Zig.")
        this.stepCtl.SetFont("s10 w600", "Segoe UI")

        this.progressCtl := g.AddProgress("xm y+6 w790 h24 Range0-100 cBlue", 0)
        this.pctCtl := g.AddText("x+10 yp+3 w60 h20 c243447", "0%")
        this.pctCtl.SetFont("s10 w700", "Segoe UI")

        logLabel := g.AddText("xm y+12 w860 h18 c243447", "Output")
        logLabel.SetFont("s10 w700", "Segoe UI")
        this.logCtl := g.AddEdit("xm y+4 w860 h380 ReadOnly -Wrap +VScroll +HScroll", "")
        this.logCtl.SetFont("s9", "Consolas")

        g.OnEvent("Close", (*) => this.OnClose())
        g.Show()
        this.RefreshPathSummary()
        this.Log("")
    }

    static PathSummaryText() {
        return "Source: " this.AbbreviatePath(this.sourcePath)
            . "  |  Zig: " this.AbbreviatePath(this.zigPath)
            . "  |  Out: " this.AbbreviatePath(this.finalDllPath)
    }

    static RefreshPathSummary() {
        if this.pathSummaryCtl
            this.pathSummaryCtl.Value := this.PathSummaryText()
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
        }
    }

    static AbbreviatePath(path, maxChars := 52) {
        if (StrLen(path) <= maxChars)
            return path
        return "..." SubStr(path, -(maxChars - 4))
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
        if !isZigOnly {
            this.AddSettingsRow(sg, "Paths", "configPath", "QMKconfig.ini", this.configPath, true)
            this.AddSettingsRow(sg, "Paths", "trainingDllPath", "Training DLL", this.trainingDllPath, false)
            this.AddSettingsRow(sg, "Paths", "trainingDataDir", "Training data dir", this.trainingDir, true)
            this.AddSettingsRow(sg, "Paths", "pgoTrainerSourcePath", "Trainer source", this.trainerSourcePath, true)
            this.AddSettingsRow(sg, "Tools", "clangPath", "Clang", this.clangPath, true)
            this.AddSettingsRow(sg, "Tools", "llvmProfdataPath", "llvm-profdata", this.profdataPath, true)
        }

        applyBtn := sg.AddButton("xm y+16 w140 h30 Default", "Apply")
        applyBtn.OnEvent("Click", (*) => this.ApplySettings())
        cancelBtn := sg.AddButton("x+8 yp w110 h30", "Close")
        cancelBtn.OnEvent("Click", (*) => sg.Hide())
        resetBtn := sg.AddButton("x+8 yp w160 h30", "Reload from INI")
        resetBtn.OnEvent("Click", (*) => this.ReloadSettingsIntoGui())

        this.settingsStatusCtl := sg.AddText("xm y+12 w680 h36 c243447", "Edit a path, then Apply. Missing required paths are listed after Apply.")
        sg.OnEvent("Close", (*) => (this.settingsGui := "", sg.Destroy()))
        sg.Show()
        this.CheckSettingsPaths()
    }

    static AddSettingsRow(sg, section, key, label, value, required := true) {
        lbl := sg.AddText("xm y+8 w150 h18 c243447", label)
        lbl.SetFont("s9 w600", "Segoe UI")
        edit := sg.AddEdit("x+6 yp-2 w430 h22", value)
        browse := sg.AddButton("x+6 yp w70 h22", "Browse")
        browse.OnEvent("Click", (*) => this.BrowseSettingPath(edit, label))
        this.settingsEdits[key] := { section: section, key: key, edit: edit, required: required, label: label }
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

    static ReloadSettingsIntoGui() {
        this.ReloadResolvedPaths()
        for , row in this.settingsEdits {
            switch row.key {
                case "sourcePath": row.edit.Value := this.sourcePath
                case "variablesPath": row.edit.Value := this.variablesPath
                case "configPath": row.edit.Value := this.configPath
                case "runtimeDllPath": row.edit.Value := this.finalDllPath
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
            row.edit.Opt(exists ? "+BackgroundC6F6D5" : (row.required ? "+BackgroundFED7D7" : "+BackgroundFFF5D7"))
            if (row.required && !exists)
                ok := false
        }
        return ok
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
        this.configPath := this.PackagePath("configPath", "QMKconfig.ini")
        this.trainingDllPath := this.LibPath("trainingDllPath", "QMKTrainingData.dll")
        this.finalDllPath := this.LibPath("runtimeDllPath", "QMKCoreProfiling.dll")
        this.trainingDir := this.LibPath("trainingDataDir", "TrainingData")
        this.trainerSourcePath := this.LibPath("pgoTrainerSourcePath", "QMKCorePGOTrainer.zig")
        this.trainerExePath := this.LibPath("pgoTrainerExePath", "QMKCorePGOTrainer.exe")
        this.syntheticProfilePath := this.LibPath("syntheticPgoProfilePath", "TrainingData\qmk_pgo_auto_trainer.profraw")
        this.zigPath := this.ToolPath("zigPath", "C:\Program Files\zig\zig.exe")
        this.clangPath := this.ToolPath("clangPath", "C:\Program Files\LLVM\bin\clang.exe")
        this.profdataPath := this.ToolPath("llvmProfdataPath", "C:\Program Files\LLVM\bin\llvm-profdata.exe")
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

    static SetStep(text) {
        if this.stepCtl
            this.stepCtl.Value := text
    }

    static SetProgress(pct) {
        pct := Round(Max(0, Min(100, pct)))
        if this.progressCtl
            this.progressCtl.Value := pct
        if this.pctCtl
            this.pctCtl.Value := pct "%"
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
            . "echo %ERRORLEVEL%> " this.Quote(exitFile) "`r`n"
        FileAppend(bat, batFile, "UTF-8-RAW")

        this.Log("$ " command)
        pid := 0
        Run(A_ComSpec ' /d /s /c "' batFile '"', workingDir, "Hide", &pid)
        this.activePid := pid

        lastLen := 0
        while ProcessExist(pid) {
            lastLen := this.PumpLog(logFile, lastLen)
            this.TickProgress()
            Sleep(120)
        }
        lastLen := this.PumpLog(logFile, lastLen)
        this.activePid := 0

        code := 0
        try code := Integer(Trim(FileRead(exitFile)))
        catch
            code := this.cancelRequested ? 1223 : 0

        for f in [logFile, exitFile, batFile]
            this.DeleteIfExists(f)
        if (this.cancelRequested)
            throw Error("Build cancelled.")
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
        mode := this.ResolveRunMode(requestedMode)
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
            MsgBox(err.Message, "QMK Compiler", "Icon!")
        } finally {
            this.DeleteIfExists(this.buildOptionsPath)
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
        mode := this.ResolveRunMode(requestedMode)
        this.stepIndex := 0
        this.steps := this.StepsForMode(mode)
        started := A_TickCount
        try {
            this.Log("=== CLI " this.ModeLabel(mode) " started ===")
            this.RunPipelineMode(mode)
            secs := Round((A_TickCount - started) / 1000, 1)
            this.Log("")
            this.Log("=== " this.ModeLabel(mode) " complete in " secs "s ===")
            this.Log("QMKconfig.ini was not changed. Reload Macropad to pick up the new DLL.")
            for line in this.logLines
                FileAppend(line, "*", "UTF-8")
            for line in this.logLines
                FileAppend(line, logPath, "UTF-8")
            return 0
        } catch Error as err {
            this.Log("")
            this.Log("*** ERROR: " err.Message " ***")
            for line in this.logLines
                FileAppend(line, "*", "UTF-8")
            for line in this.logLines
                FileAppend(line, logPath, "UTF-8")
            return 1
        } finally {
            this.DeleteIfExists(this.buildOptionsPath)
        }
    }

    static TrainAndEmbedFinalPgo() {
        this.RequireToolchain()
        DirCreate(this.trainingDir)

        ; LLVM profile-use requires the instrumented training DLL and the final DLL
        ; to share comptime control-flow shape, so both are built with compiled
        ; authoring data disabled. QMKCorePGOTrainer exercises the runtime path.
        irTrain := this.trainingDir "\QMKCore_pgo_train.ll"
        tempTrainingDll := this.libDir "\QMKTrainingData.pgo.building.dll"
        this.DeleteIfExists(irTrain)
        this.DeleteIfExists(tempTrainingDll)
        this.DeleteIfExists(this.libDir "\QMKTrainingData.lib")
        this.DeleteIfExists(this.libDir "\QMKTrainingData.pdb")
        this.DeleteIfExists(this.libDir "\QMKTrainingData.pgo.building.lib")
        this.DeleteIfExists(this.libDir "\QMKTrainingData.pgo.building.pdb")
        this.WriteBuildOptions(true, true, false, false, false)

        this.BeginStep(1)
        this.RunStep(this.ZigIrCommand(irTrain), this.libDir, "Zig training IR build")
        this.EndStep()

        this.BeginStep(2)
        this.RunStep(this.ClangInstrumentCommand(irTrain, tempTrainingDll), this.libDir, "Clang instrumented training DLL build")
        this.EndStep()
        this.DeleteIfExists(this.buildOptionsPath)

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
        if FileExist(this.trainerExePath) {
            this.Log("Reusing existing PGO trainer exe: " this.trainerExePath)
        } else {
            this.RequireFile(this.trainerSourcePath, "PGO trainer source")
            this.RunStep(this.ZigTrainerCommand(), this.libDir, "PGO trainer build")
        }
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
        this.CompileFinalFromProfile(profdata)
    }

    static QuickCompileFromMergedProfile() {
        this.RequireToolchain()
        DirCreate(this.trainingDir)
        profdata := this.ProfileDataPath()
        this.RequireFile(profdata, "merged PGO profile data")
        this.Log("Reusing merged PGO profile data: " profdata)
        this.CompileFinalFromProfile(profdata)
    }

    static MergeProfilesAndCompileFinal() {
        this.RequireToolchain()
        DirCreate(this.trainingDir)
        profdata := this.ProfileDataPath()
        rsp := this.trainingDir "\qmk_pgo_inputs.rsp"
        this.MergeProfiles(profdata, rsp, true)
        this.CompileFinalFromProfile(profdata)
    }

    static ZigOnlyCompileAndEmbed() {
        this.RequireZigOnlyToolchain()
        tempDll := this.libDir "\QMKCoreProfiling.zigonly.building.dll"
        this.DeleteIfExists(tempDll)
        this.DeleteIfExists(this.libDir "\QMKCoreProfiling.zigonly.building.lib")
        this.DeleteIfExists(this.libDir "\QMKCoreProfiling.zigonly.building.pdb")

        this.BeginStep(1)
        this.RunStep(this.ZigOnlyCommand(tempDll), this.libDir, "Zig-only runtime DLL build")
        this.EndStep()

        this.BeginStep(2)
        this.VerifyRequiredExports(tempDll)
        flags := this.GetBuildFeatureFlags(tempDll)
        if (flags != 0)
            throw Error("Zig-only runtime flags must be 0, got " Format("0x{:08X}", flags))
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
        this.EmbedDll(embedDllPath, "QMKCore", true)
        if replacedFinalDll
            this.DeleteIfExists(tempDll)
        this.Log("Embedded QMKCore from Zig-only build without changing QMKconfig.ini.")
        this.EndStep()
    }

    static MergeProfiles(profdata, rsp, deleteExisting := true) {
        this.BeginNextStep()
        this.WriteProfileResponseFile(rsp)
        if deleteExisting
            this.DeleteIfExists(profdata)
        this.RunStep(this.Quote(this.profdataPath) " merge -output=" this.Quote(profdata) " @" this.Quote(rsp), this.libDir, "llvm-profdata merge")
        this.EndStep()
    }

    static CompileFinalFromProfile(profdata) {
        irFinal := this.trainingDir "\QMKCore_pgo_final.ll"
        tempDll := this.libDir "\QMKCoreProfiling.pgo.building.dll"

        this.WriteBuildOptions(false, false, false, false, false)
        this.DeleteIfExists(irFinal)
        this.DeleteIfExists(tempDll)
        this.DeleteIfExists(this.libDir "\QMKCoreProfiling.pgo.building.lib")
        this.DeleteIfExists(this.libDir "\QMKCoreProfiling.pgo.building.pdb")

        this.BeginNextStep()
        this.RunStep(this.ZigIrCommand(irFinal), this.libDir, "Zig final IR build")
        this.EndStep()

        this.BeginNextStep()
        this.RunStep(this.ClangFinalCommand(irFinal, profdata, tempDll), this.libDir, "Clang final PGO build")
        this.EndStep()
        this.DeleteIfExists(this.buildOptionsPath)

        this.BeginNextStep()
        this.VerifyRequiredExports(tempDll)
        flags := this.GetBuildFeatureFlags(tempDll)
        if (flags != 0)
            throw Error("Final PGO runtime flags must be 0, got " Format("0x{:08X}", flags))
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
        this.EmbedDll(embedDllPath, "QMKCore", true)
        if replacedFinalDll
            this.DeleteIfExists(tempDll)
        this.Log("Embedded QMKCore without changing QMKconfig.ini.")
        this.EndStep()
    }

    ; -------------------------------------------------------------- commands

    static WriteBuildOptions(compileProfiling, compilePgo, microbench, hasShortcuts, hasHotstrings) {
        text := "pub const compile_with_profiling = " (compileProfiling ? "true" : "false") ";`n"
            . "pub const compile_with_pgo = " (compilePgo ? "true" : "false") ";`n"
            . "pub const microbenchdebug = " (microbench ? "true" : "false") ";`n"
            . "pub const has_qmk_shortcuts = " (hasShortcuts ? "true" : "false") ";`n"
            . "pub const has_qmk_hotstrings = " (hasHotstrings ? "true" : "false") ";`n"
        this.DeleteIfExists(this.buildOptionsPath)
        FileAppend(text, this.buildOptionsPath, "UTF-8-RAW")
    }

    static ZigIrCommand(irPath) {
        return this.Quote(this.zigPath)
            . " build-lib -dynamic -target x86_64-windows-gnu -O ReleaseFast -flto"
            . " -fomit-frame-pointer -fsingle-threaded -fno-stack-check -fno-unwind-tables"
            . " --dep build_options"
            . " -Mroot=" this.Quote(this.sourcePath)
            . " -Mbuild_options=" this.Quote(this.buildOptionsPath)
            . " -femit-llvm-ir=" this.Quote(irPath)
            . " -fno-emit-bin -lntdll -luser32 -lkernel32"
    }

    static ZigOnlyCommand(dllPath) {
        return this.Quote(this.zigPath)
            . " build-lib -dynamic -target x86_64-windows-gnu -O ReleaseFast -flto"
            . " -fomit-frame-pointer -fsingle-threaded -fno-stack-check -fno-unwind-tables"
            . " --dep build_options"
            . " -Mroot=" this.Quote(this.sourcePath)
            . " -Mbuild_options=" this.Quote(this.runtimeBuildOptionsPath)
            . " -femit-bin=" this.Quote(dllPath)
            . " -lntdll -luser32 -lkernel32"
    }

    static ZigTrainerCommand() {
        return this.Quote(this.zigPath)
            . " build-exe " this.Quote(this.trainerSourcePath)
            . " -O ReleaseFast -target x86_64-windows-gnu"
            . " -femit-bin=" this.Quote(this.trainerExePath)
    }

    static ClangInstrumentCommand(irPath, dllPath) {
        return this.ClangBaseCommand("-fprofile-generate=" this.Quote(this.trainingDir), irPath, dllPath)
    }

    static ClangFinalCommand(irPath, profdata, dllPath) {
        return this.ClangBaseCommand("-fprofile-use=" this.Quote(profdata), irPath, dllPath)
    }

    static ClangBaseCommand(profileArg, irPath, dllPath) {
        libs := this.GetWindowsLibPaths()
        return this.Quote(this.clangPath)
            . " " profileArg
            . " -mllvm -disable-vp -O2 -target x86_64-pc-windows-msvc -shared -fuse-ld=lld"
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

    static EmbedDll(dllPath, variableName, requireZeroFlags) {
        this.RequireFile(dllPath, "DLL")
        this.RequireFile(this.variablesPath, "QMKVariables")
        this.VerifyRequiredExports(dllPath)
        flags := this.GetBuildFeatureFlags(dllPath)
        if (requireZeroFlags && flags != 0)
            throw Error("DLL feature flags must be 0, got " Format("0x{:08X}", flags))
        dllBytes := FileRead(dllPath, "RAW")
        b64 := this.BufferToBase64(dllBytes)
        text := FileRead(this.variablesPath, "UTF-8")
        replacement := variableName " := `"`r`n    (`r`n" b64 "`r`n    )`""
        newText := this.ReplaceAssignmentBlock(text, variableName, replacement)
        this.AtomicWriteText(this.variablesPath, newText, "UTF-8-RAW")
    }

    static EmbedDllUnchecked(dllPath, variableName) {
        this.RequireFile(dllPath, "DLL")
        this.RequireFile(this.variablesPath, "QMKVariables")
        dllBytes := FileRead(dllPath, "RAW")
        b64 := this.BufferToBase64(dllBytes)
        text := FileRead(this.variablesPath, "UTF-8")
        replacement := variableName " := `"`r`n    (`r`n" b64 "`r`n    )`""
        newText := this.ReplaceAssignmentBlock(text, variableName, replacement)
        this.AtomicWriteText(this.variablesPath, newText, "UTF-8-RAW")
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

    static GetWindowsLibPaths() {
        vcRoot := "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC"
        vc := this.FindNewestSubdirWithFile(vcRoot, "lib\x64\libcmt.lib") "\lib\x64"
        kitRoot := "C:\Program Files (x86)\Windows Kits\10\Lib"
        kit := this.FindNewestSubdirWithFile(kitRoot, "ucrt\x64\libucrt.lib")
        return { vc: vc, ucrt: kit "\ucrt\x64", um: kit "\um\x64" }
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

QMKPgoCompiler.Main()
