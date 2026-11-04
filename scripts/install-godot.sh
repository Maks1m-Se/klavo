#!/usr/bin/env bash
set -euo pipefail
version=4.6.3
release="https://github.com/godotengine/godot/releases/download/${version}-stable"
engine="Godot_v${version}-stable_linux.x86_64"
tools_dir="${RUNNER_TEMP:-/tmp}/piano-godot"
templates="$HOME/.local/share/godot/export_templates/${version}.stable"
mkdir -p "$tools_dir" "$templates"
curl -fsSL --retry 3 "$release/$engine.zip" -o "$tools_dir/editor.zip"
unzip -oq "$tools_dir/editor.zip" -d "$tools_dir"
ln -sf "$tools_dir/$engine" "$tools_dir/godot"
printf '%s\n' "$tools_dir" >> "$GITHUB_PATH"
curl -fsSL --retry 3 "$release/Godot_v${version}-stable_export_templates.tpz" -o "$tools_dir/templates.tpz"
case "${1:?Choose web or android}" in
  web) unzip -ojq "$tools_dir/templates.tpz" templates/version.txt templates/web_nothreads_release.zip -d "$templates" ;;
  android) unzip -ojq "$tools_dir/templates.tpz" templates/version.txt templates/android_debug.apk templates/android_source.zip -d "$templates" ;;
esac
