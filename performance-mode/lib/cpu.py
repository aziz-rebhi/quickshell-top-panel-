import glob
import os

from .common import load_config, log, run

EPP = {"silent": "power", "balanced": "balanced",
       "performance": "performance", "gaming": "performance", "ai": "performance"}


def _policies():
    d = glob.glob("/sys/devices/system/cpu/cpufreq/policy*")
    if d:
        return sorted(d)
    return sorted(glob.glob("/sys/devices/system/cpu/cpu*/cpufreq"))


def _write(path, val):
    try:
        with open(path, "w") as f:
            f.write(str(val))
        return True
    except Exception as e:
        log(f"cpu: cannot write {path} = {val}: {e}", "WARNING")
        return False


def _has_epp():
    ps = _policies()
    return bool(ps) and os.path.exists(os.path.join(ps[0], "energy_performance_preference"))


def load_fallback(available):
    try:
        cfg = load_config().get("defaults", {}).get("governor_fallback", [])
    except Exception:
        cfg = []
    for g in cfg + ["schedutil", "ondemand", "conservative", "powersave"]:
        if g in available:
            return g
    return available[0] if available else "schedutil"


def set_governor(governor):
    ok = True
    chosen = governor
    for d in _policies():
        avail = ""
        try:
            avail = open(os.path.join(d, "scaling_available_governors")).read()
        except Exception:
            pass
        if avail and chosen not in avail.split():
            fb = load_fallback(avail.split())
            log(f"cpu: governor {chosen} unavailable, using {fb}", "WARNING")
            chosen = fb
        ok &= _write(os.path.join(d, "scaling_governor"), chosen)
    return ok


def set_boost(value):
    w = "1" if value in (True, "1", 1) else "0"
    targets = []
    if os.path.exists("/sys/devices/system/cpu/cpufreq/boost"):
        targets.append("/sys/devices/system/cpu/cpufreq/boost")
    targets += [d + "/boost" for d in _policies() if os.path.exists(d + "/boost")]
    ok = True
    for t in dict.fromkeys(targets):
        ok &= _write(t, w)
    return ok


def set_mode(mode, cfg):
    notes = []
    ok = True
    if _has_epp():
        epp = EPP.get(mode)
        if epp:
            for d in _policies():
                ok &= _write(os.path.join(d, "energy_performance_preference"), epp)
            log(f"cpu: EPP -> {epp}")
    else:
        notes.append("EPP unsupported (acpi-cpufreq, not amd_pstate)")
    governor = cfg.get("governor")
    if governor:
        if not set_governor(governor):
            ok = False
        log(f"cpu: governor -> {governor}")
    boost = cfg.get("boost")
    if boost is not None:
        if not set_boost(boost):
            ok = False
        log(f"cpu: boost -> {'1' if boost else '0'}")
    pp = cfg.get("power_profile")
    if pp:
        rc, _out, err = run(["powerprofilesctl", "set", pp])
        if rc != 0:
            notes.append("power-profiles-daemon not active")
            log(f"cpu: power-profiles-daemon '{pp}' failed: {err}", "WARNING")
        else:
            log(f"cpu: power profile -> {pp}")
    return ok, "; ".join(notes)


def status():
    res = {"driver": "", "governor": "", "boost": "", "epp": ""}
    try:
        res["driver"] = open("/sys/devices/system/cpu/cpu0/cpufreq/scaling_driver").read().strip()
    except Exception:
        pass
    ps = _policies()
    if ps:
        for key, name in (("governor", "scaling_governor"),
                          ("epp", "energy_performance_preference")):
            try:
                res[key] = open(os.path.join(ps[0], name)).read().strip()
            except Exception:
                pass
    try:
        res["boost"] = open("/sys/devices/system/cpu/cpufreq/boost").read().strip()
    except Exception:
        pass
    return res