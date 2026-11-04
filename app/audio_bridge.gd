extends Node
class_name MetronomeAudio

signal failed(message: String)
var running := false
var config: Dictionary = {}
var native_plugin: Object
var desktop_player: AudioStreamPlayer
var began_usec := 0
var cached_status: Dictionary = {}
var poll_elapsed := 0.0

func _ready() -> void:
    if Engine.has_singleton("PulseAudio"):
        native_plugin = Engine.get_singleton("PulseAudio")
    desktop_player = AudioStreamPlayer.new()
    add_child(desktop_player)

func start(settings: Dictionary) -> void:
    config = settings.duplicate(true)
    running = true
    began_usec = Time.get_ticks_usec()
    if OS.has_feature("web"):
        JavaScriptBridge.eval("window.PulseAudio.start(" + JSON.stringify(config) + ");")
    elif native_plugin != null:
        native_plugin.start(JSON.stringify(config))
    elif OS.has_feature("android"):
        running = false
        failed.emit("The Android audio module is unavailable in this build.")
    else:
        desktop_player.stream = make_desktop_loop(config)
        desktop_player.volume_db = linear_to_db(maxf(0.00001, float(config.volume)))
        desktop_player.play()

func stop() -> void:
    running = false
    if OS.has_feature("web"): JavaScriptBridge.eval("window.PulseAudio.stop();")
    elif native_plugin != null: native_plugin.stop()
    desktop_player.stop()

func set_volume(value: float) -> void:
    config.volume = value
    if OS.has_feature("web"): JavaScriptBridge.eval("window.PulseAudio.volume(" + str(value) + ");")
    elif native_plugin != null: native_plugin.volume(value)
    desktop_player.volume_db = linear_to_db(maxf(0.00001, value))

func status() -> Dictionary:
    if OS.has_feature("web") or native_plugin != null:
        return cached_status
    var elapsed := float(Time.get_ticks_usec() - began_usec) / 1000000.0
    return {"running": running, "seconds": elapsed, "bpm": config.get("bpm", 96), "bar": int(elapsed * float(config.get("bpm", 96)) / 60.0 / int(config.get("beats", 4)))}

func _process(delta: float) -> void:
    if not running: return
    poll_elapsed += delta
    if poll_elapsed < 0.05: return
    poll_elapsed = 0
    var raw: Variant
    if OS.has_feature("web"):
        raw = JavaScriptBridge.eval("window.PulseAudio ? window.PulseAudio.status() : '{}'", true)
    elif native_plugin != null:
        raw = native_plugin.status()
    else: return
    if raw is String:
        var decoded: Variant = JSON.parse_string(raw)
        if decoded is Dictionary:
            cached_status = decoded
            if not str(decoded.get("error", "")).is_empty():
                running = false
                failed.emit(str(decoded.error))
            elif not bool(decoded.get("running", true)) and Time.get_ticks_usec() - began_usec > 1000000:
                running = false

func make_desktop_loop(c: Dictionary) -> AudioStreamWAV:
    # Editor/desktop preview only. Android uses its foreground audio service;
    # the browser uses an AudioWorklet with the same timing parameters.
    var rate := 24000
    var beat_frames := rate * 60.0 / float(c.bpm)
    var beats: int = c.beats
    var bars: int = int(c.get("audibleBars", 1)) + int(c.get("silentBars", 0)) if int(c.get("silentBars", 0)) > 0 else 1
    var frames := int(round(beat_frames * beats * bars))
    var pcm := PackedFloat32Array()
    pcm.resize(frames)
    for bar in bars:
        if int(c.get("silentBars", 0)) > 0 and bar >= int(c.get("audibleBars", 1)): continue
        for beat in beats:
            var strength: int = c.accents[beat % c.accents.size()]
            if strength == 0: continue
            for sub in int(c.subdivision):
                var offset := float(sub) / int(c.subdivision)
                if int(c.subdivision) == 2 and sub == 1: offset = float(c.get("swing", 0.5))
                var start_frame := int(round((bar * beats + beat + offset) * beat_frames))
                add_click(pcm, start_frame, rate, 1560.0 if strength == 2 and sub == 0 else 1200.0, 0.4 if strength == 2 and sub == 0 else 0.13 if sub > 0 else 0.29)
        var poly: int = c.get("poly", 0)
        for pulse in poly:
            add_click(pcm, int(round((bar * beats + float(pulse) * beats / poly) * beat_frames)), rate, 720.0, 0.24)
    var bytes := PackedByteArray()
    bytes.resize(frames * 2)
    for i in frames: bytes.encode_s16(i * 2, int(clampf(pcm[i], -1, 1) * 32767))
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = rate
    stream.data = bytes
    stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    stream.loop_begin = 0
    stream.loop_end = frames
    return stream

func add_click(pcm: PackedFloat32Array, start_frame: int, rate: int, frequency: float, gain: float) -> void:
    for i in int(rate * 0.045):
        var index := start_frame + i
        if index >= pcm.size(): break
        var t := float(i) / rate
        var envelope := minf(1, t / 0.0012) * minf(1, (0.045 - t) / 0.006) * exp(-t / 0.009)
        pcm[index] += (0.78 * sin(TAU * frequency * t) + 0.22 * sin(TAU * frequency * 1.63 * t)) * envelope * gain
