#!/usr/bin/env bash
# Fedora/Linux launcher for the already-built A12/A13 bootchain.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

printf '[ICH Linux] host=%s arch=%s\n' "$(uname -s)" "$(uname -m)"

if [[ -f "$ROOT/.linux-runtime" ]]; then
    # shellcheck disable=SC1090
    source "$ROOT/.linux-runtime"
fi

if [[ -z "${USBLITER8CTL:-}" ]]; then
    for candidate in \
        "$ROOT/tools/linux/usbliter8/usbliter8ctl" \
        "$ROOT/../usbliter8ra1n/tools/usbliter8ctl" \
        "$ROOT/../usbliter8/usbliter8ctl" \
        "$HOME/usbliter8ra1n/tools/usbliter8ctl" \
        "$HOME/usbliter8/usbliter8ctl"
    do
        [[ -f "$candidate" ]] && USBLITER8CTL="$candidate" && break
    done
fi

if [[ -z "${IRECOVERY:-}" ]]; then
    IRECOVERY="$(command -v irecovery 2>/dev/null || true)"
fi

export IRECOVERY USBLITER8CTL

printf '[ICH Linux] irecovery=%s\n' "${IRECOVERY:-NOT_FOUND}"
printf '[ICH Linux] usbliter8ctl=%s\n' "${USBLITER8CTL:-NOT_FOUND}"

[[ -x "$IRECOVERY" ]] || {
    echo "ERROR: irecovery not found. Run ./setup-linux.sh --install" >&2
    exit 1
}
[[ -f "$USBLITER8CTL" ]] || {
    echo "ERROR: usbliter8ctl not found." >&2
    echo "Run ./setup-linux.sh --install or set USBLITER8CTL=/absolute/path/to/usbliter8ctl" >&2
    exit 1
}

printf '[ICH Linux] checking Python/PyUSB...\n'
python3 -c 'import usb; print("[ICH Linux] PyUSB=OK")'

printf '[ICH Linux] checking Apple USB...\n'
"$IRECOVERY" -q || true

# Keep USB access unprivileged; udev rules installed by setup-linux.sh should
# grant the active user access to Apple DFU/Recovery interfaces.
exec "$ROOT/boot.sh" --backend linux "$@"
