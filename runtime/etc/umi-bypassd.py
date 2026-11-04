#!/usr/bin/env python3
# umi: apply the "direct power (bypass battery)" preference chosen in
# Settings > Battery to the smb5 charger. Preference file is written by the
# system-settings QML panel (Qt.labs.settings, ini format, key "bypass").
import time

CONF = "/home/phablet/.config/umi-bypass.conf"
USB_ONLINE = "/sys/class/power_supply/usb/online"
SYS = "/sys/class/power_supply/battery/bypass_charging"


def read_pref():
    try:
        with open(CONF) as f:
            for line in f:
                line = line.strip()
                if line.startswith("bypass="):
                    return line.split("=", 1)[1].strip().lower() in (
                        "true", "1", "yes", "on")
    except FileNotFoundError:
        pass
    except Exception:
        pass
    return True  # default: bypass on (run from USB power)


def usb_online():
    try:
        with open(USB_ONLINE) as f:
            return f.read().strip() == "1"
    except Exception:
        return False


def apply(value):
    try:
        with open(SYS, "w") as f:
            f.write("1\n" if value else "0\n")
        return True
    except Exception:
        return False


last = None
while True:
    # bypass only while external power is present: otherwise the faked
    # full battery would hide a real low battery
    value = read_pref() and usb_online()
    if value != last:
        if apply(value):
            last = value
    time.sleep(1)
