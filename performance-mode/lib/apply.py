import time

from . import cpu, fan, gamemode, gpu, mem
from .common import load_config, log, state_mode, state_write

STEPS = [
    ("CPU", lambda mode, cfg: cpu.set_mode(mode, cfg)),
    ("GPU", lambda mode, cfg: gpu.set_mode(mode, cfg)),
    ("Memory", lambda mode, cfg: mem.apply(cfg)),
    ("Fan", lambda mode, cfg: fan.set_fan(cfg.get("fan_speed") or 0)),
    ("GameMode", lambda mode, cfg: gamemode.ensure(cfg)),
]


def apply_mode(mode):
    cfg = load_config()
    m = cfg["mode"].get(mode)
    if m is None:
        raise SystemExit(f"unknown mode: {mode}")
    prev = state_mode()
    log(f"switching {prev or 'none'} -> {mode}")
    results = {}
    for name, fn in STEPS:
        try:
            ok = fn(mode, m)
            results[name] = "ok" if ok else "failed"
            if not ok:
                log(f"{name}: reported failure", "WARNING")
        except Exception as e:
            results[name] = "failed"
            log(f"{name}: {e}", "WARNING")
    payload = {"mode": mode, "previous": prev, "applied": results, "time": time.time()}
    state_write(payload)
    failed = [k for k, v in results.items() if v == "failed"]
    if failed:
        log(f"mode switch finished with failures: {', '.join(failed)}", "WARNING")
    else:
        log(f"mode switch complete -> {mode} (prev {prev or 'none'})")
    return payload