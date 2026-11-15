@echo off
cls
echo ==========================================================
echo  Intel ME Firmware-Update fuer LIFEBOOK E754 vPro
echo  Ziel: 9.1.45.3000 (Fujitsu-Paket 1219020, SHA256 geprueft)
echo ==========================================================
echo.
echo  WICHTIG: Netzteil anschliessen, Rechner NICHT ausschalten.
echo.
echo Aktuelle ME-Version:
set MEFAIL=
\ME\FWUPDLCL.EXE -fwver > \ME\VORHER.TXT
if errorlevel 1 set MEFAIL=1
type \ME\VORHER.TXT
if "%MEFAIL%"=="1" goto nichtlesbar
echo.
choice /C:JN Jetzt die ME-Firmware flashen
if errorlevel 2 goto abbruch
REM geflasht wird nur bei genau 1 (J); CHOICE liefert nach Strg+C 0
if not errorlevel 1 goto abbruch
echo.
echo Starte Update, das dauert einige Minuten ...
\ME\FWUPDLCL.EXE -f \ME\ME91_5M.BIN
if errorlevel 1 goto fehler
echo OK > \ME\ERGEBNIS.TXT
echo.
echo ======================================================
echo  ME-Update ERFOLGREICH. Neue Version:
\ME\FWUPDLCL.EXE -fwver > \ME\NACHHER.TXT
type \ME\NACHHER.TXT
echo  Stick abziehen, dann Taste druecken fuer Neustart.
echo  Danach im BIOS (F2) Secure Boot wieder einschalten!
echo ======================================================
pause
fdapm coldboot
goto ende
:fehler
echo FEHLER > \ME\ERGEBNIS.TXT
echo.
echo !!! ME-Update mit Fehler beendet. Rechner NICHT ausschalten, !!!
echo !!! Foto vom Bildschirm machen, Issue im Repo anlegen.      !!!
goto ende
:nichtlesbar
echo NICHTLESBAR > \ME\ERGEBNIS.TXT
echo.
echo ME nicht lesbar - Update wird NICHT gestartet. Stick abziehen, neu starten.
goto ende
:abbruch
echo ABGEBROCHEN > \ME\ERGEBNIS.TXT
echo Abgebrochen, nichts geflasht. Stick abziehen und neu starten.
:ende
