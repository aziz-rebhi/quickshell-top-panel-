from .common import log, run


def set_fan(speed):
    if speed:  # fixed percent
        rc, _out, err = run(["nbfc", "set", "-s", str(int(speed))])
        if rc != 0:
            log(f"fan: nbfc set -s {int(speed)}% failed: {err}", "WARNING")
            return False
        log(f"fan: fixed {int(speed)}%")
        return True
    rc, _out, err = run(["nbfc", "set", "-a"])
    if rc != 0:
        log(f"fan: nbfc set -a failed: {err}", "WARNING")
        return False
    log("fan: automatic curve")
    return True


def status():
    if not _has_nbfc():
        return "nbfc not installed"
    rc, out, err = run(["nbfc", "status"])
    return out or err or f"rc={rc}"


def _has_nbfc():
    import shutil
    return shutil.which("nbfc") is not None