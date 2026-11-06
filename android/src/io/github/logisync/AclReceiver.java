package io.github.logisync;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/**
 * Registrado no manifest: o Android entrega ACL_CONNECTED/DISCONNECTED mesmo com o app parado,
 * entao o servico e (re)iniciado e recebe o evento.
 */
public class AclReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        Intent s = new Intent(context, SyncService.class)
                .setAction(intent.getAction())
                .putExtras(intent);
        context.startForegroundService(s);
    }
}
