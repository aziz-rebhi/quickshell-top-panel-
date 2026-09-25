#!/usr/bin/env python3
"""Desktop app scanner + launcher for Quickshell AppLauncher.

Commands:
  scan              Print JSON array of unique desktop applications
  launch <id>       Launch app by desktop id (basename without .desktop)
  resolve-icon <n>  Print best icon path for a FreeDesktop icon name

Scan priority (highest first — first wins on duplicate id):
  1. ~/.local/share/applications
  2. ~/.local/share/flatpak/exports/share/applications
  3. /var/lib/flatpak/exports/share/applications
  4. /usr/local/share/applications
  5. /usr/share/applications
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home()
DESKTOP_DIRS = [
    HOME / ".local/share/applications",
    HOME / ".local/share/flatpak/exports/share/applications",
    Path("/var/lib/flatpak/exports/share/applications"),
    Path("/usr/local/share/applications"),
    Path("/usr/share/applications"),
]

# Environments we consider "matching" for OnlyShowIn / NotShowIn
CURRENT_DESKTOPS = {
    "Hyprland",
    "hyprland",
    "wlroots",
    "Wayland",
    "GNOME",  # many apps only list GNOME; still show them
    "KDE",
    "XFCE",
    "LXQt",
}

ICON_EXTS = (".svg", ".svgz", ".png", ".webp", ".xpm", ".jpg", ".jpeg", ".ico")
ICON_SIZES = (
    "512x512",
    "512x512@2",
    "256x256",
    "256x256@2",
    "128x128",
    "128x128@2",
    "96x96",
    "72x72",
    "64x64",
    "64x64@2",
    "48x48",
    "48x48@2",
    "36x36",
    "32x32",
    "32x32@2",
    "24x24",
    "22x22",
    "16x16",
    "16x16@2",
    "scalable",
)
ICON_CATEGORIES = (
    "apps",
    "legacy",
    "devices",
    "mimetypes",
    "status",
    "places",
    "categories",
    "preferences",
    "emblems",
    "emotes",
    "actions",
    "intl",
)
ICON_ALIASES = {"hwloc": "utilities-system-monitor"}


def parse_desktop(path: Path) -> dict | None:
    """Parse a .desktop file into a dict. Returns None if it should be hidden."""
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None

    # Only care about the main [Desktop Entry] group
    entry: dict[str, str] = {}
    in_entry = False
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            in_entry = line == "[Desktop Entry]"
            continue
        if not in_entry:
            continue
        if "=" not in line:
            continue
        key, _, val = line.partition("=")
        key = key.strip()
        # Prefer unlocalized keys; first wins for localized
        if key not in entry:
            entry[key] = val.strip()

    if entry.get("Type", "Application") != "Application":
        return None
    if entry.get("NoDisplay", "").lower() in ("true", "1"):
        return None
    if entry.get("Hidden", "").lower() in ("true", "1"):
        return None

    only = entry.get("OnlyShowIn", "")
    if only:
        tags = {t.strip() for t in only.split(";") if t.strip()}
        if tags and not (tags & CURRENT_DESKTOPS):
            return None

    not_show = entry.get("NotShowIn", "")
    if not_show:
        tags = {t.strip() for t in not_show.split(";") if t.strip()}
        # Hide only if explicitly excluded for Hyprland/wlroots
        if tags & {"Hyprland", "hyprland", "wlroots"}:
            return None

    name = entry.get("Name") or entry.get("GenericName")
    if not name:
        return None

    desktop_id = path.stem  # without .desktop
    exec_line = entry.get("Exec", "").strip()
    try_exec = entry.get("TryExec", "").strip()
    if try_exec:
        # Absolute path or on PATH
        if try_exec.startswith("/"):
            if not Path(try_exec).exists():
                return None
        elif not shutil.which(try_exec):
            return None

    icon = entry.get("Icon", "").strip() or "application-x-executable"
    terminal = entry.get("Terminal", "").lower() in ("true", "1")
    dbus = entry.get("DBusActivatable", "").lower() in ("true", "1")
    categories = [c for c in entry.get("Categories", "").split(";") if c]
    keywords = [k for k in entry.get("Keywords", "").split(";") if k]
    generic = entry.get("GenericName", "")
    comment = entry.get("Comment", "")

    # Detect flatpak from path or Exec
    is_flatpak = (
        "flatpak" in str(path)
        or exec_line.startswith("flatpak ")
        or "/flatpak/" in exec_line
    )

    return {
        "id": desktop_id,
        "name": name,
        "genericName": generic,
        "comment": comment,
        "icon": icon,
        "exec": exec_line,
        "terminal": terminal,
        "dbus": dbus,
        "categories": categories,
        "keywords": keywords,
        "path": str(path),
        "flatpak": is_flatpak,
        "source": _source_label(path),
    }


def _source_label(path: Path) -> str:
    s = str(path)
    if "flatpak" in s and str(HOME) in s:
        return "flatpak-user"
    if "flatpak" in s:
        return "flatpak-system"
    if str(HOME) in s:
        return "user"
    return "system"


def scan() -> list[dict]:
    """Scan all desktop dirs; first occurrence of each id wins (priority order)."""
    seen: set[str] = set()
    apps: list[dict] = []
    # Also dedupe by lowercase name when id differs (firefox vs org.mozilla.firefox)
    name_seen: dict[str, str] = {}  # lower(name) -> id kept

    for d in DESKTOP_DIRS:
        if not d.is_dir():
            continue
        try:
            files = sorted(d.glob("*.desktop"))
        except OSError:
            continue
        for f in files:
            app = parse_desktop(f)
            if not app:
                continue
            aid = app["id"]
            if aid in seen:
                continue
            nkey = app["name"].casefold()
            # Prefer flatpak / user over system for same display name
            if nkey in name_seen:
                prev_id = name_seen[nkey]
                # Already kept a higher-priority entry
                continue
            seen.add(aid)
            name_seen[nkey] = aid
            apps.append(app)

    apps.sort(key=lambda a: a["name"].casefold())
    return apps


def _icon_roots() -> list[Path]:
    """Return icon roots in user-first, system-second lookup order."""
    roots: list[Path] = []
    data_home = os.environ.get("XDG_DATA_HOME")
    if data_home:
        roots.append(Path(data_home) / "icons")

    roots.extend(
        [
            HOME / ".local/share/icons",
            HOME / ".icons",
            HOME / ".local/share/flatpak/exports/share/icons",
            Path("/var/lib/flatpak/exports/share/icons"),
            Path("/usr/local/share/icons"),
            Path("/usr/share/icons"),
            Path("/usr/local/share/pixmaps"),
            Path("/usr/share/pixmaps"),
        ]
    )

    for data_dir in os.environ.get("XDG_DATA_DIRS", "").split(":"):
        if data_dir:
            roots.append(Path(data_dir) / "icons")

    unique: list[Path] = []
    seen: set[str] = set()
    for root in roots:
        key = str(root)
        if key not in seen:
            seen.add(key)
            unique.append(root)
    return unique


def _icon_theme_dirs(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    if root.name == "pixmaps":
        return [root]
    try:
        dirs = [p for p in root.iterdir() if p.is_dir()]
    except OSError:
        return []

    priority = {
        "hicolor": 0,
        "Adwaita": 10,
        "AdwaitaLegacy": 11,
        "breeze": 20,
        "breeze-dark": 21,
        "HighContrast": 30,
    }
    return sorted(dirs, key=lambda p: (priority.get(p.name, 50), p.name))


def _find_icon_recursive(directory: Path, base: str) -> str:
    """Find an icon in non-standard theme subdirectories."""
    try:
        for current, _, files in os.walk(directory):
            for filename in files:
                for ext in ICON_EXTS:
                    if filename == f"{base}{ext}":
                        path = Path(current) / filename
                        if path.is_file():
                            return str(path)
    except OSError:
        pass
    return ""


def resolve_icon(name: str) -> str:
    """Resolve a FreeDesktop icon name or path to a usable image path."""
    if not name:
        return ""

    if name.startswith("file://"):
        name = name[7:]
    direct = Path(name).expanduser()
    if direct.is_file():
        return str(direct)

    base = Path(name).name
    for ext in ICON_EXTS:
        if base.lower().endswith(ext):
            base = base[: -len(ext)]
            break

    candidates = [base]
    alias = ICON_ALIASES.get(base)
    if alias and alias not in candidates:
        candidates.append(alias)
    if base.endswith("-symbolic"):
        plain = base[: -len("-symbolic")]
        if plain not in candidates:
            candidates.append(plain)
    else:
        symbolic = f"{base}-symbolic"
        if symbolic not in candidates:
            candidates.append(symbolic)

    roots = _icon_roots()
    for candidate in candidates:
        for root in roots:
            if root.name == "pixmaps":
                for ext in ICON_EXTS:
                    path = root / f"{candidate}{ext}"
                    if path.is_file():
                        return str(path)
                continue

            for theme_dir in _icon_theme_dirs(root):
                for size in ICON_SIZES:
                    for ext in ICON_EXTS:
                        for category in ICON_CATEGORIES:
                            path = theme_dir / size / category / f"{candidate}{ext}"
                            if path.is_file():
                                return str(path)
                        path = theme_dir / size / f"{candidate}{ext}"
                        if path.is_file():
                            return str(path)

                found = _find_icon_recursive(theme_dir, candidate)
                if found:
                    return found

    # Some desktop entries reference icons that are not installed. Keep the
    # launcher visually complete with a standard fallback instead of a blank
    # image.
    for fallback in ("application-x-executable", "preferences-desktop"):
        for root in roots:
            if root.name == "pixmaps":
                for ext in ICON_EXTS:
                    path = root / f"{fallback}{ext}"
                    if path.is_file():
                        return str(path)
                continue
            for theme_dir in _icon_theme_dirs(root):
                for size in ICON_SIZES:
                    for ext in ICON_EXTS:
                        for category in ICON_CATEGORIES:
                            path = theme_dir / size / category / f"{fallback}{ext}"
                            if path.is_file():
                                return str(path)
                        path = theme_dir / size / f"{fallback}{ext}"
                        if path.is_file():
                            return str(path)
                found = _find_icon_recursive(theme_dir, fallback)
                if found:
                    return found
    return ""


def expand_exec(exec_line: str) -> list[str]:
    """Parse Exec= into argv, dropping field codes and respecting quotes."""
    # Remove field codes: %f %F %u %U %i %c %k %% etc.
    cleaned = re.sub(r"%[fFuUdDnNickvm]", "", exec_line)
    cleaned = cleaned.replace("%%", "%")
    # Tokenize with simple quote support
    tokens: list[str] = []
    buf: list[str] = []
    in_quote: str | None = None
    i = 0
    while i < len(cleaned):
        ch = cleaned[i]
        if in_quote:
            if ch == in_quote:
                in_quote = None
            elif ch == "\\" and i + 1 < len(cleaned):
                buf.append(cleaned[i + 1])
                i += 1
            else:
                buf.append(ch)
        else:
            if ch in ('"', "'"):
                in_quote = ch
            elif ch.isspace():
                if buf:
                    tokens.append("".join(buf))
                    buf = []
            else:
                buf.append(ch)
        i += 1
    if buf:
        tokens.append("".join(buf))
    return [t for t in tokens if t]


def launch(desktop_id: str) -> int:
    """Launch application by desktop id. Exit code 0 on success."""
    # Find the .desktop file (same priority as scan)
    desktop_path: Path | None = None
    for d in DESKTOP_DIRS:
        candidate = d / f"{desktop_id}.desktop"
        if candidate.is_file():
            desktop_path = candidate
            break

    if desktop_path is None:
        print(f"desktop-apps: not found: {desktop_id}", file=sys.stderr)
        return 1

    app = parse_desktop(desktop_path)
    if not app:
        print(f"desktop-apps: hidden or invalid: {desktop_id}", file=sys.stderr)
        return 1

    # 1) Flatpak
    if app["flatpak"]:
        # Prefer desktop id as flatpak app id when it looks like reverse-DNS
        if "." in desktop_id and not desktop_id.startswith("."):
            r = subprocess.run(
                ["flatpak", "run", desktop_id],
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            if r.returncode == 0:
                return 0
        # Fall through to Exec

    # 2) DBus activation
    if app["dbus"]:
        # org.freedesktop.Application interface
        bus_name = desktop_id
        try:
            r = subprocess.run(
                [
                    "gdbus",
                    "call",
                    "--session",
                    "--dest",
                    bus_name,
                    "--object-path",
                    "/" + bus_name.replace(".", "/"),
                    "--method",
                    "org.freedesktop.Application.Activate",
                    "{}",
                ],
                start_new_session=True,
                capture_output=True,
                timeout=5,
            )
            if r.returncode == 0:
                return 0
        except (FileNotFoundError, subprocess.TimeoutExpired, OSError):
            pass

    # 3) gtk-launch
    if shutil.which("gtk-launch"):
        r = subprocess.run(
            ["gtk-launch", desktop_id],
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if r.returncode == 0:
            return 0

    # 4) Parse Exec=
    argv = expand_exec(app["exec"])
    if not argv:
        print(f"desktop-apps: empty Exec for {desktop_id}", file=sys.stderr)
        return 1

    if app["terminal"]:
        term = (
            os.environ.get("TERMINAL")
            or os.environ.get("TERMCMD")
            or shutil.which("ghostty")
            or shutil.which("kitty")
            or shutil.which("alacritty")
            or shutil.which("foot")
            or shutil.which("xterm")
        )
        if term:
            argv = [term, "-e", *argv]

    try:
        subprocess.Popen(
            argv,
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            cwd=HOME,
        )
        return 0
    except OSError as e:
        print(f"desktop-apps: launch failed: {e}", file=sys.stderr)
        return 1


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: desktop-apps.py scan|launch <id>|resolve-icon <name>", file=sys.stderr)
        return 2
    cmd = sys.argv[1]
    if cmd == "scan":
        apps = scan()
        # Lightweight payload for QML (icons resolved lazily)
        out = [
            {
                "id": a["id"],
                "name": a["name"],
                "genericName": a["genericName"],
                "comment": a["comment"],
                "icon": a["icon"],
                "categories": a["categories"],
                "keywords": a["keywords"],
                "flatpak": a["flatpak"],
                "terminal": a["terminal"],
                "source": a["source"],
            }
            for a in apps
        ]
        json.dump(out, sys.stdout, ensure_ascii=False, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0
    if cmd == "launch":
        if len(sys.argv) < 3:
            print("usage: desktop-apps.py launch <id>", file=sys.stderr)
            return 2
        return launch(sys.argv[2])
    if cmd == "resolve-icon":
        if len(sys.argv) < 3:
            print("usage: desktop-apps.py resolve-icon <name>", file=sys.stderr)
            return 2
        path = resolve_icon(sys.argv[2])
        print(path)
        return 0 if path else 1
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
