import shutil

from .common import log


def ensure(cfg):
    if not cfg.get("use_gamemode"):
        return True
    if shutil.which("gamemoderun"):
        log("gamemode: available — launch games with `gamemoderun` to get the requested boosts")
    else:
        log("gamemode: not installed; gaming mode continues without it", "WARNING")
    return True