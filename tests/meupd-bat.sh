#!/bin/bash
# MEUPD.BAT laeuft nur auf DOS und laesst sich hier nicht ausfuehren. Geprueft
# wird statisch, dass nach CHOICE nur bei genau 1 (J) geflasht werden kann:
# vor dem Flash-Aufruf muessen beide Abbruch-Pruefungen stehen (ERRORLEVEL 0
# kommt von CHOICE nach Strg+C und darf nicht durchfallen).
set -euo pipefail
cd "$(dirname "$0")/.."
bat=tools/me-stick/MEUPD.BAT

zeile() { grep -n -i -m1 "$1" "$bat" | cut -d: -f1 || true; }
choice=$(zeile '^choice ')
n2=$(zeile '^if errorlevel 2 goto abbruch')
n1=$(zeile '^if not errorlevel 1 goto abbruch')
flash=$(zeile 'FWUPDLCL.EXE -f ')

for v in choice n2 n1 flash; do
    [ -n "${!v}" ] || { echo "FEHL: '$v' nicht in $bat gefunden"; exit 1; }
done
if [ "$choice" -lt "$n2" ] && [ "$n2" -lt "$flash" ] && [ "$n1" -lt "$flash" ] && [ "$choice" -lt "$n1" ]; then
    echo "OK: vor dem Flash stehen beide Abbruch-Pruefungen nach CHOICE"
else
    echo "FEHL: Reihenfolge CHOICE ($choice), if errorlevel 2 ($n2), if not errorlevel 1 ($n1), Flash ($flash)"
    exit 1
fi
