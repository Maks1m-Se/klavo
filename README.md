# Klavo · Piano & Metronome

A small instrument for checking pitches, trying chords and finding the tempo before a song. Built for Android phones, tablets and the browser.

- **Piano** — polyphonic keyboard, octave controls, note names and sustain.
- **Metronome** — tap tempo, subdivisions, adjustable accents and local tempo favorites.
- **Practice** — tempo trainer, silent bars, swing and polyrhythms.

[Open the web app](https://maks1m-se.github.io/klavo/) · [Download Android APK](https://github.com/Maks1m-Se/klavo/releases/latest/download/Klavo.apk)

The web app requires WebGL 2. The Android download is a debug-signed test APK for ARM64 phones and tablets running Android 8 or later.

No account or ads. Piano recordings and the click engine are bundled in the app.

| Piano | Metronome |
| :---: | :---: |
| <img src="https://maks1m-se.github.io/klavo/screenshots/piano.png" width="290" alt="Klavo piano keyboard in portrait orientation"> | <img src="https://maks1m-se.github.io/klavo/screenshots/metronome.png" width="290" alt="Klavo metronome with tempo, accents, and favorites"> |

## Build

Use Godot 4.6.3 with its export templates and Python 3. On the command line, run `bash scripts/build-web.sh` to produce the web app in `dist/`. Serve that directory on localhost or over HTTPS so the AudioWorklet can start. Run `npm test` to check metronome timing.

For Android, install JDK 17, SDK platform 36, Build Tools 36.1.0, platform-tools and the Godot Android export templates. Set `JAVA_HOME` and `ANDROID_HOME`, then run `bash scripts/build-android.sh`. The APK is written to `build/Klavo.apk`.

Piano recordings by Alexander Holm are licensed under CC BY 3.0. See [recording credits](assets/piano/ATTRIBUTION.md).
