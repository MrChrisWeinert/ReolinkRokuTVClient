# ReolinkTVClient — background

Goal: a live 2×2 wall of the 4 Reolink cameras on the TV via a Roku channel, fed
**only** from the local NVR — no Reolink cloud / AWS relay.

## What's proven (see `docs/FINDINGS.md`)

- All 8 local RTSP URLs found and tested. 7 of 8 work directly; CX810 4K main is a
  known NVR firmware bug (using its sub stream instead, per a deliberate call).
- `ffmpeg` composites the 4 sub streams into a 1920×1080 2×2 mosaic that looks exactly
  like the reference screenshot.

## Architecture

```
   NVR 192.168.2.199 (RTSP 554) — h264Preview_01..04_sub
                    │  (exactly 4 sessions, one process)
           ┌────────▼─────────┐
           │  backend host     │   reolinkstreamer.lan
           │  ffmpeg pipeline  │   -> 2x2 mosaic + per-cam HLS files
           │  static file srv  │   :8088
           └────────┬──────────┘
                    │  plain HTTP
              ┌─────▼─────┐
              │  Roku(s)  │   any number, all read the same files
              └───────────┘
```

**Why a middleware box instead of the Rokus hitting the NVR directly:** the
RLN8-410 is old and its RTSP server cross-talks between sessions once several are
open (see `docs/FINDINGS.md`) — so exactly one process (the ffmpeg pipeline) talks
to it, ever, and every Roku reads the files that process writes. Roku also can't
speak RTSP at all; it needs HLS, which the pipeline produces directly.

Earlier revisions tried routing the pipeline through `go2rtc` and/or `MediaMTX` for
stream fan-out and low-latency HLS. Both were removed: they added RTSP sessions and
churn (which is what actually triggers the NVR cross-talk), MediaMTX's low-latency
HLS turned out to be cookie/session-gated and unusable from a Roku, and a single
ffmpeg process talking straight to the NVR is simply more reliable. Full history in
`docs/FINDINGS.md`.

## Status (2026-09-11)

| Piece | State |
|---|---|
| NVR discovery | ✅ done, `docs/FINDINGS.md` |
| Backend | ✅ live on `reolinkstreamer.lan` — `reolinktv-mosaic` (ffmpeg) + `reolinktv-hls` (file server), both systemd, auto-restart. ~20% of one core. |
| Tile sync | ✅ the 4 cameras' clocks stay within ~2-3s of each other (`-itsoffset` per camera; see FINDINGS). |
| Roku channel | ✅ installed and running on two TVs (192.168.2.31, 192.168.2.200). |
| CX810 4K | using its sub stream (640×360) — the 4K main stream has a firmware bug. |
