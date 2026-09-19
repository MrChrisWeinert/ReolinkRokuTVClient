#!/usr/bin/env bash
# Deploy the backend to a Linux box as native systemd services (no Docker).
#
#   SSH_HOST=me@reolinkstreamer.lan SUDO_PASS=... ./deploy.sh
#
# Idempotent: re-run after editing .env / mosaic/*.sh to push changes.
set -euo pipefail
cd "$(dirname "$0")"

: "${SSH_HOST:?set SSH_HOST=user@host}"
: "${SUDO_PASS:?set SUDO_PASS}"
SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
REMOTE_DIR="/opt/reolinktv"

[ -f .env ] || { echo "create backend/.env first (cp .env.example .env)"; exit 1; }

echo ">> staging files"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/reolinktv"
cp .env mosaic/run.sh mosaic/serve.sh mosaic/sync-tune.sh "$TMP/reolinktv/"

emit_unit() { # name  description  after  execstart
  cat > "$TMP/reolinktv/reolinktv-$1.service" <<EOF
[Unit]
Description=$2
After=$3
Wants=$3

[Service]
Type=simple
EnvironmentFile=${REMOTE_DIR}/.env
Environment=HLS_DIR=${REMOTE_DIR}/hls
ExecStart=$4
Restart=always
RestartSec=4
User=root

[Install]
WantedBy=multi-user.target
EOF
}

# Just two services. go2rtc + MediaMTX were both trialed as the fan-out/packager
# layer and both introduced RTSP cross-talk with this NVR (see docs/FINDINGS.md);
# the single ffmpeg pipeline talking straight to the NVR is what's reliable.
emit_unit hls    "ReolinkTV HLS static server"    "network-online.target" \
  "/bin/bash ${REMOTE_DIR}/serve.sh"
emit_unit mosaic "ReolinkTV media pipeline"       "network-online.target" \
  "/bin/bash ${REMOTE_DIR}/run.sh"

echo ">> uploading to ${SSH_HOST}:/tmp"
tar czf - -C "$TMP" reolinktv | sshpass -e ssh "${SSH_OPTS[@]}" "$SSH_HOST" 'cat > /tmp/reolinktv.tgz'

echo ">> installing on remote"
sshpass -e ssh "${SSH_OPTS[@]}" "$SSH_HOST" "SUDO_PASS='${SUDO_PASS}' REMOTE_DIR='${REMOTE_DIR}' bash -s" <<'REMOTE'
set -euo pipefail
sudo() { echo "$SUDO_PASS" | command sudo -S -p '' "$@"; }

sudo mkdir -p "$REMOTE_DIR/hls"
sudo tar xzf /tmp/reolinktv.tgz -C /opt
sudo cp -f /opt/reolinktv/reolinktv/* "$REMOTE_DIR"/ 2>/dev/null || true
sudo rm -rf /opt/reolinktv/reolinktv
rm -f /tmp/reolinktv.tgz

if ! command -v ffmpeg >/dev/null; then
  echo ">> apt install ffmpeg"
  sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ffmpeg >/dev/null
fi
ffmpeg -version | head -1

# retire the earlier go2rtc / mediamtx / llhls services if this box had them
for old in go2rtc llhls; do
  sudo systemctl disable --now "reolinktv-$old" 2>/dev/null || true
  sudo rm -f "/etc/systemd/system/reolinktv-$old.service"
done

sudo chmod +x "$REMOTE_DIR"/*.sh
sudo cp "$REMOTE_DIR"/reolinktv-*.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable reolinktv-hls reolinktv-mosaic
sudo systemctl restart reolinktv-hls
sleep 2
sudo systemctl restart reolinktv-mosaic
sleep 3
echo ">> status"
systemctl is-active reolinktv-hls reolinktv-mosaic
REMOTE

echo ">> done."
echo "   HLS : http://${SSH_HOST#*@}:8088/mosaic/index.m3u8   (Roku)"
