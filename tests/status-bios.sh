#!/bin/bash
# Prueft die Auswertung von BIOS_CNTL in tools/e754-firmware-status.sh gegen
# Attrappen (id, setpci, lspci): kein Zugriff auf echte Hardware, kein root.
set -euo pipefail
cd "$(dirname "$0")/.."

attrappen=$(mktemp -d)
trap 'rm -rf "$attrappen"' EXIT
cat > "$attrappen/id" <<'ATT'
#!/bin/sh
echo 0
ATT
cat > "$attrappen/setpci" <<'ATT'
#!/bin/sh
# nur BIOS_CNTL (0xdc) liefert etwas
case "$*" in *0xdc.b*) echo "$BIOS_CNTL" ;; *) exit 1 ;; esac
ATT
cat > "$attrappen/lspci" <<'ATT'
#!/bin/sh
exit 0
ATT
chmod +x "$attrappen"/*

fehler=0
pruefe() {  # pruefe <BIOS_CNTL> <OK|WARN> <Muster in der Zeile>
    local zeile
    zeile=$(BIOS_CNTL="$1" PATH="$attrappen:$PATH" bash tools/e754-firmware-status.sh 2>/dev/null \
        | grep 'BIOS_CNTL=' || true)
    if [[ "$zeile" == *"[$2]"* && "$zeile" == *"$3"* ]]; then
        echo "  OK    BIOS_CNTL=0x$1 -> $2"
    else
        echo "  FEHL  BIOS_CNTL=0x$1 erwartet $2 mit '$3', erhalten: '$zeile'"
        fehler=$((fehler + 1))
    fi
}

pruefe 00 WARN "BLE=0 SMM_BWP=0"
pruefe 02 WARN "SMM_BWP=0"      # nur BLE: das Race bleibt moeglich
pruefe 20 WARN "BLE=0"          # nur SMM_BWP
pruefe 22 OK   "vollstaendig"   # BLE + SMM_BWP
pruefe 23 WARN "BIOSWE=1"       # Schreibzugriff freigeschaltet

[ "$fehler" -eq 0 ] || { echo "$fehler Pruefung(en) fehlgeschlagen"; exit 1; }
echo "alle Pruefungen bestanden"
