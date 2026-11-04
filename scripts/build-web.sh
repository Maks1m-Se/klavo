#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
engine=${GODOT:-godot}
python3 scripts/fetch-piano.py
mkdir -p dist
"$engine" --headless --editor --import --quit
"$engine" --headless --export-release Web dist/index.html
cp web/*.js dist/
python3 - <<'PY'
from pathlib import Path
worker = Path("dist/index.service.worker.js")
marker = 'const CACHED_FILES = ['
text = worker.read_text()
assert marker in text
worker.write_text(text.replace(marker, marker + '"audio-bridge.js","rhythm-core.js","rhythm-worklet.js",', 1))
PY
touch dist/.nojekyll
