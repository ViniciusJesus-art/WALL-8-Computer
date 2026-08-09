@echo off
setlocal

rem Vai para a pasta Software
cd /d "%~dp0.."

Tools\customasm.exe CARD\CARD_03.asm -f binary -o CARD\CARD_03.bin

if errorlevel 1 (
    echo.
    echo ERRO AO COMPILAR O CARTUCHO
    pause
    exit /b 1
)

echo.
echo CARTUCHO COMPILADO COM SUCESSO
pause