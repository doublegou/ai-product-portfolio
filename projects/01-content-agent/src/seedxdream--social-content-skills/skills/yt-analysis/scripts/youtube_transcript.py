#!/usr/bin/env python3
"""Fetch a YouTube transcript, preferring captions with a Whisper fallback."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import html
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any


SKILL_DIR = Path(__file__).resolve().parent.parent
VENV_BIN = SKILL_DIR / ".venv" / ("Scripts" if os.name == "nt" else "bin")
MODELS_DIR = SKILL_DIR / "models"


def configure_console() -> None:
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8", errors="replace")


def find_tool(name: str) -> Path:
    suffix = ".exe" if os.name == "nt" else ""
    local = VENV_BIN / f"{name}{suffix}"
    if local.is_file():
        return local
    found = shutil.which(name)
    if found:
        return Path(found)
    if os.name == "nt":
        local_app_data = Path(os.environ.get("LOCALAPPDATA", ""))
        packages = local_app_data / "Microsoft" / "WinGet" / "Packages"
        patterns = {
            "yt-dlp": "yt-dlp.yt-dlp_*/*yt-dlp.exe",
            "ffmpeg": "yt-dlp.FFmpeg_*/**/bin/ffmpeg.exe",
            "ffprobe": "yt-dlp.FFmpeg_*/**/bin/ffprobe.exe",
            "deno": "DenoLand.Deno_*/deno.exe",
        }
        link = local_app_data / "Microsoft" / "WinGet" / "Links" / f"{name}.exe"
        candidates = [link] if link.is_file() else []
        if name in patterns and packages.is_dir():
            candidates.extend(packages.glob(patterns[name]))
        for candidate in candidates:
            if candidate.is_file():
                return candidate
    raise FileNotFoundError(f"Required tool not found: {name}")


def tool_env(ffmpeg: Path, deno: Path | None = None) -> dict[str, str]:
    env = os.environ.copy()
    tool_dirs = [str(ffmpeg.parent)]
    if deno:
        tool_dirs.append(str(deno.parent))
    env["PATH"] = os.pathsep.join(tool_dirs) + os.pathsep + env.get("PATH", "")
    env["PYTHONUTF8"] = "1"
    env["PYTHONIOENCODING"] = "utf-8"
    return env


def run(command: list[str], env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(
            command,
            check=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            capture_output=True,
            env=env,
        )
    except subprocess.CalledProcessError as exc:
        details = (exc.stderr or exc.stdout or str(exc)).strip()
        raise RuntimeError(details) from exc


def safe_name(value: str, video_id: str) -> str:
    value = re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", value).strip(" .")
    value = re.sub(r"\s+", " ", value)[:120].rstrip(" ._") or "youtube-video"
    return f"{value} [{video_id}]"


def match_language(tracks: dict[str, Any], requested: str) -> str | None:
    if requested in tracks:
        return requested
    requested = requested.lower()
    for key in tracks:
        if key.lower() == requested:
            return key
    for key in tracks:
        if key.lower().startswith(requested + "-"):
            return key
    return None


def select_track(info: dict[str, Any], requested: str | None) -> tuple[str, str] | None:
    manual = info.get("subtitles") or {}
    automatic = info.get("automatic_captions") or {}
    if requested:
        for source, tracks in (("manual", manual), ("automatic", automatic)):
            match = match_language(tracks, requested)
            if match:
                return source, match
        available = sorted(set(manual) | set(automatic))
        raise RuntimeError(
            f"Requested subtitle language '{requested}' is unavailable. "
            f"Available: {', '.join(available)}"
        )

    source_language = info.get("language")
    if source_language:
        for source, tracks in (("manual", manual), ("automatic", automatic)):
            match = match_language(tracks, source_language)
            if match:
                return source, match
    for preference in ("en", "en-orig", "zh-Hans", "zh-Hant", "zh"):
        for source, tracks in (("manual", manual), ("automatic", automatic)):
            match = match_language(tracks, preference)
            if match:
                return source, match
    if manual:
        return "manual", next(iter(manual))
    if automatic:
        return "automatic", next(iter(automatic))
    return None


def merge_progressive(chunks: list[str]) -> list[str]:
    merged: list[str] = []
    for chunk in chunks:
        chunk = re.sub(r"\s+", " ", chunk).strip()
        if not chunk:
            continue
        if not merged:
            merged.append(chunk)
            continue
        previous = merged[-1]
        if chunk == previous or previous.startswith(chunk):
            continue
        if chunk.startswith(previous):
            merged[-1] = chunk
        else:
            merged.append(chunk)
    return merged


def parse_json3(path: Path) -> tuple[str, list[dict[str, Any]]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    chunks: list[str] = []
    segments: list[dict[str, Any]] = []
    for event in data.get("events", []):
        text = "".join(segment.get("utf8", "") for segment in event.get("segs", []))
        text = re.sub(r"\s+", " ", text).strip()
        if not text or (chunks and text == chunks[-1]):
            continue
        chunks.append(text)
        segments.append(
            {
                "start_seconds": round(event.get("tStartMs", 0) / 1000, 3),
                "duration_seconds": round(event.get("dDurationMs", 0) / 1000, 3),
                "text": text,
            }
        )
    return "\n".join(chunks).strip(), segments


def vtt_time_seconds(value: str) -> float:
    parts = value.replace(",", ".").split(":")
    if len(parts) == 3:
        hours, minutes, seconds = parts
    elif len(parts) == 2:
        hours, (minutes, seconds) = "0", parts
    else:
        raise ValueError(f"Invalid VTT timestamp: {value}")
    return int(hours) * 3600 + int(minutes) * 60 + float(seconds)


def parse_vtt(path: Path) -> tuple[str, list[dict[str, Any]]]:
    raw = path.read_text(encoding="utf-8-sig", errors="replace")
    segments: list[dict[str, Any]] = []
    for block in re.split(r"\r?\n\s*\r?\n", raw):
        lines = [line.strip() for line in block.splitlines() if line.strip()]
        timestamp_index = next((index for index, line in enumerate(lines) if "-->" in line), None)
        if timestamp_index is None:
            continue
        timing = lines[timestamp_index].split("-->", 1)
        start = vtt_time_seconds(timing[0].strip())
        end = vtt_time_seconds(timing[1].strip().split()[0])
        text_lines = [
            re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", html.unescape(line))).strip()
            for line in lines[timestamp_index + 1 :]
        ]
        text = " ".join(line for line in text_lines if line).strip()
        if not text:
            continue
        segment = {
            "start_seconds": round(start, 3),
            "duration_seconds": round(max(0.0, end - start), 3),
            "text": text,
        }
        if segments and text == segments[-1]["text"]:
            continue
        if segments and text.startswith(segments[-1]["text"]):
            previous_start = segments[-1]["start_seconds"]
            segment["start_seconds"] = previous_start
            segment["duration_seconds"] = round(max(0.0, end - previous_start), 3)
            segments[-1] = segment
        else:
            segments.append(segment)
    return "\n".join(segment["text"] for segment in segments).strip(), segments


def write_artifacts(
    output_dir: Path,
    info: dict[str, Any],
    source: str,
    language: str,
    text: str,
    segments: list[dict[str, Any]],
) -> tuple[Path, Path]:
    stem = safe_name(info.get("title") or "youtube-video", info.get("id") or "unknown")
    text_path = output_dir / f"{stem}.transcript.txt"
    json_path = output_dir / f"{stem}.transcript.json"
    text_path.write_text(text.rstrip() + "\n", encoding="utf-8")
    payload = {
        "url": info.get("webpage_url") or info.get("original_url"),
        "video_id": info.get("id"),
        "title": info.get("title"),
        "channel": info.get("channel") or info.get("uploader"),
        "duration_seconds": info.get("duration"),
        "language": language,
        "source": source,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "text": text,
        "segments": segments,
    }
    json_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return text_path, json_path


def fetch_info(yt_dlp: Path, url: str, env: dict[str, str]) -> dict[str, Any]:
    result = run([str(yt_dlp), "--dump-single-json", "--skip-download", "--no-warnings", url], env)
    return json.loads(result.stdout)


def estimate_audio_size(yt_dlp: Path, url: str, env: dict[str, str]) -> int | None:
    try:
        result = run(
            [str(yt_dlp), "-f", "bestaudio", "--skip-download", "--print", "%(filesize,filesize_approx)s", url],
            env,
        )
        value = result.stdout.strip().splitlines()[-1]
        return int(value) if value.isdigit() else None
    except (RuntimeError, ValueError, IndexError):
        return None


def download_caption(
    yt_dlp: Path,
    url: str,
    source: str,
    language: str,
    work_dir: Path,
    env: dict[str, str],
) -> Path:
    flag = "--write-subs" if source == "manual" else "--write-auto-subs"
    run(
        [
            str(yt_dlp), flag, "--skip-download", "--sub-langs", language,
            "--sub-format", "json3/vtt/best", "--output", str(work_dir / "%(id)s.%(ext)s"), url,
        ],
        env,
    )
    matches = sorted(work_dir.glob(f"*.{language}.*"))
    if not matches:
        matches = sorted(path for path in work_dir.iterdir() if path.suffix.lower() in {".json3", ".vtt"})
    if not matches:
        raise RuntimeError("yt-dlp reported success but no caption file was created")
    return matches[0]


def whisper_transcript(
    yt_dlp: Path,
    url: str,
    info: dict[str, Any],
    work_dir: Path,
    env: dict[str, str],
    keep_audio: bool,
    output_dir: Path,
) -> tuple[str, list[dict[str, Any]], str]:
    run(
        [str(yt_dlp), "-x", "--audio-format", "mp3", "--output", str(work_dir / "audio_%(id)s.%(ext)s"), url],
        env,
    )
    audio_files = sorted(work_dir.glob("audio_*.mp3"))
    if not audio_files:
        raise RuntimeError("Audio extraction completed but no MP3 file was created")
    audio_path = audio_files[0]
    import whisper

    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    model = whisper.load_model("base", device="cpu", download_root=str(MODELS_DIR))
    result = model.transcribe(str(audio_path), fp16=False)
    segments = [
        {
            "start_seconds": round(segment["start"], 3),
            "duration_seconds": round(segment["end"] - segment["start"], 3),
            "text": segment["text"].strip(),
        }
        for segment in result.get("segments", [])
        if segment.get("text", "").strip()
    ]
    text = result.get("text", "").strip() or "\n".join(segment["text"] for segment in segments)
    if keep_audio:
        shutil.copy2(audio_path, output_dir / audio_path.name)
    return text, segments, result.get("language") or info.get("language") or "unknown"


def self_check() -> int:
    checks: dict[str, Any] = {"skill_dir": str(SKILL_DIR)}
    try:
        yt_dlp = find_tool("yt-dlp")
        ffmpeg = find_tool("ffmpeg")
        ffprobe = find_tool("ffprobe")
        try:
            deno = find_tool("deno")
        except FileNotFoundError:
            deno = None
        env = tool_env(ffmpeg, deno)
        checks.update(
            {
                "yt_dlp": {"path": str(yt_dlp), "version": run([str(yt_dlp), "--version"], env).stdout.strip()},
                "ffmpeg": {"path": str(ffmpeg), "available": True},
                "ffprobe": {"path": str(ffprobe), "available": True},
                "deno": {"path": str(deno) if deno else None, "available": deno is not None},
            }
        )
        import torch
        import whisper

        checks["torch"] = torch.__version__
        checks["whisper"] = str(Path(whisper.__file__).resolve())
        checks["whisper_base_model"] = str(MODELS_DIR / "base.pt")
        checks["whisper_base_model_downloaded"] = (MODELS_DIR / "base.pt").is_file()
        checks["ok"] = True
        print(json.dumps(checks, ensure_ascii=False, indent=2))
        return 0
    except Exception as exc:
        checks["ok"] = False
        checks["error"] = str(exc)
        print(json.dumps(checks, ensure_ascii=False, indent=2))
        return 1


def main() -> int:
    configure_console()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("url", nargs="?", help="YouTube video URL")
    parser.add_argument("--output-dir", type=Path, default=Path("outputs/youtube"))
    parser.add_argument("--lang", help="Preferred subtitle language code")
    parser.add_argument("--allow-whisper", action="store_true", help="Approve audio download and Whisper fallback")
    parser.add_argument("--keep-raw", action="store_true", help="Keep the downloaded raw caption file")
    parser.add_argument("--keep-audio", action="store_true", help="Keep audio downloaded for Whisper")
    parser.add_argument("--self-check", action="store_true")
    args = parser.parse_args()
    if args.self_check:
        return self_check()
    if not args.url:
        parser.error("url is required unless --self-check is used")

    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    yt_dlp = find_tool("yt-dlp")
    ffmpeg = find_tool("ffmpeg")
    try:
        deno = find_tool("deno")
    except FileNotFoundError:
        deno = None
    env = tool_env(ffmpeg, deno)
    info = fetch_info(yt_dlp, args.url, env)
    track = select_track(info, args.lang)

    with tempfile.TemporaryDirectory(prefix="youtube-transcript-", dir=output_dir) as temp_name:
        work_dir = Path(temp_name)
        if track:
            source, language = track
            caption_path = download_caption(yt_dlp, args.url, source, language, work_dir, env)
            if caption_path.suffix.lower() == ".json3":
                text, segments = parse_json3(caption_path)
            else:
                text, segments = parse_vtt(caption_path)
            if args.keep_raw:
                shutil.copy2(caption_path, output_dir / caption_path.name)
        elif not args.allow_whisper:
            response = {
                "status": "whisper_confirmation_required",
                "title": info.get("title"),
                "duration_seconds": info.get("duration"),
                "estimated_audio_bytes": estimate_audio_size(yt_dlp, args.url, env),
                "message": "No captions are available. Ask before downloading audio, then rerun with --allow-whisper.",
            }
            print(json.dumps(response, ensure_ascii=False, indent=2))
            return 3
        else:
            source = "whisper-base"
            text, segments, language = whisper_transcript(
                yt_dlp, args.url, info, work_dir, env, args.keep_audio, output_dir
            )

    text_path, json_path = write_artifacts(output_dir, info, source, language, text, segments)
    print(
        json.dumps(
            {
                "status": "ok",
                "source": source,
                "language": language,
                "title": info.get("title"),
                "text_path": str(text_path),
                "json_path": str(json_path),
                "characters": len(text),
            },
            ensure_ascii=False,
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
