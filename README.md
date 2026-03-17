# Brookcam

Powers the livestream of video at my tennis club

## Hardware

1. The camera is a [Reolink E1 Pro](https://reolink.com/us/product/e1-outdoor-pro/) outdoor camera which provides video via [RTSP](https://en.wikipedia.org/wiki/Real-Time_Streaming_Protocol).
1. This software runs on a Mac mini 
1. The camera is connected via WiFi and the Mac mini is connected to the WiFi router via Ethernet so they're on the same network
1. We're using the low resolution RTSP feed so the livestream is very little overhead on the Mac mini or ISP uplink. 4k resolution is possible but less reliable.

## YouTube

1. The club has a Google workspace and we created a YouTube channel and stream key
1. v1.0 used a manually-created (via the Go Live button) livestream.
1. v2.0 uses a manually-created scheduled livestream with autostart and autostop for less manual intervention.
1. v3.0 uses the YouTube Data API v3 to automatically create a fresh broadcast each morning. This fixes the "preparing stream" issue that occurred when YouTube's Go Live session got stuck after the overnight gap. See [SETUP.md](SETUP.md) for API configuration.
1. We disabled DVR recording, and enabled embedding since the video is enabled on the club web page.

## Brookcam uploader

1. I started with [Open Broadcaster Studio](https://obsproject.com/) (OBS) but found it to be unstable. Every time I exited the app, it crashed and lost settings.
1. Once I realized that OBS is a frontend to [FFmpeg](https://ffmpeg.org/), I developed the brookcam script you see here. It started simple but got more complex as I discovered audio/video encoding quirks which caused YouTube to terminate the livestream.

## Availability

1. The uploader is launched by MacOS `launchd`. The brookcam plist tells launchd to launch the uploader at 6 AM. 
1. The watchdog script watches for stalls or failures and kills the brookcam uploader
1. The plist file is a `LaunchDaemon` so it launches when the machine powers on even before a user logs in. This should be resilient against power outages. The Mac mini is configured to boot after a power outage.
1. The deploy script puts the plist files where they need to go, and should be run with every `git pull` on the Mac mini.
1. The brookcam script exits at 8 PM and `launchd` starts it again at 6 AM. 

## Remote monitoring

1. The Mac mini is on a [Tailscale](https://tailscale.com/) VPN that I set up for remote management
1. The watchdog script uses [Pushover](https://pushover.net/) to send alerts to my phone when the livestream is down.

## Security

1. Secrets (camera password, YouTube stream key, Pushover API key) are stored in an environment (env) file on the Mac mini which is not in this repo (via `.gitignore`)

## Version history

1. v1.0 tried to keep the livestream up 24/7 but network issues at the club made that problematic. The brookcam and watchdog scripts were run manually in Terminal, in the login session for the gm user
1. v2.0 uses launchd and a manually-created scheduled YouTube livestream to automatically start and stop the livestream. That way we can see court conditions during the daytime but skip the difficulties of keeping the stream up 24/7.
1. v3.0 uses the YouTube Data API v3 to create a fresh broadcast each morning automatically, eliminating the "preparing stream" problem that occurred when resuming after the overnight gap.