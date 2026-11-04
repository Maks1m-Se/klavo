@tool
extends EditorPlugin

var exporter: AudioExport

func _enter_tree() -> void:
    exporter = AudioExport.new()
    add_export_plugin(exporter)

func _exit_tree() -> void:
    remove_export_plugin(exporter)

class AudioExport extends EditorExportPlugin:
    func _get_name() -> String:
        return "PulseAudio"

    func _supports_platform(platform: EditorExportPlatform) -> bool:
        return platform is EditorExportPlatformAndroid

    func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
        return PackedStringArray(["pulse_audio/bin/pulse-audio.aar"])
