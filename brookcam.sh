ffmpeg \
  \
  # --- RTSP input stability ---
  -rtsp_transport tcp \                    # Use TCP to avoid UDP packet loss/jitter
  -fflags +genpts+discardcorrupt \          # Generate clean timestamps, drop broken frames
  -use_wallclock_as_timestamps 1 \          # Replace camera PTS with wall-clock time
  -max_delay 0 \                            # Drop late frames instead of buffering
  -analyzeduration 1000000 \                # Limit probe time (faster, more predictable)
  -probesize 1000000 \                      # Limit probe size (avoids RTSP stalls)
  \
  # --- Camera input ---
  -i rtsp://USER:PASS@CAMERA_IP:554/h264Preview_01_main \
                                            # Reolink E1 Pro main RTSP stream
  \
  # --- Inject silent audio (YouTube requires audio) ---
  -f lavfi \
  -i anullsrc=channel_layout=stereo:sample_rate=44100 \
                                            # Fake silent AAC-compatible audio
  \
  # --- Stream selection ---
  -map 0:v:0 \                              # Use video from RTSP camera
  -map 1:a:0 \                              # Use injected silent audio
  \
  # --- Video processing ---
  -vf "scale=2560:1440:flags=lanczos" \      # Scale to 1440p (better YouTube quality tier)
  -vsync cfr \                              # HARD constant frame rate (rewrite timestamps)
  -r 30 \                                   # Output exactly 30 fps
  \
  # --- Video encoding (Apple Silicon hardware) ---
  -c:v h264_videotoolbox \                  # Apple hardware H.264 encoder
  -profile:v high \                         # YouTube-compatible H.264 profile
  -level 5.1 \                              # Required for 1440p@30
  -pix_fmt yuv420p \                        # Mandatory pixel format for YouTube
  \
  # --- GOP / keyframe control (YouTube critical) ---
  -g 60 \                                   # Keyframe every 2 seconds (30fps × 2)
  -keyint_min 60 \                          # Prevent early keyframes
  -bf 0 \                                   # Disable B-frames (YouTube stability)
  -sc_threshold 0 \                         # Disable scene-change keyframes
  \
  # --- Bitrate control (CBR-like) ---
  -b:v 9000k \                              # Target video bitrate (1440p30)
  -maxrate 9000k \                          # Prevent bitrate spikes
  -bufsize 18000k \                         # VBV buffer (2× bitrate)
  \
  # --- Hardware encoder behavior ---
  -realtime 1 \                             # Force real-time mode (no buffering bursts)
  -allow_sw 0 \                             # Fail if hardware encoder is unavailable
  \
  # --- Audio encoding (silent but valid) ---
  -c:a aac \                                # YouTube-required audio codec
  -b:a 128k \                               # Standard audio bitrate
  -ar 44100 \                               # Audio sample rate
  -ac 2 \                                   # Stereo (expected by YouTube)
  -af aresample=async=1 \                   # Keep audio clock stable vs video
  \
  # --- Output ---
  -f flv \                                  # Required container for RTMP
  rtmp://a.rtmp.youtube.com/live2/YOUR-STREAM-KEY
