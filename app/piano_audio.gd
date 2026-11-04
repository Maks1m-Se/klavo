extends Node
class_name PianoAudio

var sustain := false
var volume := 0.8
var sample_map: Array = []
var cache: Dictionary = {}
var voices: Array[Dictionary] = []
var serial := 0

func _ready() -> void:
    sample_map = JSON.parse_string(FileAccess.get_file_as_string("res://assets/piano/note-map.json"))
    # Compressed resources are cached; individual recordings are decoded on demand.
    for i in 32:
        var player := AudioStreamPlayer.new()
        player.bus = "Master"
        add_child(player)
        voices.append({"player": player, "midi": -1, "held": false, "serial": 0, "tween": null})

func set_volume(value: float) -> void:
    volume = clampf(value, 0.0, 1.0)
    for voice in voices:
        if voice.midi >= 0:
            voice.player.volume_db = linear_to_db(maxf(0.00001, volume * 0.6))

func nearest_sample(midi: int) -> Dictionary:
    var best: Dictionary = sample_map[0]
    for candidate in sample_map:
        if abs(int(candidate.midi) - midi) < abs(int(best.midi) - midi): best = candidate
    return best

func note_on(midi: int) -> void:
    var sample := nearest_sample(midi)
    var path: String = "res://assets/piano/" + sample.file
    if not cache.has(path): cache[path] = load(path)
    var selected: Dictionary = voices[0]
    for voice in voices:
        if not voice.player.playing:
            selected = voice
            break
        if voice.serial < selected.serial: selected = voice
    if selected.tween != null and is_instance_valid(selected.tween): selected.tween.kill()
    selected.player.stop()
    selected.player.stream = cache[path]
    selected.player.pitch_scale = pow(2.0, float(midi - int(sample.midi)) / 12.0)
    selected.player.volume_db = linear_to_db(maxf(0.00001, volume * 0.6))
    selected.midi = midi
    selected.held = true
    serial += 1
    selected.serial = serial
    selected.player.play()

func release_voice(voice: Dictionary) -> void:
    if voice.midi < 0 or not voice.player.playing: return
    var player: AudioStreamPlayer = voice.player
    var start_db := player.volume_db
    # The damper takes most of the energy quickly, then the string and body
    # ring out quietly. Lower notes keep a slightly longer tail.
    var pitch := clampf((float(voice.midi) - 21.0) / 87.0, 0.0, 1.0)
    var tail_seconds := lerpf(0.33, 0.17, pitch)
    var tween := create_tween()
    tween.tween_property(player, "volume_db", start_db - 14.0, 0.035).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    tween.tween_property(player, "volume_db", start_db - 58.0, tail_seconds)
    tween.tween_callback(player.stop)
    voice.tween = tween
    voice.held = false
    voice.midi = -1

func note_off(midi: int) -> void:
    for voice in voices:
        if voice.midi == midi and voice.held:
            voice.held = false
            if not sustain: release_voice(voice)

func set_sustain(value: bool) -> void:
    sustain = value
    if not value:
        for voice in voices:
            if not voice.held and voice.player.playing: release_voice(voice)

func stop_all() -> void:
    for voice in voices:
        if voice.tween != null and is_instance_valid(voice.tween): voice.tween.kill()
        voice.player.stop()
        voice.midi = -1
        voice.held = false

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT: stop_all()
