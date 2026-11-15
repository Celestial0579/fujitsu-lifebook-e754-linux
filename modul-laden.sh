# shellcheck shell=bash
# Laden des Moduls nach Installation oder Update. Wird von install.sh
# eingebunden und in tests/install-laden.sh gegen Attrappen geprueft.

MODUL=fujitsu_fext_extra
MODUL_SYSFS="${MODUL_SYSFS:-/sys/module/$MODUL}"

# modul_laden <Version>
# Laedt das frisch installierte Modul. Ist schon eine Fassung geladen
# (Update), wird sie vorher entladen: modprobe kehrt bei einem geladenen
# Modul sofort mit 0 zurueck, ohne die neue Fassung zu laden.
# Rueckgabe 0: Modul laeuft (oder laeuft nach einem Neustart in der neuen
# Fassung), 1: Modul konnte nicht geladen werden.
modul_laden() {
    local ver="$1" meldung laeuft

    if [ -d "$MODUL_SYSFS" ] && ! modprobe -r "$MODUL" 2>/dev/null; then
        echo "WARNUNG: $MODUL ist schon geladen und liess sich nicht entladen."
        echo "Die neue Fassung $ver ist erst nach einem Neustart aktiv."
        return 0
    fi

    if ! meldung=$(modprobe "$MODUL" 2>&1); then
        [ -z "$meldung" ] || echo "$meldung" >&2
        case "$meldung" in
            *"Key was rejected by service"* | *"Required key not available"*)
                echo
                echo "Secure Boot ist aktiv und der DKMS-Schluessel noch nicht eingetragen:"
                echo "  sudo mokutil --import /var/lib/shim-signed/mok/MOK.der"
                echo "Einmal-Passwort festlegen, neu starten, im blauen MOK-Manager 'Enroll MOK' waehlen."
                ;;
            *)
                echo "Modul konnte nicht geladen werden, siehe: sudo dmesg | tail"
                ;;
        esac
        return 1
    fi

    echo "OK: Modul geladen -> /sys/devices/platform/fujitsu-fext-extra"
    laeuft=$(cat "$MODUL_SYSFS/version" 2>/dev/null || true)
    if [ -n "$laeuft" ] && [ "$laeuft" != "$ver" ]; then
        echo "WARNUNG: geladen ist Fassung $laeuft, installiert wurde $ver. Neustart empfohlen."
    fi
    return 0
}
