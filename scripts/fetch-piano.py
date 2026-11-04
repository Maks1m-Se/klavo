"""Fetch and verify the freely licensed piano recordings used by the app."""
import hashlib
import json
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

samples = Path(__file__).resolve().parents[1] / "assets" / "piano"

def fetch(entry):
    path = samples / entry["name"]
    if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == entry["sha256"]:
        return
    with urllib.request.urlopen(entry["url"], timeout=60) as response:
        data = response.read()
    if len(data) != entry["bytes"] or hashlib.sha256(data).hexdigest() != entry["sha256"]:
        raise ValueError(f"Unexpected content for {path.name}")
    path.write_bytes(data)

with ThreadPoolExecutor(max_workers=8) as pool:
    list(pool.map(fetch, json.loads((samples / "downloaded-manifest.json").read_text())))
