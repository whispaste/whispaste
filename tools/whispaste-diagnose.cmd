@echo off
rem ===========================================================================
rem  WhisPaste-Diagnose - AV-sicherer Doppelklick-Starter
rem
rem  Fuehrt das danebenliegende PowerShell-Skript aus, ohne dass der Nutzer
rem  die ExecutionPolicy aendern oder PowerShell von Hand oeffnen muss.
rem  Im Gegensatz zur kompilierten .exe wird hier nichts compiliert -> keine
rem  Antiviren-Falschalarme (Defender/SmartScreen).
rem
rem  Diese .cmd MUSS im selben Ordner wie whispaste-diagnose.ps1 liegen.
rem  Erzeugt eine Report-Datei auf dem Desktop und zeigt sie im Fenster an.
rem ===========================================================================
setlocal
set "SCRIPT=%~dp0whispaste-diagnose.ps1"

if not exist "%SCRIPT%" (
  echo [FEHLER] whispaste-diagnose.ps1 nicht gefunden neben dieser .cmd-Datei.
  echo          Bitte beide Dateien in denselben Ordner legen.
  echo.
  pause
  exit /b 1
)

rem Das ps1 gibt selbst eine ausfuehrliche Abschluss-Anweisung aus; die Pause
rem uebernimmt diese .cmd (daher -NoPause), damit der Nutzer nicht zweimal
rem bestaetigen muss.
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -NoPause %*
set "RC=%ERRORLEVEL%"

echo.
pause
exit /b %RC%
