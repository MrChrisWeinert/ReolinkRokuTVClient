#!/usr/bin/env bash
# Tiny static HTTP server for the HLS tree (Roku fetches playlists + .ts here).
# Python 3.7+ http.server is threaded (ThreadingHTTPServer) -- fine for a few TVs.
: "${HLS_DIR:=/opt/reolinktv/hls}"
: "${HLS_PORT:=8088}"
mkdir -p "$HLS_DIR"
cd "$HLS_DIR"
exec python3 -m http.server "$HLS_PORT" --bind 0.0.0.0
