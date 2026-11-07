@echo off
setlocal enabledelayedexpansion

:: ============================================================
:: Print-Excel.bat  —  Print an .xlsx file from Windows CMD
:: Usage:  Print-Excel.bat <file.xlsx> [copies]
:: Requires Microsoft Excel to be installed.
:: ============================================================

if "%~1"=="" (
    echo.
    echo  Usage:   %~nx0 file.xlsx [copies]
    echo  Example: %~nx0 report.xlsx
    echo           %~nx0 report.xlsx 2
    echo.
    exit /b 1
)

set "FILE=%~f1"
set "COPIES=%~2"
if "%COPIES%"=="" set "COPIES=1"

if not exist "%FILE%" (
    echo.
    echo  Error: File not found — %FILE%
    echo.
    exit /b 1
)

:: --- Validate copies is a positive integer ---
for /f "delims=0123456789" %%c in ("%COPIES%") do (
    echo  Error: Copies must be a positive integer.
    exit /b 1
)

:: --- Discover printers via PowerShell ---
echo.
echo  Discovering printers...
set COUNT=0
for /f "usebackq delims=" %%P in (
    `powershell -NoProfile -Command "Get-CimInstance Win32_Printer | Select-Object -ExpandProperty Name | Sort-Object"`
) do (
    set /a COUNT+=1
    set "PRINTER_!COUNT!=%%P"
)

if %COUNT%==0 (
    echo  No printers found on this system.
    exit /b 1
)

:: --- Printer selection ---
if %COUNT%==1 (
    set "SELECTED=!PRINTER_1!"
    echo  Single printer found — using: !SELECTED!
) else (
    echo.
    echo  Available printers:
    echo.
    for /l %%i in (1,1,%COUNT%) do (
        echo    [%%i] !PRINTER_%%i!
    )
    echo.

    :pick
    set "CHOICE="
    set /p "CHOICE=  Select printer [1-%COUNT%]: "
    if not defined CHOICE goto pick
    for /f "delims=0123456789" %%c in ("!CHOICE!") do goto pick
    if !CHOICE! LSS 1 goto pick
    if !CHOICE! GTR %COUNT% goto pick
    set "SELECTED=!PRINTER_%CHOICE%!"
)

echo.
echo  File   : %~nx1
echo  Printer: !SELECTED!
echo  Copies : %COPIES%
echo.

:: --- Pass values via environment variables to avoid quoting issues ---
set "PRINT_FILE=%FILE%"
set "PRINT_PRINTER=!SELECTED!"
set "PRINT_COPIES=%COPIES%"

powershell -NoProfile -Command ^
    "$xl=$null; $wb=$null; " ^
    "try { " ^
        "$xl = New-Object -ComObject Excel.Application; " ^
        "$xl.Visible = $false; $xl.DisplayAlerts = $false; " ^
        "$wb = $xl.Workbooks.Open($env:PRINT_FILE, 0, $true); " ^
        "$wb.PrintOut([Type]::Missing, [Type]::Missing, [int]$env:PRINT_COPIES, $false, $env:PRINT_PRINTER); " ^
        "Write-Host '  Print job sent successfully.' " ^
    "} catch { " ^
        "Write-Error ('Print failed: ' + $_); exit 1 " ^
    "} finally { " ^
        "if ($wb) { $wb.Close($false) }; " ^
        "if ($xl) { $xl.Quit() }; " ^
        "[GC]::Collect() " ^
    "}"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo  Print failed. See error above.
    exit /b 1
)

echo.
