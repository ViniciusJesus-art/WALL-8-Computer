@echo off
setlocal

rem Vai para a pasta Software
cd /d "%~dp0.."

Tools\customasm.exe BIOS\wall8_bios_monitor_v4_1.asm -f binary -o BIOS\wall8_bios_monitor_v4_1.bin

if errorlevel 1 (
    echo.
    echo ERRO AO COMPILAR O CARTUCHO
    pause
    exit /b 1
)

echo.
echo CARTUCHO COMPILADO COM SUCESSO
pause