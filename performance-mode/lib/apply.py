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


def requested(cfg):
    """What the mode asked for, in the same vocabulary `effective()` reads
    back. The panel compares the two to show requested-vs-effective; the
    thermal guard never touches this block, so the original intent survives
    every mitigation."""
    def s(v):
        return "" if v is None else str(v)

    boost = cfg.get("boost")
    persist = cfg.get("nvidia_persistence")
    fan_speed = cfg.get("fan_speed")
    return {
        "governor": s(cfg.get("governor")),
        "boost": "" if boost is None else ("1" if boost else "0"),
        "fan_curve": ("Manual %d%%" % int(fan_speed)) if fan_speed else "Automatic",
        "nvidia_runtime_pm": s(cfg.get("nvidia_control")),
        "nvidia_persistence": ("" if persist is None else
                               ("enabled" if persist else "disabled")),
        "power_profile": s(cfg.get("power_profile")),
        "swappiness": s(cfg.get("swappiness")),
        "page_cluster": s(cfg.get("page_cluster")),
        "vfs_cache_pressure": s(cfg.get("vfs_cache_pressure")),
        "gamemode": "available" if cfg.get("use_gamemode") else "",
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
        # `applied` is the coarse summary scripts and `status` read. Recording
        # an optional-but-missing lever as "failed" made `performance-mode
        # status` print "failed: GameMode" and the switch log warn about it,
        # for a switch that in fact succeeded. The detailed `levers` block
        # below still says "unsupported", and `failed` filters on the literal
        # "failed" value, so this only removes the false alarm.
        applied[name] = status
        levers[name] = {"status": status, "note": note or ""}
        log(f"{name}: {status}" + (f" — {note}" if note else ""))
    spec = thermal_spec()
    payload = {
        "mode": mode,
        "previous": prev,
        "applied": applied,
        "levers": levers,
        "requested": requested(m),
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