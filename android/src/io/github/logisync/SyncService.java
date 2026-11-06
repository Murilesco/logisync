package io.github.logisync;

import android.annotation.SuppressLint;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ServiceInfo;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;

import java.text.SimpleDateFormat;
import java.util.ArrayDeque;
import java.util.Date;
import java.util.Locale;

/**
 * Quando o teclado sai deste aparelho (Easy-Switch), manda o mouse para o canal configurado.
 */
@SuppressLint("MissingPermission")
public class SyncService extends Service {
    static final String CHANNEL = "logisync";
    static final ArrayDeque<String> LOG = new ArrayDeque<>();
    static final long SETTLE_MS = 400;

    private final Handler main = new Handler(Looper.getMainLooper());
    private boolean keyboardUp;

    public static void start(Context ctx) {
        ctx.startForegroundService(new Intent(ctx, SyncService.class));
    }

    static SharedPreferences prefs(Context ctx) {
        return ctx.getSharedPreferences("cfg", MODE_PRIVATE);
    }

    static synchronized void log(String s) {
        android.util.Log.i("LogiSync", s);
        LOG.addFirst(new SimpleDateFormat("HH:mm:ss", Locale.ROOT).format(new Date()) + "  " + s);
        while (LOG.size() > 100) LOG.removeLast();
    }

    static boolean matches(BluetoothDevice d, String pattern) {
        String n = d.getName();
        return n != null && !pattern.isEmpty() && n.toLowerCase(Locale.ROOT).contains(pattern.toLowerCase(Locale.ROOT));
    }

    /** Pode haver pareamentos antigos com o mesmo nome: prefere o conectado, depois o ultimo visto. */
    static BluetoothDevice bonded(Context ctx, String pattern) {
        BluetoothAdapter a = ctx.getSystemService(BluetoothManager.class).getAdapter();
        if (a == null) return null;
        String last = prefs(ctx).getString("lastMouse", "");
        BluetoothDevice lastSeen = null, any = null;
        for (BluetoothDevice d : a.getBondedDevices()) {
            if (!matches(d, pattern)) continue;
            if (isConnected(d)) return d;
            if (d.getAddress().equals(last)) lastSeen = d;
            if (any == null) any = d;
        }
        return lastSeen != null ? lastSeen : any;
    }

    static boolean isConnected(BluetoothDevice d) {
        try {
            return (Boolean) BluetoothDevice.class.getMethod("isConnected").invoke(d);
        } catch (Exception e) {
            return false;
        }
    }

    /** Eventos ACL chegam via AclReceiver (manifest), mesmo se o processo tiver morrido. */
    private void onAcl(Intent i) {
        BluetoothDevice d = i.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice.class);
        if (d == null) return;
        boolean up = BluetoothDevice.ACTION_ACL_CONNECTED.equals(i.getAction());
        if (up && matches(d, prefs(this).getString("mouse", "MX Anywhere"))) {
            prefs(this).edit().putString("lastMouse", d.getAddress()).apply();
            log("mouse conectado");
        }
        if (!matches(d, prefs(this).getString("keyboard", "K950"))) return;
        keyboardUp = up;
        log("teclado " + (up ? "conectado" : "desconectado"));
        if (!up) main.postDelayed(this::onKeyboardLeft, SETTLE_MS);
    }

    private void onKeyboardLeft() {
        SharedPreferences p = prefs(this);
        if (keyboardUp) { log("teclado voltou rapido; ignorado"); return; }
        if (!p.getBoolean("enabled", true)) return;
        BluetoothDevice mouse = bonded(this, p.getString("mouse", "MX Anywhere"));
        if (mouse == null) { log("mouse nao pareado com este aparelho"); return; }
        moveMouse(this, mouse, p.getInt("host", 0));
    }

    static void moveMouse(Context ctx, BluetoothDevice mouse, int host) {
        HidppGatt.changeHost(ctx, mouse, host, (ok, msg) -> log("mouse: " + msg));
    }

    @Override
    public void onCreate() {
        super.onCreate();
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(CHANNEL, "LogiSync", NotificationManager.IMPORTANCE_MIN));
        Notification n = new Notification.Builder(this, CHANNEL)
                .setSmallIcon(android.R.drawable.stat_sys_data_bluetooth)
                .setContentTitle("LogiSync ativo")
                .setContentText("O mouse segue o Easy-Switch do teclado")
                .setOngoing(true)
                .build();
        startForeground(1, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE);
        log("serviço iniciado");
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && intent.getAction() != null) onAcl(intent);
        return START_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
