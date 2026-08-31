import glob


def cpu_temp():
    """k10temp is the trusted sensor (acpitz reads stuck ~100C on this box)."""
    for d in glob.glob("/sys/class/hwmon/hwmon*"):
        try:
            if open(d + "/name").read().strip() == "k10temp":
                return int(open(d + "/temp1_input").read().strip()) / 1000.0
        except Exception:
            continue
    for d in glob.glob("/sys/class/hwmon/hwmon*"):
        for i in range(1, 8):
            try:
                return int(open(f"{d}/temp{i}_input").read().strip()) / 1000.0
            except Exception:
                pass
    return None


def zones():
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