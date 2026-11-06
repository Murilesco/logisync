"""Remembers when the keyboard was last typed on, so a keyboard that merely went to sleep
is not mistaken for an Easy-Switch press. Implemented with Raw Input on Windows; other
platforms report 'just now' (guard disabled)."""
import sys
import threading
import time


class KeyGuard:
    def __init__(self, keyboard_pid=None, log=print):
        self.last = time.time()
        self.pid = keyboard_pid
        self.log = log

    def idle_seconds(self):
        return time.time() - self.last

    def start(self):
        if sys.platform == "win32" and self.pid:
            self.last = 0.0
            threading.Thread(target=self._win_loop, daemon=True).start()

    def _win_loop(self):
        import ctypes
        import ctypes.wintypes as wt

        user32 = ctypes.WinDLL("user32", use_last_error=True)
        kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        WM_INPUT, RID_INPUT, RIDI_DEVICENAME, RIM_TYPEKEYBOARD, RIDEV_INPUTSINK = 0x00FF, 0x10000003, 0x20000007, 1, 0x100
        WNDPROC = ctypes.WINFUNCTYPE(ctypes.c_ssize_t, wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM)
        user32.DefWindowProcW.argtypes = [wt.HWND, wt.UINT, wt.WPARAM, wt.LPARAM]
        user32.DefWindowProcW.restype = ctypes.c_ssize_t
        user32.GetRawInputData.argtypes = [wt.HANDLE, wt.UINT, wt.LPVOID, ctypes.POINTER(wt.UINT), wt.UINT]
        user32.GetRawInputDeviceInfoW.argtypes = [wt.HANDLE, wt.UINT, wt.LPVOID, ctypes.POINTER(wt.UINT)]
        user32.CreateWindowExW.restype = wt.HWND
        user32.CreateWindowExW.argtypes = [wt.DWORD, wt.LPCWSTR, wt.LPCWSTR, wt.DWORD, ctypes.c_int, ctypes.c_int,
                                           ctypes.c_int, ctypes.c_int, wt.HWND, wt.HMENU, wt.HINSTANCE, wt.LPVOID]
        kernel32.GetModuleHandleW.restype = wt.HMODULE
        kernel32.GetModuleHandleW.argtypes = [wt.LPCWSTR]

        class RAWINPUTHEADER(ctypes.Structure):
            _fields_ = [("dwType", wt.DWORD), ("dwSize", wt.DWORD), ("hDevice", wt.HANDLE), ("wParam", wt.WPARAM)]

        class RAWINPUTDEVICE(ctypes.Structure):
            _fields_ = [("usUsagePage", wt.USHORT), ("usUsage", wt.USHORT), ("dwFlags", wt.DWORD), ("hwndTarget", wt.HWND)]

        class WNDCLASSW(ctypes.Structure):
            _fields_ = [("style", wt.UINT), ("lpfnWndProc", WNDPROC), ("cbClsExtra", ctypes.c_int),
                        ("cbWndExtra", ctypes.c_int), ("hInstance", wt.HINSTANCE), ("hIcon", wt.HICON),
                        ("hCursor", wt.HANDLE), ("hbrBackground", wt.HBRUSH), ("lpszMenuName", wt.LPCWSTR),
                        ("lpszClassName", wt.LPCWSTR)]

        cache = {}
        tag = f"pid&{self.pid:04x}"

        def is_keyboard(hdev):
            if hdev not in cache:
                n = wt.UINT(0)
                user32.GetRawInputDeviceInfoW(hdev, RIDI_DEVICENAME, None, ctypes.byref(n))
                buf = ctypes.create_unicode_buffer(n.value + 1)
                user32.GetRawInputDeviceInfoW(hdev, RIDI_DEVICENAME, buf, ctypes.byref(n))
                cache[hdev] = tag in buf.value.lower()
            return cache[hdev]

        def wndproc(hwnd, msg, wp, lp):
            if msg == WM_INPUT:
                sz = wt.UINT(0)
                user32.GetRawInputData(wt.HANDLE(lp), RID_INPUT, None, ctypes.byref(sz), ctypes.sizeof(RAWINPUTHEADER))
                buf = ctypes.create_string_buffer(sz.value)
                user32.GetRawInputData(wt.HANDLE(lp), RID_INPUT, buf, ctypes.byref(sz), ctypes.sizeof(RAWINPUTHEADER))
                hdr = RAWINPUTHEADER.from_buffer_copy(buf)
                if hdr.dwType == RIM_TYPEKEYBOARD and hdr.hDevice and is_keyboard(hdr.hDevice):
                    self.last = time.time()
            return user32.DefWindowProcW(hwnd, msg, wp, lp)

        self._proc = WNDPROC(wndproc)
        hinst = kernel32.GetModuleHandleW(None)
        wc = WNDCLASSW(lpfnWndProc=self._proc, lpszClassName="LogiSyncRaw", hInstance=hinst)
        user32.RegisterClassW(ctypes.byref(wc))
        hwnd = user32.CreateWindowExW(0, "LogiSyncRaw", "LogiSync", 0, 0, 0, 0, 0, None, None, hinst, None)
        rid = RAWINPUTDEVICE(0x01, 0x06, RIDEV_INPUTSINK, hwnd)
        if not user32.RegisterRawInputDevices(ctypes.byref(rid), 1, ctypes.sizeof(rid)):
            self.log(f"raw input unavailable ({ctypes.get_last_error()}); key guard disabled")
            self.last = float("inf")
        msg = wt.MSG()
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) > 0:
            user32.TranslateMessage(ctypes.byref(msg))
            user32.DispatchMessageW(ctypes.byref(msg))
