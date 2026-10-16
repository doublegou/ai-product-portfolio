#!/usr/bin/env sh
set -eu

SKILL_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VENV_DIR="$SKILL_DIR/.venv"

if ! command -v ffmpeg >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install ffmpeg
  else
    echo 'ffmpeg is required. Install it with your system package manager.' >&2
    exit 1
  fi
fi
if ! command -v deno >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
  brew install deno
fi

python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade pip setuptools wheel
"$VENV_DIR/bin/python" -m pip install --upgrade yt-dlp openai-whisper
"$VENV_DIR/bin/python" -c "from pathlib import Path; import whisper; p=Path('$SKILL_DIR')/'models'; p.mkdir(parents=True, exist_ok=True); whisper.load_model('base', download_root=str(p)); print('Whisper base model ready:', p/'base.pt')"
"$VENV_DIR/bin/python" "$SKILL_DIR/scripts/youtube_transcript.py" --self-check
