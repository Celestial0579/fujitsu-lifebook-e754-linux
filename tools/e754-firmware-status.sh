#!/bin/bash
# Firmware- und Sicherheitsstatus eines LIFEBOOK E754 anzeigen (nur lesend).
# Aufruf: sudo ./tools/e754-firmware-status.sh
set -u

[ "$(id -u)" = 0 ] || { echo "Bitte mit sudo ausfuehren (PCI-Register und TPM lesen)."; exit 1; }

ok()   { printf '  [OK]    %s\n' "$*"; }
warn() { printf '  [WARN]  %s\n' "$*"; }
info() { printf '  [INFO]  %s\n' "$*"; }

dmi() { cat "/sys/class/dmi/id/$1" 2>/dev/null; }

echo "== System"
info "$(dmi sys_vendor) $(dmi product_name), BIOS $(dmi bios_version) ($(dmi bios_date))"
[ "$(dmi product_name)" = "LIFEBOOK E754" ] || warn "Kein LIFEBOOK E754, Angaben unten evtl. nicht zutreffend"

echo "== Intel ME / AMT"
if lspci -s 00:16.0 >/dev/null 2>&1 && [ -n "$(lspci -s 00:16.0)" ]; then
  fw=$(setpci -s 00:16.0 0x40.L 2>/dev/null || true)
  if [ -n "$fw" ]; then
    v=$((16#$fw))
    state=$(( v & 0xf )); opmode=$(( (v >> 16) & 0xf )); err=$(( (v >> 12) & 0xf ))
    info "FWSTS1=0x$fw: CurrentState=$state (5=Normal), OperationMode=$opmode (0=Normal, 3=Soft-Disable), ErrorCode=$err"
  fi
else
  ok "MEI-Controller 00:16.0 nicht sichtbar (ME im BIOS verborgen)"
fi
if [ -n "$(lspci -s 00:16.3 2>/dev/null)" ]; then
  warn "AMT aktiv: KT/SOL-Controller 00:16.3 vorhanden -> im MEBx (Strg+P) 'Manageability Feature Selection' auf Disabled"
else
  ok "AMT aus (KT/SOL-Controller 00:16.3 nicht vorhanden)"
fi
ver=$(head -1 /sys/class/mei/mei0/fw_ver 2>/dev/null)
if [ -n "$ver" ]; then
  case "$ver" in
    *:9.1.4[5-9].3*|*:9.1.[5-9]*) ok "ME-Firmware $ver (INTEL-SA-00075 behoben)";;
    *) warn "ME-Firmware $ver: INTEL-SA-00075 offen (behobene Builds beginnen mit 3, z.B. 9.1.45.3000)";;
  esac
else
  info "ME-Version nicht lesbar (mei-Treiber gesperrt oder nicht geladen)"
fi
if lsmod | grep -q '^mei '; then
  info "mei-Treiber geladen (optional sperren: blacklist-intel-mei.conf)"
else
  ok "mei-Treiber nicht geladen"
fi

echo "== BIOS-Flash"
bc=$(setpci -s 00:1f.0 0xdc.b 2>/dev/null || echo "")
if [ -n "$bc" ]; then
  b=$((16#$bc))
  if (( (b >> 1) & 1 )) || (( (b >> 5) & 1 )); then ok "BIOS_CNTL=0x$bc: Schreibschutz-Lock gesetzt"
  else warn "BIOS_CNTL=0x$bc: BLE=0 und SMM_BWP=0, BIOS-Region nicht gegen Schreiben gesperrt"; fi
fi
w=0
for f in /sys/class/mtd/mtd*/flags; do
  [ -e "$f" ] || continue
  fl=$(( $(cat "$f") ))
  (( fl & 0x400 )) && { warn "$(dirname "$f" | xargs basename) ($(cat "$(dirname "$f")/name")) ist beschreibbar -> blacklist-spi-intel.conf"; w=1; }
done
[ $w = 0 ] && ok "Kein beschreibbares /dev/mtd"

echo "== TPM"
T=/sys/class/tpm/tpm0
if [ -e "$T" ]; then
  fwv=$(sed -n 's/^Firmware version: //p' "$T/device/caps" 2>/dev/null)
  info "TPM $(sed -n 's/^TCG version: //p' "$T/device/caps" 2>/dev/null), Firmware $fwv, owned=$(cat "$T/device/owned" 2>/dev/null)"
  case "$fwv" in
    4.3[0-3]) warn "Infineon $fwv ist von ROCA (CVE-2017-15361) betroffen; relevant nur fuer im TPM erzeugte RSA-Schluessel";;
    4.34|4.4*) ok "TPM-Firmware $fwv nicht von ROCA betroffen";;
  esac
else
  info "Kein TPM sichtbar"
fi

echo "== CPU-Microcode"
info "Revision $(grep -m1 microcode /proc/cpuinfo | awk '{print $3}') (0x28 ist die letzte fuer i5-4210M/Haswell 06-3c-03)"

echo "== WWAN"
if command -v qmicli >/dev/null && [ -e /dev/cdc-wdm0 ]; then
  qmicli -d /dev/cdc-wdm0 --device-open-proxy --dms-get-revision 2>/dev/null | sed -n 's/.*Revision: /  [INFO]  Modem /p'
else
  info "kein Modem/qmicli"
fi
