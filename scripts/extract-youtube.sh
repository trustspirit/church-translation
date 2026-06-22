#!/usr/bin/env bash
#
# extract-youtube.sh <YouTube-URL>
#
# Extract video metadata + an English transcript for translation.
# Strategy: official (manual) English subs > auto-generated subs > Whisper STT.
# Writes .cache/<video-id>/{meta.json,transcript.txt} and prints that dir path.
#
set -euo pipefail

WHISPER_MODEL="${WHISPER_MODEL:-medium}"

SCRIPT_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_SELF_DIR/.." && pwd)"
CACHE_ROOT="$PROJECT_ROOT/.cache"
CLEANER="$SCRIPT_SELF_DIR/clean_vtt.py"

URL="${1:-}"
if [[ -z "$URL" ]]; then
  echo "Usage: extract-youtube.sh <YouTube-URL>" >&2
  exit 1
fi

# --- dependency check (always required) ---
require() {
  local tool="$1" hint="$2"
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: required tool '$tool' not found." >&2
    echo "  Install: $hint" >&2
    exit 1
  fi
}
require yt-dlp "brew install yt-dlp"
require python3 "comes with your Python install"

# --- video id + work dir ---
VIDEO_ID="$(yt-dlp --no-warnings --get-id "$URL")" \
  || { echo "Error: could not read video id from URL" >&2; exit 1; }
WORK="$CACHE_ROOT/$VIDEO_ID"
mkdir -p "$WORK"

# --- cache hit ---
if [[ -s "$WORK/transcript.txt" && -s "$WORK/meta.json" ]]; then
  echo "$WORK"
  exit 0
fi

# --- metadata (filter to needed fields with python, no jq dependency) ---
yt-dlp --no-warnings --dump-single-json "$URL" | python3 -c '
import json, sys
d = json.load(sys.stdin)
keys = ["title", "uploader", "upload_date", "description", "webpage_url"]
json.dump({k: d.get(k) for k in keys},
          open(sys.argv[1], "w", encoding="utf-8"),
          ensure_ascii=False, indent=2)
' "$WORK/meta.json"

# --- helper: turn any downloaded .vtt into transcript.txt ---
write_transcript_from_vtt() {
  local vtt
  vtt="$(ls -1 "$WORK"/*.vtt 2>/dev/null | head -n1 || true)"
  [[ -n "$vtt" ]] || return 1
  python3 "$CLEANER" "$vtt" > "$WORK/transcript.txt"
  [[ -s "$WORK/transcript.txt" ]]
}

# 1) official (manual) English subtitles
rm -f "$WORK"/*.vtt
yt-dlp --no-warnings --skip-download --write-subs --sub-langs en \
  --sub-format vtt -o "$WORK/%(id)s.%(ext)s" "$URL" || true
if write_transcript_from_vtt; then
  echo "$WORK"; exit 0
fi

# 2) auto-generated English subtitles
rm -f "$WORK"/*.vtt
yt-dlp --no-warnings --skip-download --write-auto-subs --sub-langs en \
  --sub-format vtt -o "$WORK/%(id)s.%(ext)s" "$URL" || true
if write_transcript_from_vtt; then
  echo "$WORK"; exit 0
fi

# 3) Whisper STT fallback (needs whisper + ffmpeg)
require whisper "pip install -U openai-whisper"
require ffmpeg "brew install ffmpeg"
yt-dlp --no-warnings -f bestaudio -x --audio-format m4a \
  -o "$WORK/audio.%(ext)s" "$URL" \
  || { echo "Error: no subtitles found and audio download failed" >&2; exit 1; }
whisper "$WORK/audio.m4a" --language English --model "$WHISPER_MODEL" \
  --output_format txt --output_dir "$WORK" >&2
if [[ -s "$WORK/audio.txt" ]]; then
  python3 -c '
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
print(re.sub(r"\s+", " ", text).strip())
' "$WORK/audio.txt" > "$WORK/transcript.txt"
  echo "$WORK"; exit 0
fi

echo "Error: failed to produce a transcript" >&2
exit 1
