import argparse
import json
import os
import sys
import time

from . import apply, doctor, sensors, thermal
from .common import elevate, load_config, log, state_read, state_write

MODES = ["silent", "balanced", "performance", "gaming", "ai"]

MODE_LABELS = {
    "silent": "Silent",
    "balanced": "Balanced",
    "performance": "Performance",
    "gaming": "Gaming",
    "ai": "AI",
}


def _print_status(json_out):
    from . import cpu, gpu, mem, fan
    st = state_read()
    mode = st.get("mode") if st else None
    data = {
        "mode": mode,
        "available": MODES,
        "cpu": cpu.status(),
        "gpu": gpu.status(),
        "mem": mem.status(),
        "tempC": thermal.cpu_temp(),
        "applied": (st or {}).get("applied"),
        "levers": (st or {}).get("levers"),
        "effective": (st or {}).get("effective"),
        "thermal": (st or {}).get("thermal"),
    }
    if json_out:
        print(json.dumps(data, indent=2))
        return
    th = data.get("thermal") or {}
    if th.get("active"):
        print(f"thermal protection: ACTIVE (stage {th.get('stage')}) — CPU {th.get('last_temp','?')}°C, "
              f"threshold {th.get('threshold')}°C")
    eff = data.get("effective") or {}
    if eff:
        print(f"effective: governor {eff.get('governor')}  boost {eff.get('boost')}  "
              f"nvidia_pm {eff.get('nvidia_runtime_pm')}  fan {eff.get('fan_curve')}")
    print(f"mode: {MODE_LABELS.get(mode, mode or 'none')} ({mode or 'none'})")
    print(f"governor: {data['cpu'].get('governor')}  boost: {data['cpu'].get('boost')}  "
          f"epp: {data['cpu'].get('epp') or '-'}")
    print(f"gpu: {data['gpu'].get('name', 'n/a')}  runtime_pm: {data['gpu'].get('runtime_pm','-')}  "
          f"persistence: {data['gpu'].get('persistence','-')}")
    print(f"mem: swappiness {data['mem'].get('vm/swappiness','?')}, "
          f"page-cluster {data['mem'].get('vm/page-cluster','?')}")
    t = data["tempC"]
    print(f"temp: {t:.0f}°C" if t else "temp: N/A")
    if data.get("applied"):
        failed = [k for k, v in data["applied"].items() if v == "failed"]
        print(f"last apply: {'ALL OK' if not failed else 'failed: ' + ', '.join(failed)}")


def cmd_set(mode):
    mode = mode.strip().lower()
    if mode not in MODES:
        print(f"unknown mode '{mode}'. modes: {', '.join(MODES)}", file=sys.stderr)
        sys.exit(2)
    apply.apply_mode(mode)


def cmd_toggle():
    cur = state_read().get("mode") if state_read() else None
    idx = MODES.index(cur) if cur in MODES else -1
    nxt = MODES[idx + 1] if idx < len(MODES) - 1 else MODES[0]
    print(f"toggling: {cur or 'none'} -> {nxt}")
    apply.apply_mode(nxt)


def cmd_discover(refresh=False, json_out=False):
    """Resolve hwmon / power_supply paths by driver name. Read-only, never
    elevates: the panel calls this instead of hardcoding hwmonN."""
    c = sensors.discover(force=refresh)
    if json_out:
        print(json.dumps(c, indent=2))
        return 0
    print("== sensor discovery ==")
    print(f"cpu temp  : {c.get('cpu_temp') or '(none)'}  [{c.get('cpu_temp_name') or '-'}]")
    print(f"igpu temp : {c.get('igpu_temp') or '(none)'}  [{c.get('igpu_temp_name') or '-'}]")
    print(f"igpu load : {c.get('igpu_busy') or '(none)'}")
    names = c.get("fan_names") or []
    fans = c.get("fans") or []
    if fans:
        for n, p in zip(names, fans):
            print(f"fan       : {p}  [{n}]")
    else:
        print("fan       : (none — hwmon exposes no fan*_input; nbfc is authoritative)")
    print(f"ac        : {', '.join(c.get('mains') or []) or '(none)'}")
    print(f"battery   : {c.get('battery') or '(none)'}  [{c.get('battery_name') or '-'}]")
    print(f"cache     : {sensors.cache_path()}")
    t = thermal.cpu_temp()
    print(f"cpu_temp  : {t:.1f}°C" if t is not None else "cpu_temp  : N/A")
    return 0


def cmd_watch():
    cfg = load_config()
    th = cfg.get("thermal", {})
    t_start = th.get("threshold", 88)
    t_hard = th.get("hard_threshold", 92)
    t_resume = th.get("resume", 82)
    poll = th.get("poll_seconds", 10)
    st = state_read()
    if not st or st.get("mode") not in MODES:
        log("watch: no valid state, restoring balanced", "WARNING")
        apply.apply_mode("balanced")
    log(f"watch: progressive thermal guard (poll {poll}s, mild>{t_start}C, "
        f"hard>{t_hard}C, resume<{t_resume}C)")
    time.sleep(3)
    while True:
        t = thermal.cpu_temp()
        st = state_read() or {}
        mode = st.get("mode") if st.get("mode") in MODES else "balanced"
        tstate = st.get("thermal") or {}
        active = bool(tstate.get("active"))
        stage = tstate.get("stage")
        if mode in apply.HARD_MODES:
            if active:
                if t is not None and t < t_resume:
                    log(f"watch: cooled to {t:.0f}C < {t_resume}C, restoring full {mode}")
                    apply.apply_mode(mode)
                elif stage != "hard" and t is not None and t >= t_hard:
                    log(f"watch: CPU {t:.0f}C >= {t_hard}C in {mode} -> hard mitigation", "WARNING")
                    apply.mitigate(mode, "hard")
            elif t is not None and t >= t_start:
                log(f"watch: CPU {t:.0f}C >= {t_start}C in {mode} -> mild mitigation (boost off)", "WARNING")
                apply.mitigate(mode, "mild")
        else:
            if active:
                log(f"watch: non-hard mode {mode}, clearing mitigation")
                apply.apply_mode(mode)
        time.sleep(poll)


def main():
    p = argparse.ArgumentParser(prog="performance-mode",
                                description="5-mode system performance manager")
    sub = p.add_subparsers(dest="cmd")
    s_status = sub.add_parser("status", help="show current system + mode state")
    s_status.add_argument("--json", action="store_true")
    sub.add_parser("current", help="print the active mode name")
    sub.add_parser("list", help="list available modes")
    sp_set = sub.add_parser("set", help="apply a mode (root)")
    sp_set.add_argument("mode")
    sub.add_parser("toggle", help="cycle to the next mode (root)")
    sub.add_parser("doctor", help="diagnose the system")
    sp_discover = sub.add_parser(
        "discover", help="resolve sensor paths by driver name (read-only)")
    sp_discover.add_argument("--json", action="store_true")
    sp_discover.add_argument("--refresh", action="store_true",
                             help="ignore the cache and re-scan sysfs")
    sub.add_parser("watch", help="restore-on-boot state init (run by systemd, root)")

    a = p.parse_args()
    if a.cmd is None:
        p.print_help()
        return 1
    if a.cmd in ("set", "toggle", "watch") and os.geteuid() != 0:
        elevate(sys.argv[1:])

    if a.cmd == "status":
        _print_status(a.json)
    elif a.cmd == "current":
        st = state_read()
        print(st.get("mode") if st and st.get("mode") in MODES else "none")
    elif a.cmd == "list":
        print("\n".join(MODES))
    elif a.cmd == "set":
        cmd_set(a.mode)
    elif a.cmd == "toggle":
        cmd_toggle()
    elif a.cmd == "doctor":
        doctor.report()
    elif a.cmd == "discover":
        return cmd_discover(refresh=a.refresh, json_out=a.json)
    elif a.cmd == "watch":
        cmd_watch()
    return 0


if __name__ == "__main__":
    sys.exit(main())