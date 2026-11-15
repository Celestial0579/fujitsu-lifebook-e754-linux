#!/bin/bash
# Prueft modul_laden() aus modul-laden.sh gegen eine Attrappe von modprobe:
# kein root, kein Kernel-Modul. Behandelt werden Update eines geladenen
# Moduls (Regressionspruefung zu #12) sowie Ladefehler mit und ohne
# Secure Boot.
set -uo pipefail
cd "$(dirname "$0")/.."

arbeit=$(mktemp -d)
trap 'rm -rf "$arbeit"' EXIT

# shellcheck source=modul-laden.sh
. ./modul-laden.sh

# Attrappe: protokolliert die Aufrufe; Verhalten ueber Umgebungsvariablen.
#   ATT_ENTLADEN=fehl   modprobe -r scheitert
#   ATT_LADEN=<Text>    modprobe scheitert mit dieser Meldung
#   ATT_VERSION=<Ver>   die geladene Fassung meldet diese Version
modprobe() {
    echo "modprobe $*" >> "$arbeit/aufrufe"
    if [ "$1" = "-r" ]; then
        [ "${ATT_ENTLADEN:-}" != fehl ] || return 1
        rm -rf "$MODUL_SYSFS"
        return 0
    fi
    if [ -n "${ATT_LADEN:-}" ]; then
        echo "modprobe: ERROR: could not insert '$1': $ATT_LADEN" >&2
        return 1
    fi
    mkdir -p "$MODUL_SYSFS"
    [ -z "${ATT_VERSION:-}" ] || echo "$ATT_VERSION" > "$MODUL_SYSFS/version"
    return 0
}

fehler=0
# fall <Beschreibung> <erwarteter Rueckgabewert> <Muster...>
# Jedes Muster muss in Ausgabe plus Aufrufprotokoll vorkommen; "!Muster"
# darf nicht vorkommen.
fall() {
    local beschreibung="$1" erwartet="$2" ausgabe rc muster ok=1
    shift 2
    : > "$arbeit/aufrufe"
    ausgabe=$(modul_laden 0.5.3 2>&1); rc=$?
    ausgabe="$ausgabe
$(cat "$arbeit/aufrufe")"
    [ "$rc" -eq "$erwartet" ] || ok=0
    for muster in "$@"; do
        if [ "${muster:0:1}" = "!" ]; then
            [[ "$ausgabe" != *"${muster:1}"* ]] || ok=0
        else
            [[ "$ausgabe" == *"$muster"* ]] || ok=0
        fi
    done
    if [ "$ok" -eq 1 ]; then
        echo "  OK    $beschreibung"
    else
        echo "  FEHL  $beschreibung (rc=$rc, erwartet $erwartet)"
        echo "$ausgabe" | sed 's/^/          /'
        fehler=$((fehler + 1))
    fi
}
neu() {  # Ausgangslage: Modul nicht geladen, alles klappt
    MODUL_SYSFS="$arbeit/sys-modul"
    rm -rf "$MODUL_SYSFS"
    unset ATT_ENTLADEN ATT_LADEN ATT_VERSION
}

neu
ATT_VERSION=0.5.3
fall "frische Installation laedt das Modul" 0 "OK: Modul geladen" "!modprobe -r" "!WARNUNG"

# Update: alte Fassung ist geladen. modprobe haette sie unveraendert gelassen,
# deshalb muss erst entladen und dann neu geladen werden.
neu
mkdir -p "$MODUL_SYSFS"
echo 0.5.1 > "$MODUL_SYSFS/version"
ATT_VERSION=0.5.3
fall "Update entlaedt die alte Fassung und laedt die neue" 0 \
    "modprobe -r fujitsu_fext_extra" "modprobe fujitsu_fext_extra" "OK: Modul geladen" "!WARNUNG"

neu
mkdir -p "$MODUL_SYSFS"
ATT_ENTLADEN=fehl
fall "nicht entladbare alte Fassung: Hinweis auf Neustart" 0 "Neustart" "!OK: Modul geladen"

neu
ATT_VERSION=0.5.1
fall "geladene Fassung weicht von der installierten ab: Warnung" 0 "WARNUNG: geladen ist Fassung 0.5.1"

neu
ATT_LADEN="Key was rejected by service"
fall "abgelehnter Schluessel: MOK-Hinweis, Exit 1" 1 "mokutil --import"

neu
ATT_LADEN="Required key not available"
fall "fehlender Schluessel: MOK-Hinweis, Exit 1" 1 "mokutil --import"

neu
ATT_LADEN="No such device"
fall "anderer Ladefehler: kein MOK-Hinweis, Exit 1, Meldung von modprobe" 1 \
    "No such device" "dmesg" "!mokutil"

[ "$fehler" -eq 0 ] || { echo "$fehler Pruefung(en) fehlgeschlagen"; exit 1; }
echo "alle Pruefungen bestanden"
