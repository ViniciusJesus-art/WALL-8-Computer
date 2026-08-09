@echo off
setlocal

rem Vai para a pasta Software
cd /d "%~dp0.."

Tools\customasm.exe Checkup\wall8_checkup_completo_v1.asm -f binary -o Checkup\wall8_checkup_completo_v1.bin

if errorlevel 1 (
    echo.
    echo ERRO AO COMPILAR O CARTUCHO
    pause
    exit /b 1
)

echo.
echo CARTUCHO COMPILADO COM SUCESSO
pause