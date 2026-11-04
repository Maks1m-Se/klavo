# Piano & Metronome

A small instrument for checking pitches, trying chords and finding the tempo before a song. Built for Android phones, tablets and the browser.

- **Piano** — polyphonic keyboard, octave controls, note names and sustain.
- **Metronome** — tap tempo, subdivisions, adjustable accents and local tempo favorites.
- **Practice** — tempo trainer, silent bars, swing and polyrhythms.

No account or ads. Piano recordings and the click engine are bundled in the app.

## Build

Use Godot 4.6.3 with its export templates and Python 3. On the command line, run `bash scripts/build-web.sh` to produce the web app in `dist/`. Serve that directory on localhost or over HTTPS so the AudioWorklet can start. Run `npm test` to check metronome timing.

Piano recordings by Alexander Holm are licensed under CC BY 3.0. See [recording credits](assets/piano/ATTRIBUTION.md).
