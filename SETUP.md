# YouTube API Setup Guide

One-time setup to enable create-broadcast.sh.

## 1. Create a Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Sign in with the club's Google Workspace account
3. Click **Select a project** > **New Project**
4. Name it something like "Brookcam" and click **Create**
5. This is free — no billing required for the YouTube Data API at our usage level

## 2. Enable the YouTube Data API v3

1. In the Cloud Console, go to **APIs & Services** > **Library**
2. Search for "YouTube Data API v3"
3. Click on it and click **Enable**

## 3. Configure the OAuth Consent Screen

1. Go to **APIs & Services** > **OAuth consent screen**
2. Choose **Internal** (available because you're on Google Workspace)
   - Internal means only users in your organization can authorize
   - This avoids the 7-day refresh token expiry that affects External apps in "testing" mode
3. Fill in the required fields:
   - App name: "Brookcam"
   - User support email: your email
   - Developer contact: your email
4. Click **Save and Continue** through the remaining steps
5. Add the scope: `https://www.googleapis.com/auth/youtube`

## 4. Create OAuth Credentials

1. Go to **APIs & Services** > **Credentials**
2. Click **+ Create Credentials** > **OAuth client ID**
3. Application type: **Desktop app**
4. Name: "Brookcam Mac mini"
5. Click **Create**
6. Click **Download JSON** — save the `client_secret_*.json` file
7. Transfer this file to the Mac mini (e.g., via AirDrop or scp)

## 5. Run the Setup Script

On the Mac mini, with the club manager present (they need to authorize in the browser):

```bash
# Install jq if not already present
brew install jq

# Run setup — pass the path to the downloaded JSON file
./setup-oauth.sh ~/Downloads/client_secret_*.json
```

The script will:
1. Open a browser for Google authorization
2. Ask you to paste the redirect URL
3. Exchange the code for OAuth tokens
4. Save credentials to `brookcam.env`

## 6. Test It

```bash
# Create a test broadcast
./create-broadcast.sh

# Check YouTube Studio — you should see a new scheduled broadcast
# Start ffmpeg — it should auto-transition to live
```

## Troubleshooting

**"Token has been expired or revoked"**
- If using an **External** OAuth consent screen in testing mode, refresh tokens expire after 7 days
- Fix: Switch to **Internal** (requires Google Workspace), or publish the app
- Workaround: Re-run `setup-oauth.sh` to get a new refresh token

**"Access Not Configured" or 403 errors**
- Make sure YouTube Data API v3 is enabled in the Cloud Console

**"No live streams found"**
- Create a stream in YouTube Studio first (Go Live > Stream > get a stream key)
- The stream key in YouTube Studio must match `YOUTUBE_STREAM_KEY` in `brookcam.env`

**Quota exceeded (403)**
- The free quota is 10,000 units/day; we use ~300/day
- Check usage at **APIs & Services** > **Dashboard** in Cloud Console

---

## Operational Lessons Learned

### Broadcast vs. Stream

YouTube has two separate concepts that are easy to confuse:

- **Stream**: A persistent RTMP ingest endpoint with a fixed stream key. There is one of these and it never changes.
- **Broadcast**: A schedulable video event that is bound to a stream. `create-broadcast.sh` creates a fresh one each day.

ffmpeg sends RTMP data to the **stream key**. YouTube routes that to whichever **broadcast** is currently bound to the stream. If no broadcast is active, viewers see "video unavailable" even though ffmpeg is running fine.

### AutoStart is unreliable on reused broadcasts

`enableAutoStart: true` is supposed to transition a broadcast from `upcoming` to `live` automatically when RTMP data arrives. In practice this works reliably for freshly created broadcasts but not always for broadcasts that have been disconnected and reconnected. When it fails, ffmpeg streams happily to YouTube but viewers see "video unavailable".

The fix in `create-broadcast.sh`:
- If any broadcast is already **active**, skip creation entirely and let ffmpeg reconnect — YouTube keeps the existing broadcast live
- If a broadcast is stuck in **upcoming**, delete it and create a fresh one — this gives autoStart a clean slate

Do not check for an existing broadcast by title/date alone — a previous day's broadcast may still be active after an overnight disconnect, and creating a new one alongside it causes the "video unavailable" problem.

### Network outages at the club

The club's router occasionally drops DNS resolution overnight, causing both `create-broadcast.sh` (OAuth calls) and ffmpeg (RTMP connection) to fail immediately. This is normal and self-resolving. The 5-minute retry delay in `run.sh` for fast-exit sessions (under 30 seconds) handles this gracefully.

### The watchdog and yt-dlp n-challenge warnings

The watchdog uses `yt-dlp` to check whether the stream is live. yt-dlp may print warnings about failing to solve YouTube's "n challenge" (an anti-bot measure for download URLs). These warnings are harmless — they do not affect the `is_live` metadata field that the watchdog checks. The final output (`True` or `False`) is reliable.

### What "Broken pipe" on the RTMP output means

When YouTube closes the RTMP connection on its end, ffmpeg exits with `Broken pipe` errors on the output. This is normal and expected — it just means YouTube dropped the connection. The restart loop in `run.sh` handles it. The `Failed to update header` messages that follow are also harmless (they are ffmpeg trying to finalise an FLV container over a non-seekable network connection).

### Running the scripts

- The normal configuration is the two launchd agents installed by `install-launchd.sh` (see "Surviving a reboot" below). They start at login and restart the scripts if they exit.
- To debug by hand, stop the agents first so launchd does not restart them underneath you:

```bash
launchctl bootout gui/$(id -u)/com.brookcam.watchdog
launchctl bootout gui/$(id -u)/com.brookcam.stream
```

  Then run `./run.sh` and `./watchdog.sh` in separate terminal tabs (e.g. in tmux or via macOS Screen Sharing over Tailscale). Ctrl-C stops the foreground script; because both run in the foreground of their own terminal, they are independent and can be stopped/restarted individually. Stop the watchdog when examining logs so it does not restart ffmpeg mid-investigation.
- `launchctl kickstart -k gui/$(id -u)/com.brookcam.stream` restarts the stream agent in place.

---

## Surviving a reboot

The Mac mini loses power and reboots occasionally. Four things have to be true for the stream to come back without anyone logging in over Tailscale.

### 1. The Mac powers itself back on

```bash
sudo pmset -a autorestart 1     # power back on after a power failure
sudo pmset -a sleep 0 disksleep 0 displaysleep 0
sudo pmset -a womp 1            # wake for network access
```

### 2. It logs into the GUI session automatically

System Settings > Users & Groups > **Automatic login** > select the `gm` user.

This is not optional. ffmpeg needs a logged-in Aqua session for two reasons: `h264_videotoolbox` hardware encoding, and Local Network access to the camera. A LaunchDaemon running as root at boot has neither, which is why the first attempt at this (commit `b700e7d`) was reverted with "ffmpeg can't see the camera in that network env."

**FileVault must be off**, or the Mac will sit at the unlock screen after a power cut and never reach the desktop. Automatic login is disabled while FileVault is enabled.

### 3. The launchd agents are installed

```bash
cd ~/brookcam
./install-launchd.sh
```

This writes `~/Library/LaunchAgents/com.brookcam.{stream,watchdog}.plist` and starts them. They run as the `gm` user in the Aqua session, with `RunAtLoad` (start at login) and `KeepAlive` (restart if the script exits). Logs go to `~/Library/Logs/brookcam.log` and `~/Library/Logs/brookcam-watchdog.log`.

Do not run the installer with `sudo` — per-user agents are the whole point.

To go back to running by hand: `./install-launchd.sh uninstall`.

### 4. Local Network permission is granted to the launchd job

This is the step that failed in March, and it is the one that is genuinely awkward. Since macOS Sequoia a process needs permission to reach devices on the local network, and the permission is attributed to the **responsible process**. Start the stream from Terminal and Terminal.app is responsible — it already has the grant, which is why running by hand works. Under launchd the binary itself is responsible and starts with no grant, so the RTSP connection times out with nothing in the log to explain it.

**First, confirm that permissions are actually the problem.** Run the diagnostic both ways, in a GUI Terminal via Screen Sharing (not over ssh — an ssh session has its own permission context and will mislead you):

```bash
cd ~/brookcam
./check-camera.sh              # probes the camera from your Terminal
./check-camera.sh --as-agent   # probes it from a throwaway LaunchAgent
```

Read the two results together:

| Terminal | LaunchAgent | Meaning |
| --- | --- | --- |
| ok | ok | Permissions are fine; the stream failure is something else |
| ok | fail | Local Network privacy — continue below |
| fail | fail | The camera is off, `CAMERA_IP` is wrong, or the network is down |

**To grant it:** open System Settings > Privacy & Security > **Local Network** and look for an entry named `ffmpeg`, `bash`, or `com.brookcam.stream`. Enable it, then restart the agent:

```bash
launchctl kickstart -k gui/$(id -u)/com.brookcam.stream
```

An entry only appears *after* the process has tried and been denied, so install the agents and let them fail once before looking. There is no command-line way to grant this — `tccutil` only supports `reset SERVICE BUNDLE_ID`, and `ffmpeg` is a bare Unix binary with no bundle identifier. If the entry never shows up, or the toggle does not stick, do not keep fighting it: use the Terminal route below. It is not a hack, it is the same mechanism that already works today.

### The Terminal route (reliable, and probably what you want)

Terminal.app has a bundle identifier and already holds the Local Network grant. Launching the scripts through it sidesteps the whole problem.

**Do not add Terminal.app itself to Login Items** — that just opens an empty window. Add the two `.command` files; macOS opens `.command` documents with Terminal.app, which is the entire point:

1. Run `./install-launchd.sh uninstall` first, so both mechanisms are not starting ffmpeg at once
2. System Settings > General > **Login Items & Extensions**
3. Under "Open at Login", click **+** and add:
   - `~/brookcam/run.command`
   - `~/brookcam/watchdog.command`
4. Log out and back in — two Terminal windows should open and start streaming

The trade-off is that you lose launchd's `KeepAlive`, so nothing restarts the script if it is killed outright. In practice `run.sh` and `watchdog.sh` loop forever and only stop if someone closes the window, and the visible Terminal windows are arguably easier to check over Screen Sharing than a log file.

If the first Terminal launch prompts about allowing access to devices on the local network, say yes. If it was denied at some point, toggle Terminal back on in System Settings > Privacy & Security > Local Network. (`tccutil reset LocalNetwork com.apple.Terminal` is reported to re-trigger the prompt, but the exact service name was not verified here — use the UI if tccutil rejects it.)

### Verifying

The honest test is a real reboot, done while you are on site or on Tailscale:

```bash
sudo reboot
# wait ~2 minutes, then
launchctl list | grep brookcam
tail -20 ~/Library/Logs/brookcam.log
```
