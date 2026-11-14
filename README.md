# LIFEBOOK E754 – Hardware unter Linux

## Treiber `fujitsu-fext-extra` (DKMS 0.2, signiert mit MOK)

Ruft `\_SB.FEXT.FUNC` direkt auf; ergänzt den Mainline-Treiber `fujitsu_laptop`.

| Pfad | Funktion |
|---|---|
| `hwmon/…/fan1_input` | Lüfterdrehzahl (EC-Reg. 0x50, 30 000 000 / Periode) |
| `hwmon/…/temp1_input` | CPU-Temperatur laut EC |
| `hwmon/…/temp2_input` | geglättete Regeltemperatur des EC |
| `/sys/devices/platform/fujitsu-fext-extra/fan_curve` | Lüfterkurve der Firmware (°C, Stellwert) |
| `…/bay_power` | Strom Modulschacht (DVD) 0/1 |
| `…/bluetooth_power` | Strom Bluetooth-Controller 0/1 |

Entwicklung: `modprobe fujitsu_fext_extra allow_raw=1` → `raw_call` (`echo "1006 10 150 0" > raw_call; cat raw_call`).

Neu bauen nach Codeänderung: Version in `dkms.conf` erhöhen, nach `/usr/src/fujitsu-fext-extra-<ver>` kopieren, `dkms install`.

Nicht genutzt: S009 HWMR (zwingt den Lüfter auf Vollgas), S007 _PPC (unter intel_pstate wirkungslos), S00A Anytime-USB-Charge (Bitbelegung unbekannt).

## Weitere Fixes
- `/etc/udev/rules.d/80-iwlwifi-7260-no-aspm.rules` – ASPM L1 aus für Intel 7260 (fiel sonst vom PCIe-Bus)
- `iwlwifi-watchdog.service` – PCI-Reset der WLAN-Karte bei Firmware-Absturz, Log `/var/log/wifi-monitor/events.log`

## Testergebnisse 2026-11-14
S3 ✅ · s2idle ✅ · Hibernate ❌ (Secure-Boot-Lockdown) · Ladegrenze 50–100 % ✅ · Fingerprint ✅ · BT/Bay-Strom ✅ · Hotkeys ✅
(Helligkeit, Lautstärke, Stumm, Win+P, Funk = KEY_RFKILL, Taste mit Scan 0x413 = KEY_PROG4, frei belegbar)
Package-C-State nur PC2 (~6,5 W idle), Folge von ASPM-aus am WLAN. Akku 69 % Restkapazität.
