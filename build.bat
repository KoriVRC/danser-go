@echo off
setlocal enabledelayedexpansion

:: danser-go Windows Build Script (Port of dist-win.sh)
:: Usage: build.bat <version> [snapshot]
:: Example: build.bat 0.7.1

if "%~1" == "" (
    echo Usage: build.bat ^<version^> [snapshot]
    echo Example: build.bat 0.7.1
    exit /b 1
)

set "VERSION_ARG=%~1"
set "SNAPSHOT_ARG=%~2"

:: Replicate version formatting logic: 0.7.1 -> 0,7,1,
set "VER_RAW=%VERSION_ARG:.=,%"
set "VER_FORMATTED=%VER_RAW%,"

set "EXEC_NAME=%VERSION_ARG%"
set "BUILD_NAME=%VERSION_ARG%"

if not "%SNAPSHOT_ARG%" == "" (
    set "EXEC_NAME=%EXEC_NAME%-s%SNAPSHOT_ARG%"
    set "BUILD_NAME=%BUILD_NAME%-snapshot%SNAPSHOT_ARG%"
    set "VER_FORMATTED=%VER_FORMATTED%%SNAPSHOT_ARG%"
) else (
    set "VER_FORMATTED=%VER_FORMATTED%0"
)

:: Environment Setup
:: We use generic names, assuming they are in the PATH (e.g. from WinLibs)
if "%CC%" == "" set "CC=gcc"
if "%CXX%" == "" set "CXX=g++"

set "GOOS=windows"
set "GOARCH=amd64"
set "CGO_ENABLED=1"
set "CGO_LDFLAGS=-static-libstdc++ -static-libgcc -Wl,-Bstatic -lstdc++ -lpthread -Wl,-Bdynamic"
set "WINDRESFLAGS=-F pe-x86-64"
set "BUILD_DIR=dist\build-win"
set "TARGET_DIR=dist\artifacts"

if "%DANSER_BUILD_MODE%" == "" set "DANSER_BUILD_MODE=0"

if "%DANSER_BUILD_MODE%" == "0" goto build_process
if "%DANSER_BUILD_MODE%" == "1" goto build_process
goto pack_check

:build_process
echo --- Starting Build for version %BUILD_NAME% ---
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

:: 1. Build danser-core.dll
echo [1/4] Generating danser-core resources...
(
    echo #include "winuser.h"
    echo 1 VERSIONINFO
    echo FILEVERSION %VER_FORMATTED%
    echo FILEFLAGSMASK 0x3fL
    echo FILEOS 0x40004L
    echo FILETYPE 0x1L
    echo FILESUBTYPE 0x0L
    echo BEGIN
    echo   BLOCK "StringFileInfo"
    echo   BEGIN
    echo     BLOCK "040904b0"
    echo     BEGIN
    echo       VALUE "CompanyName", "Wieku"
    echo       VALUE "FileDescription", "danser-core.dll"
    echo       VALUE "LegalCopyright", "Wieku 2018-2024"
    echo       VALUE "ProductName", "danser"
    echo       VALUE "ProductVersion", "%BUILD_NAME%"
    echo     END
    echo   END
    echo   BLOCK "VarFileInfo"
    echo   BEGIN
    echo     VALUE "Translation", 0x409, 1200
    echo   END
    echo END
) > "%BUILD_DIR%\core.rc"
windres -l 0 %WINDRESFLAGS% -o "%BUILD_DIR%\danser.syso" "%BUILD_DIR%\core.rc"

echo [2/4] Bundling assets...
go run tools/assets/assets.go ./ %BUILD_DIR%/

copy "%BUILD_DIR%\danser.syso" "danser.syso" >nul

echo [3/4] Building danser-core.dll (C-Shared)...
go build -trimpath -ldflags "-s -w -X 'github.com/wieku/danser-go/build.VERSION=%BUILD_NAME%' -X 'github.com/wieku/danser-go/build.Stream=Release'" -buildmode=c-shared -o "%BUILD_DIR%\danser-core.dll" -v -tags "exclude_cimgui_glfw exclude_cimgui_sdli"

if errorlevel 1 (
    echo Error building danser-core.dll
    del /f "danser.syso"
    exit /b %errorlevel%
)

del /f "danser.syso"

:: 2. Build CLI and Launcher
echo [4/4] Generating application resources...
(
    echo #include "winuser.h"
    echo 1 VERSIONINFO
    echo FILEVERSION %VER_FORMATTED%
    echo FILEFLAGSMASK 0x3fL
    echo FILEOS 0x40004L
    echo FILETYPE 0x1L
    echo FILESUBTYPE 0x0L
    echo BEGIN
    echo   BLOCK "StringFileInfo"
    echo   BEGIN
    echo     BLOCK "040904b0"
    echo     BEGIN
    echo       VALUE "CompanyName", "Wieku"
    echo       VALUE "FileDescription", "danser"
    echo       VALUE "LegalCopyright", "Wieku 2018-2024"
    echo       VALUE "ProductName", "danser"
    echo       VALUE "ProductVersion", "%BUILD_NAME%"
    echo     END
    echo   END
    echo   BLOCK "VarFileInfo"
    echo   BEGIN
    echo     VALUE "Translation", 0x409, 1200
    echo   END
    echo END
    echo 2 ICON assets/textures/favicon.ico
) > "%BUILD_DIR%\danser.rc"
windres -l 0 %WINDRESFLAGS% -o "%BUILD_DIR%\danser.syso" "%BUILD_DIR%\danser.rc"

echo Copying dependency DLLs...
for %%f in (bass.dll bass_fx.dll bassmix.dll libyuv.dll) do (
    if exist "%%f" (
        copy "%%f" "%BUILD_DIR%\" >nul
    ) else (
        echo Warning: %%f not found in root directory.
    )
)

echo Compiling danser-cli.exe...
%CC% -O3 -o "%BUILD_DIR%\danser-cli.exe" -I. cmain/main_danser.c -I"%BUILD_DIR%" -L"%BUILD_DIR%" -ldanser-core "%BUILD_DIR%\danser.syso" -municode

echo Generating Launcher resources...
(
    echo #include "winuser.h"
    echo 1 VERSIONINFO
    echo FILEVERSION %VER_FORMATTED%
    echo FILEFLAGSMASK 0x3fL
    echo FILEOS 0x40004L
    echo FILETYPE 0x1L
    echo FILESUBTYPE 0x0L
    echo BEGIN
    echo   BLOCK "StringFileInfo"
    echo   BEGIN
    echo     BLOCK "040904b0"
    echo     BEGIN
    echo       VALUE "CompanyName", "Wieku"
    echo       VALUE "FileDescription", "danser launcher"
    echo       VALUE "LegalCopyright", "Wieku 2018-2024"
    echo       VALUE "ProductName", "danser"
    echo       VALUE "ProductVersion", "%BUILD_NAME%"
    echo     END
    echo   END
    echo   BLOCK "VarFileInfo"
    echo   BEGIN
    echo     VALUE "Translation", 0x409, 1200
    echo   END
    echo END
    echo 2 ICON assets/textures/favicon.ico
) > "%BUILD_DIR%\launcher.rc"
windres -l 0 %WINDRESFLAGS% -o "%BUILD_DIR%\danser.syso" "%BUILD_DIR%\launcher.rc"

echo Compiling danser.exe (Launcher)...
%CC% -O3 -D LAUNCHER -o "%BUILD_DIR%\danser.exe" -I. cmain/main_danser.c -I"%BUILD_DIR%" -L"%BUILD_DIR%" -ldanser-core "%BUILD_DIR%\danser.syso" -municode

:: Cleanup temp files in build dir
del /f "%BUILD_DIR%\danser.syso"
if exist "%BUILD_DIR%\danser-core.h" del /f "%BUILD_DIR%\danser-core.h"
del /f "%BUILD_DIR%\core.rc"
del /f "%BUILD_DIR%\danser.rc"
del /f "%BUILD_DIR%\launcher.rc"

echo Running ffmpeg tool...
go run tools/ffmpeg/ffmpeg.go "%BUILD_DIR%/"

:pack_check
if "%DANSER_BUILD_MODE%" == "0" goto pack_process
if "%DANSER_BUILD_MODE%" == "2" goto pack_process
goto end

:pack_process
if not exist "%TARGET_DIR%" mkdir "%TARGET_DIR%"
echo [Zip] Packing to %TARGET_DIR%\danser-%EXEC_NAME%-win.zip...
go run tools/pack2/pack.go "%TARGET_DIR%\danser-%EXEC_NAME%-win.zip" "%BUILD_DIR%/"

:end
echo --- Build Process Complete ---
endlocal
