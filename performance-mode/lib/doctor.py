import os
import shutil

from . import cpu, fan, gpu, mem, thermal
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

    print("\n-- Thermal --")
    t = thermal.cpu_temp()
    print(f"cpu_temp(k10temp): {t if t is not None else 'N/A'}°C")
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

    print("\n-- Config --")
    cfg = load_config()
    print(f"modes: {', '.join(cfg['mode'].keys())}")