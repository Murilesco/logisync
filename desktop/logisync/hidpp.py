"""HID++ 2.0 minimal client: find Logitech devices and send CHANGE_HOST (0x1814)."""
import re
import sys
import time

if sys.platform.startswith("linux"):
    try:
        import hidraw as hid  # hidapi's hidraw backend sees Bluetooth devices on Linux
    except ImportError:
        import hid
else:
    import hid

LOGITECH_VID = 0x046D
HIDPP_USAGE_PAGE = 0xFF43
FEATURE_CHANGE_HOST = 0x1814
SW_ID = 0x0B
LONG_REPORT = 0x11
BLE_DEVICE_INDEX = 0xFF


def _norm(s):
    return (s or "").replace("_", " ").lower()


def find(name):
    """Return the hidapi dict of the HID++ interface whose product name contains `name`."""
    for d in hid.enumerate(LOGITECH_VID):
        if _norm(name) in _norm(d.get("product_string")) and d.get("usage_page") == HIDPP_USAGE_PAGE:
            return d
    return None


def bt_address(d):
    """Windows HID paths embed the BLE address: ..._rev&0008_aabbccddeeff&col06..."""
    m = re.search(rb"_([0-9a-f]{12})&col", d["path"], re.I)
    return int(m.group(1), 16) if m else None


def _request(h, feat, fn, *params, wait=True):
    pkt = [LONG_REPORT, BLE_DEVICE_INDEX, feat, (fn << 4) | SW_ID, *params]
    h.write(bytes(pkt + [0] * (20 - len(pkt))))
    if not wait:
        return None
    end = time.time() + 1.5
    while time.time() < end:
        r = h.read(64, 300)
        if r and r[2] == feat and r[3] == ((fn << 4) | SW_ID):
            return r[4:]
        if r and r[2] == 0xFF and r[3] == feat:
            raise IOError(f"HID++ error 0x{r[5]:02x}")
    raise TimeoutError("no HID++ answer")


def _open(d):
    h = hid.device()
    h.open_path(d["path"])
    return h


_feature_index = {}  # HID path -> CHANGE_HOST index, so a switch needs a single write


def _change_host_index(h, d):
    idx = _feature_index.get(d["path"])
    if idx is None:
        idx = _request(h, 0x00, 0, FEATURE_CHANGE_HOST >> 8, FEATURE_CHANGE_HOST & 0xFF)[0]
        if not idx:
            raise IOError("device has no CHANGE_HOST feature")
        _feature_index[d["path"]] = idx
    return idx


def host_info(d):
    """-> (number of hosts, current host index). Also caches the CHANGE_HOST index."""
    h = _open(d)
    try:
        r = _request(h, _change_host_index(h, d), 0)
        return r[0], r[1]
    finally:
        h.close()


def change_host(d, host):
    """host: 0 = channel 1, 1 = channel 2, 2 = channel 3. Call host_info() earlier, while nothing
    is waiting, so this is a single write: a mouse in power saving can take seconds per answer."""
    h = _open(d)
    try:
        _request(h, _change_host_index(h, d), 1, host, wait=False)  # switches at once, never answers
    finally:
        h.close()
