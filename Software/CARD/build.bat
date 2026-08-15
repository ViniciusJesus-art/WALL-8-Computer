@echo off
setlocal

rem Vai para a pasta Software
cd /d "%~dp0.."

Tools\customasm.exe CARD\CARD_battle_city_wall8.asm -f binary -o CARD\CARD_battle_city_wall8.bin

if errorlevel 1 (
    echo.
    echo ERRO AO COMPILAR O CARTUCHO
    pause
    exit /b 1
)

echo.
echo CARTUCHO COMPILADO COM SUCESSO
pause