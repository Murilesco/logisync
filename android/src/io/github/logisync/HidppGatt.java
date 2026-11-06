package io.github.logisync;

import android.annotation.SuppressLint;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothGatt;
import android.bluetooth.BluetoothGattCallback;
import android.bluetooth.BluetoothGattCharacteristic;
import android.bluetooth.BluetoothGattDescriptor;
import android.bluetooth.BluetoothGattService;
import android.bluetooth.BluetoothProfile;
import android.content.Context;
import android.os.Handler;
import android.os.Looper;

import java.util.UUID;

/**
 * HID++ 2.0 sobre o servico GATT da Logitech (00010000-...-011f2000046d).
 * Quadro de 18 bytes: [indice da feature, (funcao << 4) | swId, 16 bytes de parametros].
 * Envia CHANGE_HOST (0x1814) setCurrentHost para o dispositivo.
 */
@SuppressLint("MissingPermission")
public class HidppGatt extends BluetoothGattCallback {
    static final UUID SERVICE = UUID.fromString("00010000-0000-1000-8000-011f2000046d");
    static final UUID CHAR = UUID.fromString("00010001-0000-1000-8000-011f2000046d");
    static final UUID CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
    static final int SW_ID = 0x0B;
    static final int TIMEOUT_MS = 6000;

    public interface Done {
        void result(boolean ok, String msg);
    }

    private final int host;
    private final Done done;
    private final Handler main = new Handler(Looper.getMainLooper());
    private BluetoothGatt gatt;
    private BluetoothGattCharacteristic ch;
    private boolean finished;

    private HidppGatt(int host, Done done) {
        this.host = host;
        this.done = done;
    }

    /** host: 0 = canal 1, 1 = canal 2, 2 = canal 3 */
    public static void changeHost(Context ctx, BluetoothDevice dev, int host, Done done) {
        HidppGatt h = new HidppGatt(host, done);
        h.main.postDelayed(() -> h.finish(false, "tempo esgotado (mouse nao conectado aqui?)"), TIMEOUT_MS);
        h.gatt = dev.connectGatt(ctx, false, h, BluetoothDevice.TRANSPORT_LE);
    }

    private void finish(boolean ok, String msg) {
        main.post(() -> {
            if (finished) return;
            finished = true;
            if (gatt != null) {
                // da tempo do quadro sair antes de fechar
                BluetoothGatt g = gatt;
                main.postDelayed(() -> { g.disconnect(); g.close(); }, ok ? 500 : 0);
            }
            done.result(ok, msg);
        });
    }

    private void send(int feat, int fn, int... params) {
        byte[] f = new byte[18];
        f[0] = (byte) feat;
        f[1] = (byte) ((fn << 4) | SW_ID);
        for (int i = 0; i < params.length; i++) f[2 + i] = (byte) params[i];
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            gatt.writeCharacteristic(ch, f, BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE);
        } else {
            ch.setWriteType(BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE);
            ch.setValue(f);
            gatt.writeCharacteristic(ch);
        }
    }

    @Override
    public void onConnectionStateChange(BluetoothGatt g, int status, int state) {
        if (state == BluetoothProfile.STATE_CONNECTED) {
            g.discoverServices();
        } else if (state == BluetoothProfile.STATE_DISCONNECTED) {
            finish(false, "GATT desconectado (status " + status + ")");
        }
    }

    @Override
    public void onServicesDiscovered(BluetoothGatt g, int status) {
        BluetoothGattService s = g.getService(SERVICE);
        if (s == null || (ch = s.getCharacteristic(CHAR)) == null) {
            finish(false, "servico HID++ da Logitech nao encontrado");
            return;
        }
        g.setCharacteristicNotification(ch, true);
        BluetoothGattDescriptor d = ch.getDescriptor(CCCD);
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            g.writeDescriptor(d, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
        } else {
            d.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
            g.writeDescriptor(d);
        }
    }

    @Override
    public void onDescriptorWrite(BluetoothGatt g, BluetoothGattDescriptor d, int status) {
        send(0x00, 0, 0x18, 0x14); // root.getFeature(CHANGE_HOST)
    }

    @Override
    public void onCharacteristicChanged(BluetoothGatt g, BluetoothGattCharacteristic c, byte[] v) {
        handle(v);
    }

    @Override
    @SuppressWarnings("deprecation")
    public void onCharacteristicChanged(BluetoothGatt g, BluetoothGattCharacteristic c) {
        if (android.os.Build.VERSION.SDK_INT < 33) handle(c.getValue());
    }

    private void handle(byte[] v) {
        if (v == null || v.length < 3) return;
        int feat = v[0] & 0xFF, fn = v[1] & 0xFF;
        if (feat == 0xFF) {
            finish(false, String.format("erro HID++ 0x%02x", v[3] & 0xFF));
        } else if (feat == 0x00 && fn == SW_ID) {
            int idx = v[2] & 0xFF;
            if (idx == 0) { finish(false, "dispositivo sem CHANGE_HOST"); return; }
            send(idx, 1, host); // CHANGE_HOST.setCurrentHost(host); o dispositivo troca na hora
            finish(true, "enviado para o canal " + (host + 1));
        }
    }
}
