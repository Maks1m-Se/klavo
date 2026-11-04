extends Control
class_name PianoKeyboard

signal note_pressed(midi: int)
signal note_released(midi: int)
signal range_changed(first: String, last: String)

var octave := 3
var show_labels := true
var compact := false
var accent := Color("cccccc")
var white_keys: Array[Dictionary] = []
var black_keys: Array[Dictionary] = []
var fingers: Dictionary = {}
var active: Dictionary = {}
var mouse_down := false
var white_count := 8
const WHITE_SEMITONES := [0, 2, 4, 5, 7, 9, 11]
const NAMES := ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    focus_mode = Control.FOCUS_ALL
    resized.connect(rebuild)
    rebuild()

static func note_name(midi: int) -> String:
    return NAMES[posmod(midi, 12)] + str(int(midi / 12) - 1)

func rebuild() -> void:
    release_all()
    white_count = 15 if size.x >= 510.0 or compact else 8
    if size.x >= 940.0:
        white_count = 22
    white_keys.clear()
    black_keys.clear()
    var width: float = size.x / white_count
    var base: int = (octave + 1) * 12
    for i in white_count:
        var midi: int = base + int(i / 7) * 12 + WHITE_SEMITONES[i % 7]
        white_keys.append({"midi": midi, "rect": Rect2(i * width, 0, width, size.y)})
        if i < white_count - 1 and i % 7 not in [2, 6]:
            black_keys.append({"midi": midi + 1, "rect": Rect2((i + 0.68) * width, 0, width * 0.64, size.y * 0.61)})
    range_changed.emit(note_name(base), note_name(white_keys.back().midi))
    queue_redraw()

func _draw() -> void:
    var font: Font = ThemeDB.fallback_font
    for key in white_keys:
        var rect: Rect2 = key.rect
        draw_style_box(key_style(Color.WHITE, Color("b0b0b0"), 1), rect)
        if active.has(key.midi):
            draw_rect(Rect2(rect.position.x + 2, size.y - 8, rect.size.x - 4, 5), accent)
        if show_labels:
            var label: String = note_name(key.midi) if key.midi % 12 == 0 else NAMES[key.midi % 12]
            var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
            draw_string(font, Vector2(rect.position.x + (rect.size.x - text_size.x) / 2, size.y - 22), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("343434"))
    for key in black_keys:
        var rect: Rect2 = key.rect
        draw_style_box(key_style(Color("111111"), Color("000000"), 1), rect)
        draw_line(Vector2(rect.position.x + 3, rect.end.y - 5), Vector2(rect.end.x - 3, rect.end.y - 5), Color("292929"), 2)
        if active.has(key.midi):
            draw_rect(Rect2(rect.position.x + 3, rect.end.y - 11, rect.size.x - 6, 4), accent)

func key_style(fill: Color, border: Color, width: int) -> StyleBoxFlat:
    var style := StyleBoxFlat.new()
    style.bg_color = fill
    style.border_color = border
    style.border_width_right = width
    style.corner_radius_bottom_left = 4
    style.corner_radius_bottom_right = 4
    return style

func note_at(point: Vector2) -> int:
    for key in black_keys:
        if key.rect.has_point(point): return key.midi
    for key in white_keys:
        if key.rect.has_point(point): return key.midi
    return -1

func press_finger(id: int, point: Vector2) -> void:
    var midi := note_at(point)
    if fingers.get(id, -1) == midi: return
    release_finger(id)
    if midi < 21 or midi > 108: return
    fingers[id] = midi
    active[midi] = int(active.get(midi, 0)) + 1
    if active[midi] == 1: note_pressed.emit(midi)
    queue_redraw()

func release_finger(id: int) -> void:
    if not fingers.has(id): return
    var midi: int = fingers[id]
    fingers.erase(id)
    active[midi] -= 1
    if active[midi] <= 0:
        active.erase(midi)
        note_released.emit(midi)
    queue_redraw()

func release_all() -> void:
    for id in fingers.keys(): release_finger(id)
    mouse_down = false

func _gui_input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed: press_finger(event.index, event.position)
        else: release_finger(event.index)
        accept_event()
    elif event is InputEventScreenDrag:
        press_finger(event.index, event.position)
        accept_event()
    elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        mouse_down = event.pressed
        if mouse_down: press_finger(-1, event.position)
        else: release_finger(-1)
        accept_event()
    elif event is InputEventMouseMotion and mouse_down:
        press_finger(-1, event.position)
        accept_event()

func _notification(what: int) -> void:
    if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
        release_all()
