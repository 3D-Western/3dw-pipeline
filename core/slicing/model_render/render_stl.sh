#!/usr/bin/env bash

set -euo pipefail

IMG_SIZE="${IMG_SIZE:-800}"
DIST="${DIST:-300}"
ELEV_TOP="${ELEV_TOP:-60}"
ELEV_BOTTOM="${ELEV_BOTTOM:-120}"
TMP_SCAD="${TMP_SCAD:-__tmp_render.scad}"
OPENSCAD_BIN="${OPENSCAD_BIN:-openscad}"
BLENDER_BIN="${BLENDER_BIN:-blender}"
BACKEND="${MODEL_RENDER_BACKEND:-openscad}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLENDER_SCRIPT="${SCRIPT_DIR}/render_stl_blender.py"

usage() {
    cat <<EOF
Usage: $(basename "$0") model.stl [--parallel] [--backend openscad|blender]
EOF
}

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

STL="$1"
shift || true

PARALLEL=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --parallel)
            PARALLEL="--parallel"
            ;;
        --backend)
            if [[ $# -lt 2 ]]; then
                usage
                exit 1
            fi
            BACKEND="$2"
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage
            exit 1
            ;;
    esac
    shift
done

if [[ ! -f "$STL" ]]; then
    echo "STL not found: $STL" >&2
    exit 1
fi

STL_DIR="$(dirname "$STL")"
OUTDIR="${STL_DIR}/renders"
mkdir -p "$OUTDIR"

angles=(0 90 180 270)

render_with_openscad() {
    command -v "$OPENSCAD_BIN" >/dev/null || {
        echo "OpenSCAD binary not found in PATH: $OPENSCAD_BIN" >&2
        exit 1
    }

    cat > "$TMP_SCAD" <<EOF
import("$STL", convexity=5, center=true);
EOF

    render_view() {
        local yaw="$1" pitch="$2" name="$3"
        local cmd=(
            "$OPENSCAD_BIN"
            "--imgsize=${IMG_SIZE},${IMG_SIZE}"
            "--projection=p"
            "--autocenter"
            "--viewall"
            "--camera=0,0,0,${pitch},0,${yaw},${DIST}"
            -o "${OUTDIR}/${name}.png"
            "$TMP_SCAD"
        )

        if command -v xvfb-run >/dev/null; then
            xvfb-run -a "${cmd[@]}" >/dev/null
        else
            "${cmd[@]}" >/dev/null
        fi

        echo "Rendered: ${name}.png"
    }

    local pids=()
    for yaw in "${angles[@]}"; do
        if [[ "$PARALLEL" == "--parallel" ]]; then
            render_view "$yaw" "$ELEV_TOP" "top_${yaw}" &
            pids+=("$!")
        else
            render_view "$yaw" "$ELEV_TOP" "top_${yaw}"
        fi
    done

    for yaw in "${angles[@]}"; do
        if [[ "$PARALLEL" == "--parallel" ]]; then
            render_view "$yaw" "$ELEV_BOTTOM" "bottom_${yaw}" &
            pids+=("$!")
        else
            render_view "$yaw" "$ELEV_BOTTOM" "bottom_${yaw}"
        fi
    done

    if [[ "$PARALLEL" == "--parallel" ]]; then
        wait "${pids[@]}"
    fi

    rm -f "$TMP_SCAD"
}

render_with_blender() {
    command -v "$BLENDER_BIN" >/dev/null || {
        echo "Blender binary not found in PATH: $BLENDER_BIN" >&2
        exit 1
    }

    "$BLENDER_BIN" --background --python "$BLENDER_SCRIPT" -- \
        --stl "$STL" \
        --output-dir "$OUTDIR" \
        --img-size "$IMG_SIZE" \
        --distance "$DIST" \
        --elev-top "$ELEV_TOP" \
        --elev-bottom "$ELEV_BOTTOM"
}

echo "Rendering previews for $STL using backend=$BACKEND"
start="$(date +%s)"

case "$BACKEND" in
    openscad)
        render_with_openscad
        ;;
    blender)
        render_with_blender
        ;;
    *)
        echo "Unsupported backend: $BACKEND (expected openscad|blender)" >&2
        exit 1
        ;;
esac

end="$(date +%s)"
echo "Render complete in $((end - start))s -> Saved in $OUTDIR"
