# QMK Compiler GUI

Use the compiler only when you want to rebuild the native QMKCore runtime, change native Zig code, or regenerate the embedded native payload. You do **not** need to compile QMKCore when you only change ordinary QMK mappings in AutoHotkey.

## Before opening the compiler

For the normal GUI build, have:

- Windows
- AutoHotkey v2
- Zig 0.16
- the complete QMK.ahk release folder kept together

The **Full PGO Build** also needs LLVM/Clang, `llvm-profdata`, and the Windows MSVC build tools. PGO is optional and takes longer than the standard Zig build.

## Open the compiler

1. Start your QMK.ahk script.
2. Open **QMK Settings** from the tray menu, or call `QMKUserConfig.ShowGui()` from your script.
3. Select the **Compile** tab.
4. Click **Open PGO Compiler**.

The compiler window opens with the package paths and toolchain status visible in its log pane.

## Recommended build: Zig Build

1. In the compiler window, click **Compiler Settings**.
2. Open **Zig Build Settings** and confirm the paths for:
   - `QMKCore.zig`
   - `QMKVariables.ahk`
   - the final runtime DLL
   - Zig 0.16
   - the optional Interception DLL input
3. Leave the shipped build defaults unless you have a reason to change them. Use **Build Flags** only when you understand the effect of the change.
4. Click **Save** in the settings window.
5. Back in the main compiler window, click **Zig Build**.

The compiler builds the runtime, checks the resulting exports and build identity, and embeds the resulting native payload into `lib/QMKVariables.ahk`. Read the log pane for the exact output and wait for the completion message before closing the window.

After a successful build, reload your running AutoHotkey script so it loads the updated embedded payload.

## Optional build: Full PGO Build

Use this only when you specifically want profile-guided optimization:

1. Open **Compiler Settings** → **PGO Settings**.
2. Confirm the paths for `QMKconfig.ini`, the training DLL, the training-data folder, `QMKCorePGOTrainer.zig`, Clang, and `llvm-profdata`.
3. Resolve every missing dependency shown by the compiler.
4. Save the settings.
5. Click **Full PGO Build**.

This path emits a training build, prepares or rebuilds the PGO trainer when its source is missing or stale, runs the training pass, merges profile data, builds the final runtime, and embeds it into `QMKVariables.ahk`. It creates local training artifacts and can take substantially longer than **Zig Build**.

## Optional user-shortcut transpilation

The **Generate User Shortcuts** checkbox and the **Transpile User Shortcuts** settings tab are for intentionally compiling selected AutoHotkey shortcut sources into the native build. Leave them off for a clean generic release or demo unless you explicitly selected sanitized source files.

When enabled, the compiler rebuilds the checked-in Zig transpiler source if its executable is missing or stale. The transpiler executable, source-hash marker, generated shortcut bundle, and callback files are local build outputs; they are not release source files and should not be committed.

## Maintenance actions

The **Maintenance** tab provides:

- **Embed Interception DLL** — manually embeds the selected Interception import payload.
- **Restore QMK Variables** — restores the locally preserved original `QMKVariables.ahk` content.

Use these only when you understand which payload and architecture are selected. The compiler normally embeds the runtime as part of the build pipeline.

## What should remain local

Compilation can create DLLs, PGO profiles, training data, transpiler/trainer executables, hash markers, PDBs, and generated shortcut files. These are machine-specific or generated outputs. Keep them out of commits unless a future release policy explicitly says otherwise.
