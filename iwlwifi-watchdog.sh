#!/bin/bash
# Erkennt den 7260-"fell off bus"-Zustand im Kernel-Log und belebt die Karte per PCI remove/rescan wieder.
DEV=0000:02:00.0
LOG=/var/log/wifi-monitor/events.log
PAT='iwlwifi.*(transaction failed, dumping registers|Device is not enabled|Failed to start RT ucode|Failed to run INIT ucode)'
last=0
journalctl -k -f -n0 -o cat | grep --line-buffered -E "$PAT" | while read -r line; do
  now=$(date +%s); (( now - last < 120 )) && continue; last=$now
  echo "$(date '+%F %T') WATCHDOG: $line -> PCI-Reset $DEV" | tee -a "$LOG"
  sleep 3
  [ -e /sys/bus/pci/devices/$DEV/remove ] && echo 1 > /sys/bus/pci/devices/$DEV/remove
  sleep 2; echo 1 > /sys/bus/pci/rescan; sleep 10
  if nmcli -t -f DEVICE dev | grep -q '^wlp2s0$'; then echo "$(date '+%F %T') WATCHDOG: wlp2s0 wieder da" | tee -a "$LOG"
  else echo "$(date '+%F %T') WATCHDOG: Rescan erfolglos, Modul-Reload" | tee -a "$LOG"; modprobe -r iwlmvm iwlwifi; sleep 2; modprobe iwlwifi; fi
done
