import json
import os
import subprocess
import sys
import time

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def config_path():
    return os.path.join(BASE, "config", "config.toml")


def load_config():
    import tomllib
    with open(config_path(), "rb") as f:
        return tomllib.load(f)


def run(cmd, timeout=30):
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout)
        return p.returncode, p.stdout.decode().strip(), p.stderr.decode().strip()
    except Exception as e:
        return -1, "", str(e)


def log(msg, level="INFO"):
    line = f"[{time.strftime('%H:%M:%S')}] {level:<7} {msg}"
    print(line, file=sys.stderr)
    try:
        subprocess.run(["logger", "-t", "performance-mode", "--", f"{level}: {msg}"],
                       check=False)
    except Exception:
        pass
    try:
        lf = load_config().get("state", {}).get("log")
        if lf and os.geteuid() == 0 and os.access(os.path.dirname(lf), os.W_OK):
            with open(lf, "a") as f:
                f.write(msg + "\n")
    except Exception:
        pass


def state_path():
    return load_config()["state"]["file"]


def state_read():
    try:
        with open(state_path()) as f:
            return json.load(f)
    except Exception:
        return None


def state_write(payload):
    p = state_path()
    os.makedirs(os.path.dirname(p), exist_ok=True)
    tmp = p + ".tmp"
    with open(tmp, "w") as f:
        json.dump(payload, f, indent=2)
    os.chmod(tmp, 0o644)
    os.replace(tmp, p)


def state_merge(delta):
    """Read the current state, overlay changes, write atomically.
    Used by the thermal guard so mitigation updates don't clobber the
    selected mode or per-lever results written by a user switch."""
    st = state_read() or {}
    st.update(delta)
    state_write(st)
    return st


def state_mode():
    st = state_read()
    return st.get("mode") if st else None


def elevate(argv):
    """Run the subcommand via passwordless sudo if not already root."""
    if os.geteuid() == 0:
        return
    script = os.path.realpath(sys.argv[0])
    cmd = ["sudo", "-n", script] + list(argv)
    log(f"elevating: {' '.join(cmd)}")
    try:
        rc, _out, err = run(cmd)
    except Exception as e:
        print(f"error: could not elevate: {e}", file=sys.stderr)
        sys.exit(2)
    if rc != 0:
        print(f"error: mode switch failed (rc={rc}).", file=sys.stderr)
        if _out.strip():
            print(_out.strip(), file=sys.stderr)
        if err.strip():
            print(err.strip(), file=sys.stderr)
        sys.exit(rc)
    sys.exit(0)