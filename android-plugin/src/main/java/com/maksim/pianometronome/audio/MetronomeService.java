package com.maksim.pianometronome.audio;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.media.AudioAttributes;
import android.media.AudioFocusRequest;
import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;
import android.os.Build;
import android.os.IBinder;
import android.os.PowerManager;
import android.os.Process;
import android.os.SystemClock;
import org.json.JSONException;
import org.json.JSONObject;

public final class MetronomeService extends Service {
    private static final String CHANNEL = "metronome";
    private static final String STOP = "com.maksim.pianometronome.STOP";
    private static final int RATE = 48000;
    private static volatile Session current;
    static volatile String error = "";

    private AudioManager audio;
    private AudioFocusRequest focus;
    private PowerManager.WakeLock wake;
    private final BroadcastReceiver unplugged = new BroadcastReceiver() {
        @Override public void onReceive(Context context, Intent intent) { stopSelf(); }
    };

    @Override public void onCreate() {
        super.onCreate();
        audio = getSystemService(AudioManager.class);
        getSystemService(NotificationManager.class).createNotificationChannel(
                new NotificationChannel(CHANNEL, "Metronome", NotificationManager.IMPORTANCE_LOW));
        IntentFilter filter = new IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY);
        if (Build.VERSION.SDK_INT >= 33) registerReceiver(unplugged, filter, Context.RECEIVER_NOT_EXPORTED);
        else registerReceiver(unplugged, filter);
    }

    @Override public int onStartCommand(Intent intent, int flags, int id) {
        if (intent == null || STOP.equals(intent.getAction())) {
            stopSelf();
            return START_NOT_STICKY;
        }

        error = "";
        startForeground(1, notification());
        stopSession();
        AudioAttributes attributes = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build();
        focus = new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attributes)
                .setOnAudioFocusChangeListener(change -> { if (change < 0) stopSelf(); }).build();
        if (audio.requestAudioFocus(focus) != AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
            error = "Android audio is in use.";
            stopSelf();
            return START_NOT_STICKY;
        }

        try {
            JSONObject config = new JSONObject(intent.getStringExtra("config"));
            wake = getSystemService(PowerManager.class)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "PianoMetronome:Playback");
            wake.acquire();
            Session session = new Session(new RhythmRenderer(RATE, config));
            current = session;
            Thread thread = new Thread(() -> play(session, attributes), "Metronome audio");
            thread.start();
        } catch (JSONException | RuntimeException problem) {
            error = "Android could not open the metronome audio output.";
            stopSelf();
        }
        return START_NOT_STICKY;
    }

    private Notification notification() {
        int flags = PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE;
        PendingIntent stop = PendingIntent.getService(this, 1, new Intent(this, MetronomeService.class)
                .setAction(STOP), flags);
        Intent launch = getPackageManager().getLaunchIntentForPackage(getPackageName());
        Notification.Builder notification = new Notification.Builder(this, CHANNEL)
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle("Metronome")
                .setContentText("Metronome is running")
                .setOngoing(true)
                .addAction(new Notification.Action.Builder(null, "Stop", stop).build());
        if (launch != null) notification.setContentIntent(PendingIntent.getActivity(this, 0, launch, flags));
        return notification.build();
    }

    private void play(Session session, AudioAttributes attributes) {
        Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO);
        AudioTrack track = null;
        try {
            int min = AudioTrack.getMinBufferSize(RATE, AudioFormat.CHANNEL_OUT_MONO, AudioFormat.ENCODING_PCM_FLOAT);
            if (min <= 0) throw new IllegalStateException("Unsupported audio output format");
            track = new AudioTrack.Builder().setAudioAttributes(attributes)
                    .setAudioFormat(new AudioFormat.Builder().setSampleRate(RATE)
                            .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                            .setEncoding(AudioFormat.ENCODING_PCM_FLOAT).build())
                    .setTransferMode(AudioTrack.MODE_STREAM).setBufferSizeInBytes(Math.max(min, 2048))
                    .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY).build();
            if (track.getState() != AudioTrack.STATE_INITIALIZED) throw new IllegalStateException("AudioTrack initialization failed");
            if (session.stopped) return;
            track.play();
            session.startedAt = SystemClock.elapsedRealtime();
            float[] buffer = new float[256];
            while (!session.stopped) {
                session.renderer.render(buffer);
                for (int offset = 0; offset < buffer.length && !session.stopped;) {
                    int written = track.write(buffer, offset, buffer.length - offset, AudioTrack.WRITE_BLOCKING);
                    if (written <= 0) throw new IllegalStateException("AudioTrack write failed");
                    offset += written;
                }
            }
        } catch (RuntimeException problem) {
            if (!session.stopped) getMainExecutorCompat(() -> {
                if (current == session && !session.stopped) {
                    error = "Android audio output stopped unexpectedly.";
                    stopSelf();
                }
            });
        } finally {
            if (track != null) {
                if (track.getPlayState() == AudioTrack.PLAYSTATE_PLAYING) track.pause();
                track.release();
            }
        }
    }

    private void getMainExecutorCompat(Runnable task) {
        new android.os.Handler(getMainLooper()).post(task);
    }

    private void stopSession() {
        Session session = current;
        if (session != null) session.stopped = true;
        current = null;
        if (focus != null) { audio.abandonAudioFocusRequest(focus); focus = null; }
        if (wake != null) { if (wake.isHeld()) wake.release(); wake = null; }
    }

    @Override public void onDestroy() {
        stopSession();
        unregisterReceiver(unplugged);
        stopForeground(STOP_FOREGROUND_REMOVE);
        super.onDestroy();
    }

    @Override public IBinder onBind(Intent intent) { return null; }

    static void setVolume(float value) {
        Session session = current;
        if (session != null) session.renderer.volume = Math.max(0, Math.min(1, value));
    }

    static String status() {
        Session session = current;
        JSONObject result = new JSONObject();
        try {
            result.put("error", error);
            result.put("running", session != null && !session.stopped);
            if (session != null) {
                long start = session.startedAt;
                result.put("seconds", start == 0 ? 0 : (SystemClock.elapsedRealtime() - start) / 1000.0);
                result.put("bpm", session.renderer.currentBpm);
                result.put("bar", session.renderer.currentBar);
                result.put("beat", session.renderer.currentBeat);
            }
        } catch (JSONException impossible) {
            return "{}";
        }
        return result.toString();
    }

    private static final class Session {
        final RhythmRenderer renderer;
        volatile boolean stopped;
        volatile long startedAt;

        Session(RhythmRenderer renderer) { this.renderer = renderer; }
    }
}
