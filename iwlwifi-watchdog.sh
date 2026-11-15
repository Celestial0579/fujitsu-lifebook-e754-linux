#!/bin/bash
# Erkennt den 7260-"fell off bus"-Zustand im Kernel-Log und belebt die Karte per
# PCI remove/rescan wieder. Ausgaben gehen nur ins Journal:
#   journalctl -u iwlwifi-watchdog
set -u

# Intel Wireless 7260 (8086:08b1 / 8086:08b2) suchen: Hersteller UND Geraet pruefen
find_dev() {
  local d
  for d in /sys/bus/pci/devices/*; do
    [ "$(cat "$d/vendor" 2>/dev/null)" = 0x8086 ] || continue
    case "$(cat "$d/device" 2>/dev/null)" in
      0x08b1|0x08b2) basename "$d"; return 0 ;;
    esac
  done
  return 1
}

# Netzwerk-Interface der Karte (leer, wenn keines existiert)
iface_of() {
  local n
  for n in "/sys/bus/pci/devices/$1/net/"*; do
    [ -e "$n" ] && { basename "$n"; return 0; }
  done
  return 1
}

DEV=$(find_dev) || { echo "Keine Intel Wireless 7260 gefunden, Waechter beendet."; exit 0; }
IFACE=$(iface_of "$DEV")
echo "Ueberwache $DEV (${IFACE:-ohne Interface})"

# Nur echte iwlwifi-Kernelmeldungen dieser Karte, am Zeilenanfang verankert
PAT="^iwlwifi ${DEV//./\\.}: (iwlwifi transaction failed, dumping registers|Device is not enabled|Failed to start RT ucode|Failed to run INIT ucode)"
MAX_TRIES=5           # danach aufgeben, bis die Karte wieder laeuft
last=0; tries=0

journalctl -k -f -n0 -o cat | grep --line-buffered -E "$PAT" | while read -r line; do
  now=$(date +%s)
  (( now - last < 120 )) && continue
  last=$now
  if (( tries >= MAX_TRIES )); then
    # Karte inzwischen wieder da (manuell, Suspend/Resume)? Dann neu zaehlen.
    if [ -n "$(iface_of "$DEV")" ]; then
      echo "$(iface_of "$DEV") wieder da, setze Zaehler zurueck"
      tries=0
    else
      echo "Schon $tries erfolglose Resets, ueberspringe: $line"
      continue
    fi
  fi
  tries=$((tries + 1))
  echo "Absturz erkannt ($line) -> PCI-Reset $DEV, Versuch $tries/$MAX_TRIES"
  sleep 3
  [ -e "/sys/bus/pci/devices/$DEV/remove" ] && echo 1 > "/sys/bus/pci/devices/$DEV/remove"
  sleep 2
  echo 1 > /sys/bus/pci/rescan
  sleep 10
  IFACE=$(iface_of "$DEV")
  if [ -n "$IFACE" ]; then
    echo "$IFACE wieder da"
    tries=0
  else
    echo "Rescan erfolglos, lade iwlwifi neu"
    modprobe -r iwlmvm iwlwifi; sleep 2; modprobe iwlwifi; sleep 5
    IFACE=$(iface_of "$DEV")
    [ -n "$IFACE" ] && { echo "$IFACE nach Modul-Reload wieder da"; tries=0; }
  fi
done
# Nur erreicht, wenn der Kernel-Log-Strom endet (journalctl beendet): mit
# Fehlerstatus aus, damit systemd (Restart=on-failure) den Waechter neu startet.
echo "Kernel-Log-Strom beendet, Waechter beendet sich"
exit 1
