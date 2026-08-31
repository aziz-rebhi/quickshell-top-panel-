import shutil

from .common import log


def ensure(cfg):
    if not cfg.get("use_gamemode"):
        return True, ""
    if shutil.which("gamemoderun"):
        log("gamemode: available — launch games with `gamemoderun` to get the requested boosts")
        return True, "available"
    log("gamemode: not installed; gaming mode continues without it", "WARNING")
    return False, "gamemode not installed"


def effective():
    return "available" if shutil.which("gamemoderun") else "not installed"