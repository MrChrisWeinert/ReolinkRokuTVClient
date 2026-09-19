#!/usr/bin/env bash
# The whole media pipeline in ONE ffmpeg.
#   inputs : the 4 camera sub-streams, pulled straight from the NVR. This ffmpeg
#            is the ONLY thing that connects to the NVR -- the RLN8-410's LIVE555
#            server cross-talks between sessions once several are open, and go2rtc
#            / MediaMTX in the path just moved the problem around. Video only
#            (ingesting the AAC RTP too triggers the same cross-talk).
#   sync   : each input is held back by CAM_DELAY_n seconds (-itsoffset) so all
#            four tiles show the same wall-clock moment. Re-tune with sync-tune.sh.
#   outputs: mosaic + cam1..4 as HLS files under $HLS_DIR, served by serve.sh.
# Restarts forever; a 12s input stall trips a restart that reconnects all four.

: "${NVR_HOST:=192.168.2.199}"
: "${NVR_RTSP_PORT:=554}"
: "${NVR_USER:=nvruser}"
: "${NVR_PASS:=changeme}"
: "${MOSAIC_FPS:=12}"
: "${MOSAIC_BITRATE:=3500k}"
: "${HLS_DIR:=/opt/reolinktv/hls}"
: "${CAM_DELAY_1:=0}"
: "${CAM_DELAY_2:=4}"
: "${CAM_DELAY_3:=9}"
: "${CAM_DELAY_4:=9}"

trap 'kill "$FFPID" 2>/dev/null; exit 0' TERM INT

MOSAIC_GOP="$MOSAIC_FPS"
B="rtsp://${NVR_USER}:${NVR_PASS}@${NVR_HOST}:${NVR_RTSP_PORT}"
for d in mosaic cam1 cam2 cam3 cam4; do mkdir -p "${HLS_DIR}/$d"; done

# per-input options; -itsoffset must come right before its -i
ipre() { echo "-allowed_media_types video -rtsp_transport tcp -thread_queue_size 1024 -timeout 12000000 -itsoffset $1"; }

FC="[0:v]scale=960:540,setsar=1,fps=${MOSAIC_FPS}[a];\
[1:v]scale=960:540,setsar=1,fps=${MOSAIC_FPS}[b];\
[2:v]scale=960:540,setsar=1,fps=${MOSAIC_FPS}[c];\
[3:v]scale=960:540,setsar=1,fps=${MOSAIC_FPS}[d];\
[a][b]hstack[top];[c][d]hstack[bot];[top][bot]vstack,format=yuv420p[v]"

HLS=(-f hls -hls_time 1 -hls_list_size 4
     -hls_flags delete_segments+append_list+omit_endlist+independent_segments
     -hls_delete_threshold 3 -hls_segment_type mpegts)
HLS_TEE="f=hls:hls_time=1:hls_list_size=4:hls_flags=delete_segments+append_list+omit_endlist+independent_segments:hls_delete_threshold=3:hls_segment_type=mpegts"

while true; do
  echo "$(date '+%H:%M:%S') pipeline: starting ffmpeg (delays: $CAM_DELAY_1/$CAM_DELAY_2/$CAM_DELAY_3/$CAM_DELAY_4)"
  ffmpeg -hide_banner -loglevel error -nostats \
    $(ipre "$CAM_DELAY_1") -i "$B/h264Preview_01_sub" \
    $(ipre "$CAM_DELAY_2") -i "$B/h264Preview_02_sub" \
    $(ipre "$CAM_DELAY_3") -i "$B/h264Preview_03_sub" \
    $(ipre "$CAM_DELAY_4") -i "$B/h264Preview_04_sub" \
    -filter_complex "$FC" \
    -map '[v]' -c:v libx264 -preset veryfast -tune zerolatency \
      -g "$MOSAIC_GOP" -keyint_min "$MOSAIC_GOP" -sc_threshold 0 \
      -b:v "$MOSAIC_BITRATE" -maxrate "$MOSAIC_BITRATE" -bufsize "$MOSAIC_BITRATE" -an \
      "${HLS[@]}" "${HLS_DIR}/mosaic/index.m3u8" \
    -map 0:v -c copy "${HLS[@]}" "${HLS_DIR}/cam1/index.m3u8" \
    -map 1:v -c copy "${HLS[@]}" "${HLS_DIR}/cam2/index.m3u8" \
    -map 2:v -c copy "${HLS[@]}" "${HLS_DIR}/cam3/index.m3u8" \
    -map 3:v -c copy "${HLS[@]}" "${HLS_DIR}/cam4/index.m3u8" &
  FFPID=$!
  wait "$FFPID"
  echo "$(date '+%H:%M:%S') pipeline: ffmpeg exited ($?), restarting in 5s"
  sleep 5
done
