"""Sensor discovery — resolve hwmon / power_supply paths by NAME, not index.

hwmonN numbering is assigned in driver-probe order and changes across
reboots, kernel updates, module reloads and dock attach/detach, so any path
baked in at authoring time (hwmon4, ACAD, BAT0) silently starts reading a
different device or nothing at all. Everything here resolves name -> path
once, caches the result under XDG_CACHE_HOME, and re-resolves as soon as a
cached path disappears or keeps failing to read.

Used by the controller (thermal guard, doctor) and, over
`performance-mode discover --json`, by the Quickshell monitor so both sides
always agree on which sensor is which.
"""

import glob
import hashlib
import json
import os
import time

CACHE_VERSION = 1
# Re-resolve at least this often: catches a hwmon renumber that happened
# while every recorded path still happens to exist (rare, but cheap to rule
# out) and keeps a long-lived `watch` process honest after suspend.
CACHE_TTL = 300.0

# CPU package sensor, most trusted first. k10temp exposes Tctl/Tdie, which is
# what the thermal guard thresholds were tuned against; zenpower is the
# community driver for the same die; coretemp is the Intel equivalent.
CPU_NAMES = ("k10temp", "zenpower", "coretemp", "soc_thermal", "cpu_thermal")
# Integrated GPU. Driver name is amdgpu/radeon for AMD, i915 for Intel.
IGPU_NAMES = ("amdgpu", "radeon", "i915")
# Never accept these as a CPU reading. The fan controller shares the hwmon
# bus, acpitz is pinned near 100C on this laptop, and the rest are unrelated
# devices: a plausible-looking wrong temperature is worse than no reading.
TEMP_DENY = ("acpitz", "acad", "bat", "battery", "nvme", "asus", "it87",
             "nct", "thinkpad", "dell", "hp", "fan")
# Fan controllers worth reading first when several hwmons expose fan inputs.
FAN_PREFER = ("nct", "asus", "hp", "it87")
MAX_FANS = 4

_cache = None
_miss = 0


def cache_path():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(
        os.path.expanduser("~"), ".cache")
    return os.path.join(base, "performance-mode", "sensors.json")


def _read_int(path):
    try:
        with open(path) as f:
            return int(f.read().strip())
    except Exception:
        return None


def _hwmons():
    """[(driver name, dir)] in probe order."""
    out = []
    for d in sorted(glob.glob("/sys/class/hwmon/hwmon*")):
        try:
            with open(os.path.join(d, "name")) as f:
                out.append((f.read().strip().lower(), d))
        except Exception:
            continue
    return out


def _temp_files(d):
    """[(index, path, label)] for every readable temp input under a hwmon."""
    out = []
    for p in sorted(glob.glob(os.path.join(d, "temp*_input"))):
        try:
            idx = int(os.path.basename(p)[len("temp"):-len("_input")])
        except ValueError:
            continue
        label = ""
        try:
            with open(p[: -len("_input")] + "_label") as f:
                label = f.read().strip().lower()
        except Exception:
            pass
        out.append((idx, p, label))
    return out


def _pick_temp(hw, names):
    """(driver name, path) of the best CPU-ish temp input, or ("", "")."""
    for want in names:
        for name, d in hw:
            if name != want:
                continue
            files = _temp_files(d)
            if not files:
                continue
            for pref in ("tctl", "tdie", "package", "cpu", "core"):
                for _idx, p, label in files:
                    if pref in label:
                        return name, p
            return name, files[0][1]
    # No known CPU driver: take the lowest-index reading of any hwmon that is
    # not an explicitly non-CPU device.
    for name, d in hw:
        if any(bad in name for bad in TEMP_DENY):
            continue
        files = _temp_files(d)
        if files:
            return name, files[0][1]
    return "", ""


def _fans(hw):
    out = []
    for name, d in hw:
        for p in sorted(glob.glob(os.path.join(d, "fan*_input"))):
            out.append((name, p))
    out.sort(key=lambda t: (0 if any(t[0].startswith(x) for x in FAN_PREFER)
                            else 1, t[1]))
    return out[:MAX_FANS]


def _power():
    """(mains online paths, battery dir)."""
    mains, bats = [], []
    for d in sorted(glob.glob("/sys/class/power_supply/*")):
        try:
            with open(os.path.join(d, "type")) as f:
                t = f.read().strip().lower()
        except Exception:
            continue
        if t in ("mains", "usb") and os.path.exists(os.path.join(d, "online")):
            mains.append(os.path.join(d, "online"))
        elif t == "battery" and os.path.exists(os.path.join(d, "capacity")):
            bats.append(d)
    return mains, (bats[0] if bats else "")


def _igpu_busy_path(hw, name):
    """amdgpu exposes load on the PCI device, not on the hwmon dir."""
    for n, d in hw:
        if n == name:
            # /sys/class/hwmon/hwmonN -> .../0000:01:00.0/hwmon/hwmonN
            dev = os.path.dirname(os.path.dirname(os.path.realpath(d)))
            if os.path.exists(os.path.join(dev, "gpu_busy_percent")):
                return os.path.join(dev, "gpu_busy_percent")
    for card in sorted(glob.glob("/sys/class/drm/card[0-9]*"))[:8]:
        p = os.path.join(card, "device", "gpu_busy_percent")
        if os.path.exists(p):
            return p
    return ""


def _build():
    hw = _hwmons()
    mains, battery = _power()
    cpu_name, cpu_temp = _pick_temp(hw, CPU_NAMES)
    igpu_name, igpu_temp = _pick_temp(hw, IGPU_NAMES)
    fans = _fans(hw)
    paths = {
        "cpu_temp": cpu_temp,
        "cpu_temp_name": cpu_name,
        "igpu_temp": igpu_temp,
        "igpu_temp_name": igpu_name,
        "igpu_busy": _igpu_busy_path(hw, igpu_name),
        "fans": [p for _n, p in fans],
        "fan_names": [n for n, _p in fans],
        "mains": mains,
        "battery": battery,
        "battery_name": os.path.basename(battery) if battery else "",
    }
    # Signature of the path layout only, so callers can skip work when nothing
    # moved (a poll re-validating the cache should not churn QML state).
    paths["sig"] = hashlib.sha1(json.dumps(
        {k: v for k, v in paths.items() if k != "sig"},
        sort_keys=True).encode()).hexdigest()[:12]
    return paths


def _valid(c):
    if not isinstance(c, dict) or c.get("version") != CACHE_VERSION:
        return False
    for key in ("cpu_temp", "igpu_temp", "igpu_busy", "battery"):
        p = c.get(key) or ""
        if p and not os.path.exists(p):
            return False
    for key in ("fans", "mains"):
        for p in c.get(key) or []:
            if not os.path.exists(p):
                return False
    return True


def _load():
    try:
        with open(cache_path()) as f:
            return json.load(f)
    except Exception:
        return None


def _save(c):
    payload = dict(c)
    payload["version"] = CACHE_VERSION
    payload["generated"] = time.time()
    p = cache_path()
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
        tmp = p + ".tmp"
        with open(tmp, "w") as f:
            json.dump(payload, f, indent=2)
        os.replace(tmp, p)
        c["generated"] = payload["generated"]
    except Exception:
        pass


def discover(force=False):
    """Resolved sensor paths. Re-resolves when the cache expired or a path
    it names has gone away."""
    global _cache
    if not force:
        if _cache is None:
            _cache = _load()
        c = _cache
        if c and (time.time() - c.get("generated", 0)) < CACHE_TTL and _valid(c):
            return c
        c = _build()
        _cache = c
        _save(c)
        return c
    c = _build()
    _cache = c
    _save(c)
    return c


def _read_key(key):
    """Read a discovered int path; after repeated failures re-resolve once.

    A path that keeps failing across polls means the hwmon bus was
    renumbered (reboot, module reload, dock attach) — one forced
    re-discovery, then give up and report no reading rather than guess.
    """
    global _miss
    v = _read_int(discover().get(key) or "")
    if v is not None:
        _miss = 0
        return v
    if _miss < 2:
        _miss += 1
        return None
    _miss = 0
    return _read_int(discover(force=True).get(key) or "")


def cpu_temp_c():
    """CPU package temperature in °C, or None when unreadable."""
    v = _read_key("cpu_temp")
    return v / 1000.0 if v is not None else None


def igpu_temp_c():
    v = _read_key("igpu_temp")
    return v / 1000.0 if v is not None else None


def igpu_busy_pct():
    v = _read_key("igpu_busy")
    return None if v is None else min(100, max(0, v))


def fan_rpm():
    """Highest non-zero fan reading, or None when nothing is readable."""
    best = None
    for p in discover().get("fans") or []:
        v = _read_int(p)
        if v is not None and v > 0:
            best = v if best is None else max(best, v)
    return best


def ac_online():
    """True on AC, False on battery, None when no adapter node is readable."""
    paths = discover().get("mains") or []
    seen = False
    for p in paths:
        v = _read_int(p)
        if v is None:
            continue
        seen = True
        if v == 1:
            return True
    return False if seen else None


def battery_state():
    """(capacity %, status string)."""
    d = discover().get("battery") or ""
    if not d:
        return None, ""
    return _read_int(os.path.join(d, "capacity")), _read_str(
        os.path.join(d, "status"))


def _read_str(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except Exception:
        return ""
