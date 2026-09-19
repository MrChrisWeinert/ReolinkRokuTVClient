#!/usr/bin/env bash
# Re-run the NVR discovery. Prints channel names, resolutions, and which RTSP
# paths actually work. Handy after firmware/camera changes.
#
#   NVR_HOST=192.168.2.199 NVR_USER=nvruser NVR_PASS=changeme ./probe-nvr.sh

: "${NVR_HOST:=192.168.2.199}"
: "${NVR_USER:=nvruser}"
: "${NVR_PASS:=changeme}"
API="https://${NVR_HOST}/cgi-bin/api.cgi"

jqget() { command -v jq >/dev/null && jq "$@" || cat; }

echo "== login =="
TOK=$(curl -sk -m10 -X POST "$API?cmd=Login" -H 'Content-Type: application/json' \
  -d "[{\"cmd\":\"Login\",\"param\":{\"User\":{\"userName\":\"$NVR_USER\",\"password\":\"$NVR_PASS\"}}}]" \
  | grep -o '"name" *: *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
[ -n "$TOK" ] || { echo "login failed"; exit 1; }
echo "token=$TOK"

echo "== device =="
curl -sk -m10 -X POST "$API?cmd=GetDevInfo&token=$TOK" -H 'Content-Type: application/json' \
  -d '[{"cmd":"GetDevInfo","param":{}}]' | jqget -r '.[0].value.DevInfo | "\(.model)  fw \(.firmVer)  \(.channelNum)ch"'

echo "== channels =="
for ch in 0 1 2 3 4 5 6 7; do
  name=$(curl -sk -m10 -X POST "$API?cmd=GetOsd&token=$TOK" -H 'Content-Type: application/json' \
    -d "[{\"cmd\":\"GetOsd\",\"param\":{\"channel\":$ch}}]" \
    | grep -o '"name" *: *"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
  [ -n "$name" ] || continue
  n=$(printf '%02d' $((ch+1)))
  for q in main sub; do
    url="rtsp://${NVR_USER}:${NVR_PASS}@${NVR_HOST}:554/h264Preview_${n}_${q}"
    res=$(ffprobe -v error -rtsp_transport tcp -timeout 8000000 \
          -show_entries stream=codec_name,width,height -of csv=p=0 "$url" 2>/dev/null \
          | head -1)
    printf '  ch%s %-10s %-4s  %s\n' "$n" "$name" "$q" "${res:-<<< FAILED >>>}"
  done
done
