extends SceneTree

func _initialize() -> void:
    capture.call_deferred()

func capture() -> void:
    root.size = Vector2i(420, 800)
    var app: Variant = load("res://app/main.tscn").instantiate()
    root.add_child(app)
    app.settings.appearance = "dark"
    app.settings.keep_awake = false
    app.settings.octave = 3
    app.settings.bpm = 112
    app.settings.favorites = [88, 112, 137]
    var directory := ProjectSettings.globalize_path("res://dist/screenshots")
    DirAccess.make_dir_recursive_absolute(directory)
    for view in ["piano", "metronome"]:
        app.settings.view = view
        app.build_ui()
        for i in 4:
            await process_frame
        await RenderingServer.frame_post_draw
        var image := root.get_texture().get_image()
        if image == null or image.save_png(directory.path_join(view + ".png")) != OK:
            push_error("Could not capture the " + view + " screenshot")
            quit(1)
            return
    quit()
