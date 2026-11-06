package io.github.logisync;

import android.Manifest;
import android.annotation.SuppressLint;
import android.app.Activity;
import android.bluetooth.BluetoothDevice;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.PowerManager;
import android.provider.Settings;
import android.text.InputType;
import android.view.View;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

@SuppressLint({"MissingPermission", "SetTextI18n", "BatteryLife"})
public class MainActivity extends Activity {
    private final Handler h = new Handler(Looper.getMainLooper());
    private TextView logView;
    private EditText kbd, mouse, host;

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        SharedPreferences p = SyncService.prefs(this);
        LinearLayout l = new LinearLayout(this);
        l.setOrientation(LinearLayout.VERTICAL);
        int pad = (int) (16 * getResources().getDisplayMetrics().density);
        l.setPadding(pad, pad * 2, pad, pad);

        kbd = field(l, "Nome do teclado (contém)", p.getString("keyboard", "K950"), false);
        mouse = field(l, "Nome do mouse (contém)", p.getString("mouse", "MX Anywhere"), false);
        host = field(l, "Canal do mouse quando o teclado sair daqui (1-3)", String.valueOf(p.getInt("host", 0) + 1), true);

        button(l, "Salvar", v -> {
            p.edit().putString("keyboard", kbd.getText().toString().trim())
                    .putString("mouse", mouse.getText().toString().trim())
                    .putInt("host", Math.max(0, Math.min(2, parse(host) - 1))).apply();
            SyncService.log("configuração salva");
        });
        button(l, "Testar: mandar o mouse agora", v -> {
            BluetoothDevice m = SyncService.bonded(this, p.getString("mouse", "MX Anywhere"));
            if (m == null) SyncService.log("mouse não encontrado entre os pareados");
            else SyncService.moveMouse(this, m, p.getInt("host", 0));
        });
        button(l, "Escolher layout do teclado físico", v ->
                startActivity(new Intent("android.settings.HARD_KEYBOARD_SETTINGS")));
        button(l, "Desativar otimização de bateria", v -> requestBattery());

        logView = new TextView(this);
        logView.setTextIsSelectable(true);
        logView.setTypeface(android.graphics.Typeface.MONOSPACE);
        logView.setPadding(0, pad, 0, 0);
        l.addView(logView);

        ScrollView sv = new ScrollView(this);
        sv.addView(l);
        setContentView(sv);

        if (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED
                || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(new String[]{Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.POST_NOTIFICATIONS}, 1);
        } else {
            SyncService.start(this);
        }
        refresh();
    }

    @Override
    public void onRequestPermissionsResult(int code, String[] perms, int[] res) {
        if (checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED) {
            SyncService.start(this);
            requestBattery();
        }
    }

    private void requestBattery() {
        PowerManager pm = getSystemService(PowerManager.class);
        if (!pm.isIgnoringBatteryOptimizations(getPackageName())) {
            startActivity(new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:" + getPackageName())));
        }
    }

    private void refresh() {
        synchronized (SyncService.class) {
            logView.setText(String.join("\n", SyncService.LOG));
        }
        h.postDelayed(this::refresh, 1000);
    }

    private static int parse(EditText e) {
        try { return Integer.parseInt(e.getText().toString().trim()); } catch (NumberFormatException x) { return 1; }
    }

    private EditText field(LinearLayout l, String label, String value, boolean number) {
        TextView t = new TextView(this);
        t.setText(label);
        l.addView(t);
        EditText e = new EditText(this);
        e.setText(value);
        e.setSingleLine();
        if (number) e.setInputType(InputType.TYPE_CLASS_NUMBER);
        l.addView(e);
        return e;
    }

    private void button(LinearLayout l, String label, View.OnClickListener c) {
        Button b = new Button(this);
        b.setText(label);
        b.setOnClickListener(c);
        l.addView(b);
    }

    @Override
    protected void onDestroy() {
        h.removeCallbacksAndMessages(null);
        super.onDestroy();
    }
}
