@echo off
if /i "%~1" NEQ "__stayopen__" (
  start "QMKCore Zig Build" /wait cmd /k ""%~f0" __stayopen__"
  exit /b
)

set "ZIG=C:\Program Files\zig\zig.exe"
set "DEST=C:\Users\s262925\OneDrive\Documents\AutoHotkey\lib"
set "SCRIPT=C:\Users\s262925\OneDrive\Documents\AutoHotkey\lib\Macropad Compile.ahk"
set "SRC=C:\Users\s262925\OneDrive\Documents\AutoHotkey\lib\Libraries\QMKInterception\QMKCoreInterceptiondebugprofiling.zig"
set "LIB_DIR=C:\Users\s262925\OneDrive\Documents\AutoHotkey\lib\Libraries\QMKInterception"
set "DLL=QMKCoreZigProfiling.dll"

if not exist "%ZIG%" ( echo ERROR: zig.exe not found & pause & exit /b 1 )
if not exist "%SRC%" ( echo ERROR: source missing & pause & exit /b 1 )
if not exist "%LIB_DIR%\interception.lib" ( echo WARNING: interception.lib not found )

echo Compiling...
"%ZIG%" build-lib ^
    -dynamic ^
    -target x86_64-windows-gnu ^
    -O ReleaseFast ^
    -fsingle-threaded ^
    -fno-stack-check ^
    -fno-unwind-tables ^
    -femit-bin="%DLL%" ^
    "%SRC%" ^
    -lntdll ^
    -luser32 ^
    -lkernel32

if %ERRORLEVEL% NEQ 0 (
    echo BUILD FAILED
    pause & exit /b 1
)

echo Build OK - copying...
copy /Y "%DLL%" "%DEST%\%DLL%"
if %ERRORLEVEL% NEQ 0 ( echo COPY FAILED & pause & exit /b 1 )

echo SUCCESS: %DLL% copied to %DEST%


powershell -NoProfile -ExecutionPolicy Bypass -Command ^
"Add-Type -AssemblyName System.Windows.Forms; ^
$qmk = [Convert]::ToBase64String([IO.File]::ReadAllBytes('C:\Users\s262925\OneDrive\Documents\AutoHotkey\lib\Libraries\QMKInterception\QMKCoreZigProfiling.dll')); ^
[System.Windows.Forms.Clipboard]::SetText($qmk); ^
Write-Host 'Copied to clipboard!'"
pause
exit