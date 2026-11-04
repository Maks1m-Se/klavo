package com.maksim.pianometronome.audio;

import org.json.JSONArray;
import org.json.JSONObject;

final class RhythmRenderer {
    private final int rate, beats, subdivision, audible, silent, poly, rampEvery;
    private final int[] accents;
    private final double swing, rampStep, target;
    private final float[][] clicks = new float[4][];
    private final int[] cursor = {-1, -1, -1, -1};
    private int beat, sub, bar;
    private double bpm, nextStep, nextPoly;
    private long frame;
    volatile float volume;
    volatile int currentBeat, currentBar;
    volatile double currentBpm;

    RhythmRenderer(int rate, JSONObject config) {
        this.rate = rate;
        bpm = currentBpm = bounded(config, "bpm", 96, 20, 300);
        beats = (int) bounded(config, "beats", 4, 1, 12);
        subdivision = (int) bounded(config, "subdivision", 1, 1, 8);
        audible = (int) bounded(config, "audibleBars", 4, 1, 32);
        silent = (int) bounded(config, "silentBars", 0, 0, 32);
        poly = (int) bounded(config, "poly", 0, 0, 12);
        rampEvery = (int) bounded(config, "rampEvery", 8, 1, 64);
        rampStep = bounded(config, "rampStep", 0, 0, 40);
        target = bounded(config, "targetBpm", 120, bpm, 300);
        swing = bounded(config, "swing", .5, .5, .75);
        volume = (float) bounded(config, "volume", .6, 0, 1);
        accents = new int[beats];
        JSONArray input = config.optJSONArray("accents");
        for (int i = 0; i < beats; i++) {
            accents[i] = input == null ? (i == 0 ? 2 : 1) : input.optInt(i, 1);
        }
        int sound = (int) bounded(config, "sound", 0, 0, 2);
        clicks[0] = click(1200, .29, sound);
        clicks[1] = click(1560, .40, sound);
        clicks[2] = click(1120, .13, sound);
        clicks[3] = click(720, .24, sound);
    }

    private static double bounded(JSONObject config, String key, double fallback, double min, double max) {
        double value = config.optDouble(key, fallback);
        return Double.isFinite(value) ? Math.max(min, Math.min(max, value)) : fallback;
    }

    private float[] click(double frequency, double gain, int sound) {
        float[] output = new float[(int) Math.ceil(rate * .045)];
        for (int i = 0; i < output.length; i++) {
            double t = i / (double) rate;
            double phase = 2 * Math.PI * frequency * t;
            double wave;
            if (sound == 1) wave = Math.sin(phase * .7);
            else if (sound == 2) wave = Math.sin(phase);
            else wave = .78 * Math.sin(phase) + .22 * Math.sin(phase * 1.63);
            double envelope = Math.min(1, t / .0012) * Math.min(1, (.045 - t) / .006);
            output[i] = (float) (gain * wave * envelope * Math.exp(-t / (sound == 1 ? .006 : .009)));
        }
        return output;
    }

    private boolean isAudible(int barIndex) {
        return barIndex % (audible + silent) < audible;
    }

    void render(float[] output) {
        for (int i = 0; i < output.length; i++, frame++) {
            if (frame >= Math.round(nextStep)) {
                currentBar = bar;
                currentBeat = beat;
                currentBpm = bpm;
                int accent = accents[beat];
                if (isAudible(bar) && accent > 0) cursor[sub > 0 ? 2 : accent == 2 ? 1 : 0] = 0;
                double fraction = subdivision == 2 ? (sub == 0 ? swing : 1 - swing) : 1.0 / subdivision;
                nextStep += rate * 60.0 / bpm * fraction;
                if (++sub == subdivision) {
                    sub = 0;
                    if (++beat == beats) {
                        beat = 0;
                        if (++bar % rampEvery == 0) bpm = Math.min(target, bpm + rampStep);
                    }
                }
            }
            if (poly > 0 && frame >= Math.round(nextPoly)) {
                if (isAudible(currentBar)) cursor[3] = 0;
                nextPoly += rate * 60.0 / currentBpm * beats / poly;
            }
            float mix = 0;
            for (int voice = 0; voice < clicks.length; voice++) {
                if (cursor[voice] < 0) continue;
                mix += clicks[voice][cursor[voice]++];
                if (cursor[voice] == clicks[voice].length) cursor[voice] = -1;
            }
            output[i] = Math.max(-1, Math.min(1, mix * volume));
        }
    }
}
