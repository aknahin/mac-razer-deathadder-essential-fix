#!/bin/bash
# Renders docs/demo.gif: the UI driven by scripts/demo/demo.js against a fake mouse.
# Needs Google Chrome and ffmpeg (brew install ffmpeg). Never touches real hardware.
set -euo pipefail

cd "$(dirname "$0")/../.."
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
FPS=10
DURATION=12.5
PORT=47599
WIDTH=1280
HEIGHT=800

WORK="$(mktemp -d)"
trap 'kill $SERVER 2>/dev/null || true; rm -rf "$WORK"' EXIT

# A copy of the UI with the demo harness loaded before app.js.
cp -R Sources/deathadder-fix/Web "$WORK/site"
cp scripts/demo/demo.js "$WORK/site/demo.js"
sed -i '' 's|<script src="app.js"></script>|<script src="demo.js"></script><script src="app.js"></script>|' "$WORK/site/index.html"

python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$WORK/site" >/dev/null 2>&1 &
SERVER=$!
sleep 1

FRAMES=$(python3 -c "print(int($DURATION * $FPS))")
mkdir -p "$WORK/frames"
echo "→ Rendering $FRAMES frames"
render() {
  local i=$1 t
  t=$(python3 -c "print(round($i / $FPS, 3))")
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --mute-audio \
    --user-data-dir="$WORK/prof-$((i % 6))" --window-size=$WIDTH,$HEIGHT --virtual-time-budget=3000 \
    --screenshot="$WORK/frames/$(printf %04d "$i").png" "http://127.0.0.1:$PORT/?token=demo&t=$t" >/dev/null 2>&1
}
# Six renders at a time. Wait on their pids only: a bare `wait` would also wait for the server.
PIDS=()
for ((i = 0; i < FRAMES; i++)); do
  render "$i" &
  PIDS+=($!)
  if (( ${#PIDS[@]} == 6 )); then wait "${PIDS[@]}"; PIDS=(); fi
done
if (( ${#PIDS[@]} )); then wait "${PIDS[@]}"; fi

echo "→ Encoding GIF"
ffmpeg -loglevel error -y -framerate $FPS -i "$WORK/frames/%04d.png" \
  -vf "scale=1000:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=128:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  docs/demo.gif
echo "✓ docs/demo.gif ($(du -h docs/demo.gif | cut -f1))"
