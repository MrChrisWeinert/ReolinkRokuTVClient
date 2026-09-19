#!/usr/bin/env bash
# Standalone 2x2 mosaic — no Docker, no go2rtc. Useful for testing, or to run on
# this Mac while it's awake. Publishes an RTSP + HLS mosaic locally.
#
#   ./mosaic.sh preview           # one-shot: write mosaic.jpg and exit
#   ./mosaic.sh rtsp              # serve rtsp://<this-host>:8554/mosaic  (needs mediamtx)
#   ./mosaic.sh hls  ./out        # write ./out/mosaic.m3u8 (+ segments) continuously
#
# Env (or edit here):
: "${NVR_HOST:=192.168.2.199}"
: "${NVR_USER:=nvruser}"
: "${NVR_PASS:=changeme}"
: "${FPS:=12}"
: "${BITRATE:=3500k}"

set -euo pipefail
B="rtsp://${NVR_USER}:${NVR_PASS}@${NVR_HOST}:554"
IN=( -rtsp_transport tcp -i "$B/h264Preview_01_sub"
     -rtsp_transport tcp -i "$B/h264Preview_02_sub"
     -rtsp_transport tcp -i "$B/h264Preview_03_sub"
     -rtsp_transport tcp -i "$B/h264Preview_04_sub" )

# camera names are already burned into each feed by the NVR OSD
FC="[0:v]scale=960:540,setsar=1[a];[1:v]scale=960:540,setsar=1[b];\
[2:v]scale=960:540,setsar=1[c];[3:v]scale=960:540,setsar=1[d];\
[a][b]hstack[top];[c][d]hstack[bot];[top][bot]vstack,fps=${FPS},format=yuv420p[v]"

case "${1:-preview}" in
  preview)
    exec ffmpeg -hide_banner "${IN[@]}" -filter_complex "$FC" -map '[v]' -frames:v 1 -y mosaic.jpg
    ;;
  hls)
    OUT="${2:-./out}"; mkdir -p "$OUT"
    exec ffmpeg -hide_banner "${IN[@]}" -filter_complex "$FC" -map '[v]' \
      -c:v libx264 -preset veryfast -tune zerolatency -g $((FPS*2)) \
      -b:v "$BITRATE" -maxrate "$BITRATE" -bufsize "$BITRATE" -an \
      -f hls -hls_time 1 -hls_list_size 6 -hls_flags delete_segments+append_list \
      "$OUT/mosaic.m3u8"
    ;;
  rtsp)
    command -v mediamtx >/dev/null || { echo "install mediamtx first (brew install mediamtx)"; exit 1; }
    ( mediamtx & )  ; sleep 1
    exec ffmpeg -hide_banner "${IN[@]}" -filter_complex "$FC" -map '[v]' \
      -c:v libx264 -preset veryfast -tune zerolatency -g $((FPS*2)) \
      -b:v "$BITRATE" -maxrate "$BITRATE" -bufsize "$BITRATE" -an \
      -f rtsp rtsp://127.0.0.1:8554/mosaic
    ;;
  *) echo "usage: $0 {preview|hls [dir]|rtsp}"; exit 2 ;;
esac
