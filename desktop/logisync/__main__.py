"""LogiSync desktop agent.

When the keyboard leaves this computer (Easy-Switch key), send the mouse to the configured
channel with HID++ CHANGE_HOST. Run on every computer that shares the pair.

    python -m logisync              run in foreground
    python -m logisync --status     print what was found and exit
"""
import argparse
import json
import logging
import os
import sys
import threading
import time
from logging.handlers import RotatingFileHandler

from . import hidpp, watchers
from .keyguard import KeyGuard

DEFAULTS = {
    "keyboard": "K950",        # part of the keyboard's Bluetooth name
    "mouse": "MX Anywhere",    # part of the mouse's Bluetooth name
    "target_channel": 2,       # channel (1-3) the mouse goes to when the keyboard leaves
    "key_window_s": 600,       # only switch if the keyboard was typed on in the last N s (Windows)
    "settle_s": 0.4,
    "enabled": True,
}


def config_dir():
    if sys.platform == "win32":
        return os.path.join(os.environ["LOCALAPPDATA"], "LogiSync")
    if sys.platform == "darwin":
        return os.path.expanduser("~/Library/Application Support/LogiSync")
    return os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "logisync")


def load_config(path):
    cfg = dict(DEFAULTS)
    if os.path.exists(path):
        with open(path, encoding="utf-8-sig") as f:
            cfg.update(json.load(f))
    else:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2)
    return cfg


def main():
    ap = argparse.ArgumentParser(prog="logisync")
    ap.add_argument("--status", action="store_true")
    ap.add_argument("--config")
    args = ap.parse_args()

    base = config_dir()
    os.makedirs(base, exist_ok=True)
    cfg = load_config(args.config or os.path.join(base, "config.json"))
    log = logging.getLogger("logisync")
    log.setLevel(logging.INFO)
    fmt = logging.Formatter("%(asctime)s %(message)s")
    fh = RotatingFileHandler(os.path.join(base, "logisync.log"), maxBytes=512_000, backupCount=2, encoding="utf-8")
    fh.setFormatter(fmt)
    log.addHandler(fh)
    if sys.stdout:
        sh = logging.StreamHandler(sys.stdout)
        sh.setFormatter(fmt)
        log.addHandler(sh)

    kbd, mouse = cfg["keyboard"], cfg["mouse"]
    if args.status:
        for n in (kbd, mouse):
            d = hidpp.find(n)
            if not d:
                print(f"{n}: not found")
                continue
            try:
                hosts, cur = hidpp.host_info(d)
                print(f"{n}: {d['product_string']} pid={d['product_id']:04x} channel {cur + 1}/{hosts}")
            except Exception as e:
                print(f"{n}: {d['product_string']} found but not answering ({e})")
        return

    kd = hidpp.find(kbd)
    guard = KeyGuard(kd and kd["product_id"], log.info)
    guard.start()
    lock = threading.Lock()

    def keyboard_left():
        idle = guard.idle_seconds()
        time.sleep(cfg["settle_s"])
        if not cfg["enabled"]:
            return
        if w.connected(kbd):
            log.info("keyboard came back quickly; ignored")
        elif not w.connected(mouse):
            log.info("mouse is not connected here either (sleep/Bluetooth off?); ignored")
        elif idle > cfg["key_window_s"]:
            log.info("keyboard idle for %.0fs (probably power saving); ignored", idle)
        else:
            with lock:
                try:
                    d = hidpp.find(mouse)
                    moved = d and hidpp.change_host(d, cfg["target_channel"] - 1)
                    log.info("mouse sent to channel %d" if moved else "mouse already on channel %d",
                             cfg["target_channel"])
                except Exception as e:
                    log.info("could not switch the mouse: %s", e)

    def on_change(name, up):
        log.info("%s %s", name, "connected" if up else "disconnected")
        if name == kbd and not up:
            threading.Thread(target=keyboard_left, daemon=True).start()

    w = watchers.make([kbd, mouse], on_change)
    w.start()
    log.info("started: keyboard=%r mouse=%r target channel=%d", kbd, mouse, cfg["target_channel"])
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    main()
