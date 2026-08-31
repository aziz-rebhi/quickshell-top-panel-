import argparse
import json
import os
import sys
import time

from . import apply, doctor, thermal
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
    cfg = load_config()
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
        "watchdog": cfg.get("watchdog", {}),
    }
    if json_out:
        print(json.dumps(data, indent=2))
        return
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


def cmd_watch():
    cfg = load_config()
    w = cfg.get("watchdog", {})
    thresh = w.get("threshold", 88)
    poll = w.get("poll_seconds", 10)
    revert = w.get("revert_to", "balanced")
    st = state_read()
    if not st or st.get("mode") not in MODES:
        log(f"watch: no valid state, restoring {revert}", "WARNING")
        apply.apply_mode(revert)
    log(f"watch: monitoring CPU temp (threshold {thresh}°C, poll {poll}s, revert -> {revert})")
    while True:
        t = thermal.cpu_temp()
        st = state_read()
        m = st.get("mode") if st else revert
        if m != revert and m in MODES and t is not None and t >= thresh:
            log(f"watch: CPU {t:.0f}°C >= {thresh}°C in {m} -> force-revert to {revert}", "WARNING")
            apply.apply_mode(revert)
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
    sub.add_parser("watch", help="state-restore + thermal watchdog loop (root)")

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
    elif a.cmd == "watch":
        cmd_watch()
    return 0


if __name__ == "__main__":
    sys.exit(main())