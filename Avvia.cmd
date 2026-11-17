@echo off
rem ================================================================
rem  Avvia.cmd - avvia "Regia" con i permessi di amministratore
rem  Basta un doppio clic su questo file. Funziona su Windows 10 e 11.
rem ================================================================
setlocal
cd /d "%~dp0"
set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PS%" set "PS=powershell.exe"

rem --- Controllo permessi: "net session" riesce solo come amministratore
net session >nul 2>&1
if errorlevel 1 (
    echo Richiesta dei permessi di amministratore in corso...
    set "OTTWIN_CMD=%~f0"
    "%PS%" -NoProfile -Command "Start-Process -FilePath $env:OTTWIN_CMD -Verb RunAs"
    exit /b
)

rem --- Controllo che il programma sia nella stessa cartella
if not exist "%~dp0Regia.ps1" (
    echo File Regia.ps1 non trovato nella cartella %~dp0
    echo Se hai aperto il programma da un file .zip, estrai prima tutta la cartella.
    pause
    exit /b 1
)

echo Avvio di Regia in corso...
echo Questa finestra si chiude da sola quando chiudi il programma.
"%PS%" -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0Regia.ps1"
if errorlevel 1 (
    echo.
    echo Il programma si e' chiuso con un errore. Guarda il log nella cartella Dati\Log.
    pause
)
endlocal
