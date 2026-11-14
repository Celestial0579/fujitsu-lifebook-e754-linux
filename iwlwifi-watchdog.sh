#!/bin/bash
# Erkennt den 7260-"fell off bus"-Zustand im Kernel-Log und belebt die Karte per PCI remove/rescan wieder.
# PCI-Adresse der Intel-7260-Karte (08b1/08b2) automatisch finden (Fallback 0000:02:00.0)
DEV=$(grep -lE "0x08b[12]" /sys/bus/pci/devices/*/device 2>/dev/null | head -1 | xargs -r dirname | xargs -r basename)
DEV=${DEV:-0000:02:00.0}
IFACE=$(ls /sys/bus/pci/devices/$DEV/net 2>/dev/null | head -1)
LOG=/var/log/iwlwifi-watchdog.log
PAT='iwlwifi.*(transaction failed, dumping registers|Device is not enabled|Failed to start RT ucode|Failed to run INIT ucode)'
last=0
journalctl -k -f -n0 -o cat | grep --line-buffered -E "$PAT" | while read -r line; do
  now=$(date +%s); (( now - last < 120 )) && continue; last=$now
  echo "$(date '+%F %T') WATCHDOG: $line -> PCI-Reset $DEV" | tee -a "$LOG"
  sleep 3
  [ -e /sys/bus/pci/devices/$DEV/remove ] && echo 1 > /sys/bus/pci/devices/$DEV/remove
  sleep 2; echo 1 > /sys/bus/pci/rescan; sleep 10
  if nmcli -t -f DEVICE dev | grep -qx "${IFACE:-wlp2s0}"; then echo "$(date '+%F %T') WATCHDOG: ${IFACE:-WLAN} wieder da" | tee -a "$LOG"
  else echo "$(date '+%F %T') WATCHDOG: Rescan erfolglos, Modul-Reload" | tee -a "$LOG"; modprobe -r iwlmvm iwlwifi; sleep 2; modprobe iwlwifi; fi
done
