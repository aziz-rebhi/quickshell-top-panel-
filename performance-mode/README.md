# performance-mode

5-mode system performance manager for the HP Pavilion 15-ec1xxx (Ryzen 7 4800H + GTX 1650 Ti).

Lives inside the quickshell config. The QML island/ControlCenter read the shared state file and
call the CLI; the CLI applies policy as root via a scoped NOPASSWD sudoers entry.

## Modes

| Mode | Governor | Boost | NVIDIA runtime-PM | Persistence | Fan | Swappiness |
|---|---|---|---|---|---|---|
| silent | powersave | off | auto | off | 30% | 100 |
| balanced | schedutil | on | auto | off | auto | 100 |
| performance | performance | on | on | off | 90% | 60 |
| gaming | performance | on | on | on | 95% | 60 |
| ai | schedutil | on | on | on | 90% | 120 |

All modes set `vm.page-cluster=0`. Gaming additionally honors GameMode when installed.

`power-profiles-daemon` is kept in sync (`power-saver` / `balanced`) so it never fights the
sysfs writes. Since ppd has no performance profile, performance/gaming/ai set sysfs directly.

## CLI

```
performance-mode status [--json]   # current state from sysfs + last applied
performance-mode current           # active mode name (for scripts/QML)
performance-mode list
performance-mode set <mode>        # apply (auto-elevates via sudo)
performance-mode toggle            # cycle to next mode
performance-mode discover [--json] [--refresh]   # resolve sensor paths by driver name (read-only)
performance-mode doctor            # full system diagnosis
performance-mode watch             # restore-on-boot state init (run by systemd)
```

`discover` is read-only and never elevates. It resolves hwmon / power_supply
paths by driver *name* (`k10temp`/`zenpower`/`coretemp`, `amdgpu`, any hwmon
with `fan*_input`, `type=Mains`/`type=Battery`) and caches the result in
`$XDG_CACHE_HOME/performance-mode/sensors.json`. The cache is re-validated on
every read and rebuilt when a recorded path disappears, so `hwmonN` renumbering
after a reboot heals itself instead of silently reading the wrong chip. The
Quickshell monitor calls it once and interpolates the resolved paths into its
own probe, so the panel and the controller can never disagree about which
sensor is which.

## Install

```sh
sudo ./performance-mode/install.sh
```

This installs:
- `/etc/sudoers.d/performance-mode` — NOPASSWD for `set <mode>` and `toggle` only, on this script
- `/usr/local/bin/performance-mode` — symlink
- `performance-mode.service` (systemd, root) — restores the last mode at boot if the state is
  missing/invalid; no thermal watchdog, modes are never auto-changed during use

## QML integration

- `Widgets/mode/ModeService.qml` — thin client: polls `/var/lib/performance-mode/state.json`
  (1.2s while the Performance page is open or a switch is applying, 6s otherwise), calls the
  CLI for set/cycle. No QML-side state logic.
- `Widgets/mode/MonitorService.qml` — live hardware probe. Sensor paths come from
  `discover --json`, not from hardcoded `hwmonN`; poll rate follows page visibility
  (2s active, 8s idle). Unreadable sensors report as unavailable, never as a value.
- `controlCenter/pages/ModePage.qml` — 5 mode cards, live bars, requested→effective
  readback, per-lever results, diagnostics, switch history.
- `shell.qml` — `Alt+F5` / `/tmp/qs-mode-cycle` → `cycleMode()` (cycles all 5).

## Safety rules (baked in)

- Never disables zram, earlyoom, networking, audio, Wayland, NVMe, or stops critical services.
- Every step is idempotent and reversible; an unsupported feature logs a WARNING and continues.
- The thermal guard never rewrites the selected mode: it eases the *effective* policy and leaves
  the `requested` block in `state.json` intact, so the original intent survives every mitigation.
- CPU temperature comes only from a recognised CPU driver. `acpitz` (stuck ~100°C on this
  laptop), `nvme`, and fan-controller hwmons are explicitly excluded from the fallback.

## Security note

`install.sh` grants passwordless sudo for this script only, but the script is user-writable in
`~/.config/quickshell`. Anyone who can modify the repo gets root. Acceptable tradeoff for this
single-user machine; do not install it on a multi-user/shared box.

## Customizing

All per-mode values live in `config/config.toml`. Add/remove a mode by editing the `[mode.*]`
sections; unknown keys are ignored, missing ones are skipped. Labels/icons for the UI live in
`ModePage.qml` and `ClockWidget.qml`.

## Uninstall

```sh
sudo systemctl disable --now performance-mode.service
sudo rm /etc/systemd/system/performance-mode.service /etc/sudoers.d/performance-mode /usr/local/bin/performance-mode
sudo systemctl daemon-reload
```