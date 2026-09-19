' Backend + camera configuration.
'
' BACKEND_URL below is rewritten at package time by the Makefile from the
' BACKEND env var (default http://reolinkstreamer.lan:8088). To just hardcode it,
' edit the string and run `make install` with no BACKEND set.

function RTVConfig() as object
    return {
        ' HLS static server on the backend box (backend/mosaic/serve.sh, port 8088).
        ' Each view is <backend>/<src>/index.m3u8
        backend: "@@BACKEND_URL@@"

        ' Ordered channel list. First entry is the default view shown on launch.
        channels: [
            { name: "Wall",     src: "mosaic" }
            { name: "CX810",    src: "cam1"   }
            { name: "Doorbell", src: "cam2"   }
            { name: "RLC-510",  src: "cam3"   }
            { name: "Peak",     src: "cam4"   }
        ]

        bannerSeconds: 2.5   ' how long the channel-name banner shows after a switch
        retrySeconds: 4      ' auto-reconnect delay after a stream error
    }
end function
