# Firmware-Wartung für das LIFEBOOK E754 unter Linux

Stand November 2026, erarbeitet an einem **E754 vPro** mit BIOS 1.32. Alle Download-Angaben beziehen sich auf das offizielle Fujitsu-Portal (heute Fsas Technologies).

Den eigenen Stand zeigt:

```bash
sudo ./tools/e754-firmware-status.sh
```

## Übersicht

| Komponente | Auslieferungsstand | Neuester offizieller Stand | Lücke | Empfehlung |
|---|---|---|---|---|
| Intel ME | 9.0.22.1467 | **9.1.45.3000** (Fujitsu, 06/2018) | INTEL-SA-00075 (AMT) | AMT abschalten, optional flashen (DOS-Stick) |
| TPM Infineon SLB9655/9656 | 4.32.879.0 | **4.34.1011.0** (Fujitsu, 02/2018) | ROCA, CVE-2017-15361 | nur relevant, wenn der TPM genutzt wird |
| BIOS (vPro) | 1.32 | im EU-Portal **kein neueres** | BIOS-Region ungesperrt | `blacklist-spi-intel.conf` |
| EC | ? | 1811 (02/2016) | – | **nicht** flashen (bekannte Brick-Fälle) |
| CPU-Microcode | 0x28 | 0x28 (`intel-microcode`) | – | ist aktuell |
| WLAN 7260 / BT | -17 | letzte Version | – | ASPM-Fix, siehe README |
| Modem EM8805 | 05.05.47 (Fujitsu-OEM) | Sierra generisch 05.05.58 | – | nur bei Bedarf, sonst lassen |

## vPro oder nicht?

Fujitsu führt **„LIFEBOOK E754“** und **„LIFEBOOK E754 vPro“** als getrennte Produkte mit unterschiedlicher Firmware. Hinweise auf vPro:

- `fwupdmgr get-devices` zeigt „AMT“.
- Die ME-Version beginnt mit 9.0 oder 9.1 (5-MB-Corporate-Firmware).
- Das BIOS ist neuer als 1.26, denn die Nicht-vPro-Linie endet bei 1.26.

## Downloads im Fujitsu-Portal finden

1. Auf [support.ts.fujitsu.com](https://support.ts.fujitsu.com/downloads/product-downloads) unter „Select here“ nach `LIFEBOOK E754` suchen und **„LIFEBOOK E754 vPro“** wählen.
2. Als Betriebssystem **Windows 10 (64-bit)** einstellen, unter „OS Independent“ steht keine Firmware.
3. Im Reiter **Driver** liegen unter **Flash - Firmware** das ME-Paket und die EC-Firmware.
4. Das **TPM-Update** erscheint nicht in der Produktliste. Es lässt sich über die globale Suche nach `TPM Firmware Update 4.34` finden: „Infineon TPM 1.2 Firmware Update 4,34“.
5. Im Download-Dialog das Kästchen „I have read and agree …“ anklicken, nicht den Link daneben. Der Dialog zeigt MD5 und SHA256 an, damit nach dem Download prüfen.

| Paket | SHA256 |
|---|---|
| Intel ME Firmware ME9.1 9.1.45.3000 - QSR (zip) | `62C2117CF9EDA5EAAE51BD5F5E2291850A990E63EBE4DE1956C67BB8202D1F01` |
| Infineon TPM 1.2 Firmware Update 4,34 (7z) | `DC51137F4A72BE3F3ACD8D5009C88F6282B943D15AF5F07D8695F00032E5A57A` |

## Intel ME / AMT

**Problem:** Die ME 9.0.22 ist von INTEL-SA-00075 betroffen, einer Rechteausweitung in AMT, die in der CISA-Liste der aktiv ausgenutzten Lücken steht. Behobene Builds haben eine vierstellige Buildnummer, die mit **3** beginnt.

**Schnelle Abhilfe ohne Flash:**

1. Beim Start **Strg+P** (MEBx) bzw. F2 drücken und „Manageability Feature Selection“ bzw. „Intel AMT“ auf **Disabled** setzen. Das MEBx-Standardpasswort ab Werk ist `admin`.
2. Gegenprobe: Der PCI-Controller `00:16.3` (KT/SOL) ist danach verschwunden, `lspci -s 00:16.3` gibt nichts mehr aus.
3. Optional die Linux-Schnittstelle sperren: `blacklist-intel-mei.conf`, siehe README.

Die ME **selbst** lässt sich per Software nicht abschalten. Haswell braucht sie zum Booten. `me_cleaner`/AltMeDisable ginge nur mit einem externen SPI-Programmer, weil die ME-Region per Software nicht lesbar ist.

**Flash auf 9.1.45.3000:** Das Fujitsu-Paket enthält `FWUpdLcl.exe` für DOS und Windows, aber nichts für Linux. Das Skript `tools/build-me-stick.sh` baut daraus mit FreeDOS 1.4 einen bootfähigen Stick, ohne Root-Rechte:

```bash
./tools/build-me-stick.sh "Intel®ManagementEngineFirmwareME9.1_91453000 - QSR_1219020.zip" FD14-LiteUSB.zip
sudo dd if=me-update-usb.img of=/dev/sdX bs=4M conv=fsync status=progress   # /dev/sdX genau prüfen!
```

Ablauf beim Booten:
1. Der Stick zeigt die aktuelle ME-Version.
2. Ist die ME nicht lesbar, **bricht er ab, ohne zu flashen**.
3. Sonst fragt er mit J/N nach und protokolliert nach `\ME\*.TXT` auf dem Stick.

Zum Booten im BIOS (F2) **Secure Boot aus- und Legacy/CSM einschalten** und es danach wieder zurückstellen. Ein eingetragener MOK-Schlüssel bleibt dabei erhalten. Netzteil anschließen. Das Image wurde in QEMU getestet (Abbruch- und Fehlerpfad), auf echter Hardware ist der Flash noch **nicht** erprobt.

## TPM (Infineon, ROCA)

**Problem:** Firmware 4.32 erzeugt schwache RSA-Schlüssel. Das betrifft **nur Schlüssel, die im TPM erzeugt wurden** (BitLocker, TPM-basierte Zertifikate). Ein Ubuntu ohne `trousers`/`tcsd` nutzt den TPM 1.2 nicht.

**Unter Linux nicht direkt aktualisierbar:**
- Fujitsu (und HP, SoftPaq SP82407) liefern 4.34 nur in Infineons Windows-Updater `IFXTPMUpdate_TPM12_v0434.exe` aus.
- Infineons Linux-Werkzeug `TPMFactoryUpd` (Quelle über ChromeOS, `chromeos-base/infineon-firmware-updater`) erwartet dagegen das Containerformat `IfxFirmwareImage`.
- Dieser Container ist von Infineon zusätzlich RSA-signiert und lässt sich aus den Ressourcen der Windows-EXE (`FWBLOCK/203`, `PARAMBLOCK/202`) **nicht** nachbauen.
- Ein öffentliches Image `TPM12_4.32.879.0_to_TPM12_4.34.1011.0.BIN` haben wir nicht gefunden.

**Wege:**
1. **Nicht nutzen und so lassen**, wenn nichts den TPM verwendet. Das war unsere Wahl.
2. **Offizieller Windows-Updater** von einem Windows-To-Go- oder WinPE-Stick. Er braucht einen gesetzten TPM-Owner.
3. Wer den TPM **löschen** will (z. B. ein Owner vom alten Windows): Linux kann die BIOS-Anfrage stellen. Beim nächsten Start bestätigt man sie per Taste im BIOS.

   ```bash
   echo 14 | sudo tee /sys/class/tpm/tpm0/ppi/request   # 14 = Enable + Activate + Clear
   ```

   **Alle TPM-Schlüssel gehen dabei verloren.** BitLocker-Laufwerke vorher entschlüsseln.

## BIOS und EC

- **BIOS:** Fujitsus EU-Portal führt für das E754 vPro kein BIOS mehr. Fujitsu USA nannte zeitweise 1.35 (vPro), aber ohne auffindbare Datei. Ein Backup des 8-MB-Flash ist per Software **nicht** möglich, weil die ME-Region gesperrt ist. Vor jedem BIOS-Flash also an einen Hardware-Programmer denken.
- **BIOS-Schreibschutz:** Mit BIOS 1.32 ist `BIOS_CNTL` = 0x08 (BLE=0, SMM_BWP=0). Der Kernel-Treiber `spi_intel` stellt dann den Bereich „BIOS1“ als beschreibbares `/dev/mtd1` bereit, was den Secure-Boot-Lockdown umgeht. Abhilfe: `blacklist-spi-intel.conf`.
- **EC-Firmware:** Es gibt Berichte über E7x4, die nach einem EC-Update (bzw. dem „Battery Control Update Tool“) nicht mehr starten ([eevblog](https://www.eevblog.com/forum/repair/fujitsu-e754-ec-bios-update-killed-pc/)). Ohne konkreten Fehler daher **nicht** anfassen.

## Modem (Sierra EM7305/EM8805)

Fujitsu hat eine eigene Modem-Firmware aufgespielt (`…_Fujitsu_005.005_000`). Sierra bietet generische Firmware 05.05.58 frei an (Build 4837, CWE/NVU für `qmi-firmware-update`). Diese überschreibt aber Fujitsus Anpassungen. Fujitsu selbst bietet kein Update an. Nur sinnvoll, wenn das Modem tatsächlich genutzt wird und Probleme macht.
