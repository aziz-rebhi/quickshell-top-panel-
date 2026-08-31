import shutil

from .common import log, run


def _has_nbfc():
    return shutil.which("nbfc") is not None


def set_fan(speed):
    if not _has_nbfc():
        return False, "nbfc not installed"
    if speed:  # fixed percent
        rc, _out, err = run(["nbfc", "set", "-s", str(int(speed))])
        if rc != 0:
            log(f"fan: nbfc set -s {int(speed)}% failed: {err}", "WARNING")
            return False, "nbfc set failed"
        log(f"fan: fixed {int(speed)}%")
        return True, ""
    rc, _out, err = run(["nbfc", "set", "-a"])
    if rc != 0:
        log(f"fan: nbfc set -a failed: {err}", "WARNING")
        return False, "nbfc set failed"
    log("fan: automatic curve")
    return True, ""


def effective():
    """What the fan controller is doing right now: Automatic / Manual curve / n/a."""
    if not _has_nbfc():
        return "n/a"
    rc, out, err = run(["nbfc", "status"])
    if rc != 0:
        return "n/a"
    for line in out.splitlines():
        if line.startswith("Status:"):
            st = line.split(":", 1)[1].strip()
            return st
    return "n/a"


def status():
    if not _has_nbfc():
        return "nbfc not installed"
    rc, out, err = run(["nbfc", "status"])
    return out or err or f"rc={rc}"


def effective():
    """What the fan controller is doing right now: Automatic / Manual N% / n/a.
    nbfc owns the fan curve, so this is the authoritative cooling policy."""
    if not _has_nbfc():
        return "n/a"
    rc, out, err = run(["nbfc", "status"])
    if rc != 0:
        return "n/a"
    auto = ""
    speed = ""
    for line in out.splitlines():
        if line.startswith("Auto Control Enabled"):
            auto = line.split(":", 1)[1].strip()
        elif line.startswith("Current Fan Speed"):
            speed = line.split(":", 1)[1].strip()
    if auto.lower() == "true":
        return "Automatic"
    if speed:
        try:
            return f"Manual {float(speed):.0f}%"
        except ValueError:
            pass
    return "Manual"


def fan_pct():
    """Live fan speed percentage from the EC via nbfc (sysfs rpm is 0 on this
    laptop). Returns None when nbfc is unavailable or reports nothing."""
    if not _has_nbfc():
        return None
    rc, out, err = run(["nbfc", "status"])
    if rc != 0:
        return None
    for line in out.splitlines():
        if line.startswith("Current Fan Speed"):
            try:
                return float(line.split(":", 1)[1].strip())
            except ValueError:
                return None
    return None