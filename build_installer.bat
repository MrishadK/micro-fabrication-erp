@echo off
setlocal
echo ====================================================================
echo  MICRO Manager - Obfuscated Release & Professional Installer Build
echo ====================================================================
echo.

echo [1/2] Compiling obfuscated Windows release with stripped debug symbols...
call flutter build windows --release --obfuscate --split-debug-info=build\windows\symbols
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Flutter build failed!
    exit /b %errorlevel%
)

echo.
echo [2/2] Packaging single .exe professional installer with Inno Setup...
"C:\Users\RISHAD\AppData\Local\Programs\Inno Setup 6\ISCC.exe" "installer\micro_setup.iss"
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Inno Setup compilation failed!
    exit /b %errorlevel%
)

echo.
echo ====================================================================
echo  SUCCESS! Single .exe installer created at:
echo  dist\MICRO_Manager_Setup_v0.2.3.exe
echo ====================================================================
pause
