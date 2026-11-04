extends Control

const PianoKeys = preload("res://app/piano_keyboard.gd")
const PianoSound = preload("res://app/piano_audio.gd")
const ClockSound = preload("res://app/audio_bridge.gd")
const Palette = preload("res://app/palette.gd")
const TIMES := ["4/4", "3/4", "2/4", "6/8", "5/4", "7/8"]
const MODES := ["Basic", "Tempo Trainer", "Gap Click", "Swing / Shuffle", "Polyrhythm"]
var settings: Dictionary = {
    "view": "piano", "octave": 3, "labels": true, "sustain": false, "compact": false,
    "bpm": 96, "time": "4/4", "subdivision": 1, "accents": [2, 1, 1, 1],
    "favorites": [], "piano_volume": 0.8, "click_volume": 0.6, "click_sound": 0,
    "appearance": "dark", "keep_awake": true, "mode": "Basic",
    "target_bpm": 120, "ramp_step": 2, "ramp_every": 8,
    "audible_bars": 4, "silent_bars": 2, "swing": 0.667, "poly_a": 3, "poly_b": 2
}
var colors: Dictionary
var piano: PianoAudio
var clock: MetronomeAudio
var ui: MarginContainer
var keyboard: PianoKeyboard
var range_label: Label
var note_label: Label
var status_label: Label
var tempo_input: LineEdit
var bpm_label: Label
var play_buttons: Array[Button] = []
var beat_buttons: Array[Button] = []
var favorites_box: HFlowContainer
var favorites_edit := false
var taps: Array[float] = []
var landscape := false
var resize_queued := false
var last_beat := -1
var current_dialog: AcceptDialog
var toast_label: Label
var toast_until := 0
var startup_usec := 0
var clock_was_running := false

func _ready() -> void:
    startup_usec = Time.get_ticks_usec()
    load_settings()
    piano = PianoSound.new()
    add_child(piano)
    piano.volume = float(settings.piano_volume)
    piano.sustain = bool(settings.sustain)
    clock = ClockSound.new()
    add_child(clock)
    clock.failed.connect(show_message)
    DisplayServer.screen_set_keep_on(bool(settings.keep_awake))
    OS.low_processor_usage_mode = true
    resized.connect(queue_rebuild)
    build_ui()

func load_settings() -> void:
    if not FileAccess.file_exists("user://settings.json"): return
    var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://settings.json"))
    if not data is Dictionary: return
    for key in settings:
        if data.has(key) and typeof(data[key]) == typeof(settings[key]): settings[key] = data[key]
        elif data.has(key) and (settings[key] is int or settings[key] is float) and (data[key] is int or data[key] is float): settings[key] = data[key]
    settings.bpm = clampi(int(settings.bpm), 20, 300)
    settings.octave = clampi(int(settings.octave), 1, 6)
    settings.subdivision = clampi(int(settings.subdivision), 1, 8)
    settings.piano_volume = clampf(float(settings.piano_volume), 0, 1)
    settings.click_volume = clampf(float(settings.click_volume), 0, 1)
    if settings.time not in TIMES: settings.time = "4/4"
    if settings.mode not in MODES: settings.mode = "Basic"
    if settings.view not in ["piano", "metronome"]: settings.view = "piano"
    settings.favorites = settings.favorites.filter(func(v): return (v is int or v is float) and v >= 20 and v <= 300).slice(0, 8)
    reset_accents_if_needed()

func save_settings() -> void:
    var file := FileAccess.open("user://settings.json.tmp", FileAccess.WRITE)
    if file == null: return
    file.store_string(JSON.stringify(settings, "  "))
    file.close()
    DirAccess.rename_absolute("user://settings.json.tmp", "user://settings.json")

func box(fill: Color, border: Color, width: int = 1, radius: int = 12) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = fill
    style.border_color = border
    style.set_border_width_all(width)
    style.set_corner_radius_all(radius)
    style.content_margin_left = 13
    style.content_margin_right = 13
    style.content_margin_top = 8
    style.content_margin_bottom = 8
    return style

func make_theme() -> Theme:
    var result := Theme.new()
    result.default_font_size = 15
    for type in ["Label", "Button", "OptionButton", "CheckButton", "CheckBox", "LineEdit", "SpinBox"]:
        result.set_color("font_color", type, colors.text)
        result.set_color("font_hover_color", type, colors.text)
        result.set_color("font_pressed_color", type, colors.text)
        result.set_color("font_focus_color", type, colors.text)
    for type in ["Button", "OptionButton"]:
        result.set_stylebox("normal", type, box(colors.surface, colors.line))
        result.set_stylebox("hover", type, box(colors.soft, colors.muted))
        result.set_stylebox("pressed", type, box(colors.soft, colors.accent))
        result.set_stylebox("focus", type, box(Color.TRANSPARENT, colors.accent, 2))
        result.set_stylebox("disabled", type, box(colors.background, colors.line))
    result.set_stylebox("normal", "LineEdit", box(colors.surface, colors.line))
    result.set_stylebox("focus", "LineEdit", box(colors.surface, colors.accent, 2))
    result.set_color("caret_color", "LineEdit", colors.accent)
    result.set_stylebox("panel", "PopupMenu", box(colors.surface, colors.line))
    result.set_stylebox("panel", "AcceptDialog", box(colors.background, colors.line, 1, 18))
    result.set_color("font_color", "PopupMenu", colors.text)
    result.set_color("font_hover_color", "PopupMenu", colors.on_accent)
    result.set_stylebox("hover", "PopupMenu", box(colors.accent, colors.accent))
    result.set_constant("separation", "VBoxContainer", 12)
    result.set_constant("separation", "HBoxContainer", 10)
    return result

func label(text: String, font_size: int = 15, muted: bool = false) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", font_size)
    l.add_theme_color_override("font_color", colors.muted if muted else colors.text)
    return l

func button(text: String, callback: Callable, primary: bool = false, minimum_width: float = 0) -> Button:
    var b := Button.new()
    b.text = text
    b.custom_minimum_size = Vector2(minimum_width, 38 if landscape else 45)
    b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    if callback.is_valid(): b.pressed.connect(callback)
    if primary: style_selected(b, true)
    return b

func style_selected(b: Button, selected: bool) -> void:
    if selected:
        b.add_theme_stylebox_override("normal", box(colors.accent, colors.accent))
        b.add_theme_stylebox_override("hover", box(colors.accent.lightened(0.06), colors.accent))
        b.add_theme_color_override("font_color", colors.on_accent)
        b.add_theme_color_override("font_hover_color", colors.on_accent)
        b.add_theme_color_override("font_pressed_color", colors.on_accent)
    else:
        for key in ["normal", "hover"]: b.remove_theme_stylebox_override(key)
        for key in ["font_color", "font_hover_color", "font_pressed_color"]: b.remove_theme_color_override(key)

func spacer(vertical: bool = false) -> Control:
    var control := Control.new()
    if vertical: control.size_flags_vertical = Control.SIZE_EXPAND_FILL
    else: control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return control

func queue_rebuild() -> void:
    if resize_queued: return
    resize_queued = true
    build_ui.call_deferred()

func build_ui() -> void:
    resize_queued = false
    if piano == null: return
    if is_instance_valid(keyboard): keyboard.release_all()
    if is_instance_valid(current_dialog): current_dialog.queue_free()
    if is_instance_valid(ui):
        remove_child(ui)
        ui.queue_free()
    colors = Palette.colors(settings.appearance == "light")
    RenderingServer.set_default_clear_color(colors.background)
    theme = make_theme()
    landscape = size.x > size.y * 1.2
    keyboard = null
    tempo_input = null
    bpm_label = null
    beat_buttons.clear()
    play_buttons.clear()
    ui = MarginContainer.new()
    ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    var side_margin := maxi(16, int((size.x - 1100) / 2))
    for edge in ["left", "right"]: ui.add_theme_constant_override("margin_" + edge, side_margin)
    ui.add_theme_constant_override("margin_top", 12 if landscape else 24)
    ui.add_theme_constant_override("margin_bottom", 12 if landscape else 20)
    add_child(ui)
    var layout := VBoxContainer.new()
    layout.add_theme_constant_override("separation", 12 if landscape else 18)
    ui.add_child(layout)
    var header := HBoxContainer.new()
    layout.add_child(header)
    var titlebox := VBoxContainer.new()
    titlebox.add_theme_constant_override("separation", 2)
    titlebox.add_child(label("Piano" if settings.view == "piano" else "Metronome", 21 if landscape else 25))
    status_label = label("Grand piano" if settings.view == "piano" else mode_status(), 12, true)
    if not landscape: titlebox.add_child(status_label)
    else: status_label.hide()
    header.add_child(titlebox)
    header.add_child(spacer())
    if landscape: header.add_child(make_nav())
    var settings_button := button("Settings", open_settings)
    settings_button.add_theme_font_size_override("font_size", 12)
    header.add_child(settings_button)
    var content := VBoxContainer.new()
    content.size_flags_vertical = Control.SIZE_EXPAND_FILL
    layout.add_child(content)
    if settings.view == "piano": build_piano(content)
    else: build_metronome(content)
    toast_label = label("", 12, true)
    toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    toast_label.hide()
    layout.add_child(toast_label)
    if not landscape: layout.add_child(make_nav())
    sync_transport()

func make_nav() -> HBoxContainer:
    var nav := HBoxContainer.new()
    for name in ["piano", "metronome"]:
        var b := button(name.capitalize(), change_view.bind(name))
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        if landscape: b.custom_minimum_size.x = 112
        if settings.view == name:
            b.add_theme_stylebox_override("normal", box(colors.soft, colors.soft, 0))
            b.add_theme_color_override("font_color", colors.accent)
        nav.add_child(b)
    return nav

func change_view(view: String) -> void:
    piano.stop_all()
    settings.view = view
    save_settings()
    build_ui()

func build_piano(parent: VBoxContainer) -> void:
    var controls := HBoxContainer.new()
    parent.add_child(controls)
    var lower := button("−", change_octave.bind(-1), false, 36)
    lower.disabled = int(settings.octave) <= 1
    controls.add_child(lower)
    controls.add_child(label("Octave " + str(int(settings.octave)), 13))
    var higher := button("+", change_octave.bind(1), false, 36)
    higher.disabled = int(settings.octave) >= 6
    controls.add_child(higher)
    controls.add_child(spacer())
    var sustain_button := button("Sustain", toggle_sustain)
    sustain_button.add_theme_font_size_override("font_size", 12)
    style_selected(sustain_button, bool(settings.sustain))
    controls.add_child(sustain_button)
    var notes_button := button("Notes", toggle_labels)
    notes_button.add_theme_font_size_override("font_size", 12)
    controls.add_child(notes_button)
    style_selected(notes_button, bool(settings.labels))
    var captions := HBoxContainer.new()
    captions.add_theme_constant_override("separation", 8)
    range_label = label("", 12, true)
    note_label = label("Ready", 12, true)
    captions.add_child(range_label)
    captions.add_child(spacer())
    captions.add_child(note_label)
    parent.add_child(captions)
    keyboard = PianoKeys.new()
    keyboard.octave = int(settings.octave)
    keyboard.show_labels = bool(settings.labels)
    keyboard.compact = bool(settings.compact)
    keyboard.accent = colors.accent
    keyboard.custom_minimum_size = Vector2(0, 130 if landscape else 220)
    keyboard.size_flags_vertical = Control.SIZE_EXPAND_FILL
    keyboard.range_changed.connect(func(first, last): range_label.text = first + " — " + last)
    keyboard.note_pressed.connect(on_note_on)
    keyboard.note_released.connect(piano.note_off)
    parent.add_child(keyboard)
    if not landscape:
        var footer := HBoxContainer.new()
        footer.add_child(label("A4 = 440 Hz", 11, true))
        footer.add_child(spacer())
        var key_size := button("Key size · " + ("compact" if settings.compact else "comfortable"), toggle_key_width)
        key_size.add_theme_font_size_override("font_size", 11)
        footer.add_child(key_size)
        parent.add_child(footer)
    var mini := HBoxContainer.new()
    bpm_label = label(str(int(settings.bpm)) + " BPM", 16)
    mini.add_child(bpm_label)
    var time_button := button(str(settings.time) + " · Metronome", change_view.bind("metronome"))
    time_button.add_theme_font_size_override("font_size", 12)
    mini.add_child(time_button)
    mini.add_child(spacer())
    var play := button("Start", toggle_clock)
    mini.add_child(play)
    play_buttons.append(play)
    parent.add_child(mini)

func on_note_on(midi: int) -> void:
    piano.note_on(midi)
    if is_instance_valid(note_label): note_label.text = PianoKeys.note_name(midi)

func change_octave(direction: int) -> void:
    settings.octave = clampi(int(settings.octave) + direction, 1, 6)
    piano.stop_all()
    save_settings()
    build_ui()

func toggle_sustain() -> void:
    settings.sustain = not settings.sustain
    piano.set_sustain(settings.sustain)
    save_settings()
    build_ui()

func toggle_labels() -> void:
    settings.labels = not settings.labels
    save_settings()
    build_ui()

func toggle_key_width() -> void:
    settings.compact = not settings.compact
    save_settings()
    build_ui()

func build_metronome(parent: VBoxContainer) -> void:
    var columns: Container = HBoxContainer.new() if landscape else VBoxContainer.new()
    columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
    if landscape: columns.add_theme_constant_override("separation", 30)
    parent.add_child(columns)
    var left := VBoxContainer.new()
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left.size_flags_vertical = Control.SIZE_EXPAND_FILL
    columns.add_child(left)
    left.add_child(spacer(true))
    var tempo := HBoxContainer.new()
    tempo.alignment = BoxContainer.ALIGNMENT_CENTER
    tempo.add_child(button("−", set_bpm.bind(int(settings.bpm) - 1), false, 48))
    tempo_input = LineEdit.new()
    tempo_input.text = str(int(settings.bpm))
    tempo_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
    tempo_input.custom_minimum_size = Vector2(174, 100)
    tempo_input.expand_to_text_length = false
    tempo_input.max_length = 3
    tempo_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
    tempo_input.add_theme_font_size_override("font_size", 82)
    tempo_input.add_theme_stylebox_override("normal", box(colors.background, colors.background, 0, 0))
    tempo_input.add_theme_stylebox_override("focus", box(colors.background, colors.accent, 1, 8))
    tempo_input.text_submitted.connect(commit_tempo_text)
    tempo_input.focus_exited.connect(func():
        if is_instance_valid(tempo_input): commit_tempo_text(tempo_input.text))
    tempo.add_child(tempo_input)
    tempo.add_child(button("+", set_bpm.bind(int(settings.bpm) + 1), false, 48))
    left.add_child(tempo)
    var unit := label("BPM · " + beat_unit().to_upper(), 11, true)
    unit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    left.add_child(unit)
    left.add_child(spacer(true))
    var beats := HFlowContainer.new()
    beats.alignment = FlowContainer.ALIGNMENT_CENTER
    beats.add_theme_constant_override("h_separation", 10)
    for i in beat_count():
        var b := button(str(i + 1), cycle_accent.bind(i), false, 42)
        b.custom_minimum_size.y = 42
        beats.add_child(b)
        beat_buttons.append(b)
    left.add_child(beats)
    left.add_child(spacer(true))
    var right := VBoxContainer.new()
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    if landscape: right.size_flags_vertical = Control.SIZE_EXPAND_FILL
    columns.add_child(right)
    var pattern := HBoxContainer.new()
    pattern.add_child(select_field("Time signature", TIMES, TIMES.find(settings.time), on_time_changed))
    pattern.add_child(select_field("Subdivision", ["Beat", "2 per beat", "3 per beat", "4 per beat"], mini(int(settings.subdivision) - 1, 3), on_subdivision_changed))
    right.add_child(pattern)
    var favorite_title := HBoxContainer.new()
    favorite_title.add_child(label("Favorites", 12, true))
    favorite_title.add_child(spacer())
    var edit := button("Done" if favorites_edit else "Edit", toggle_favorites_edit)
    edit.add_theme_font_size_override("font_size", 12)
    favorite_title.add_child(edit)
    right.add_child(favorite_title)
    favorites_box = HFlowContainer.new()
    favorites_box.add_theme_constant_override("h_separation", 8)
    right.add_child(favorites_box)
    draw_favorites()
    if not landscape: right.add_child(spacer(true))
    var transport := HBoxContainer.new()
    var play := button("Start", toggle_clock, true)
    play.custom_minimum_size.y = 54
    play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    transport.add_child(play)
    play_buttons.append(play)
    var tap := button("Tap Tempo", tap_tempo)
    tap.custom_minimum_size.y = 54
    tap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    transport.add_child(tap)
    right.add_child(transport)
    var advanced := button("Advanced" if settings.mode == "Basic" else "Advanced · " + str(settings.mode), open_advanced)
    advanced.add_theme_font_size_override("font_size", 12)
    right.add_child(advanced)
    update_beats(-1)

func select_field(title: String, items: Array, selected: int, callback: Callable) -> VBoxContainer:
    var field := VBoxContainer.new()
    field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    field.add_theme_constant_override("separation", 6)
    field.add_child(label(title, 11, true))
    var choice := OptionButton.new()
    choice.custom_minimum_size.y = 44
    for item in items: choice.add_item(str(item))
    choice.select(maxi(0, selected))
    choice.item_selected.connect(callback)
    field.add_child(choice)
    return field

func beat_count() -> int:
    if settings.mode == "Polyrhythm": return int(settings.poly_b)
    if settings.time == "6/8": return 2
    return int(str(settings.time).split("/")[0])

func beat_unit() -> String:
    if settings.mode == "Polyrhythm": return "pulse B"
    if settings.time == "6/8": return "dotted quarter"
    if settings.time == "7/8": return "eighth note"
    return "quarter note"

func reset_accents_if_needed() -> void:
    var count := beat_count()
    if settings.accents.size() != count:
        settings.accents = []
        for i in count: settings.accents.append(2 if i == 0 else 1)
    else:
        for i in count: settings.accents[i] = clampi(int(settings.accents[i]), 0, 2)

func on_time_changed(index: int) -> void:
    settings.time = TIMES[index]
    if settings.mode == "Polyrhythm": settings.mode = "Basic"
    reset_accents_if_needed()
    restart_if_running()
    save_settings()
    build_ui()

func on_subdivision_changed(index: int) -> void:
    settings.subdivision = index + 1
    restart_if_running()
    save_settings()

func cycle_accent(index: int) -> void:
    settings.accents[index] = (int(settings.accents[index]) + 1) % 3
    update_beats(-1)
    restart_if_running()
    save_settings()

func update_beats(current: int) -> void:
    for i in beat_buttons.size():
        var b := beat_buttons[i]
        var strength: int = settings.accents[i % settings.accents.size()]
        b.text = "−" if strength == 0 else str(i + 1)
        b.tooltip_text = "Beat " + str(i + 1) + ": " + ["muted", "normal", "accented"][strength]
        var fill: Color = colors.soft if strength == 2 else colors.surface if strength == 1 else colors.background
        var border: Color = colors.accent if i == current or strength == 2 else colors.line
        b.add_theme_stylebox_override("normal", box(fill, border, 3 if i == current else 1, 22))
    last_beat = current

func commit_tempo_text(text: String) -> void:
    if text.is_valid_int(): set_bpm(int(text))
    elif is_instance_valid(tempo_input): tempo_input.text = str(int(settings.bpm))

func set_bpm(value: int) -> void:
    var next := clampi(value, 20, 300)
    if next == int(settings.bpm):
        if is_instance_valid(tempo_input): tempo_input.text = str(next)
        return
    settings.bpm = next
    restart_if_running()
    save_settings()
    build_ui.call_deferred()

func draw_favorites() -> void:
    if not is_instance_valid(favorites_box): return
    for child in favorites_box.get_children():
        favorites_box.remove_child(child)
        child.queue_free()
    for value in settings.favorites:
        var bpm := int(value)
        var b := button(str(bpm) + (" ×" if favorites_edit else ""), favorite_pressed.bind(bpm))
        b.custom_minimum_size.x = 52
        if bpm == int(settings.bpm):
            b.add_theme_stylebox_override("normal", box(colors.soft, colors.accent))
        favorites_box.add_child(b)
    favorites_box.add_child(button("+ Save" if settings.favorites.is_empty() else "+", add_favorite))

func toggle_favorites_edit() -> void:
    favorites_edit = not favorites_edit
    build_ui()

func favorite_pressed(bpm: int) -> void:
    if favorites_edit:
        settings.favorites.erase(bpm)
        save_settings()
        draw_favorites()
    else: set_bpm(bpm)

func add_favorite() -> void:
    if int(settings.bpm) in settings.favorites:
        show_message("Tempo already saved.")
        return
    if settings.favorites.size() >= 8:
        show_message("Eight favorites saved. Remove one with Edit.")
        return
    settings.favorites.append(int(settings.bpm))
    settings.favorites.sort()
    save_settings()
    draw_favorites()

func tap_tempo() -> void:
    var now := Time.get_ticks_usec() / 1000000.0
    if not taps.is_empty() and now - taps.back() > 4.0: taps.clear()
    taps.append(now)
    if taps.size() > 7: taps.pop_front()
    if taps.size() > 1:
        set_bpm(int(round(60.0 * (taps.size() - 1) / (taps.back() - taps.front()))))

func clock_config() -> Dictionary:
    reset_accents_if_needed()
    var mode: String = settings.mode
    return {
        "bpm": int(settings.bpm), "beats": beat_count(),
        "subdivision": 2 if mode == "Swing / Shuffle" else int(settings.subdivision),
        "accents": settings.accents, "volume": float(settings.click_volume), "sound": int(settings.click_sound),
        "swing": float(settings.swing) if mode == "Swing / Shuffle" else 0.5,
        "audibleBars": int(settings.audible_bars), "silentBars": int(settings.silent_bars) if mode == "Gap Click" else 0,
        "poly": int(settings.poly_a) if mode == "Polyrhythm" else 0,
        "rampStep": int(settings.ramp_step) if mode == "Tempo Trainer" else 0,
        "rampEvery": int(settings.ramp_every), "targetBpm": maxi(int(settings.target_bpm), int(settings.bpm))
    }

func toggle_clock() -> void:
    if clock.running: clock.stop()
    else: clock.start(clock_config())
    sync_transport()

func restart_if_running() -> void:
    if clock.running: clock.start(clock_config())

func mode_status() -> String:
    return str(settings.mode) if settings.mode != "Basic" else "Running" if clock != null and clock.running else "Ready"

func sync_transport() -> void:
    for b in play_buttons: b.text = "Stop" if clock.running else "Start"
    if is_instance_valid(status_label) and settings.view == "metronome": status_label.text = mode_status()
    clock_was_running = clock.running
    if not clock.running: update_beats(-1)

func _process(_delta: float) -> void:
    if clock == null: return
    if clock.running != clock_was_running: sync_transport()
    if clock.running:
        var info := clock.status()
        var elapsed := float(info.get("seconds", 0))
        var bpm := float(info.get("bpm", settings.bpm))
        var beat := int(info.get("beat", int(elapsed * bpm / 60.0) % beat_count()))
        if beat != last_beat: update_beats(beat)
        if settings.mode == "Tempo Trainer" and is_instance_valid(tempo_input) and not tempo_input.has_focus():
            tempo_input.text = str(int(bpm))
        if settings.mode == "Gap Click" and is_instance_valid(status_label):
            var bar := int(info.get("bar", 0))
            var is_silent := bar % (int(settings.audible_bars) + int(settings.silent_bars)) >= int(settings.audible_bars)
            status_label.text = "Gap Click · " + ("Silent" if is_silent else "Audible")
    if is_instance_valid(toast_label) and toast_label.visible and Time.get_ticks_msec() > toast_until:
        toast_label.hide()

func show_message(message: String) -> void:
    if is_instance_valid(toast_label):
        toast_label.text = message
        toast_label.show()
        toast_until = Time.get_ticks_msec() + 5000

func dialog(title: String, minimum_height: int = 300) -> VBoxContainer:
    if is_instance_valid(current_dialog): current_dialog.queue_free()
    current_dialog = AcceptDialog.new()
    current_dialog.title = title
    current_dialog.theme = theme
    current_dialog.ok_button_text = "Done"
    current_dialog.exclusive = true
    add_child(current_dialog)
    var scroll := ScrollContainer.new()
    scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    scroll.offset_left = 14
    scroll.offset_right = -14
    scroll.offset_top = 12
    scroll.offset_bottom = -56
    current_dialog.add_child(scroll)
    var content := VBoxContainer.new()
    content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    content.add_theme_constant_override("separation", 14)
    scroll.add_child(content)
    current_dialog.popup_centered(Vector2i(mini(400, int(size.x) - 32), mini(minimum_height, int(size.y) - 70)))
    return content

func slider_field(parent: VBoxContainer, title: String, value: float, callback: Callable) -> void:
    var row := HBoxContainer.new()
    row.add_child(label(title, 14))
    row.add_child(spacer())
    var slider := HSlider.new()
    slider.min_value = 0
    slider.max_value = 1
    slider.step = 0.01
    slider.value = value
    slider.custom_minimum_size = Vector2(140, 35)
    slider.value_changed.connect(callback)
    row.add_child(slider)
    parent.add_child(row)

func open_settings() -> void:
    var content := dialog("Settings", 480)
    slider_field(content, "Piano volume", float(settings.piano_volume), func(v):
        settings.piano_volume = v
        piano.set_volume(v)
        save_settings())
    slider_field(content, "Click volume", float(settings.click_volume), func(v):
        settings.click_volume = v
        clock.set_volume(v)
        save_settings())
    content.add_child(select_field("Click sound", ["Wood", "Soft click", "Electronic"], int(settings.click_sound), func(index):
        settings.click_sound = index
        restart_if_running()
        save_settings()))
    var awake := CheckButton.new()
    awake.text = "Keep screen awake"
    awake.button_pressed = bool(settings.keep_awake)
    awake.toggled.connect(func(on):
        settings.keep_awake = on
        DisplayServer.screen_set_keep_on(on)
        save_settings())
    content.add_child(awake)
    content.add_child(select_field("Appearance", ["Dark", "Light"], 1 if settings.appearance == "light" else 0, func(index):
        settings.appearance = "light" if index == 1 else "dark"
        save_settings()))
    var credits := label("Piano: Salamander Grand Piano\nAlexander Holm · CC BY 3.0\n\nVersion 0.1.0 · Offline after installation", 12, true)
    credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    content.add_child(credits)
    current_dialog.confirmed.connect(build_ui)

func number_field(parent: VBoxContainer, title: String, value: float, low: float, high: float, callback: Callable, step: float = 1) -> void:
    var row := HBoxContainer.new()
    row.add_child(label(title, 14))
    row.add_child(spacer())
    var spin := SpinBox.new()
    spin.min_value = low
    spin.max_value = high
    spin.step = step
    spin.value = value
    spin.custom_minimum_size.x = 115
    spin.value_changed.connect(callback)
    row.add_child(spin)
    parent.add_child(row)

func open_advanced() -> void:
    var content := dialog("Advanced", 400)
    for mode in MODES.slice(1): content.add_child(button(mode, open_mode.bind(mode)))
    content.add_child(button("Return to basic metronome", func():
        settings.mode = "Basic"
        reset_accents_if_needed()
        save_settings()
        restart_if_running()
        current_dialog.hide()
        build_ui()))

func open_mode(mode: String) -> void:
    var draft := settings.duplicate(true)
    var content := dialog(mode, 340)
    current_dialog.ok_button_text = "Use this mode"
    match mode:
        "Tempo Trainer":
            number_field(content, "Start BPM", draft.bpm, 20, 300, func(v): draft.bpm = int(v))
            number_field(content, "Target BPM", draft.target_bpm, 20, 300, func(v): draft.target_bpm = int(v))
            number_field(content, "Increase by", draft.ramp_step, 1, 40, func(v): draft.ramp_step = int(v))
            number_field(content, "Every N bars", draft.ramp_every, 1, 64, func(v): draft.ramp_every = int(v))
        "Gap Click":
            number_field(content, "Audible bars", draft.audible_bars, 1, 32, func(v): draft.audible_bars = int(v))
            number_field(content, "Silent bars", draft.silent_bars, 1, 32, func(v): draft.silent_bars = int(v))
        "Swing / Shuffle":
            number_field(content, "Swing %", draft.swing * 100, 50, 75, func(v): draft.swing = v / 100.0, 0.1)
            content.add_child(label("50% = straight · 66.7% = shuffle", 12, true))
        "Polyrhythm":
            number_field(content, "Pulse A", draft.poly_a, 2, 12, func(v): draft.poly_a = int(v))
            number_field(content, "Pulse B", draft.poly_b, 2, 12, func(v): draft.poly_b = int(v))
            content.add_child(label("BPM counts pulse B. Both share one cycle.", 12, true))
    current_dialog.confirmed.connect(func():
        settings = draft
        settings.mode = mode
        reset_accents_if_needed()
        save_settings()
        restart_if_running()
        build_ui())

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        if clock != null: clock.stop()
        save_settings()
