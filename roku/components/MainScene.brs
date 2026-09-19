sub init()
    m.cfg = RTVConfig()
    m.video = m.top.findNode("video")
    m.banner = m.top.findNode("banner")
    m.bannerText = m.top.findNode("bannerText")
    m.status = m.top.findNode("status")
    m.bannerTimer = m.top.findNode("bannerTimer")
    m.retryTimer = m.top.findNode("retryTimer")
    m.bannerIn = m.top.findNode("bannerIn")
    m.bannerOut = m.top.findNode("bannerOut")

    m.bannerTimer.duration = m.cfg.bannerSeconds
    m.retryTimer.duration = m.cfg.retrySeconds

    m.index = 0
    m.video.observeField("state", "onVideoState")
    m.bannerTimer.observeField("fire", "hideBanner")
    m.retryTimer.observeField("fire", "reconnect")

    m.top.setFocus(true)
    playCurrent()
end sub

function hlsUrl(src as string) as string
    return m.cfg.backend + "/" + src + "/index.m3u8"
end function

sub playCurrent()
    ch = m.cfg.channels[m.index]

    content = CreateObject("roSGNode", "ContentNode")
    content.url = hlsUrl(ch.src)
    content.streamFormat = "hls"
    content.title = ch.name
    ' live edge, keep latency low
    content.live = true

    m.video.content = content
    m.video.control = "play"

    showBanner(ch.name)
    showStatus("")
end sub

sub showBanner(name as string)
    m.bannerText.text = name
    m.bannerOut.control = "stop"
    m.bannerIn.control = "start"
    m.bannerTimer.control = "start"
end sub

sub hideBanner()
    m.bannerOut.control = "start"
end sub

sub showStatus(txt as string)
    m.status.text = txt
    if txt <> "" then
        m.status.opacity = 1.0
    else
        m.status.opacity = 0.0
    end if
end sub

sub onVideoState()
    st = m.video.state
    if st = "playing" then
        showStatus("")
    else if st = "buffering" then
        showStatus("Connecting" + Chr(8230))
    else if st = "error" then
        showStatus("Reconnecting" + Chr(8230))
        m.retryTimer.control = "start"
    else if st = "finished" then
        ' a live stream should not "finish" -- treat as a drop
        m.retryTimer.control = "start"
    end if
end sub

sub reconnect()
    playCurrent()
end sub

sub cycle(delta as integer)
    n = m.cfg.channels.count()
    m.index = (m.index + delta + n) mod n
    playCurrent()
end sub

function onKeyEvent(key as string, press as boolean) as boolean
    if not press then return false

    if key = "right" then
        cycle(1) : return true
    else if key = "left" then
        cycle(-1) : return true
    else if key = "OK" then
        showBanner(m.cfg.channels[m.index].name) : return true
    else if key = "back" then
        if m.index <> 0 then
            m.index = 0 : playCurrent() : return true
        end if
        return false   ' let Roku exit the channel from the Wall view
    else if key = "replay" then
        playCurrent() : return true
    else if key = "up" or key = "down" then
        showBanner(m.cfg.channels[m.index].name) : return true
    end if

    return false
end function
