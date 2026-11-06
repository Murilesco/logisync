# How it works: reverse-engineering notes

Everything here was observed on a **Logi K950** keyboard (BLE PID `B386`) and an **MX Anywhere 3**
mouse (BLE PID `B025`), Windows 11 and a Galaxy S25 Ultra (Android 17), in November 2026.
Other Logitech devices that speak HID++ 2.0 and have Easy-Switch should behave the same way.

## 1. The problem

Easy-Switch keys are handled inside the keyboard firmware. When you press channel 2, the keyboard
drops its Bluetooth link to host 1 and pages host 2. The mouse knows nothing about it.

Logitech's own fix, *Enhanced Easy-Switch* (Logi Options+ 2.3, 2025), only supports a few newer
keyboards and only Windows/macOS, because the switch is driven by Options+ running on each computer:
the computer the keyboard is leaving tells the mouse to follow. LogiSync does the same thing, for any
HID++ device, on any OS where we can run code - including Android.

## 2. Finding the HID++ channel

On Windows each BLE Logitech device exposes a vendor HID collection, usage page `0xFF43`, usage
`0x0202`, using HID++ *long* reports (report id `0x11`, 20 bytes):

```
11  FF  <feature index>  <function << 4 | software id>  <16 parameter bytes>
    ^ device index: 0xFF = the device itself (no receiver)
```

`root.getFeature` (feature index `0x00`, function 0) maps a feature id to its index on that device.
Probe results (read-only):

| Device | `CHANGE_HOST 0x1814` | hosts / current | `REPROG_CONTROLS_V4 0x1B04` |
|---|---|---|---|
| K950 | index `0x0A` | 3 / 0 | Easy-Switch CIDs `0xD1`-`0xD3` have flags `0x00` → **not divertable** |
| MX Anywhere 3 | index `0x0A` | 3 / 0 | - |

So the keyboard cannot tell the computer "channel 2 was pressed" before it leaves. We also captured
every HID collection of the keyboard during a switch: **no packet is sent**, all handles simply fail
at the moment of disconnection.

Conclusion: the trigger is the **Bluetooth disconnection of the keyboard**, and the action is
`CHANGE_HOST.setCurrentHost(n)` (function 1) sent to the mouse while it is still connected.

```
11 FF 0A 1B 01 00 ...   -> mouse jumps to channel 2 immediately (no reply)
          ^^ function 1 | sw id 0x0B
             ^^ host index (0-based)
```

## 3. Telling an Easy-Switch apart from a sleeping keyboard

A disconnection can also mean the keyboard went to sleep, the computer is suspending, or Bluetooth
was turned off. Before moving the mouse, the agent checks:

1. the keyboard is still disconnected after 400 ms;
2. the mouse is still connected (if both vanished, it is the computer's radio, not a switch);
3. the keyboard was typed on recently (Windows only: Raw Input filtered by the keyboard PID,
   default window 10 minutes; the keyboard only sleeps after long inactivity).

## 4. Talking HID++ without a HID driver: the GATT service

Android does not let apps open Bluetooth HID devices, and a phone cannot run Logi Options+.
But both devices also expose a **Logitech vendor GATT service** next to the HID service:

| | UUID |
|---|---|
| Service | `00010000-0000-1000-8000-011F2000046D` |
| Characteristic (read, write, write-without-response, notify) | `00010001-0000-1000-8000-011F2000046D` |

It carries HID++ frames **without the report id and device index** - 18 bytes:

```
<feature index>  <function << 4 | software id>  <16 parameter bytes>
```

Verified from Windows (WinRT GATT) before writing the Android app:

```
write  00 0A 18 14 00...   root.getFeature(0x1814)
notify 00 0A 0A 00 01 ...  -> index 0x0A
write  0A 0A 00 ...        CHANGE_HOST.getHostInfo
notify 0A 0A 03 00 ...     -> 3 hosts, current 0
```

Writes with response returned *ProtocolError* for 20-byte frames; 18-byte frames with
write-without-response work.

An Android app can `connectGatt()` to the mouse while the system HID stack is also connected to it,
enable notifications on that characteristic and send `CHANGE_HOST`. That is what
[`HidppGatt.java`](../android/src/io/github/logisync/HidppGatt.java) does.

## 5. Keeping it alive on Android

* `ACL_CONNECTED` / `ACL_DISCONNECTED` are exempt from the implicit-broadcast ban, so a
  manifest receiver wakes the app on every Bluetooth connection change, even if the process died.
* A `connectedDevice` foreground service keeps the process around; it is (re)started from the
  ACL receiver and from `BOOT_COMPLETED`.
* The app should be excluded from battery optimisation (the app asks for it).
* Phones may keep several stale bonds with the same name (Logitech uses a different address per
  channel and re-pairing creates new ones), so the mouse is chosen by "currently connected", then
  "last seen", then name.

## 6. Physical keyboard layout on Android

Android lets any app ship physical-keyboard layouts: a receiver for
`android.hardware.input.action.QUERY_KEYBOARD_LAYOUTS` pointing to `.kcm` files
(`type OVERLAY`). The user picks it under *Settings → General management → Physical keyboard*
(Samsung) per input method.

[`tools/windows_layout_to_kcm.py`](../tools/windows_layout_to_kcm.py) asks Windows (`ToUnicodeEx`)
what each scan code produces with no modifier, Shift, AltGr and Caps Lock, maps dead keys to
Android combining accents (`´` → `́`, `~` → `̃`, ...), and writes the `.kcm`. The result is
a layout that behaves exactly like the PC - e.g. ABNT2 on a US-printed keyboard, where `;` is `ç`.
