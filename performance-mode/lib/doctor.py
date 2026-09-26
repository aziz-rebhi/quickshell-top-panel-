import os
import shutil

from . import cpu, fan, gpu, mem, sensors, thermal
from .common import load_config, run, state_mode


def report():
    print("== performance-mode doctor ==")
    print(f"state: {state_mode() or '(none yet — run `performance-mode set balanced`)'}")

    print("\n-- CPU --")
    st = cpu.status()
    for k, v in st.items():
        print(f"{k}: {v}")
    if st.get("driver") == "intel_pstate":
        print("tip: intel_pstate is fine on extended model CPUs.")
    elif "amd_pstate" in st.get("driver", ""):
        print("tip: active mode uses EPP; silent/balanced map to power/balanced EPP.")
    else:
        print("note: acpi-cpufreq driver — governors only. amd_pstate would add EPP "
              "(add amd_pstate=active to kernel cmdline).")

    print("\n-- GPU --")
    g = gpu.status()
    if not g.get("present"):
        print("present: NO (nvidia-smi or NVIDIA PCI device missing)")
    else:
        print(f"name/temp: {g.get('name', '?')}  runtime_pm: {g.get('runtime_pm')}  "
              f"persistence: {g.get('persistence')}")

    print("\n-- Memory --")
    for k, v in mem.status().items():
        print(f"{k}: {v}")

    print("\n-- Sensors (discovered by driver name, not hwmon index) --")
    s = sensors.discover()
    print(f"cpu temp : {s.get('cpu_temp') or 'NONE'}  [{s.get('cpu_temp_name') or '-'}]")
    print(f"igpu temp: {s.get('igpu_temp') or 'NONE'}  [{s.get('igpu_temp_name') or '-'}]")
    print(f"igpu load: {s.get('igpu_busy') or 'NONE'}")
    fans = s.get("fans") or []
    print("fan rpm  : " + (", ".join(fans) if fans
                           else "NONE (hwmon has no fan*_input — nbfc only)"))
    print(f"ac       : {', '.join(s.get('mains') or []) or 'NONE'}")
    print(f"battery  : {s.get('battery') or 'NONE'}  [{s.get('battery_name') or '-'}]")
    cap, bstat = sensors.battery_state()
    print(f"battery now: {cap if cap is not None else 'N/A'}% {bstat or ''}")
    ac = sensors.ac_online()
    print(f"ac now   : {'on' if ac else ('off' if ac is False else 'N/A')}")
    for p in [s.get("cpu_temp"), s.get("igpu_temp"), s.get("battery")] + fans:
        if p and not os.path.exists(p):
            print(f"STALE: {p} no longer exists — re-run with --refresh")

    print("\n-- Thermal --")
    t = thermal.cpu_temp()
    print(f"cpu_temp({s.get('cpu_temp_name') or 'unresolved'}): {t if t is not None else 'N/A'}°C")
    for name, idx, v in thermal.zones():
        print(f"zone {name} temp{idx}: {v:.0f}°C")

    print("\n-- Fan --")
    print(fan.status())

    print("\n-- Power services --")
    for s in ["power-profiles-daemon.service", "tlp.service", "tuned.service",
              "auto-cpufreq.service", "thermald.service", "nvidia-powerd.service",
              "nvidia-persistenced.service", "performance-mode.service"]:
        rc, _o, err = run(["systemctl", "is-active", s])
        print(f"{s}: {'active' if rc == 0 else ('inactive' if 'inactive' in err else err.strip() or 'n/a')}")

    print("\n-- Protections --")
    for s in ["earlyoom", "systemd-oomd"]:
        if shutil.which(s):
            print(f"{s}: present")
    if os.path.exists("/usr/lib/systemd/system/systemd-zram-setup@.service"):
        print("zram: systemd-zram-setup@ present")
    run(["swapon", "--show"], timeout=5)
    rc, out, _ = run(["swapon", "--show"])
    print(out or "--")

    print("\n-- Helper binaries --")
    for b in ["nvidia-smi", "nbfc", "powerprofilesctl", "gamemederun",
              "gamemoded"]:
        p = shutil.which(b)
        note = ""
        if not p:
            note = "MISSING"
        elif b == "nvidia-smi":
            rc, out, _e = run(["nvidia-smi", "-L"], timeout=5)
            note = "no GPU reported" if rc != 0 else "ok"
        elif b == "nbfc":
            rc, out, _e = run(["nbfc", "status"], timeout=5)
            note = "ok" if rc == 0 else f"status rc={rc}"
        elif b == "powerprofilesctl":
            rc, out, _e = run(["powerprofilesctl", "get"], timeout=5)
            note = out.strip() if rc == 0 else f"rc={rc}"
        print(f"{b}: {p or 'not installed'} {note}")

    print("\n-- Config --")
    cfg = load_config()
    print(f"modes: {', '.join(cfg['mode'].keys())}")