# NVR Discovery — verified 2026-09-10

All of this was probed live against the NVR with a dedicated user-level account
(see `backend/.env.example`).

## Device

| Field | Value |
|---|---|
| Model | Reolink **RLN8-410** (8-channel NVR, H3MB02 hardware) |
| Firmware | `v2.0.0.4732_1728_21062800` (build 2021-06-28) — old, quirky RTSP |
| IP | `192.168.2.199` |
| Ports | HTTP 80, HTTPS 443, **RTSP 554**, RTMP 1935, ONVIF 8000, media 9000 (all open) |
| API | `https://192.168.2.199/cgi-bin/api.cgi` — token login with the user-level account works |
| ONVIF | `192.168.2.199:8000` — same account works, `GetStreamUri` returns the real paths |

## Channels (4 of 8 populated)

| Ch (API) | RTSP # | Name | Main | Sub | Notes |
|---|---|---|---|---|---|
| 0 | 01 | **CX810**   | 3840×2160 @25, 8 Mbps | 640×360 @15 | driveway / street |
| 1 | 02 | **Doorbell**| 2560×1920 @? , —      | 640×480 @15 | side path (rotated view) |
| 2 | 03 | **RLC-510** | 2560×1920 @30         | 640×480 @15 | yard / street |
| 3 | 04 | **Peak**    | 2560×1440 @?          | 640×352 @15 | side yard (rotated view) |

All video is **H.264**, all audio **AAC** (16 kHz on sub).

## RTSP URL scheme (this firmware)

> NOTE the path has **no `ch` prefix** — it is `h264Preview_NN_main`, not `h264Preview_chNN_main`.
> Every online tutorial shows the `ch` form; it 404s on this box.

```
rtsp://<user>:<password>@192.168.2.199:554/h264Preview_01_main    # CX810 4K   ⚠ see below
rtsp://<user>:<password>@192.168.2.199:554/h264Preview_01_sub     # CX810 360p ✅
rtsp://<user>:<password>@192.168.2.199:554/h264Preview_02_main    # Doorbell   ✅
rtsp://<user>:<password>@192.168.2.199:554/h264Preview_02_sub     # Doorbell   ✅
rtsp://<user>:<password>@192.168.2.199:554/h264Preview_03_main    # RLC-510    ✅
rtsp://<user>:<password>@192.168.2.199:554/h264Preview_03_sub     # RLC-510    ✅
rtsp://<user>:<password>@192.168.2.199:554/h264Preview_04_main    # Peak       ✅
rtsp://<user>:<password>@192.168.2.199:554/h264Preview_04_sub     # Peak       ✅
```

Auth is RTSP **Digest** (realm `LIVE555 Streaming Media`). Put the credentials in the
URL — VLC and ffmpeg both handle it.

### ⚠ The one broken stream: CX810 main (`h264Preview_01_main`)

- `DESCRIBE` authenticates, then the NVR **never sends the SDP** — every client
  (ffmpeg TCP, ffmpeg UDP, RTMP `channel0_main.bcs`, HTTP-FLV) hangs or returns EOF.
- It is **not** a permissions problem: `GET api.cgi?cmd=Snap&channel=0` returns a full
  3840×2160 JPEG instantly for that same account.
- This is the well-known Reolink-NVR bug where old firmware won't proxy a 4K main
  stream over RTSP. The other three 2.5K mains are fine.
- **Fixes, best first:**
  1. In the Reolink app: CX810 → Encode → set **Main stream to H.264** (not "Clear"/H.265)
     and/or drop it to 3072×1728. Old NVR firmware then serves it fine. *(needs admin)*
  2. Update NVR firmware (RLN8-410 has newer builds). *(needs admin, more involved)*
  3. Fallback we ship anyway: CX810 tile uses the **sub** stream; CX810 fullscreen uses
     the sub upscaled, with an optional 1 fps 4K snapshot overlay from `cmd=Snap`.

## ⚠ The NVR RTSP server cross-talks under concurrent load

The RLN8-410 runs `LIVE555 Streaming Media`. With more than ~6-8 simultaneous RTSP
sessions (e.g. go2rtc holding 8 + an ffmpeg pipeline opening 4 + ad-hoc `ffprobe`
tests) it starts **mixing RTP between sessions** — symptoms:

- `RTP: PT=60: bad cseq XXXX expected=YYYY` in a flood, with two alternating
  sequence-number spaces on one input (= two channels' packets on one socket)
- green/grey macroblock smearing on a tile (usually the CX810)
- a tile freezing on one frame for minutes (the Doorbell is the worst for this)
- ffmpeg sitting at ~3% CPU producing no output (never gets a clean keyframe)

**What actually triggers it:** total concurrent RTSP session count on the NVR, and
session *churn*. The NVR holds a dropped session open for ~2-3 minutes before
reclaiming it, so restarting the pipeline (4 sessions) repeatedly stacks zombie
sessions until it tips over. go2rtc and MediaMTX in the path both made this worse
(more sessions, more churn) and each had output-side stream-mixing bugs of their own.

**Mitigation the backend uses:**
- **One** process touches the NVR: the single ffmpeg in `mosaic/run.sh`, exactly
  4 long-lived sub-stream sessions. No go2rtc, no MediaMTX.
- `-allowed_media_types video` — don't negotiate the AAC RTP stream (halves the RTP
  streams; we don't want audio anyway).
- Restarts are expensive. `-timeout` is set to 12s but bumping it up is reasonable;
  after any restart give it ~3 min before judging stability.
- **Never** point `ffprobe`/`ffmpeg`/VLC straight at `192.168.2.199:554` while the
  pipeline is running. Test against the backend's HLS (`reolinkstreamer.lan:8088`) instead.
  If you must hit the NVR directly, stop `reolinktv-mosaic` first and wait 3 min.

## Latency (HLS on Roku)

End-to-end, live edge: **RLC-510 / Peak ≈ 3-5 s, Doorbell ≈ 5-8 s, CX810 ≈ 15-20 s**
per camera on its own — since fixed, the composited tiles are held together within
~2-3 s of each other (see "Per-camera sync" below), so the wall as a whole sits about
6-8 s behind real time. This is about as good as HLS-to-Roku latency gets; anything
tighter would need a non-HLS player.

### Per-camera sync

The four cameras have different pipeline lag (and it *drifts* by a few seconds over
time), so left alone the tiles show times up to ~15 s apart. `mosaic/run.sh` holds
each input back with `-itsoffset ${CAM_DELAY_n}` to line them up — currently
`0 / 6 / 9 / 9` s, which keeps the spread to ~2-3 s. Re-tune with
`mosaic/sync-tune.sh` (writes big crops of each tile's clock; you read them and
adjust `.env`). `tpad` was tried first for this and stalls on live multi-input —
`-itsoffset` is the one that works.

### LL-HLS (Low-Latency HLS) — tried, doesn't work for Roku

MediaMTX v1.21 produces proper LL-HLS, but its HLS **HTTP server is cookie- and
per-session-URL gated** (built for browsers / hls.js): a plain client gets a `302`
to `?cookieCheck=1` and then an HTML `<video>` player page, not a playlist, and the
media-playlist URL carries a `?session=<uuid>` token. Roku's HLS client doesn't play
that game. `hlsDirectory:` makes MediaMTX write plain playlist+segment files (Roku-OK)
but that's a static tree — no `EXT-X-PART` / blocking reload — so it's just regular
HLS again, no latency win. Net: **no LL-HLS path to a Roku**, and MediaMTX was pulled
back out of the stack (see "The NVR RTSP server cross-talks..." above).

Getting below ~2s would need a non-HLS player (e.g. something that speaks RTSP
directly) instead of a Roku — out of scope here.

## Snapshot API (works for every channel incl. CX810 4K)

```
https://192.168.2.199/cgi-bin/api.cgi?cmd=Snap&channel=<0-3>&rs=<nonce>&token=<tok>
```

## Network layout (matters for the backend host)

- Cameras + NVR live on `192.168.2.0/24`. The backend box (`reolinkstreamer.lan`)
  is on a different VLAN, `192.168.1.0/24`.
- **Inter-VLAN routing is open** on this network — a box on `.1` or `.3` can reach
  the NVR on `.2.199` just fine. (Worth confirming no firewall rule blocks
  `.x → .2.199:554` before relying on it on a different network.)

## Local tooling state (this Mac)

- Homebrew present; **ffmpeg installed this session** (`/opt/homebrew/bin/ffmpeg` 9.0.1).
- No Docker on the Mac.
