import time

from . import cpu, fan, gamemode, gpu, mem, thermal
from .common import load_config, log, state_merge, state_mode, state_write

HARD_MODES = {"performance", "gaming", "ai"}

STEPS = [
    ("CPU", lambda mode, cfg: cpu.set_mode(mode, cfg)),
    ("GPU", lambda mode, cfg: gpu.set_mode(mode, cfg)),
    ("Fan", lambda mode, cfg: fan.set_fan(cfg.get("fan_speed") or 0)),
    ("Memory", lambda mode, cfg: mem.apply(cfg)),
    ("GameMode", lambda mode, cfg: gamemode.ensure(cfg)),
]


def _classify(ok, note):
    if ok:
        return "ok"
    nl = (note or "").lower()
    if any(k in nl for k in ("unsupported", "not installed", "not present",
                             "unavailable", "skipped", "failed: epp")):
        return "unsupported"
    return "failed"


def ppd_current():
    from .common import run
    rc, out, _err = run(["powerprofilesctl", "get"])
    if rc == 0 and out.strip():
        return out.strip()
    return ""


def effective():
    """Real, current hardware policy read back from sysfs / drivers —
    not what a mode asked for. This is the source of truth for the
    'effective policy' section of the panel."""
    c = cpu.status()
    g = gpu.status()
    m = mem.status()
    return {
        "governor": c.get("governor") or "",
        "boost": c.get("boost") or "",
        "epp": c.get("epp") or "",
        "nvidia_runtime_pm": g.get("runtime_pm") or "",
        "nvidia_persistence": g.get("persistence") or "",
        "power_profile": ppd_current(),
        "gamemode": gamemode.effective(),
        "fan_curve": fan.effective(),
        "swappiness": m.get("vm/swappiness") or "",
        "page_cluster": m.get("vm/page-cluster") or "",
        "vfs_cache_pressure": m.get("vm/vfs_cache_pressure") or "",
    }


def thermal_spec():
    try:
        t = load_config().get("thermal", {})
    except Exception:
        t = {}
    return {
        "threshold": t.get("threshold", 88),
        "hard_threshold": t.get("hard_threshold", 92),
        "resume": t.get("resume", 82),
    }


def apply_mode(mode):
    cfg = load_config()
    m = cfg["mode"].get(mode)
    if m is None:
        raise SystemExit(f"unknown mode: {mode}")
    prev = state_mode()
    log(f"switching {prev or 'none'} -> {mode}")
    applied, levers = {}, {}
    for name, fn in STEPS:
        try:
            ok, note = fn(mode, m)
        except Exception as e:
            ok, note = False, str(e)
        status = _classify(ok, note)
        applied[name] = "ok" if ok else "failed"
        levers[name] = {"status": status, "note": note or ""}
        log(f"{name}: {status}" + (f" — {note}" if note else ""))
    spec = thermal_spec()
    payload = {
        "mode": mode,
        "previous": prev,
        "applied": applied,
        "levers": levers,
        "effective": effective(),
        "thermal": {
            "active": False,
            "stage": None,
            "threshold": spec["threshold"],
            "hard_threshold": spec["hard_threshold"],
            "resume": spec["resume"],
            "since": None,
            "last_temp": None,
            "note": "",
        },
        "time": time.time(),
    }
    state_write(payload)
    failed = [k for k, v in applied.items() if v == "failed"]
    unsupported = [k for k, v in levers.items() if v["status"] == "unsupported"]
    if failed:
        log(f"mode switch finished with failures: {', '.join(failed)}", "WARNING")
    if unsupported:
        log("mode switch notes: " + ", ".join(unsupported), "WARNING")
    if not failed:
        log(f"mode switch complete -> {mode} (prev {prev or 'none'})")
    return payload


def mitigate(mode, stage):
    """Progressive thermal guard for hard modes.
    - stage None: clear mitigation, re-apply the full selected mode.
    - stage 'mild': disable CPU boost (light easing).
    - stage 'hard': disable boost and ease the governor to schedutil.
    The selected mode name is preserved in state; only the effective levers
    change, so the panel can show requested-vs-effective with a reason."""
    spec = thermal_spec()
    if stage is None:
        return apply_mode(mode)
    notes = []
    if stage in ("mild", "hard"):
        if not cpu.set_boost(False):
            notes.append("boost off failed")
        else:
            notes.append("boost disabled")
    if stage == "hard":
        if cpu.set_governor("schedutil"):
            notes.append("governor eased to schedutil")
        else:
            notes.append("governor easing failed")
    return state_merge({
        "effective": effective(),
        "thermal": {
            "active": True,
            "stage": stage,
            "threshold": spec["threshold"],
            "hard_threshold": spec["hard_threshold"],
            "resume": spec["resume"],
            "since": time.time(),
            "last_temp": thermal.cpu_temp(),
            "note": ", ".join(notes),
        },
        "time": time.time(),
    })