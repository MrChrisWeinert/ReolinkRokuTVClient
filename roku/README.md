# Roku channel — "Reolink Wall"

SceneGraph channel. One full-screen `Video` node playing HLS from the go2rtc backend.
Roku can't do RTSP, so the pre-composited **mosaic** is the main view — which is
exactly the 2×2 layout from the reference screenshot.

## Remote

| Button | Action |
|---|---|
| **▶ / ◀** (right/left) | cycle `Wall → CX810 → Doorbell → RLC-510 → Peak → Wall` |
| **OK** | flash the current camera's name |
| **Replay** | force reconnect |
| **Back** | jump to Wall; press again on Wall to exit |

On a stream error it shows "Reconnecting…" and retries every `retrySeconds`.

## Configure

`components/config.brs` → `RTVConfig()`: backend URL, channel list, timings.
The backend URL is baked at package time from `make`'s `BACKEND` var
(default `http://reolinkstreamer.lan:8088`).

## Build / lint / install

```bash
# one-time: enable Developer Mode on the Roku
#   Home x3, Up x2, Right, Left, Right, Left, Right  -> set password, note IP

npx brighterscript --project bsconfig.json        # lint (0 errors expected)
make package                                       # -> build/ReolinkWall.zip
make install ROKU_HOST=<roku-ip> ROKU_PASS=<dev-password>
make install ROKU_HOST=<roku-ip> ROKU_PASS=<pw> BACKEND=http://reolinkstreamer.lan:8088
```

Same channel runs on the Roku stick and the built-in Roku TV.

## Not done / notes

- Needs the backend up (`../backend/`) and the Roku's dev IP + password to test on
  hardware — not yet run on a device.
- No true 4-pane grid: multiple `Video` nodes perform badly on Roku. The mosaic is
  the grid.
- Icons/splash are auto-generated from `docs/mosaic-sample.jpg`.
