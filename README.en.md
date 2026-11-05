# PodPointer

**Turn your AirPods case into a Mac mouse.**
Rotate the case to move the cursor, tap its front to click.

[中文](README.md)

> Experimental hobby project. Not affiliated with or endorsed by Apple.

## How it works

The charging case has no motion sensors you can read – but the earbuds do, and
when they sit inside the case they move *with* it.

```
 earbuds in the open case ──IMU──▶ CMHeadphoneMotionManager (~50 Hz)
                                          │
              rotation rate ──────────────┼──▶ cursor velocity (CGEvent)
              user acceleration spike ────┘──▶ left click
```

* **Moving** – rotation *rate* drives cursor *velocity* (gyro-mouse style), so there is
  no drift and nothing to re-centre. Yaw is rotation about gravity; pitch is rotation
  about an axis learned once during calibration.
* **Clicking** – a finger tap is a short, sharp acceleration spike after a quiet moment.
  Waving the case is large but smooth and comes with rotation, so it is ignored.
  The click lands where the cursor was ~100 ms *before* the tap jolted the case.
* **Calibration** – hold the case still, then nod it a few times. The result is stored
  per earbud and reused, so normally you only do it once.

## Requirements

* macOS 14 Sonoma or later (headphone motion on the Mac was added in macOS 14).
* AirPods that support **spatial audio with head tracking** (e.g. AirPods 3rd gen and
  later, AirPods Pro, AirPods Max). Older AirPods do not expose motion data.
* Xcode Command Line Tools (`xcode-select --install`) to build.

Developed and tested on macOS 26.5 with one pair of AirPods. Other models that support
head tracking should work but have not been verified – reports welcome.

## Setup

### 1. Turn off Automatic Ear Detection (required)

macOS only streams motion data while the AirPods are an active audio output, and with
ear detection on, buds sitting in the case are never treated as "worn".

*System Settings › (your AirPods) › Automatic Ear Detection* → **off**.

This setting lives on the AirPods, so it also affects your iPhone. Turn it back on
when you are done.

### 2. Build

```bash
git clone https://github.com/chroya/PodPointer.git && cd PodPointer
scripts/setup-signing.sh   # optional but recommended, see below
scripts/build.sh
```

`setup-signing.sh` creates a self-signed code-signing certificate in a **separate**
keychain (your login keychain is not modified). Signing with it gives the app a stable
identity, so the Accessibility permission survives rebuilds. Without it every build is
ad-hoc signed and macOS asks you to re-enable the app after each rebuild.

### 3. Run

```bash
scripts/run.sh
```

On first launch macOS asks for two permissions:

| Permission | Why |
|---|---|
| **Motion & Fitness** | read the AirPods motion sensors |
| **Accessibility** | move the cursor and click (otherwise events are silently dropped) |

A **PP** item appears in the menu bar (`PP⚠︎` = permission missing, `PP●` = pointing).

### 4. Use it

1. Open the case lid, leave the buds inside. PodPointer switches the system audio
   output to the AirPods automatically (disable with `--no-route`).
2. First time only: follow the on-screen guide – hold the case upright and still, then
   nod it (tilt the top back, then forward) 3–4 times.
3. Rotate the case to move the cursor. Hold steady, then tap the front of the case to
   click; tap twice quickly to double-click.

Menu: **Recalibrate** (⌘R) · **Pause / Resume** (⌘P) · **Open Log** · **Accessibility Settings…** · **Quit**.

## Options

Pass options to `scripts/run.sh` (or `open build/PodPointer.app --args …`). None of them
require a rebuild. The options of the last `scripts/run.sh` are remembered and reused when
the app is launched without arguments (e.g. from Finder).

| Option | Default | Description |
|---|---|---|
| `--gain <px/rad>` | 1400 | Pointer speed |
| `--accel <n>` | 0.8 | Extra speed for fast turns |
| `--deadzone <rad/s>` | 0.03 | Ignore hand tremor below this rate |
| `--smooth <0–1>` | 0.35 | Smoothing; higher is snappier but jitterier |
| `--invert-x` / `--invert-y` | off | Flip an axis |
| `--tap <g>` | 0.20 | Minimum tap strength |
| `--jerk <g>` | 0.20 | Minimum suddenness of a tap |
| `--decay <0–1>` | 0.7 | How fast a tap must fade |
| `--quiet-a <g>` / `--quiet-w <rad/s>` | 0.35 / 1.8 | Max movement right before a tap |
| `--no-route` | | Don't switch the audio output to the AirPods |
| `--lang en\|zh` | system | UI language |
| `--probe` | | Diagnostics: log sensor data, never move the cursor |
| `--tap-debug` | | Log every rejected tap candidate and the reason |
| `--hud-demo` | | Show every guide state and save PNGs to `/tmp/podpointer-hud/` |

## Known limitations

* **The lid must stay open.** With the lid closed the sensors keep working, but the
  AirPods drop the Bluetooth link after roughly 15–25 s. Continuously playing inaudible
  audio did not prevent this.
* **Audio output moves to the AirPods** while you use it.
* **Automatic Ear Detection must be off**, which also changes behaviour on your iPhone.
* Motion arrives at ~50 Hz; the cursor is interpolated at 120 Hz, but fine pixel work
  is harder than with a real mouse.
* Tap detection is heuristic. Very soft taps can be missed and vigorous shaking can
  occasionally click – tune with `--tap-debug` and the options above.
* Only left click (single / double / triple). No right click, drag or scroll yet.

## Troubleshooting

| Symptom | Check |
|---|---|
| No motion data, log says *No Bluetooth output device* | Automatic Ear Detection is still on, or the lid is closed |
| Data arrives but the cursor does not move | Accessibility permission. Remove old PodPointer entries, re-add `build/PodPointer.app` |
| Cursor moves the wrong way vertically | Recalibrate (⌘R) – the first nod must be *tilt back*; or use `--invert-y` |
| Taps are missed / phantom clicks | Run with `--tap-debug`, tap a few times, compare the logged values with the options |

Logs: `~/Library/Logs/PodPointer.log` · calibration: `~/Library/Application Support/PodPointer/calibration.json`.
Everything stays on your Mac; PodPointer makes no network connections.

## Project layout

```
Sources/
  main.swift              entry point
  AppDelegate.swift       menu bar item, HUD wiring, --hud-demo
  PointerEngine.swift     motion → calibration → cursor / clicks
  TapDetector.swift       tap-to-click heuristic
  CalibrationStore.swift  per-earbud pitch axis persistence
  AudioRoute.swift        CoreAudio: route output to the AirPods
  Mouse.swift             CGEvent output + Accessibility helpers
  HUD.swift               on-screen guide
  ClickRipple.swift       click feedback
  Config.swift, L10n.swift, Log.swift
scripts/
  build.sh                compile + bundle + sign → build/PodPointer.app
  run.sh                  launch and tail the log
  setup-signing.sh        one-time local signing certificate
  test.sh                 run the TapDetector tests
Tests/
  main.swift              tap detection tests (synthetic waveforms based on real logs)
```

No Xcode project is needed; `swiftc` compiles `Sources/*.swift` directly.
Run `scripts/test.sh` after touching the tap detection.

## Contributing

Issues and pull requests are welcome – especially test reports from other AirPods
models and better tap detection. When reporting a problem, please attach the relevant
part of `~/Library/Logs/PodPointer.log` (ideally captured with `--tap-debug` or `--probe`).

## Trademarks

AirPods is a trademark of Apple Inc., registered in the U.S. and other countries.

## License

[MIT](LICENSE)
