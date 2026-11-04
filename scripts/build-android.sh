#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
engine=${GODOT:-godot}
jdk="${JAVA_HOME:?Set JAVA_HOME to a JDK 17 installation}"
sdk="${ANDROID_HOME:?Set ANDROID_HOME to the Android SDK}"
template="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/4.6.3.stable/android_source.zip"
python3 scripts/fetch-piano.py
mkdir -p build/plugin/classes addons/pulse_audio/bin
unzip -p "$template" libs/debug/godot-lib.template_debug.aar > build/plugin/godot.aar
unzip -p build/plugin/godot.aar classes.jar > build/plugin/godot.jar
find android-plugin/src/main/java -name '*.java' -print > build/plugin/sources
"$jdk/bin/javac" --release 17 -classpath "$sdk/platforms/android-36/android.jar:build/plugin/godot.jar" -d build/plugin/classes @build/plugin/sources
"$jdk/bin/jar" cf build/plugin/classes.jar -C build/plugin/classes .
python3 - <<'PY'
import zipfile
with zipfile.ZipFile("addons/pulse_audio/bin/pulse-audio.aar", "w", zipfile.ZIP_DEFLATED) as archive:
    archive.write("android-plugin/src/main/AndroidManifest.xml", "AndroidManifest.xml")
    archive.write("build/plugin/classes.jar", "classes.jar")
    archive.writestr("R.txt", "")
PY
config="${XDG_CONFIG_HOME:-$HOME/.config}/godot"
mkdir -p "$config"
settings="$config/editor_settings-4.6.tres"
if [[ ! -f "$settings" ]]; then
  printf '[gd_resource type="EditorSettings" format=3]\n\n[resource]\nexport/android/java_sdk_path = "%s"\nexport/android/android_sdk_path = "%s"\n' "$jdk" "$sdk" > "$settings"
fi
"$engine" --headless --editor --import --quit
"$engine" --headless --install-android-build-template --export-debug Android build/Piano-Metronome.apk
