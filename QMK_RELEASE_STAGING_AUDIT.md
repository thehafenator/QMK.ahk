# QMK.ahk Release Staging Audit

**Date:** 2026-09-05
**Purpose:** Plan the move from the active QMKInterception development tree into the private GitHub repository without publishing personal shortcuts, hotstrings, generated user output, machine paths, or build debris.

## Scope and path clarification

This audit intentionally inspected only the active development tree and the Git repository. It did **not** use snapshot folders, archive folders, or historical experiment trees.

The paths supplied as production\_code do not exist literally on disk. The corresponding active directory is the repository’s active production_code directory, alongside the snapshot/archive directories that were intentionally excluded from this audit.

The three requested active files are therefore:

- production_code\QMKInterception.ahk
- production_code\QMKCompiler.ahk
- production_code\lib\QMKCore.zig

## GitHub target

- **Remote:** https://github.com/thehafenator/QMK.ahk.git
- **Target branch:** main
- **Current local release branch:** qmk-release-sync-2026-08-29
- **Current release branch commit:** 00aed03
- **Fetched origin/main commit:** 69aa79d
- **Divergence:** origin/main...HEAD = 0 28; the current release branch contains 28 commits not present in main, while main has no unique commits relative to it.
- **Visibility:** the repository is being kept private during staging. Do not make it public until the final privacy and history review is complete.

The current checkout has these working-tree items requiring separate review before any commit:

- Modified: QMKconfig.ini
- Modified according to Git: lib/QMKCore.zig (content hash matched HEAD; verify whether this is only a timestamp/line-ending/racy-index state)
- Untracked: QMKInterceptionK.ahk
- Untracked: Quick_Demo_improved.ahk

## Complete file list: current GitHub main

The fetched origin/main currently contains this small, older library layout:

~~~
Monitor Manager.ahk
OnWebsite.ahk
QMK.ahk
QMKClass.ahk
README.md
TabActivator.ahk
UIA/Lib/UIA.ahk
UIA/Lib/UIA_Browser.ahk
UIA/Lib/temp
UIA/UIATreeInspector.ahk
mouse.ahk
scroll.ahk
~~~

This is not the same package shape as the current QMKInterception release branch. The new package should be treated as a deliberate release-layout evolution, not as a blind copy onto the old tree.

## Complete file list: current release branch HEAD

The release branch currently tracks:

~~~
LICENSE
QMK Shortcuts.ahk
QMKCompiler.ahk
QMKHotkeys.ahk
QMKInterception.ahk
QMKconfig.ini
Quick_Demo.ahk
Quick_Demo_polished.ahk
Quick_Demo_updated_feedback.ahk
README.md
docs/INSTALL.md
docs/TUTORIAL.md
lib/Example Dependencies/Monitor Manager.ahk
lib/Example Dependencies/OnWebsite.ahk
lib/Example Dependencies/TabActivator.ahk
lib/Example Dependencies/UIA/Lib/UIA.ahk
lib/Example Dependencies/UIA/Lib/UIA_Browser.ahk
lib/Example Dependencies/UIA/Lib/temp
lib/Example Dependencies/UIA/UIATreeInspector.ahk
lib/Example Dependencies/mouse.ahk
lib/Example Dependencies/scroll.ahk
lib/MemoryModule/MCodeLoader.ahk
lib/MemoryModule/MemoryModule.ahk
lib/QMKCore.zig
lib/QMKCorePGOTrainer.exe
lib/QMKCorePGOTrainer.pdb
lib/QMKCorePGOTrainer.zig
lib/QMKCoreProfiling.dll
lib/QMKTrainingData.dll
lib/QMKVariables.ahk
lib/ReadMe_Tutorial.ahk
lib/ReadMe_Tutorial_original.ahk
lib/TrainingData/QMKCore_pgo_final.ll
lib/TrainingData/QMKCore_pgo_train.ll
lib/TrainingData/qmk_pgo.profdata
lib/TrainingData/qmk_pgo_auto_trainer.profraw
lib/TrainingData/qmk_pgo_inputs.rsp
lib/build_options_runtime.zig
lib/interception.dll
lib/interception.h
lib/interception.lib
lib/libstdc++-6.dll
lib/libwinpthread-1.dll
lib/root.lib
~~~

The release branch has the useful MemoryModule layout and runtime artifacts, but it does not yet contain the current transpiler source/tool pair or the current active compiler/interception implementation.

## Active development inventory

### Active top-level source files

~~~
8BitDo_QMK_Compiled_Callbacks.ahk
8BitDo_QMK.ahk
Hotstrings_Compiled_Callbacks.ahk
Hotstrings.ahk
QMK Shortcuts_Compiled_Callbacks.ahk
QMK Shortcuts.ahk
QMKCompiler.ahk
QMKconfig.ini
QMKHotkeys_Compiled_Callbacks.ahk
QMKHotkeys.ahk
QMKInterception.ahk
~~~

The mapping files and their compiled callback files are development/user inputs. They are not release payloads unless rewritten as sanitized examples.

### Active lib files relevant to packaging

The active lib contains generic source, runtime artifacts, generated output, backups, test material, caches, and several duplicate experimental binaries. Relevant groups are:

- **Generic runtime/source:** QMKCore.zig, QMKVariables.ahk, build.zig, build_options_runtime.zig, QMKCorePGOTrainer.zig, interception.h, interception.lib, root.lib, and the required runtime DLLs.
- **Transpiler:** zig_user_shortcut_transpiler\user_shortcut_transpiler.zig. The compiler rebuilds the local executable when needed.
- **Generated user output:** generated_native_user_shortcuts\generated_user_shortcuts.zig and user_callbacks.ahk.
- **Generated build configuration:** build_options_pgo.zig and build_options_generated_context.zig.
- **Training/output:** TrainingData, zig-out, transpiler out, .zig-cache, test executables, PDBs, and backup files.

Only the first two groups should be considered for a release source package. Generated output should be recreated by the user’s compiler run or replaced with a clean blank module.

For completeness, the active lib direct-file inventory is:

~~~
$compilerExe
$compilerExe.pdb
$out
$out.pdb
blank_test_build_options.zig
blank_user_shortcuts.zig
build_options_generated_context.zig
build_options_pgo.zig
build_options_runtime.zig
build.zig
generated_test_build_options.zig
interception.dll
interception.h
interception.lib
libstdc++-6.dll
libwinpthread-6.dll
QMKCore - Copy.zig
QMKCore.dll
QMKCore.pdb
QMKCore.zig
QMKCore.zig.backup.20260902
QMKCore.zig.pre_modifier_rename_20260904_182801.bak
QMKCore.zig.pre_modifier_rename_20260904_184221.bak
QMKCorePGOTrainer.exe
QMKCorePGOTrainer.pdb
QMKCorePGOTrainer.zig
QMKCoreProfiling.dll
QMKTrainingData.dll
QMKVariables.ahk
QMKVariables.ahk.backup.20260904-115904.ahk
QMKVariables.ahk.backup.20260904-132844.ahk
QMKVariables.ahk.backup.20260904-134932.ahk
QMKVariables.ahk.backup.20260904-135306.ahk
QMKVariables.ahk.backup.20260904-142129.ahk
QMKVariables.ahk.backup.20260904-144813.ahk
QMKVariables.ahk.original.bak
root.lib
test_shape_build_options.zig
test_shape.zig
test_suite.exe
test_suite.pdb
~~~

The active lib directories are .zig-cache, generated_native_user_shortcuts, TrainingData, zig_user_shortcut_transpiler, and zig-out. The direct-file list contains several development-only names and should not be treated as a copy manifest.

The transpiler directory currently contains:

~~~
out
main.exe
main.pdb
test_suite.exe
test_suite.pdb
test_suite.zig
user_shortcut_transpiler.zig
zig_user_shortcut_transpiler
zig_user_shortcut_transpiler_live
zig_user_shortcut_transpiler_live.pdb
zig_user_shortcut_transpiler_new
zig_user_shortcut_transpiler_new.exe
zig_user_shortcut_transpiler_new.pdb
zig_user_shortcut_transpiler.exe
zig_user_shortcut_transpiler.pdb
~~~

The compiler default expects zig_user_shortcut_transpiler\zig_user_shortcut_transpiler.exe; all similarly named variants, PDBs, tests, and output folders need an explicit exclusion decision.

## Exact comparison of the three requested active files

Comparison is between the active production_code files and the corresponding files in the release checkout. The active versions are not byte-identical to the release versions.

| File | Active size / lines | Release size / lines | Active SHA-256 | Release SHA-256 | Diff release → active |
|---|---:|---:|---|---|---:|
| QMKInterception.ahk | 177,826 / 3,794 | 181,620 / 3,770 | AB5A0327...F2DA8 | 33799A1A...6BC6 | +352 / -314 |
| QMKCompiler.ahk | 259,768 / 5,118 | 48,642 / 1,006 | E800BB20...BC83 | 25811E52...6A9C | +4,488 / -151 |
| lib/QMKCore.zig | 970,766 / 20,836 | 885,882 / 19,473 | F6847542...12D5 | FCAD58BA...35CB | +2,381 / -949 |

These should be reviewed as three coordinated versioned components, not copied one at a time without checking their build identity and include paths.

## Compiler and Zig dependency chain

The active build flow is approximately:

~~~
QMKCompiler.ahk
  ├─ reads QMKconfig.ini
  ├─ captures user shortcut/hotstring source files
  ├─ invokes zig_user_shortcut_transpiler\zig_user_shortcut_transpiler.exe
  ├─ emits generated_native_user_shortcuts\generated_user_shortcuts.zig
  ├─ writes build_options_pgo.zig / runtime build options
  ├─ invokes lib\build.zig
  │    └─ imports QMKCore.zig and selected build options
  ├─ produces QMKCore runtime/profiling artifacts
  ├─ embeds the runtime DLL into QMKVariables.ahk
  └─ QMKInterception.ahk loads the embedded/native runtime through MemoryModule
~~~

Important compiler responsibilities found in the active file include path resolution, generated shortcut validation, full-native callback compilation, Zig CLI invocation, PGO response-file generation, DLL export/feature validation, and embedding into QMKVariables.ahk.

The active compiler now resolves the package from the script directory, script directory fallback, or working directory instead of relying on a fixed personal path. That change is appropriate for the release package and should remain isolated as its own reviewable commit.

### Zig/build findings

- lib/build.zig is part of the compiler contract. It selects Windows GNU x64/x86 targets, DLL versus PGO-IR mode, optimization/LTO settings, and the QMKCore.zig root module.
- lib/build_options_runtime.zig is a clean generic runtime baseline.
- The active build_options_pgo.zig and build_options_generated_context.zig currently describe generated user-shortcut output. They must not be copied as public defaults.
- lib/blank_user_shortcuts.zig is the correct kind of clean baseline: no personal callbacks, zero generated rows, and an inert install function.
- generated_native_user_shortcuts is generated user output, not source to publish as-is.
- The transpiler source is zig_user_shortcut_transpiler\user_shortcut_transpiler.zig. The active folder also contains multiple renamed/duplicate executables, PDBs, test binaries, and output directories. Only the source is staged; the compiler recreates the executable locally, while duplicate experiments and build output are excluded.
- QMKCore.zig, QMKVariables.ahk, the runtime/profiling DLLs, training DLL, build options, and generated shortcut module form a build-identity group. Mixing files from different builds can create an apparently valid but incompatible package.
- Existing PGO .ll, .profdata, .profraw, response files, PDBs, and trainer binaries need an explicit policy. They are development/release assets, not generic source, and at least one tracked response file contains a machine-specific absolute path.

## Packaging findings and required decisions

1. **Use the active three files as the source of truth, subject to review.** The active compiler and interception files contain substantially newer functionality than the release checkout. QMKCore.zig is also materially different and must be paired with the matching runtime artifacts.
2. **Adapt the MemoryModule include path deliberately.** The active QMKInterception.ahk includes MemoryModule from an external development-library location, while the release package expects lib\MemoryModule\MemoryModule.ahk. Keep that packaging adjustment separate and obvious.
3. **Do not copy QMKconfig.ini as-is.** It contains machine-specific tool/source paths, a duplicate interception-DLL setting, and references to personal mapping files. Create a sanitized portable example/default instead.
4. **Do not copy personal maps or compiled callback output.** Exclude QMKHotkeys.ahk, QMK Shortcuts.ahk, Hotstrings.ahk, 8BitDo_QMK.ahk, and all corresponding *_Compiled_Callbacks.ahk files from the public package. Add sanitized examples only after the core package is stable.
5. **Do not publish generated personal build options.** Start from build_options_runtime.zig and blank_user_shortcuts.zig; generate PGO/user-shortcut options locally during a build.
6. **Bring the transpiler source into the package intentionally.** The compiler expects the source directory and rebuilds the executable with local Zig when the executable is absent or stale. Do not distribute the executable, hash marker, PDBs, or experimental variants.
7. **Add repository hygiene before staging.** The release checkout currently has no effective .gitignore protecting generated binaries, caches, PDBs, PGO scratch files, backup files, and generated user output. Add one before any broad review of changes.
8. **Review history before changing visibility.** A tracked PGO response file contains a machine-specific path. The repository may remain private during staging, but public release requires either history cleanup or a documented decision that the private history is acceptable.
9. **Clarify the relationship to main.** The fetched main is the older twelve-file layout; the current release branch is a later package line. Do not silently overwrite the old layout. Use a named staging branch and a pull request with an explicit migration summary.

## Recommended staging sequence

### Phase A — package policy and safety

- Keep the repository private.
- Add this audit and a release-oriented .gitignore.
- Resolve the QMKCore.zig working-tree status and inspect the four untracked/modified release-checkout items individually.
- Use a source-only policy for Zig/transpiler build outputs; keep the required runtime/import binaries that the normal package actually loads.

### Phase B — generic core

- Stage reviewed versions of QMKInterception.ahk, QMKCompiler.ahk, and lib/QMKCore.zig.
- Apply the local lib/MemoryModule include layout to the release copy.
- Stage QMKVariables.ahk, build.zig, generic build options, required headers/import libraries, and the matching runtime artifacts as one coherent build set.

### Phase C — compiler toolchain

- Stage zig_user_shortcut_transpiler\user_shortcut_transpiler.zig.
- Stage only the transpiler source and document that the compiler rebuilds its executable with Zig 0.16 when needed.
- Exclude caches, out, zig-out, test binaries, PDBs, backup files, generated shortcut output, and experimental duplicate binaries.

### Phase D — sanitized examples and documentation

- Add sanitized QMKconfig.ini with relative paths and placeholder/example mappings only.
- Add sanitized shortcut, hotstring, and hotkey examples if examples are needed.
- Update README/install/tutorial documentation to explain generated output, compiler prerequisites, MemoryModule layout, runtime artifacts, and what users must not commit.

### Phase E — final review and merge preparation

- Run a targeted privacy scan over the exact staging tree and Git history.
- Review git diff --cached by file; never use a broad git add ..
- Validate the AHK compiler and Zig syntax/build path without committing generated personal output.
- Commit in small logical units, push the staging branch, and open a PR into main with the audit’s migration notes.

## Explicit do-not-copy list

~~~
Personal QMKHotkeys.ahk / QMK Shortcuts.ahk / Hotstrings.ahk mappings
8BitDo_QMK.ahk and all personal compiled callback files
Machine-specific QMKconfig.ini paths
generated_native_user_shortcuts\*
build_options_pgo.zig when it imports generated personal output
build_options_generated_context.zig
.zig-cache\*
zig-out\*
transpiler out\*
PDB files and test executables
backup files and renamed experimental binaries
PGO scratch files containing machine paths
QMKVariables.ahk backup copies
~~~

## Staging pass completed 2026-09-05

- Copied only the user-approved core/compiler/Zig/runtime allowlist from the active production_code tree. The active source tree was not moved or modified.
- Copied QMKCompiler.ahk, QMKCore.zig, QMKVariables.ahk, QMKCorePGOTrainer.zig, build.zig, build_options_pgo.zig, the Interception import/runtime files, and the transpiler source. QMKCoreProfiling.dll was initially copied for comparison, then removed as an optional compiler output during the cleanup pass below.
- Temporarily generated the compiler-required transpiler executable and source hash marker during staging, then removed both as local build outputs. blank_user_shortcuts.zig is the retained clean baseline.
- Copied qmk_compiler_status.ini as requested, but .gitignore excludes it because it is transient compiler state rather than a release source file.
- Replaced the copied QMKconfig.ini with a sanitized package configuration: zero saved shortcut sources, blank local tool paths, relative package paths, and one canonical interception DLL setting.
- Adjusted only the release copy of QMKInterception.ahk to use the local lib/MemoryModule and anchored lib/QMKVariables.ahk includes. Personal-looking documentation examples were replaced with generic examples.
- Sanitized the pre-existing Outlook-specific examples in docs/TUTORIAL.md.
- Removed the pre-existing personal mapping files from the release checkout. They are not part of the new staging set.
- No Git files were staged, committed, pushed, or merged.

Targeted Zig syntax checks passed for QMKCore.zig, build.zig, QMKCorePGOTrainer.zig, the transpiler source, and build_options_pgo.zig. AHK was not runtime-validated; per packaging policy, the remaining AHK check is syntax/static review only.

The active QMKCore.zig source still contains hard-coded context identifiers associated with the development setup. They are not user shortcut mappings, but they should be replaced with generic names before a public release only as part of a rebuilt and re-embedded QMKCore/QMKVariables pairing.

### Transpiler keep/remove recommendation

Keep in the private demo/package candidate:

- zig_user_shortcut_transpiler/user_shortcut_transpiler.zig
- blank_user_shortcuts.zig

Do not keep in the package:

- transpiler out directories and generated output
- test fixtures, test_suite binaries, diagnostic tools, and probe binaries
- renamed live/new/legacy transpiler variants
- PDB files
- generated_native_user_shortcuts output and user_callbacks.ahk

The compiler now has the complete expected transpiler source path. When the executable or its source hash is absent/stale, the compiler rebuilds the transpiler from the checked-in Zig source with the user’s local Zig installation. The executable and hash marker are generated local outputs, not release-package contents.

## Trainer lifecycle update

The compiler’s PGO trainer path now follows the same freshness model as the user-shortcut transpiler:

- It requires the trainer Zig source.
- It checks the adjacent QMKCorePGOTrainer.exe.source.sha256 marker.
- It rebuilds the trainer when the executable is missing, the marker is missing, or the source hash changed.
- It writes the source hash marker only after a successful rebuild.
- It reports rebuild versus reuse in the compiler log while the existing PGO progress step remains visible.

The trainer executable, QMKTrainingData.dll, and generated marker are therefore optional build outputs. They were removed from the release candidate. A source-oriented or prebuilt-demo package does not need to ship them. If PGO is offered later, the compiler can create the trainer locally from QMKCorePGOTrainer.zig and create its training DLL through the existing pipeline.

## Current recommendation

Do not copy the entire active directory yet. First create the sanitized package boundary described above, then move the generic core/compiler/Zig/transpiler pieces in deliberate commits. The fastest safe route is not a one-shot folder copy; it is a short staging series where each commit has a clear privacy and build-purpose boundary and can be merged or reverted independently.

## Release-candidate cleanup pass 2026-09-05

- Kept exactly one local-only backup: lib/QMKVariables.ahk.original.bak. It is ignored by Git and is not part of the package. QMKCompiler.ahk now preserves that one backup and does not create timestamped copies on every embed.
- Removed unrelated release-checkout clutter from the candidate: .module_probe, lib/TrainingData, lib/ReadMe_Tutorial_original.ahk, and superseded demo variants Quick_Demo.ahk, Quick_Demo_polished.ahk, and Quick_Demo_updated_feedback.ahk.
- Removed the old personal-example reference file lib/ReadMe_Tutorial.ahk from the package. The sanitized Markdown tutorial and remote-derived docs/Quick_Demo.ahk are the retained examples.
- Removed lib/QMKCoreProfiling.dll from the checked-in candidate. It is a compiler-produced runtime artifact; the Zig source and compiler remain, and the compiler can recreate the DLL locally when needed.
- Removed the ignored QMKInterceptionK.ahk variant and qmk_compiler_status.ini transient state from the candidate. The compiler recreates its status file when needed.
- Sent those removed items to the Windows Recycle Bin; no machine-specific temporary cleanup directory is part of the release workflow.
- Kept the remote-derived docs/Quick_Demo.ahk, the active tutorial, compiler/transpiler sources, and the runtime files required by the staged package.
- The active development directory was not cleaned, renamed, or modified by this pass.

The file-by-file staging review is complete. No personal shortcut or hotstring source entered the committed diff. The package remains a private demo candidate, not a completed public release.

## Demo layout pass 2026-09-05

- Pulled the remote Quick_Demo_updated_feedback.ahk and placed it at docs/Quick_Demo.ahk.
- Pulled its original Example Dependencies tree and placed it at docs/Example Dependencies so every demo dependency is under docs.
- Changed the demo includes to resolve the package entry point from ..\\QMKInterception.ahk and the dependency tree from docs/Example Dependencies.
- Changed the demo's tutorial links and messages to open docs/TUTORIAL.md, avoiding the removed personal-example reference file.
- Sanitized the two copied dependency examples that contained development-specific application names; they now use generic example-editor placeholders.

## Final staging audit status 2026-09-05

**Status:** Ready for user review and push; not pushed to GitHub.

- Local checkpoint: current local `HEAD` includes the staged package, dependency audit, and Interception documentation pass.
- Branch state: `qmk-release-sync-2026-08-29` is one commit ahead of its tracked GitHub branch, with a clean working tree. The GUI compiler documentation commit is local and has not been pushed.
- Manifest check: all required compiler, interception, MemoryModule, Zig, transpiler-source, tutorial, and demo paths exist in the release tree.
- Demo layout check: `docs/Quick_Demo.ahk` resolves the package entry point and all seven dependency includes under `docs/Example Dependencies`.
- Privacy check: no personal mapping files, personal paths, or personal shortcut/hotstring content are tracked. The remaining filename references are intentional exclusion rules in the transpiler and repository hygiene files.
- Embedded payload check: the base64-embedded QMKCore payload was decoded in memory and contained the expected generic QMK exports, with no personal path, mapping filename, or development-identifier matches.
- Backup check: the release tree has exactly one local ignored backup, `lib/QMKVariables.ahk.original.bak`; it is not tracked and is not required on another user’s computer.
- Artifact check: no trainer executable, profiling/training DLL, PDB, PGO profile, LLVM IR, response file, cache, generated shortcut bundle, or transpiler executable is tracked. The compiler rebuilds the transpiler and PGO trainer from their checked-in Zig sources when those outputs are needed.
- Zig syntax check: passed for `QMKCore.zig`, `build.zig`, `QMKCorePGOTrainer.zig`, `build_options_pgo.zig`, `build_options_runtime.zig`, `blank_user_shortcuts.zig`, and `zig_user_shortcut_transpiler/user_shortcut_transpiler.zig`.
- AHK check limitation: the available checker copies scripts to a temporary directory, so it cannot resolve the package’s intentional relative includes; the compiler check timed out without a reported syntax error. No AHK runtime or demo execution was performed.

## Dependency verification pass 2026-09-05

- Quick demo dependency closure: all seven direct demo dependencies exist under `docs/Example Dependencies`.
- Core include closure: `QMKInterception.ahk` resolves `lib/MemoryModule/MemoryModule.ahk` and `lib/QMKVariables.ahk`; the demo resolves the repository-root `QMKInterception.ahk` and all seven `docs/Example Dependencies` files.
- Optional UIA tool: `docs/Example Dependencies/UIA/UIATreeInspector.ahk` uses the standard AHK library form `#Include <UIA>`, resolved by its sibling `UIA/Lib/UIA.ahk`. It is not required by the quick demo, but its local library file is present.
- Compiler dependency closure: the checked-in Zig sources and clean build-option baselines are present. The transpiler executable, PGO trainer executable, training DLL, profiling DLL, generated shortcut bundle, and other build outputs are intentionally generated locally by the compiler.
- External prerequisites are limited to Windows, AutoHotkey v2, and the optional Interception driver for driver-backed operation. Zig 0.16 is required for native rebuilds; LLVM/Clang/MSVC are required only for the full PGO path.
- Documentation correction: README and installation guidance now identify `QMKInterception.ahk` as the actual library entry file; `QMK.ahk` remains the project name.

## Interception documentation pass 2026-09-05

- Reviewed the upstream [AutoHotInterception README](https://github.com/evilC/AutoHotInterception/blob/master/README.md), the [official Interception repository](https://github.com/oblitum/Interception), and the separate [Interception driver fix](https://github.com/hygorostrowskij/interception-driver-fix).
- Added the official elevated-command-prompt installation sequence (`install-interception.exe`, then `install-interception.exe /install`) to README.md, docs/INSTALL.md, and docs/TUTORIAL.md.
- Documented archive/DLL unblocking, backend selection, device-ID/reconnect troubleshooting, and low-level input safety warnings.
- Kept the boundary explicit: the external driver and AutoHotInterception wrapper are optional external prerequisites; their installers, service files, wrapper DLLs, and sample trees are not copied into this QMK.ahk release.
- Added `docs/COMPILER_GUI.md` as the single click-by-click guide for QMK Settings → Compile → Open PGO Compiler, including standard Zig versus optional PGO, transpiler behavior, and generated-output boundaries.

## Production sync pass 2026-09-05

- Inspected the actual active directory `production_code`; the user-provided spelling `production\_code` is not a literal directory name on this machine.
- Excluded all snapshot/archive/refactor/test directories, personal mapping files, personal compiled callbacks, generated shortcut output, PDBs, executables, caches, profiles, backups, and machine-specific configuration.
- Rejected the active `QMKconfig.ini` because it names personal shortcut sources and absolute local tool paths.
- Rejected the active `QMKInterception.ahk` as a direct copy because its documentation examples contain personal application/context callbacks and its MemoryModule include points outside the release package. The already-sanitized release wrapper remains authoritative.
- Rejected the active `QMKCompiler.ahk` as a direct copy because it would replace the release compiler's source-freshness checks with executable-presence-only reuse behavior. The release compiler's transpiler/trainer rebuild policy remains authoritative.
- Rejected the active `lib/QMKVariables.ahk` after decoding its embedded payload found personal compiled material. The sanitized release QMKCore/QMKVariables pairing was restored and preserved.
- Retained the active transpiler source's generic compatibility improvements for hotstring object fields and `TapHolds`; it contains no personal mappings. No runtime build or demo execution was performed.

Deliberate remaining caveats:

1. The demo and native runtime were not executed, per the syntax-only instruction.
2. The release keeps the embedded runtime payload already paired with the staged `QMKVariables.ahk`; rebuilding the native core is intentionally deferred until the user is ready to verify that runtime behavior.
3. GitHub visibility and the remote branch were not changed. The next external action is a user-approved push of the local checkpoint, followed later by a pull request into `main`.
