#!/bin/bash
# Installiert fujitsu-fext-extra (DKMS) und optional die Intel-7260-WLAN-Fixes.
# Aufruf: sudo ./install.sh [--no-wifi]
set -euo pipefail
cd "$(dirname "$0")"
[ "$(id -u)" = 0 ] || { echo "Bitte mit sudo ausfuehren."; exit 1; }

NAME=fujitsu-fext-extra
VER=$(sed -n 's/^PACKAGE_VERSION="\(.*\)"/\1/p' $NAME/dkms.conf)

model=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
echo "Modell: $model"
[ "$model" = "LIFEBOOK E754" ] || echo "WARNUNG: nur auf LIFEBOOK E754 getestet; Laden dort nur mit 'modprobe $NAME force=1'."

command -v dkms >/dev/null || apt-get install -y dkms
apt-get install -y "linux-headers-$(uname -r)" || true

dkms remove "$NAME/$VER" --all >/dev/null 2>&1 || true
rm -rf "/usr/src/$NAME-$VER"
cp -r "$NAME" "/usr/src/$NAME-$VER"
dkms install "$NAME/$VER"
echo fujitsu_fext_extra > /etc/modules-load.d/$NAME.conf

if [ "${1:-}" != "--no-wifi" ] && grep -qsE '0x08b[12]' /sys/bus/pci/devices/*/device; then
  echo "Intel Wireless 7260 gefunden: installiere ASPM-Fix und Watchdog"
  install -m644 80-iwlwifi-7260-no-aspm.rules /etc/udev/rules.d/
  udevadm control --reload && udevadm trigger -s pci -a vendor=0x8086
  install -m755 iwlwifi-watchdog.sh /usr/local/sbin/
  install -m644 iwlwifi-watchdog.service /etc/systemd/system/
  systemctl daemon-reload && systemctl enable --now iwlwifi-watchdog.service
fi

if modprobe fujitsu_fext_extra 2>/dev/null; then
  echo "OK: Modul geladen -> /sys/devices/platform/fujitsu-fext-extra"
elif mokutil --sb-state 2>/dev/null | grep -q enabled; then
  echo
  echo "Secure Boot ist aktiv und der DKMS-Schluessel noch nicht eingetragen:"
  echo "  sudo mokutil --import /var/lib/shim-signed/mok/MOK.der"
  echo "Einmal-Passwort festlegen, neu starten, im blauen MOK-Manager 'Enroll MOK' waehlen."
else
  echo "Modul konnte nicht geladen werden, siehe: sudo dmesg | tail"
  exit 1
fi
