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
performance-mode doctor            # full system diagnosis
performance-mode watch             # restore-on-boot + thermal watchdog (run by systemd)
```

## Install

```sh
sudo ./performance-mode/install.sh
```

This installs:
- `/etc/sudoers.d/performance-mode` — NOPASSWD for `set <mode>` and `toggle` only, on this script
- `/usr/local/bin/performance-mode` — symlink
- `performance-mode.service` (systemd, root) — restores the last mode at boot and force-reverts
  to **balanced** when CPU ≥ **88°C** (configurable in `config/config.toml` under `[watchdog]`)

## QML integration

- `Widgets/mode/ModeService.qml` — thin client: reads `/var/lib/performance-mode/state.json`,
  calls the CLI for set/cycle. No QML-side watchdog anymore (controller owns it).
- `controlCenter/pages/ModePage.qml` — 5 mode cards.
- `shell.qml` — `Alt+F5` / `/tmp/qs-mode-cycle` → `cycleMode()` (cycles all 5).

## Safety rules (baked in)

- Never disables zram, earlyoom, networking, audio, Wayland, NVMe, or stops critical services.
- Every step is idempotent and reversible; an unsupported feature logs a WARNING and continues.
- No automatic switching in v1 except the thermal watchdog revert.
- k10temp is the trusted temp sensor (acpitz reads a stuck ~100°C on this laptop).

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