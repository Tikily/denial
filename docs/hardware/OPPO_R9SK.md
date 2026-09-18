# OPPO R9s/k (`oppo-r9sk`) mobile test host

A Debian-based OPPO R9s/k (Qualcomm msm8953 / Snapdragon 625) running Denial as
its mobile shell. This host demonstrates the same cross-compiled ARM64 Denial
deployment as the Moto Edge 70 (`roadstr`), on a simpler, portrait-only panel
with no under-display fingerprint sensor and no hardware double-tap wake.

## Hardware (probed 2026-09-18, host `qcom-8953`)

- SoC: Qualcomm msm8953, AArch64 (`aarch64`), kernel
  `6.19.5-msm8953-kily`.
- Display controller: Adreno/msm_dpu through
  `platform-1a01000.display-controller`, exposed as `/dev/dri/card0` and
  `/dev/dri/renderD128`.
- Connector: `card0-DSI-1` (DSI, no EDID), the only output. Fixed portrait
  mode 1080x1920; enabled and connected.
- Panel driver/module: `panel_oppo16027jdi_r63452` (JDI R63452).
- Touch: Synaptics s3320 on `0-0020` (rmi4), input node `event3`.
- Buttons: gpio-keys, pm8941_pwrkey, pm8941_resin.

## Configuration

Files in `/etc/denial/` are root-owned and follow `packaging/arch/`. The
notable mobile selections are:

- `session.conf`: `DENIAL_SHELL_PROFILE=mobile` (or `DENIA_SHELL_PROFILE`).
  The PC package defaults to the desktop shell; the mobile profile must be
  selected explicitly for this host's shell.
- `outputs.conf`: use `dev/denial-outputs-oppo-r9sk.conf`. The desktop system
  bar is hidden because the mobile shell draws its own status/navigation bars.

## Differences from the Moto Edge 70

| Capability | Roadstr (`roadstr`) | OPPO R9s/k (`oppo-r9sk`) |
| --- | --- | --- |
| Connector | `DSI-1` | `DSI-1` |
| Panel | `csot_nt37706_667_1220x2712` | JDI R63452 |
| Native mode | 1220x2712 | 1080x1920 portrait |
| Under-display fingerprint (FOD) | JIIOV jv0307, HBM illumination | none (no `/etc/denial/fingerprint.json`) |
| Hardware double-tap wake | BTN_TRIGGER_HAPPY6 (709) | none (no `/etc/denial/wake-gesture.json`) |

`fingerprint.json` and `wake-gesture.json` are deliberately absent on this
host: the presentation worker and wake gesture decoder both require device
hardware that the R9s/k does not ship. The shared Flutter mobile scene,
session flow and output pipeline are the same software used on Roadstr.

## Starting a session (tty1)

There is no display manager on this host. The compositor must be started from
the physical tty1 login with an active logind/session-bus context so the
launcher and native service integration can activate:

```sh
loginctl activate-session "$(loginctl show-user kily -p Display --value)"
exec systemd-run --user --scope denial-session
```

A bare `denial-session` started from a getty prompt without a user D-Bus
socket produces four non-fatal environment errors but still presents the
shell: `could not activate the compositor session environment` (ENOENT on the
session bus), `could not own org.freedesktop.Notifications`, `XDG_SESSION_ID
is required`, and `logind SetBrightness ... Your session has no seat`. The
brightness provider registers the kernel backlight but cannot write it until a
seat session owns the display. Two startup `MissingAuthorization` backing-store
messages are a transient first-frame race and resolve once the authorized
render pipeline takes over.