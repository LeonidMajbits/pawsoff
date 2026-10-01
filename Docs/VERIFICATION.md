# Native admission matrix — do not mark source checks as hardware passes

Current record: **all native runtime rows below are NOT RUN in the authoring environment.** Write actual host results into a new `Validation/host-.../` directory, including macOS version, Mac model/architecture, display arrangement, input devices, signing identity class and permission state. Record failures, not just final passes. Keep the delivery's original evidence intact.

## A. Compile and package

```bash
cd pawsoff
make verify
make probes
open -g dist/PawsOff.app
```

Expect the native executable and bundle/signature checks to pass, and 63 core XCTest cases plus 34 static checks. Linux `swift test` does not build AppKit. `make verify` does not run this manual matrix, and probe compilation has its own `make probes` gate. Use the actual compiler error if a host SDK rejects an API spelling; do not replace the tap with a listen-only monitor to obtain a green build.

## B. Permission and shortcut admission

With permission absent, try Ctrl+1 and the menu button. The app must leave all displays uncovered and explain why. Grant Accessibility to the exact bundle and relaunch. Check the full keyboard/mouse mask gate. If it fails, inspect Input Monitoring; do not accept partial protection. In Terminal enable Secure Keyboard Entry and confirm arming is refused; restore its prior state afterward. First establish a working escape path before any prolonged input test.

Exercise Ctrl+1 from Finder, an editor, Terminal and a fullscreen ordinary application. Verify one press arms, release/repress disarms; a long held activation chord does not immediately toggle back. Check Mission Control/Desktop 1 shortcut conflicts. With an intentional registration conflict, the menu should still arm after permission and double Escape should dismiss. Remove the conflict manually and relaunch; PawsOff must not edit OS shortcuts.

## C. Safe input and focus probe

```bash
dist/probes/focus-probe 180 > /tmp/pawsoff-focus.ndjson &
dist/probes/input-probe > /tmp/pawsoff-input.ndjson
```

The input probe intentionally opens/focuses its own harmless window and logs aggregate event counts, its own key-window/active flags and heartbeat. It does not store typed characters. Focus it, release all controls, then arm PawsOff with Ctrl+1. The original probe should remain the foreground application and retain its key window through the curtain's active interval; normal Settings/permission UI interactions are excluded from this focus experiment.

| Case | Acceptance evidence |
|---|---|
| Ordinary letter/digit keys, space, return, backspace, arrow keys | No new keyDown counts while active; no edited document is involved |
| Key releases and modifiers | No newly pressed key reaches the probe; documented pre-arming/neutral paired releases are allowed |
| Left/right/auxiliary clicks, drag, wheel/trackpad scrolling | No new corresponding probe counts while active |
| Ctrl+C, Ctrl+D, Cmd+Q/W, Cmd+Tab and OS-reserved shortcuts | Record actual results; required ordinary-app protection must pass, reserved bypasses must be recorded rather than hidden |
| Holding Escape or a repeating key | Does not trigger a two-press escape sequence |
| Two released-between Escapes within 650 ms | Curtain disappears; its Escape keyUp does not leak as a new action |
| Two Escapes over 650 ms apart, or interrupted by a click/key | Does not dismiss |
| Ctrl+1 with Shift/Option/Command/Fn | Does not match the unlock chord |
| Keep a normal key held, then request exit with Ctrl+1 | Curtain lifts; held-key releases drain; input resumes only when neutral or the five-second safety cap fires |
| Menu activation with an ordinary pre-held `1` | Its paired release is not left stuck; global activation is separately tested |
| Mouse pointer travel and hidden-cursor foreground app | Pointer location stays visible; no cursor-hide-count accumulation across 100 cycles |

Avoid real shell/editor data during initial tests. To end the harmless input probe, dismiss PawsOff, return to its launching Terminal and press Ctrl+C. Focus-probe sampling cannot prove microsecond ordering or keyboard focus inside a foreign app; the probe's own `isKeyWindow`/active state adds a direct bounded check. For the lab's real UI, log that application's own activation/key-window signals where available.

## D. Appearance, topology and transitions

Set both sliders to 0, 50 and 100; verify stored values across process restarts. At 100% tint, verify the numeric mapping is 0.82 and the desktop is not deliberately replaced by opaque black. Inspect dark/light desktop content, Reduce Transparency and multiple appearance modes. Verify all popover controls remain visible even with a multi-line permission/failure message. The exact system material and visual silhouette need eyes-on testing; the math test alone is not rendering verification.

Test a single monitor; two extended monitors; mixed Retina/scaling; negative display-coordinate origins; display rotation; mirror mode; fullscreen apps on different Spaces; Stage Manager on/off if used. Connect/disconnect a display while guarded, then reattach it; all reported screens must be covered without losing the tap or requiring app activation. The new monitor may show a frame before its screen notification. Disconnect every display/dock and verify the guard disarms, not traps the next session. Record any protected/system UI above the app window separately.

Toggle at least 100 times. Confirm no multiplying windows, growing live worker-thread count, stuck modifier, leaked power assertion or stale Carbon latch. The pure-core thousand-cycle test does not replace this native resource-lifetime run.

## E. Failure recovery and sleep policy

Prepare a separate SSH connection or Terminal recovery path before inducing failures. Revoke Accessibility while active and verify the curtain is removed with a failure message. Enable Secure Input from another test process and observe the same behavior. Tap timeout testing should be done with a debugger in an expendable session, not by deliberately hanging a working terminal under the guard. Observe fail-open behavior and document any event leakage during the transition.

Stall only the AppKit main thread under a debugger while allowing the event-tap worker to run: the process should terminate after its heartbeat threshold, releasing windows/filter/assertions. Suspending the whole process does **not** test that watchdog; neither thread can run then. It is acceptable and expected that a user recovery command/OS termination is needed for whole-process suspension.

Compare `pmset -g assertions` before, during and after guarding. Only PawsOff's scoped idle-system/display assertions should appear/disappear. No persistent power/security setting may change. Test the existing screensaver/auto-lock interval and record that it can still take effect; this utility must not bypass organizational security policy. Test explicit lock, sleep and session switch in a safe context: the guard must be off on return. Do not expect it to prevent lid/thermal/forced sleep or to replace the OS password step after an independent OS lock.

## F. Capture and workload continuation

Follow `Docs/SCREEN_CAPTURE.md` for unmodified-display control versus PawsOff-excluded capture. Check successful repeated shareable-content queries **and** the actual captured image/stream scene while guarded. Test each real lab capture client, because the utility cannot change a client's filter by itself. A pass on the standalone probe does not silently configure Gemini's capture pipeline.

For an optional single-process CPU/file-heartbeat baseline:

```bash
python3 Tools/workload_probe.py --seconds 90 --label baseline \
  --heartbeat-dir /tmp/pawsoff-heartbeat-baseline > /tmp/pawsoff-baseline.ndjson
# In a separate run, arm the curtain after the probe starts and leave it active.
python3 Tools/workload_probe.py --seconds 90 --label curtain \
  --heartbeat-dir /tmp/pawsoff-heartbeat-curtain > /tmp/pawsoff-curtain.ndjson
```

Use new heartbeat directories and new log filenames for repeated runs. The probe atomically replaces `heartbeat.json` once per bucket; attach the real file watcher and verify continuing callbacks. It deliberately occupies a CPU core; do not confuse probe overhead with PawsOff overhead. Its short Linux self-test is only script validation.

Alternate baseline/curtain order over several repeats with identical workload, AC power, thermal state and capture settings. Compare completed tasks/sec or tokens/sec for the real lab, watcher gaps, probe bucket times, Activity Monitor App Nap state and system load. Choose an allowed regression threshold **before** inspecting results. Zero measured regression within that test's precision is not a universal 100%-speed guarantee. No runtime performance threshold has been passed in this source handoff.

## Native release decision

Promote only after build, ordinary input, unlock, focus, actual display topology, fail-open behavior, cleanup and the lab's required capture/workload path pass on the target Mac. Record known OS-reserved bypasses and retained auto-lock policy. Reject unattended use when the full event mask is unavailable, native input leaks, focus changes, capture sees the curtain unexpectedly, or workloads miss the chosen performance boundary.
