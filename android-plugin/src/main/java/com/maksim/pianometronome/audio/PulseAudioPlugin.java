package com.maksim.pianometronome.audio;

import android.app.Activity;
import android.content.Intent;
import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

public final class PulseAudioPlugin extends GodotPlugin {
    public PulseAudioPlugin(Godot godot) { super(godot); }

    @Override public String getPluginName() { return "PulseAudio"; }

    @UsedByGodot public void start(String config) {
        Activity activity = getActivity();
        if (activity == null) return;
        activity.runOnUiThread(() -> {
            try {
                activity.startForegroundService(new Intent(activity, MetronomeService.class)
                        .putExtra("config", config));
            } catch (RuntimeException error) {
                MetronomeService.error = "Android could not start the metronome.";
            }
        });
    }

    @UsedByGodot public void stop() {
        Activity activity = getActivity();
        if (activity != null) activity.runOnUiThread(() ->
                activity.stopService(new Intent(activity, MetronomeService.class)));
    }

    @UsedByGodot public void volume(float value) {
        MetronomeService.setVolume(value);
    }

    @UsedByGodot public String status() { return MetronomeService.status(); }
}
