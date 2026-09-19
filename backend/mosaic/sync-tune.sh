#!/usr/bin/env bash
# Help re-tune the per-camera delays (CAM_DELAY_1..4 in .env) that line the four
# mosaic tiles up to the same wall-clock moment.
#
#   ./sync-tune.sh
#
# Grabs a current wall frame and writes big crops of each tile's burned-in clock
# to /tmp/sync-*.png . Read the four times, then for each camera:
#
#     new CAM_DELAY_n  =  current CAM_DELAY_n  +  (that tile's time − EARLIEST time)
#
# i.e. hold the fast tiles back to match the slowest one. Edit .env and
#   sudo systemctl restart reolinktv-mosaic
#
# (OCR of the NVR's dot-matrix clock font is too unreliable to automate.)

set -euo pipefail
cd "$(dirname "$0")"
HLS="${HLS_URL:-http://127.0.0.1:8088/mosaic/index.m3u8}"
OUT="${OUT:-/tmp}"

seg=$(curl -fsS "$HLS" | grep -v '^#' | tail -1)
curl -fsS "${HLS%/*}/$seg" -o "$OUT/sync-seg.ts"
ffmpeg -hide_banner -loglevel error -i "$OUT/sync-seg.ts" -frames:v 1 -y "$OUT/sync-frame.png"

# tile clock locations on the 1920x1080 wall (x y w h) — the NVR OSD sits in a
# different corner per camera
crop() { ffmpeg -hide_banner -loglevel error -i "$OUT/sync-frame.png" \
  -vf "crop=$1,scale=iw*3:ih*3" -y "$OUT/sync-$2.png"; echo "  $OUT/sync-$2.png  ($2)"; }
echo "wrote:"
crop "480:46:8:486"    cam1_CX810      # bottom-left of top-left tile
crop "480:46:966:8"    cam2_Doorbell   # top-left of top-right tile
crop "480:46:8:548"    cam3_RLC510     # top-left of bottom-left tile
crop "480:46:966:1026" cam4_Peak       # bottom-left of bottom-right tile
echo "  $OUT/sync-frame.png  (whole wall)"
echo
echo "current delays:"; grep -E '^CAM_DELAY_' ./.env || true
