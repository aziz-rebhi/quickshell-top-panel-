import glob
import os
import shutil

from .common import log, run


def _nvidia_pcis():
    found = []
    for d in glob.glob("/sys/bus/pci/devices/*"):
        try:
            vendor = open(os.path.join(d, "vendor")).read().strip()
            cls = open(os.path.join(d, "class")).read().strip()
        except Exception:
            continue
        if vendor == "0x10de" and (int(cls, 16) & 0xFF0000) == 0x030000:
            found.append(d)
    return found


def available():
    return shutil.which("nvidia-smi") is not None and bool(_nvidia_pcis())


def _write(path, val):
    try:
        with open(path, "w") as f:
            f.write(val)
        return True
    except Exception as e:
        log(f"gpu: cannot write {path} = {val}: {e}", "WARNING")
        return False


def set_mode(mode, cfg):
    if not available():
        return True, "NVIDIA not present — skipped"
    notes = []
    ok = True
    ctrl = cfg.get("nvidia_control")
    if ctrl:
        for d in _nvidia_pcis():
            if not _write(os.path.join(d, "power/control"), ctrl):
                ok = False
        log(f"gpu: NVIDIA PCI power/control -> {ctrl}")
    pm = cfg.get("nvidia_persistence")
    if pm is not None:
        rc, _out, err = run(["nvidia-smi", "-pm", "1" if pm else "0"])
        if rc != 0:
            notes.append("nvidia-smi -pm failed")
            log(f"gpu: nvidia-smi -pm failed: {err}", "WARNING")
            ok = False
        else:
            log(f"gpu: NVIDIA persistence mode -> {'on' if pm else 'off'}")
    return ok, "; ".join(notes)


def status():
    res = {"present": available(), "runtime_pm": "", "persistence": ""}
    for d in _nvidia_pcis():
        try:
            res["runtime_pm"] = open(os.path.join(d, "power/control")).read().strip()
            break
        except Exception:
            pass
    if available():
        rc, out, _err = run(["nvidia-smi", "--query-gpu=name,persistence_mode",
                             "--format=csv,noheader"])
        if rc == 0 and out:
            name, pm = [x.strip() for x in out.split(",")]
            res["persistence"] = pm.lower()
            res["name"] = name
    return res