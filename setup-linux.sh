#!/usr/bin/env bash
# Fedora/Linux runtime setup for an already-built ICH A12/A13 ramdisk.
# Does not build IMG4 payloads.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

INSTALL=0
INSTALL_UDEV=0

usage() {
    cat <<'EOF'
usage: ./setup-linux.sh [--install] [--install-udev]

  --install       install Fedora runtime packages and fetch usbliter8ctl
  --install-udev install the supplied Apple USB udev rules

Normal runtime:
  ./boot-linux.sh --debug --with-fw --logo
EOF
}

while (($#)); do
    case "$1" in
        --install) INSTALL=1 ;;
        --install-udev) INSTALL_UDEV=1 ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 64 ;;
    esac
    shift
done

[[ "$(uname -s)" == Linux ]] || { echo "This script is for Linux." >&2; exit 1; }

source /etc/os-release
ARCH="$(uname -m)"
printf '=== ICH Linux runtime ===\ndistro=%s\narch=%s\n' "${ID:-unknown}" "$ARCH"

if [[ "${ID:-}" != fedora ]]; then
    echo "This repo's automated installer currently targets Fedora." >&2
    exit 1
fi

if ((INSTALL)); then
    sudo dnf install -y \
        libirecovery-utils \
        libirecovery \
        libusb1 \
        python3 \
        python3-pyusb \
        usbutils \
        perl \
        git
fi

command -v irecovery >/dev/null 2>&1 || {
    echo "irecovery is missing. Run: ./setup-linux.sh --install" >&2
    exit 1
}

python3 -c 'import usb; print("PyUSB: OK")' || {
    echo "PyUSB is missing. Run: ./setup-linux.sh --install" >&2
    exit 1
}

if ((INSTALL_UDEV || INSTALL)); then
    sudo install -Dm0644 "$ROOT/udev/99-ich-apple.rules" \
        /etc/udev/rules.d/99-ich-apple.rules
    sudo udevadm control --reload-rules
    sudo udevadm trigger --subsystem-match=usb
fi

# Locate a usable usbliter8ctl. The RP2350 firmware itself is separate; this is
# the host-side Python controller for the PWND DFU handoff.
USBLITER8CTL="${USBLITER8CTL:-}"
for candidate in \
    "$USBLITER8CTL" \
    "$ROOT/tools/linux/usbliter8/usbliter8ctl" \
    "$ROOT/../usbliter8ra1n/tools/usbliter8ctl" \
    "$ROOT/../usbliter8/usbliter8ctl" \
    "$HOME/usbliter8ra1n/tools/usbliter8ctl" \
    "$HOME/usbliter8/usbliter8ctl"
do
    if [[ -n "$candidate" && -f "$candidate" ]]; then
        USBLITER8CTL="$candidate"
        break
    fi
done

if [[ -z "$USBLITER8CTL" || ! -f "$USBLITER8CTL" ]]; then
    if command -v git >/dev/null 2>&1; then
        mkdir -p "$ROOT/tools/linux"
        if [[ ! -d "$ROOT/tools/linux/usbliter8" ]]; then
            git clone --depth 1 https://github.com/JoshAtticus/usbliter8.git \
                "$ROOT/tools/linux/usbliter8"
        fi
        USBLITER8CTL="$ROOT/tools/linux/usbliter8/usbliter8ctl"
    fi
fi

[[ -f "$USBLITER8CTL" ]] || {
    echo "usbliter8ctl not found." >&2
    echo "Set USBLITER8CTL=/absolute/path/to/usbliter8ctl and retry." >&2
    exit 1
}

chmod +x "$USBLITER8CTL" 2>/dev/null || true

printf '\n=== detected tools ===\n'
printf 'irecovery:    %s\n' "$(command -v irecovery)"
printf 'usbliter8ctl: %s\n' "$USBLITER8CTL"
printf 'python3:      %s\n' "$(command -v python3)"
printf 'USB devices:\n'
lsusb -d 05ac: || true

cat > "$ROOT/.linux-runtime" <<EOF
IRECOVERY=$(command -v irecovery)
USBLITER8CTL=$USBLITER8CTL
ARCH=$ARCH
EOF

printf '\nSetup complete.\n'
printf 'For normal use, do NOT use sudo after installing udev rules:\n\n'
printf '  USBLITER8CTL="%s" ./boot-linux.sh --debug --with-fw --logo\n\n' "$USBLITER8CTL"
printf 'First diagnostic:\n  ./boot-linux.sh --validate\n  ./boot-linux.sh --dry-run --debug\n'
