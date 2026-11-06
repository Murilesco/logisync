"""Per-OS 'is the keyboard/mouse connected to this computer?' watchers.

Each watcher calls on_change(name, connected) from any thread.
"""
import json
import subprocess
import sys
import threading
import time

from . import hidpp


class PollWatcher:
    """Portable fallback (macOS): a disconnected BLE device disappears from the HID tree."""

    def __init__(self, names, on_change, interval=0.25):
        self.names, self.on_change, self.interval = names, on_change, interval
        self.state = {n: self.connected(n) for n in names}

    def connected(self, name):
        return hidpp.find(name) is not None

    def start(self):
        threading.Thread(target=self._run, daemon=True).start()

    def _run(self):
        while True:
            for n in self.names:
                up = self.connected(n)
                if up != self.state[n]:
                    self.state[n] = up
                    self.on_change(n, up)
            time.sleep(self.interval)


class BlueZWatcher(PollWatcher):
    """Linux: read org.bluez Device1.Connected over D-Bus (busctl, no extra dependency)."""

    def _devices(self):
        out = subprocess.run(
            ["busctl", "--system", "--json=short", "call", "org.bluez", "/",
             "org.freedesktop.DBus.ObjectManager", "GetManagedObjects"],
            capture_output=True, text=True, timeout=5).stdout
        objs = json.loads(out)["data"][0] if out else {}
        for ifaces in objs.values():
            dev = ifaces.get("org.bluez.Device1")
            if dev:
                yield dev.get("Name", {}).get("data", ""), dev.get("Connected", {}).get("data", False)

    def connected(self, name):
        try:
            return any(hidpp._norm(name) in hidpp._norm(n) and c for n, c in self._devices())
        except Exception:
            return False

    def __init__(self, names, on_change):
        super().__init__(names, on_change, interval=0.3)


class WinRTWatcher:
    """Windows: BluetoothLEDevice.ConnectionStatusChanged events (instant)."""

    def __init__(self, names, on_change):
        self.names, self.on_change = names, on_change
        self.devices = {}

    def start(self):
        import asyncio
        threading.Thread(target=lambda: asyncio.run(self._run()), daemon=True).start()

    async def _run(self):
        import asyncio
        from winrt.windows.devices.bluetooth import BluetoothLEDevice, BluetoothConnectionStatus

        def up(dev):
            return dev.connection_status == BluetoothConnectionStatus.CONNECTED

        while len(self.devices) < len(self.names):
            for n in self.names:
                if n in self.devices:
                    continue
                d = hidpp.find(n)
                addr = d and hidpp.bt_address(d)
                if addr:
                    dev = await BluetoothLEDevice.from_bluetooth_address_async(addr)
                    if dev:
                        self.devices[n] = dev
                        dev.add_connection_status_changed(lambda s, _, n=n: self.on_change(n, up(s)))
            if len(self.devices) < len(self.names):
                await asyncio.sleep(10)
        while True:
            await asyncio.sleep(3600)

    def connected(self, name):
        from winrt.windows.devices.bluetooth import BluetoothConnectionStatus
        dev = self.devices.get(name)
        return bool(dev) and dev.connection_status == BluetoothConnectionStatus.CONNECTED


def make(names, on_change):
    if sys.platform == "win32":
        return WinRTWatcher(names, on_change)
    if sys.platform.startswith("linux"):
        return BlueZWatcher(names, on_change)
    return PollWatcher(names, on_change)
