$ErrorActionPreference = 'Stop'
$SkillDir = Split-Path -Parent $PSScriptRoot
$VenvDir = Join-Path $SkillDir '.venv'

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    winget install --id yt-dlp.FFmpeg --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
}
if (-not (Get-Command deno -ErrorAction SilentlyContinue)) {
    winget install --id DenoLand.Deno --exact --silent --accept-package-agreements --accept-source-agreements --disable-interactivity
}

$Python = Get-Command python -ErrorAction SilentlyContinue
if (-not $Python) { $Python = Get-Command py -ErrorAction SilentlyContinue }
$PythonPath = if ($Python) { $Python.Source } else { $null }
if (-not $PythonPath) {
    $BundledPython = Get-ChildItem -Path "$env:USERPROFILE\.cache\codex-runtimes\*\dependencies\python\python.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($BundledPython) { $PythonPath = $BundledPython.FullName }
}
if (-not $PythonPath) { throw 'Python 3.10+ is required.' }

if (-not (Test-Path -LiteralPath $VenvDir)) {
    & $PythonPath -m venv $VenvDir
}
$VenvPython = Join-Path $VenvDir 'Scripts\python.exe'
& $VenvPython -m pip install --upgrade pip setuptools wheel
& $VenvPython -m pip install --upgrade torch --index-url https://download.pytorch.org/whl/cpu
& $VenvPython -m pip install --upgrade yt-dlp openai-whisper
& $VenvPython -c "from pathlib import Path; import whisper; p=Path(r'$SkillDir')/'models'; p.mkdir(parents=True, exist_ok=True); whisper.load_model('base', device='cpu', download_root=str(p)); print('Whisper base model ready:', p/'base.pt')"
& $VenvPython (Join-Path $PSScriptRoot 'youtube_transcript.py') --self-check
