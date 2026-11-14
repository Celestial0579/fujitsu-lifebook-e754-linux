#!/bin/bash
# Baut ein bootfaehiges FreeDOS-Image, das die Intel-ME-Firmware eines
# LIFEBOOK E754 vPro auf 9.1.45.3000 aktualisiert (behebt INTEL-SA-00075).
#
# Benoetigt (selbst herunterladen, wird hier nicht verteilt):
#   1. Fujitsu "Intel Management Engine Firmware ME9.1 9.1.45.3000 - QSR" (zip, 18 MB)
#      support.ts.fujitsu.com -> Produkt "LIFEBOOK E754 vPro" -> Windows 10 -> Driver -> Flash - Firmware
#   2. FreeDOS 1.4 Lite USB: https://download.freedos.org/1.4/FD14-LiteUSB.zip
#
# Aufruf: ./tools/build-me-stick.sh <ME-zip> <FD14-LiteUSB.zip> [ausgabe.img]
# Kein root noetig (mtools). Danach auf einen USB-Stick schreiben, siehe README.
set -euo pipefail

ME_SHA=62c2117cf9eda5eaae51bd5f5e2291850a990e63ebe4de1956c67bb8202d1f01
FD_SHA=857dcd2ebf9d3d094320154db5fb5b830acba6fb98f981a95a0ca7ab3350338b
HERE=$(cd "$(dirname "$0")" && pwd)

[ $# -ge 2 ] || { sed -n '2,13p' "$0"; exit 1; }
ME_ZIP=$1; FD_ZIP=$2; OUT=${3:-me-update-usb.img}

for t in mcopy mmd mren mtype unzip sha256sum; do
  command -v "$t" >/dev/null || { echo "Fehlt: $t (sudo apt install mtools unzip)"; exit 1; }
done
check() { echo "$2  $1" | sha256sum -c --quiet - || { echo "SHA256 von $1 stimmt nicht"; exit 1; }; }
check "$ME_ZIP" "$ME_SHA"
check "$FD_ZIP" "$FD_SHA"

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
unzip -q "$ME_ZIP" -d "$W/me"
unzip -q "$FD_ZIP" FD14LITE.img -d "$W"
TOOL=$(find "$W/me" -path '*DOS update tool*' -iname 'FWUpdLcl.exe' | head -1)
BIN=$(find "$W/me" -path '*64-bit*' -iname 'ME9.1_5M_Production.bin' | head -1)
[ -n "$TOOL" ] && [ -n "$BIN" ] || { echo "ME-Paket hat unerwarteten Inhalt"; exit 1; }

cp "$W/FD14LITE.img" "$OUT"
export MTOOLS_SKIP_CHECK=1
D="$OUT@@32256"            # FAT16-Partition beginnt bei Sektor 63

mmd -i "$D" ::ME
mcopy -i "$D" "$TOOL" ::ME/FWUPDLCL.EXE
mcopy -i "$D" "$BIN" ::ME/ME91_5M.BIN
mcopy -i "$D" "$HERE/me-stick/MEUPD.BAT" ::ME/MEUPD.BAT

# FreeDOS-Installer abschalten, stattdessen das ME-Update aufrufen
mren -i "$D" ::setup.bat ::SETUP.OFF
mtype -i "$D" ::fdauto.bat | tr -d '\r' \
  | sed 's|^if not exist SETUP.BAT goto Done$|goto Done|; s|^:Done$|:Done\nCALL \\ME\\MEUPD.BAT|' \
  | sed 's/$/\r/' > "$W/fdauto.bat"
grep -q 'CALL \\ME\\MEUPD.BAT' "$W/fdauto.bat" || { echo "fdauto.bat unerwartet"; exit 1; }
mcopy -o -i "$D" "$W/fdauto.bat" ::fdauto.bat

# CHOICE.EXE fehlt in der Lite-Variante, liegt aber als Paket bei
mcopy -i "$D" ::packages/base/choice.zip "$W/choice.zip"
unzip -q -j "$W/choice.zip" BIN/CHOICE.EXE -d "$W"
mcopy -i "$D" "$W/CHOICE.EXE" ::freedos/bin/CHOICE.EXE

echo "Fertig: $OUT ($(sha256sum "$OUT" | cut -c1-16)...)"
echo "Auf USB-Stick schreiben (ALLE Daten darauf gehen verloren, /dev/sdX genau pruefen!):"
echo "  sudo dd if=$OUT of=/dev/sdX bs=4M conv=fsync status=progress"
