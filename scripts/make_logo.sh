#!/usr/bin/env bash
# Build a centered ICH boot logo on a pure-black fullscreen canvas.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/env.sh"
source "$ROOT/scripts/devices.sh"

PNG="$NR_RESOURCES/ich_logo.png"
BOARD=""
WIDTH=""
HEIGHT=""
MARK=""
CPID="0x8020"
OUT_DEST=""

_args=()
while (($#)); do
    case "$1" in
        --out)
            [[ $# -ge 2 ]] || { echo "make_logo: --out needs a path" >&2; exit 2; }
            OUT_DEST="$2"
            shift 2
            ;;
        *)
            _args+=("$1")
            shift
            ;;
    esac
done
if ((${#_args[@]})); then
    set -- "${_args[@]}"
else
    set --
fi

if (($# >= 1)) && [[ "$1" == *.png || "$1" == *.PNG || "$1" == /* || "$1" == ./* ]]; then
    PNG="$1"
    shift
    if (($# >= 2)) && [[ "$1" =~ ^[0-9]+$ && "$2" =~ ^[0-9]+$ ]]; then
        WIDTH="$1"
        HEIGHT="$2"
        shift 2
        (($#)) && [[ "$1" =~ ^[0-9]+$ ]] && { MARK="$1"; shift; }
        (($#)) && CPID="$1"
    fi
elif (($# >= 1)); then
    BOARD="$1"
    shift
    (($#)) && [[ -f "$1" || "$1" == *.png ]] && { PNG="$1"; shift; }
fi

if [[ -n "$BOARD" ]]; then
    BOARD="$(printf '%s' "$BOARD" | tr '[:upper:]' '[:lower:]')"
fi

if [[ -z "$WIDTH" || -z "$HEIGHT" ]]; then
    BOARD="${BOARD:-${NR_BOARD:-n841ap}}"
    panel="$(nr_panel_for_board "$BOARD")" && known=1 || known=0
    read -r WIDTH HEIGHT <<<"$panel"
    if ((known == 0)); then
        echo "warning: unknown board '$BOARD' — using fallback panel ${WIDTH}x${HEIGHT}" >&2
    fi
fi

MARK="${MARK:-$(nr_logo_mark_for_panel "$WIDTH" "$HEIGHT")}"
CPID="${NR_CPID:-$CPID}"

IBOOTIM="$NR_TOOLS/ibootim"
IMG4="$NR_TOOLS/img4"
IM4M="$NR_RESOURCES/IM4M_$CPID"
[[ -f "$IM4M" ]] || IM4M="$NR_RESOURCES/IM4M_0x8020"

if [[ -n "$OUT_DEST" ]]; then
    CACHE="$(dirname "$OUT_DEST")/.logo_build"
else
    CACHE="$NR_RESOURCES/logo_cache"
fi
mkdir -p "$CACHE"
TAG="${BOARD:-${WIDTH}x${HEIGHT}}"
TAG="${TAG//\//_}"
FULL="$CACHE/${TAG}_${WIDTH}x${HEIGHT}.png"
RAW="$CACHE/${TAG}_${WIDTH}x${HEIGHT}.raw"
OUT="$CACHE/${TAG}_${WIDTH}x${HEIGHT}.img4"
PUB_RAW="$NR_RESOURCES/ich_logo.raw"
PUB_OUT="$NR_RESOURCES/logo.img4"

[[ -f "$PNG" ]] || { echo "missing PNG: $PNG" >&2; exit 1; }
[[ -x "$IBOOTIM" && -x "$IMG4" ]] || { echo "missing ibootim/img4" >&2; exit 1; }
[[ -f "$IM4M" ]] || { echo "missing IM4M" >&2; exit 1; }

echo "logo: board=${BOARD:-custom} panel=${WIDTH}x${HEIGHT} mark=${MARK} cpid=${CPID}"

python3 - "$PNG" "$FULL" "$WIDTH" "$HEIGHT" "$MARK" <<'PY'
from pathlib import Path
import sys
from PIL import Image

src, out, W, H, LOGO = sys.argv[1], Path(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
im = Image.open(src).convert("RGBA")
base = Image.new("RGBA", im.size, (255, 255, 255, 255))
base.paste(im, mask=im.split()[-1])
gray = base.convert("L")
bw = gray.point(lambda p: 255 if p < 140 else 0, mode="L").convert("RGB")

mark = bw.resize((LOGO, LOGO), Image.Resampling.NEAREST)
px = mark.load()
for y in range(LOGO):
    for x in range(LOGO):
        r, g, b = px[x, y]
        px[x, y] = (255, 255, 255) if (r + g + b) > 300 else (0, 0, 0)

canvas = Image.new("RGB", (W, H), (0, 0, 0))
x = (W - LOGO) // 2
y = (H - LOGO) // 2
canvas.paste(mark, (x, y))
out.parent.mkdir(parents=True, exist_ok=True)
canvas.save(out)
white = sum(1 for p in canvas.getdata() if p[0] > 200)
print(f"fullscreen {W}x{H} mark={LOGO} at ({x},{y}) white_pixels={white}")
if white < 100:
    raise SystemExit("logo mark has no visible white pixels — abort")
PY

# ibootim in this project is distributed as an x86_64 Darwin binary.
# On Apple Silicon runners, force the Intel execution path and use an
# x86_64 libpng when one has been prepared by CI.
IBOOTIM_RUN=("$IBOOTIM")
if [[ "$(uname -s)" == "Darwin" ]] && file "$IBOOTIM" 2>/dev/null | grep -q 'x86_64'; then
    if command -v arch >/dev/null 2>&1; then
        IBOOTIM_RUN=(arch -x86_64 "$IBOOTIM")
    fi
    if [[ -n "${X86_LIBPNG:-}" && -d "$X86_LIBPNG/lib" ]]; then
        export DYLD_LIBRARY_PATH="$X86_LIBPNG/lib:${DYLD_LIBRARY_PATH:-}"
    elif [[ -d /usr/local/opt/libpng/lib ]]; then
        export DYLD_LIBRARY_PATH="/usr/local/opt/libpng/lib:${DYLD_LIBRARY_PATH:-}"
    fi
fi

file "$IBOOTIM" 2>/dev/null || true
if [[ -n "${DYLD_LIBRARY_PATH:-}" ]]; then
    echo "ibootim DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH"
fi

"${IBOOTIM_RUN[@]}" "$FULL" "$RAW"
"$IMG4" -i "$RAW" -o "$OUT" -A -T logo -M "$IM4M"

if [[ -n "$OUT_DEST" ]]; then
    mkdir -p "$(dirname "$OUT_DEST")"
    cp -f "$OUT" "$OUT_DEST"
    echo "wrote $OUT_DEST (centered for ${WIDTH}x${HEIGHT})"
    rm -rf "$CACHE"
else
    cp -f "$RAW" "$PUB_RAW"
    cp -f "$OUT" "$PUB_OUT"
    echo "wrote $OUT"
    echo "published $PUB_OUT (centered for ${WIDTH}x${HEIGHT})"
fi
