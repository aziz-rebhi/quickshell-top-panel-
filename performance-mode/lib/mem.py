from .common import log

MOVES = {
    "swappiness": "vm/swappiness",
    "page_cluster": "vm/page-cluster",
    "vfs_cache_pressure": "vm/vfs_cache_pressure",
}


def _set(syspath, val):
    path = "/proc/sys/" + syspath
    try:
        with open(path, "w") as f:
            f.write(str(val))
        return True
    except Exception as e:
        log(f"mem: cannot set {syspath} = {val}: {e}", "WARNING")
        return False


def apply(cfg):
    ok = True
    for key, syspath in MOVES.items():
        v = cfg.get(key)
        if v is not None:
            ok &= _set(syspath, v)
            log(f"mem: {syspath} -> {v}")
    return ok


def status():
    res = {}
    for _key, syspath in MOVES.items():
        try:
            res[syspath] = open("/proc/sys/" + syspath).read().strip()
        except Exception:
            pass
    return res