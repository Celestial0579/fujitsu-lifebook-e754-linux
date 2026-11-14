# Fujitsu LIFEBOOK E754 unter Linux

[![CI](https://github.com/Celestial0579/fujitsu-lifebook-e754-linux/actions/workflows/ci.yml/badge.svg)](https://github.com/Celestial0579/fujitsu-lifebook-e754-linux/actions/workflows/ci.yml)

Zusatztreiber und Fixes für das **Fujitsu LIFEBOOK E754**, die Funktionen nachrüsten, die sonst nur Fujitsus Windows-Tools ansprechen.

> **English summary:** `fujitsu-fext-extra` is an out-of-tree kernel module for the Fujitsu LIFEBOOK E754 that complements the mainline `fujitsu_laptop` driver. It exposes the fan speed, EC temperatures and the firmware fan curve via hwmon/sysfs, and lets you power the modular bay and the Bluetooth controller on and off. Also included: a udev rule and a watchdog for the Intel Wireless 7260 "falling off the PCIe bus". Install with `sudo ./install.sh`. Tested on BIOS 1.32, kernel 7.0, Ubuntu 26.04, Secure Boot enabled.

## Firmware-Stand prüfen und warten

```bash
sudo ./tools/e754-firmware-status.sh
```

Zeigt ME/AMT, BIOS-Schreibschutz, TPM (ROCA), Microcode und Modem. Was sich aktualisieren lässt, wo es die offiziellen Pakete gibt und was man besser lässt, steht in **[FIRMWARE.md](FIRMWARE.md)**. Dazu gehört ein Skript, das einen FreeDOS-Stick für das ME-Update auf 9.1.45.3000 baut.

## Installation

```bash
git clone https://github.com/Celestial0579/fujitsu-lifebook-e754-linux.git
cd fujitsu-lifebook-e754-linux
sudo ./install.sh            # Treiber + WLAN-Fixes (falls Intel 7260 verbaut)
sudo ./install.sh --no-wifi  # nur der Treiber
```

Das Skript installiert das Modul per DKMS, sodass es nach jedem Kernel-Update automatisch neu gebaut wird, und lädt es beim Booten.

**Secure Boot:** DKMS signiert das Modul mit einem eigenen Schlüssel. Diesen musst du einmal eintragen:

```bash
sudo mokutil --import /var/lib/shim-signed/mok/MOK.der
```

Einmal-Passwort festlegen, neu starten. Im blauen MOK-Manager schnell eine Taste drücken (er wartet nur ~10 s), dann **Enroll MOK → Continue → Yes**, Passwort eingeben, **Reboot**.

## Treiber `fujitsu-fext-extra`

Ruft die Firmware-Schnittstelle `\_SB.FEXT.FUNC` (ACPI FUJ02E3) direkt auf und ergänzt so `fujitsu_laptop` (Hotkeys, LEDs, Ladegrenze), ohne dessen ACPI-Gerät zu übernehmen.

| Pfad | Funktion |
|---|---|
| `…/hwmon/hwmonN/fan1_input` | Lüfterdrehzahl in U/min |
| `…/hwmon/hwmonN/temp1_input` | CPU-Temperatur laut EC |
| `…/hwmon/hwmonN/temp2_input` | geglättete Regeltemperatur des EC |
| `/sys/devices/platform/fujitsu-fext-extra/fan_curve` | Lüfterkurve der Firmware (°C, Stellwert 0–255) |
| `…/bay_power` | Strom Modulschacht (z. B. DVD-Laufwerk) `0`/`1` |
| `…/bluetooth_power` | Strom Bluetooth-Controller `0`/`1`. Das Funkteil geht nur an, wenn der Hardware-Funkschalter an ist (sonst zeigt `rfkill` „hard blocked“) |

Beispiel:

```bash
cat /sys/devices/platform/fujitsu-fext-extra/hwmon/hwmon*/fan1_input
echo 0 | sudo tee /sys/devices/platform/fujitsu-fext-extra/bay_power   # DVD aus (spart Strom)
```

### Modul-Parameter

| Parameter | Wirkung |
|---|---|
| `force=1` | auch auf anderen Modellen als E754 laden (auf eigene Gefahr, andere LIFEBOOKs mit FUJ02E3 könnten passen) |
| `allow_raw=1` | Entwickler-Attribut `raw_call`: `echo "<func> <a1> <a2> <a3>" > raw_call; cat raw_call` (Hex). Wirkt **nur ohne Kernel-Lockdown** (auch zur Laufzeit geprüft), also normalerweise nicht bei aktivem Secure Boot, braucht `CAP_SYS_RAWIO` und erlaubt nur die Funktionen `0x1000–0x10ff`. |

### Sicherheit

- **Lesen** (Sensoren, `fan_curve`, Schalterzustände) darf jeder Nutzer. Die Sensorwerte werden 1 s gecacht und die Lüfterkurve nur einmal beim Laden gelesen, damit niemand den EC per Leseschleife ausbremsen kann.
- **Schalten** (`bay_power`, `bluetooth_power`) nur root.
- **`raw_call`** erlaubt beliebige Firmware-Aufrufe (SMIs, EC- und Port-Zugriffe) und ist damit so mächtig wie `/dev/port`. Er ist standardmäßig aus und unter Lockdown gesperrt, damit das signierte Modul den Secure-Boot-Schutz nicht aushebelt.
- ⚠️ `bay_power=0` trennt das Laufwerk im Modulschacht hart vom Strom. Ein eingebundenes Laufwerk vorher aushängen.

### Technische Details (aus der DSDT, BIOS 1.32)

| FUNC | Bedeutung | Nutzung |
|---|---|---|
| `0x1005` S005 | Gerätestrom: Bit 0 = Modulschacht (SATA-Port 2), Bit 10 = Bluetooth; `S005(1, mask, value)`, gesetztes Bit = aus | `bay_power`, `bluetooth_power` |
| `0x1006` S006 | EC-Mailbox, `S006(0x10, 0x01rr)` liest EC-Bank 1 Register `rr` | Sensoren, Lüfterkurve |
| `0x1007` S007 | CPU-Grenze über `_PPC` | nicht genutzt, wirkungslos unter `intel_pstate` |
| `0x1009` S009 | Fujitsu-Hardwaremonitor | nicht genutzt, zwingt den Lüfter für die Messung auf Vollgas |
| `0x100A` S00A | Anytime-USB-Charge (SMI 0x88) | nicht umgesetzt, Bitbelegung unbekannt |

EC-Bank 1: `0x00` lo = CPU-°C · `0x10–0x1b` Lüfterkurve (hi = Stellwert, lo = °C) · `0x50` Tacho-Periode (U/min = 30 000 000 / Wert) · `0x52` hi = Regeltemperatur.

Hinweise und Messwerte von anderen LIFEBOOK-Modellen (E734, E744, E753 …) sind als Issue oder PR willkommen.

## WLAN-Fixes für Intel Wireless 7260

Die 7260 fällt mit aktivem PCIe-ASPM-L1 gelegentlich vom Bus. Im Kernel-Log steht dann `iwlwifi transaction failed`, die Register lesen `ffffffff`, und das WLAN ist bis zum Neustart tot.

- `80-iwlwifi-7260-no-aspm.rules` schaltet ASPM L1 und ClockPM für die Karte ab. Kosten: Die CPU-Package kommt im Leerlauf nur noch bis PC2 (≈ 1–2 W mehr).
- `iwlwifi-watchdog.service` erkennt den Absturz trotzdem und setzt die Karte per PCI remove/rescan zurück, ohne Neustart. Nach 5 erfolglosen Resets gibt er auf, bis die Karte wieder läuft. Log: `journalctl -u iwlwifi-watchdog`.

## Optional: BIOS-Flash vor Schreibzugriffen schützen

Auf dem getesteten E754 (BIOS 1.32) ist der BIOS-Schreibschutz des Chipsatzes nicht gesetzt (`BIOS_CNTL`: BLE=0, SMM_BWP=0). Der Kernel-Treiber `spi_intel` stellt dann den Bereich „BIOS1“ als **beschreibbares** `/dev/mtd1` bereit. Darin liegen BIOS-Daten einschließlich Secure-Boot-Variablen. Root könnte sie am Kernel-Lockdown vorbei roh überschreiben.

Prüfen:

```bash
sudo setpci -s 00:1f.0 0xdc.b       # 08 = ungesperrt (Bits 1 und 5 nicht gesetzt)
cat /sys/class/mtd/mtd*/flags 2>/dev/null   # 0xc00 = beschreibbar
```

Abhilfe: Den Treiber sperren. Im Alltag braucht ihn nichts, fwupd liest darüber nur die BIOS-Version.

```bash
sudo install -m644 blacklist-spi-intel.conf /etc/modprobe.d/
sudo modprobe -r spi_intel_platform spi_intel
sudo update-initramfs -u
```

Rückgängig: die Datei löschen, `sudo update-initramfs -u`, neu starten.

## Optional: Intel ME / AMT abschotten

Die ME-Firmware 9.0.x des E754 vPro ist von INTEL-SA-00075 (AMT) betroffen. Fujitsu bietet ME 9.1.45.3000 an, das Update geht aber nur von DOS oder Windows aus. Ohne Flash lässt sich die Lücke so abschwächen:

1. **AMT abschalten:** Strg+P beim Start (MEBx) bzw. F2 → „Intel AMT“ → **Disabled**. Das ist Intels offizielle Abhilfe.
2. **ME-Schnittstelle unter Linux sperren:** Dann kann kein Programm mehr mit der ME sprechen.

```bash
sudo install -m644 blacklist-intel-mei.conf /etc/modprobe.d/
sudo modprobe -r mei_hdcp mei_pxp mei_me mei
sudo update-initramfs -u
```

Nebenwirkung: HDCP/PXP-Kopierschutz der Grafik ist nicht verfügbar. Rückgängig: die Datei löschen, `sudo update-initramfs -u`, neu starten.

## Getestet

LIFEBOOK E754, BIOS 1.32, i5-4210M, Ubuntu 26.04, Kernel 7.0, Secure Boot an.
Treiber-Stresstest (0.4): 8 parallele Leser + Bluetooth-Schalten + 100× Entladen/Laden unter Last ohne Oops/WARN; 600 Lade-Zyklen ohne Anstieg in den kmalloc-Caches.
S3 ✅ · s2idle ✅ · Ladegrenze (`charge_control_end_threshold`, mainline) ✅ · Fingerabdruck (fprintd) ✅ · Hotkeys ✅ (die ECO-Taste meldet `KEY_PROG4` und ist frei belegbar)

## Lizenz

GPL-2.0-or-later, siehe [LICENSE](LICENSE).
