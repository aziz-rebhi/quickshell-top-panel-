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


def _set_governor(governor):
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


def load_fallback(available):
    try:
        cfg = load_config().get("defaults", {}).get("governor_fallback", [])
    except Exception:
        cfg = []
    for g in cfg + ["schedutil", "ondemand", "conservative", "powersave"]:
        if g in available:
            return g
    return available[0] if available else "schedutil"


def set_mode(mode, cfg):
    ok = True
    if _has_epp():
        epp = EPP.get(mode)
        if epp:
            for d in _policies():
                ok &= _write(os.path.join(d, "energy_performance_preference"), epp)
            log(f"cpu: EPP -> {epp}")
    governor = cfg.get("governor")
    if governor:
        _set_governor(governor)
        log(f"cpu: governor -> {governor}")
    boost = cfg.get("boost")
    if boost is not None:
        w = "1" if boost else "0"
        targets = []
        if os.path.exists("/sys/devices/system/cpu/cpufreq/boost"):
            targets.append("/sys/devices/system/cpu/cpufreq/boost")
        targets += [d + "/boost" for d in _policies() if os.path.exists(d + "/boost")]
        for t in dict.fromkeys(targets):
            _write(t, w)
        log(f"cpu: boost -> {w}")
    pp = cfg.get("power_profile")
    if pp:
        rc, _out, err = run(["powerprofilesctl", "set", pp])
        if rc != 0:
            log(f"cpu: power-profiles-daemon '{pp}' failed: {err}", "WARNING")
        else:
            log(f"cpu: power profile -> {pp}")
    return ok


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