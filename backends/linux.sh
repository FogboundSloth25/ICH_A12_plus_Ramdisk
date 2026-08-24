#!/usr/bin/env bash
# Fedora/Linux runtime backend.
# Recovery transport: irecovery/libirecovery.
# PWND DFU raw boot: usbliter8ctl + PyUSB.

backend_init_linux() {
    BACKEND_NAME="linux"

    if [[ -n "${IRECOVERY:-}" ]]; then
        :
    else
        for candidate in \
            "$ROOT/tools/linux/irecovery" \
            "$ROOT/tools/linux/irecovery-x86_64" \
            "$(command -v irecovery 2>/dev/null || true)" \
            /usr/bin/irecovery \
            /usr/local/bin/irecovery
        do
            [[ -x "$candidate" ]] && IRECOVERY="$candidate" && break
        done
    fi

    if [[ -n "${USBLITER8CTL:-}" ]]; then
        :
    else
        for candidate in \
            "$ROOT/tools/linux/usbliter8ctl" \
            "$ROOT/tools/linux/usbliter8/usbliter8ctl" \
            "$ROOT/../usbliter8ra1n/tools/usbliter8ctl" \
            "$ROOT/../usbliter8/tools/usbliter8ctl" \
            "$HOME/usbliter8ra1n/usbliter8ctl" \
            "$HOME/usbliter8/usbliter8ctl"
        do
            [[ -f "$candidate" ]] && USBLITER8CTL="$candidate" && break
        done
    fi

    export IRECOVERY USBLITER8CTL
}

backend_require_runtime_tools() {
    backend_require_executable IRECOVERY "$IRECOVERY" || return 1

    [[ -f "$USBLITER8CTL" ]] || {
        backend_error "usbliter8ctl unavailable" \
            "The Linux backend could not find usbliter8ctl." \
            "A readable usbliter8ctl Python script." \
            "Run ./setup-linux.sh or set USBLITER8CTL=/absolute/path/to/usbliter8ctl."
        return 1
    }

    command -v python3 >/dev/null 2>&1 || {
        backend_error "Python unavailable" "python3 is required to run usbliter8ctl." \
            "Python 3 with PyUSB." "Install python3 and python3-pyusb, then retry."
        return 1
    }

    python3 -c 'import usb' >/dev/null 2>&1 || {
        backend_error "PyUSB unavailable" "usbliter8ctl cannot import the usb module." \
            "The Fedora python3-pyusb package and libusb1 runtime." \
            "Run ./setup-linux.sh, then retry."
        return 1
    }

    printf '[+] Linux runtime\n'
    printf '[+] irecovery: %s\n' "$IRECOVERY"
    printf '[+] usbliter8ctl: %s\n' "$USBLITER8CTL"
    printf '[+] python3: %s\n' "$(command -v python3)"
}

backend_query() {
    backend_with_timeout 8 "$IRECOVERY" -q
}

backend_send_file() {
    backend_with_timeout "${IRECV_UPLOAD_TIMEOUT_SECS:-300}" "$IRECOVERY" -f "$1"
}

backend_send_command() {
    backend_with_timeout "${IRECV_CMD_TIMEOUT_SECS:-30}" "$IRECOVERY" -c "$1"
}

backend_boot_raw() {
    python3 "$USBLITER8CTL" boot "$1"
}

backend_supports_local_logo_build() { return 1; }

backend_usb_apple_present() {
    local product_id="${1:?product_id required}"
    local d pid_file

    for d in /sys/bus/usb/devices/*/idVendor; do
        [[ -f "$d" ]] || continue
        [[ "$(< "$d")" == "05ac" ]] || continue
        pid_file="${d%idVendor}idProduct"
        [[ -f "$pid_file" ]] || continue
        [[ "$(< "$pid_file")" == "$product_id" ]] && return 0
    done

    if command -v lsusb >/dev/null 2>&1; then
        lsusb -d "05ac:${product_id}" >/dev/null 2>&1 && return 0
    fi
    return 1
}

backend_usb_settle() {
    if command -v udevadm >/dev/null 2>&1; then
        udevadm settle --timeout="${1:-5}" 2>/dev/null || true
    fi
}

backend_usb_record_apple_port() {
    _ICH_USB_PORT=""
    _ICH_USB_BUS=""
    local d base pid

    for d in /sys/bus/usb/devices/*/idVendor; do
        [[ -f "$d" && "$(< "$d")" == "05ac" ]] || continue
        base="${d%/idVendor}"
        pid="$(< "${base}/idProduct" 2>/dev/null || true)"
        if [[ "$pid" == "1227" ]]; then
            _ICH_USB_PORT="${base##*/}"
            _ICH_USB_BUS="${_ICH_USB_PORT%%-*}"
            printf '  [usb] Apple DFU: bus=%s port=%s\n' "$_ICH_USB_BUS" "$_ICH_USB_PORT"
            return 0
        fi
    done
    return 1
}

backend_usb_kickstart_reenumerate() {
    local kicked=0
    local d base pid bus_path

    for d in /sys/bus/usb/devices/*/idVendor; do
        [[ -f "$d" && "$(< "$d")" == "05ac" ]] || continue
        base="${d%/idVendor}"
        pid="$(< "${base}/idProduct" 2>/dev/null || true)"
        if [[ "$pid" == "1227" && -w "${base}/remove" ]]; then
            printf '  [usb] removing stale DFU entry %s\n' "${base##*/}"
            echo 1 > "${base}/remove" 2>/dev/null || true
            kicked=1
        fi
    done

    if [[ -n "${_ICH_USB_BUS:-}" ]]; then
        bus_path="/sys/bus/usb/devices/usb${_ICH_USB_BUS}"
        if [[ -w "$bus_path/authorized" ]]; then
            printf '  [usb] cycling USB bus %s for re-enumeration\n' "$_ICH_USB_BUS"
            echo 0 > "$bus_path/authorized" 2>/dev/null || true
            sleep 0.5
            echo 1 > "$bus_path/authorized" 2>/dev/null || true
            kicked=1
        fi
    fi

    backend_usb_settle 5
    return $(( ! kicked ))
}
