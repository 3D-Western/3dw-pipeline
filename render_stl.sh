set -euo pipefail

# --- CONFIG ---
IMG_SIZE=800
DIST=300
ELEV_TOP=60
ELEV_BOTTOM=120
ANGLES=(0 90 180 270)
TMP_SCAD="__tmp_render.scad"

# --- INPUT ---
if [[ $# -lt 1 ]]; then
    echo "Usage: ./render_views.sh model.stl [--parallel]"
    exit 1
fi

STL="$1"
PARALLEL="${2:-}"

# Create output subdirectory (renders/)
STL_DIR="$(dirname "$STL")"
OUTDIR="${STL_DIR}/renders"
mkdir -p "$OUTDIR"

# Pre-create a SCAD file for import
cat > "$TMP_SCAD" <<EOF
import("$STL", convexity=5, center=true);
EOF

render_view() {
    local yaw=$1 pitch=$2 name=$3
    "C:/Program Files/OpenSCAD/openscad.com" \
        --imgsize=${IMG_SIZE},${IMG_SIZE} \
        --projection=p \
        --autocenter \
        --viewall \
        --camera=0,0,0,${pitch},0,${yaw},${DIST} \
        -o "${OUTDIR}/${name}.png" \
        "$TMP_SCAD" >/dev/null
    echo "Rendered: ${name}.png"
}

echo "Rendering 8 views of $STL..."
START=$(date +%s)
PIDS=()

# Top 4
for yaw in "${ANGLES[@]}"; do
    if [[ "$PARALLEL" == "--parallel" ]]; then
        render_view "$yaw" "$ELEV_TOP" "top_${yaw}" &
        PIDS+=($!)
    else
        render_view "$yaw" "$ELEV_TOP" "top_${yaw}"
    fi
done

# Bottom 4
for yaw in "${ANGLES[@]}"; do
    if [[ "$PARALLEL" == "--parallel" ]]; then
        render_view "$yaw" "$ELEV_BOTTOM" "bottom_${yaw}" &
        PIDS+=($!)
    else
        render_view "$yaw" "$ELEV_BOTTOM" "bottom_${yaw}"
    fi
done

if [[ "$PARALLEL" == "--parallel" ]]; then
    echo "Waiting for ${#PIDS[@]} parallel renders..."
    wait "${PIDS[@]}"
fi

END=$(date +%s)
echo "Render complete in $((END - START))s → Saved in $OUTDIR"
rm -f "$TMP_SCAD"
