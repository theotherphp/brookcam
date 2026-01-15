#!/usr/bin/env python3

import time
import json
import requests
from googleapiclient.discovery import build

# --------------------------
# Load configuration
# --------------------------
with open("/usr/local/youtube-watchdog/config.json") as f:
    cfg = json.load(f)

YOUTUBE_API_KEY = cfg["youtube_api_key"]
POLL_INTERVAL = cfg.get("poll_interval_sec", 60)
FAIL_THRESHOLD = cfg.get("consecutive_failures", 2)
ALERT_METHOD = cfg.get("alert_method", "telegram")
TELEGRAM_BOT_TOKEN = cfg.get("telegram_bot_token")
TELEGRAM_CHAT_ID = cfg.get("telegram_chat_id")

# --------------------------
# YouTube API setup
# --------------------------
youtube = build("youtube", "v3", developerKey=YOUTUBE_API_KEY)

def is_live():
    """Return True if YouTube considers the broadcast live."""
    try:
        request = youtube.liveBroadcasts().list(
            part="status",
            broadcastStatus="active",
            mine=True
        )
        response = request.execute()
        if not response["items"]:
            return False
        status = response["items"][0]["status"]["lifeCycleStatus"]
        return status.lower() == "live"
    except Exception as e:
        print(f"Error querying YouTube API: {e}")
        return False

# --------------------------
# Alerting
# --------------------------
def alert(msg):
    if ALERT_METHOD == "telegram":
        requests.post(
            f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage",
            json={"chat_id": TELEGRAM_CHAT_ID, "text": msg}
        )
    elif ALERT_METHOD == "pushover":
        requests.post(
            "https://api.pushover.net/1/messages.json",
            data={
                "token": cfg["pushover_app_token"],
                "user": cfg["pushover_user_key"],
                "message": msg
            }
        )
    else:
        print("ALERT:", msg)

# --------------------------
# Watchdog loop
# --------------------------
failure_count = 0

while True:
    live = is_live()
    if live:
        failure_count = 0
    else:
        failure_count += 1
        if failure_count >= FAIL_THRESHOLD:
            alert("⚠️ YouTube stream is NOT LIVE")
            failure_count = 0  # reset to avoid repeated alerts
    time.sleep(POLL_INTERVAL)
