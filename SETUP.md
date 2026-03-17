# YouTube API Setup Guide

One-time setup to enable automatic daily broadcast creation.

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
