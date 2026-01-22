#!/bin/sh
# Shell script to upload from Reolink E1 Pro to YouTube Live

# Secrets are stored in environment variables (not github)
# CAMERA_USER, CAMERA_PASSWORD, CAMERA_IP, YOUTUBE_STREAM_KEY

ENV_PATH="./brookcam.env"
if [[ ! -f "$ENV_PATH" ]]; then
  echo "env file not found"
  exit 1
fi
source $ENV_PATH

while true; do
  echo "Starting stream $(date +"%a %x at %r")"

  # RTSP input: TCP transport, generate clean timestamps, drop corrupt frames
  # Video input: Reolink E1 Pro main stream (h264Preview_01_main)
  # Audio input: Silent generated audio (YouTube requires an audio track)
  # Video encoding: h264_videotoolbox (Apple Silicon), 1440p20, 9Mbps CBR
  # GOP: Keyframe every 2s (YouTube requirement)
  # Audio encoding: AAC stereo 128k
  # Output: FLV over RTMP to YouTube Live

  # Restart every 12 hours to avoid YouTube's ~24h connection limit
  gtimeout --signal=SIGINT 43200 ffmpeg \
    -loglevel info -nostats \
    -rtsp_transport tcp \
    -fflags +genpts+discardcorrupt \
    -use_wallclock_as_timestamps 1 \
    -max_delay 0 \
    -analyzeduration 2000000 \
    -probesize 2000000 \
    -thread_queue_size 512 \
    -i "rtsp://$CAMERA_USER:$CAMERA_PASSWORD@$CAMERA_IP:554/h264Preview_01_main" \
    \
    -f lavfi \
    -i anullsrc=channel_layout=stereo:sample_rate=44100 \
    \
    -map 0:v:0 \
    -map 1:a:0 \
    \
    -vf "scale=2560:1440:flags=lanczos" \
    -fps_mode cfr \
    -r 20 \
    \
    -c:v h264_videotoolbox \
    -profile:v high \
    -level 5.1 \
    -pix_fmt yuv420p \
    \
    -g 40 \
    \
    -b:v 9000k \
    -maxrate 9000k \
    -bufsize 18000k \
    \
    -realtime 1 \
    -allow_sw 0 \
    \
    -c:a aac \
    -b:a 128k \
    -ar 44100 \
    -ac 2 \
    -af aresample=async=1 \
    \
    -f flv \
    "rtmp://a.rtmp.youtube.com/live2/$YOUTUBE_STREAM_KEY"
done
