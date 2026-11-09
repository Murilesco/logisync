<div align="center">

# LogiSync

**Press Easy-Switch on your Logitech keyboard - the mouse follows.**
Works between Windows, Linux, macOS, Android and iOS, with keyboards and mice that Logitech's own
*Enhanced Easy-Switch* does not support.

[![build](https://github.com/Murilesco/logisync/actions/workflows/build.yml/badge.svg)](https://github.com/Murilesco/logisync/actions/workflows/build.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[English](README.md) · [Português](README.pt-BR.md) · [How it works](docs/PROTOCOL.md)

</div>

---

Logitech keyboards and mice with **Easy-Switch** can pair with up to 3 devices, but each one switches
on its own. The keyboard has a key for it; the mouse button is usually underneath. LogiSync makes the
mouse follow the keyboard:

```
 keyboard: Easy-Switch 1 -> 2           keyboard: Easy-Switch 2 -> 1
 PC notices the keyboard left           phone notices the keyboard left
 PC sends the mouse to channel 2  ───►  phone sends the mouse to channel 1  ───► back on the PC
```

There is no driver to replace and no firmware to flash. A small agent runs on every device you
switch between. When the keyboard leaves, it sends the mouse the same HID++ `CHANGE_HOST` command
that Logitech's software uses. See [docs/PROTOCOL.md](docs/PROTOCOL.md) for the reverse-engineering
details.

**Bonus for Android:** copy your exact Windows keyboard layout to the phone, so every key types the
same thing on both (e.g. ABNT2 on a US-printed keyboard, `;` → `ç`).

## Status

| Platform | Mouse follows keyboard | Tested on |
|---|---|---|
| Windows 10/11 | ✅ | Windows 11 + K950 + MX Anywhere 3 |
| Android 12+ | ✅ + keyboard layouts | Galaxy S25 Ultra, Android 17, incl. Samsung DeX |
| Linux (BlueZ) | 🧪 experimental | not yet tested on hardware - reports welcome |
| macOS | 🧪 experimental | not yet tested on hardware - reports welcome |
| iOS / iPadOS | 🧪 experimental source | not yet built - needs Xcode and a developer account |

Devices: any Logitech **Bluetooth** keyboard + mouse with Easy-Switch and HID++ 2.0
(`CHANGE_HOST` / `0x1814`): MX Keys, MX Master, MX Anywhere, K950, K380, Pebble, ERGO, ...
Run `python -m logisync --status` to check yours. Bolt/Unifying receivers are not supported yet.

## Quick start

> Pair the keyboard **and** the mouse to the same channel numbers on every device first
> (e.g. PC = channel 1 on both, phone = channel 2 on both).

Then install LogiSync on **each** device and set *"send the mouse to channel N when the keyboard
leaves"*. On the PC that is channel 2, on the phone channel 1.

### Windows

Requires [Python 3.10+](https://www.python.org/downloads/).

```powershell
git clone https://github.com/Murilesco/logisync
cd logisync\desktop
powershell -ExecutionPolicy Bypass -File install-windows.ps1 -Keyboard "K950" -Mouse "MX Anywhere" -Channel 2
```

This installs the dependencies, copies the agent to `%LOCALAPPDATA%\LogiSync` and adds a logon task
that runs it hidden. Uninstall with `install-windows.ps1 -Uninstall`.

### Android

1. Download `LogiSync.apk` from the [latest release](https://github.com/Murilesco/logisync/releases/latest)
   and install it (allow "install unknown apps").
2. Open **LogiSync**, allow Bluetooth and notifications, and accept *ignore battery optimization*.
3. Fill in the keyboard and mouse names and the channel (e.g. `1`), then tap **Save**.
   **Test: send the mouse now** should move the mouse right away.
4. *(optional)* With the keyboard connected to the phone, tap **Choose physical keyboard layout**
   → your keyboard → each input method → pick a layout:
   * **Português (Brasil ABNT2) - igual ao Windows**: for typing in Android apps.
   * **Português (Brasil ABNT2) - Área de Trabalho Remota**: for remote desktop (Windows App,
     RustDesk, ...), e.g. Samsung DeX connected to a Windows PC. Also enable *Use scancode input
     when available* in Windows App → Settings → General. Accents are then composed by the remote
     Windows exactly like a local keyboard (`´` + `a` → `á`). In local Android apps the physical
     accent keys do nothing with this variant (the on-screen keyboard is not affected).

The app runs as a small foreground service (you can hide its notification in Android settings).
It wakes on every Bluetooth connection change, so it survives reboots, updates and memory cleanup.

### Linux

```bash
git clone https://github.com/Murilesco/logisync
cd logisync/desktop
./install-linux.sh            # asks for sudo once to add a udev rule for hidraw access
nano ~/.config/logisync/config.json
systemctl --user restart logisync
```

### macOS

```bash
git clone https://github.com/Murilesco/logisync
cd logisync/desktop
./install-macos.sh
```

Grant *Input Monitoring* to the Python binary if macOS asks. Config:
`~/Library/Application Support/LogiSync/config.json`.

### iOS / iPadOS (experimental)

```bash
cd ios && brew install xcodegen && xcodegen && open LogiSync.xcodeproj
```

Sign with your team and run on the device. iOS limits background Bluetooth, so this has to be
validated on a real device. Pull requests are very welcome.

## Configuration (desktop)

`config.json`, created on first run:

| Key | Default | Meaning |
|---|---|---|
| `keyboard` | `"K950"` | part of the keyboard's Bluetooth name |
| `mouse` | `"MX Anywhere"` | part of the mouse's Bluetooth name |
| `target_channel` | `2` | channel (1-3) the mouse goes to when the keyboard leaves **this** device |
| `key_window_s` | `0` (off) | Windows: if > 0, only switch if the keyboard was typed on in the last N seconds. Only useful if your keyboard drops Bluetooth when it sleeps (the K950 does not) |
| `settle_s` | `0.4` | wait before acting, to ignore short glitches |
| `enabled` | `true` | turn it off without uninstalling |

Logs: `logisync.log` next to the config (Linux: `journalctl --user -u logisync`).

## Copy your Windows keyboard layout to Android

```powershell
python tools\windows_layout_to_kcm.py my-layout.kcm            # current layout
python tools\windows_layout_to_kcm.py 00010416 abnt2.kcm      # a specific one (KLID)
python tools\windows_layout_to_kcm.py --remote rdp.kcm         # remote desktop variant
```

Put the `.kcm` in `android/res/raw/`, add an entry to `android/res/xml/keyboard_layouts.xml`, and
build. Ready-made: [`layouts/`](layouts/).

**Why a remote desktop variant?** Remote desktop clients send the character Android produced.
A dead key (`´`) produces a bare accent, so the remote PC receives `´` and `a` separately. When the
accent keys produce *no* character, the client falls back to sending the scan code, and the remote
Windows composes `á` with its own layout.

## Building the Android app

No Gradle needed: JDK 17 + Android SDK (`platforms;android-35`, `build-tools;35.0.0`).

```bash
export ANDROID_HOME=~/Android/Sdk
bash android/build.sh            # Windows: android\build.ps1
adb install -r android/build/LogiSync.apk
```

CI builds the APK on every push (download it from the run artifacts). Release APKs are signed by the maintainer, so updates install over the previous version.

## Troubleshooting

| Symptom | Check |
|---|---|
| Mouse does not follow from the PC | Look at the log. *keyboard idle…* means `key_window_s` is on: set it to `0`. *mouse asleep here* means the mouse's Bluetooth was parked at switch time (nothing can reach a sleeping mouse): just move the mouse and it jumps to the other device. |
| Mouse does not come back from the phone | Open the app and look at the log. Make sure battery optimization is off for LogiSync. |
| `--status` says *not found* | The name in the config must be part of the Bluetooth name (`Logi K950`, `MX Anywhere 3`). |
| Remote desktop shows `´a` instead of `á` | Use the *Área de Trabalho Remota* layout variant and enable scancode input in the client. |
| Linux: permission denied | Reconnect the device after installing so the udev rule applies. |

## Contributing

Issues and PRs are welcome, especially test reports for Linux/macOS/iOS and other Logitech
models (paste the output of `python -m logisync --status`). Read
[docs/PROTOCOL.md](docs/PROTOCOL.md) first.

## Disclaimer

Not affiliated with or endorsed by Logitech. "Logitech", "Logi", "Easy-Switch", "MX" and product
names are trademarks of Logitech. LogiSync only sends the same HID++ commands the official software
sends, and never writes firmware. Use at your own risk ([MIT license](LICENSE)).
