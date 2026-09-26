import glob

from . import sensors


def cpu_temp():
    """CPU package temperature in °C from the discovered k10temp / zenpower /
    coretemp hwmon. Never falls back to an unrelated sensor: a wrong but
    plausible temperature is worse than no reading (the guard would ease the
    policy for a hot GPU). Returns None when nothing is readable."""
    return sensors.cpu_temp_c()


def zones():
    """Every readable hwmon temperature, for `doctor`. Diagnostic only —
    callers must not use this as the CPU temperature."""
    out = []
    for d in glob.glob("/sys/class/hwmon/hwmon*"):
        try:
            name = open(d + "/name").read().strip()
        except Exception:
            continue
        for i in range(1, 8):
            try:
                v = int(open(f"{d}/temp{i}_input").read().strip())
                out.append((name, i, v / 1000.0))
            except Exception:
                pass
    return out
