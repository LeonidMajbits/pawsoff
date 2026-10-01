# PawsOff 1.0.0 — Architecture and Build Guide

**Commission:** Stage 1, zero-interruption macOS cat guard and screen curtain.  
**Repository:** `https://github.com/LeonidMajbits/pawsoff`  
**Delivery class:** complete source implementation; native host build/runtime admission verified.

## 1. What is delivered, and what is not claimed

This is a standalone Swift package using AppKit, Carbon, Core Graphics, ApplicationServices and IOKit. All requested filenames are implemented. The ZIP contains the native app source, independently testable input/appearance core, tests, Makefile, local bundle generator, no-clobber installer, verification probes and evidence logs. It has no external package dependency or runtime network dependency.

The authoring environment has Swift 6.2.1 for x86_64 Linux, not an Apple SDK. It successfully ran 63 XCTest cases and 34 finite source-contract checks, syntax-parsed the native Swift, checked shell/Python syntax and ran a small workload-probe self-test. **It did not compile/link AppKit, launch the Mac app, exercise TCC, suppress real HID events, render a curtain, test a fullscreen Space, or run ScreenCaptureKit.** Native API typing and actual system behavior remain host gates, not inferred successes. This version names the source handoff, not a notarized binary release.

Three absolute requirements need an engineering boundary. An ordinary app cannot guarantee suppression of every OS-reserved input path. It cannot guarantee the scheduling/performance of arbitrary other processes. It cannot hide its overlay from an unrelated capture process's unmodified display filter. This implementation addresses ordinary cat input, avoids deliberate focus changes, keeps idle sleep assertions scoped to the curtain, and supplies a supported capture-client exclusion path rather than claiming those absolute guarantees.

## 2. Why a filtering event tap, not a global monitor or key window

Apple distinguishes global event monitors, which observe other apps' events without modifying delivery, from local monitors, which only filter the installing application's event stream [S1]. Merely overriding `keyDown` in an overlay would require that overlay to become the keyboard target; that conflicts with keeping the working application's key window.

PawsOff instead installs an **active** `CGEvent.tapCreate` at `.cgSessionEventTap`, `.headInsertEventTap`, `.defaultTap`. Returning `nil` suppresses an event. The curtain stays non-key/non-main and is ordered with `orderFrontRegardless()`. This is the main architectural choice: visual coverage and event admission are separate mechanisms.

The app checks Accessibility authorization, rejects Secure Event Input, creates the tap, then enumerates taps with `CGGetEventTapList` to verify that the full requested ordinary keyboard/mouse mask survived authorization. Apple's API documentation warns that disallowed event bits can be removed rather than producing an obvious complete failure [S2]. A mouse-only tap must never earn an “Active” badge.

The main required mask includes ordinary key down/up and modifier changes, left/right/other mouse buttons and drags, pointer movement, scrolling and tablet events. A best-effort bit for system-defined media events is also requested, but successful creation does not imply hardware-control coverage. A session filter is not a privileged driver or secure desktop boundary.

## 3. Modules and ownership

| Component | Responsibility and state owner |
|---|---|
| `main.swift` / `InstanceLock` | Acquire a per-user process lock, start an accessory `NSApplication`, retain its delegate |
| `AppDelegate` | Wire settings, menu, shortcut and curtain; launch idle; terminate cleanly |
| `SettingsManager` / `PreferenceStore` | AppKit-facing preference changes; injectable UserDefaults storage |
| `AppearanceSettings` | Clamp percentage values and compute the exact 0.82 maximum tint alpha |
| `MenuBarController` | Paw status item, measured-height visual-effect popover, controls, permission action, status and quit |
| `HotkeyManager` | Carbon global Ctrl+1 registration, matching IDs, repeat latch, explicit registration failure |
| `CurtainController` | Main-thread lifecycle, per-display window map, power lifetime, screen/Space observers, pointer locator |
| `CurtainWindow` | Borderless non-key/non-main full-screen-frame window at `.screenSaver` level |
| `ShieldView` | Frost, tint, badge, visible pointer locator and responder-level input absorption |
| `InputShield` | Dedicated event-tap run loop, permission/mask checks, small lock, lifecycle generation, watchdogs |
| `InputGate` | Deterministic idle/active/draining event policy and paired-release bookkeeping |
| `PowerAssertionManager` | Scoped idle-system/display assertions and the guard's own activity assertion |

AppKit windows, menus and observers are owned by the main thread. The active filter runs on a dedicated high-priority Thread/CFRunLoop, avoiding dependence on a busy AppKit callback for every input decision. Shared gate/resource state has one short `NSLock`; the event callback does not perform file, network, UI or permission work. A lifecycle generation rejects stale asynchronous notifications after a session ends.

The event-tap `userInfo` context has an explicit retained lifetime through its worker; it weakly references the owner. A suppressed callback result remains `nil` all the way to Quartz. Coalescing that result to the original event would defeat the entire shield, so the source audit checks the forwarding form.

## 4. Lifecycle and input semantics

**Idle → arming.** Carbon receives a fresh Ctrl+1, or the menu closes and requests arming. No other application is activated. The controller obtains idle-sleep assertions, creates/verifies the tap and waits for its worker to enable it. Only then does it mark the guard active and show windows. Any setup failure rolls back the tap, windows and power assertions and reports an error. The app does not arm automatically at launch.

**Active.** Routine new keys, click buttons, dragging and wheel events return `nil`. Root view responder methods also swallow those AppKit events if delivered to the curtain. Mouse movement is deliberately passed so the native pointer can move; the overlay absorbs ordinary view-level motion and adds a 30 Hz, position-change-only locator update. System gestures/hot corners and other processes' global monitors are outside an absolute isolation claim.

**Unlock.** The tap recognizes exactly Control plus the physical ANSI 1 key, with no extra Shift/Option/Command/Fn. It also recognizes two fresh, released-between Escape presses, no modifiers, within 650 ms. Holding Escape or autorepeating the activation chord cannot unlock. Modifier changes, other fresh keys, clicks/dragging/scroll break the Escape sequence. Pointer motion does not.

**Draining.** Unlock keyDown is suppressed and asynchronously removes the curtain. The filter remains briefly to absorb the unlock keyUp and any held inputs. It needs a neutral held-key/button/modifier state and at least 100 ms before stopping, checked on the worker's 100 ms timer. The Carbon latch is then reset so the consumed release cannot wedge the next activation. All keys and mouse buttons should be released before starting another session.

**Pre-existing input.** A down that reached the working app before arming may require its matching up to avoid a stuck key or drag. The gate permits those paired releases once. It suppresses the `1` release only when Carbon consumed the activation down; a pre-held ordinary `1` during menu activation is treated differently. Initial ordinary key states and left/right/center button states are sampled. This is a practical transition boundary, not an atomic HID snapshot: events already beyond the tap when arming begins, unusual pre-held auxiliary buttons, and deliberate input races require host testing. Never claim that a source-level state machine can retroactively cancel an already-delivered down.

## 5. Failure behavior and recovery

A tap-disable callback, lost authorization, Secure Event Input or an invalid enabled state triggers **fail-open** teardown. The curtain is removed and the menu reports the reason. This deliberately avoids trapping the operator or presenting a false protected state. Some input may pass during an OS-driven failure/teardown; the badge cannot establish an absolute failure-proof isolation guarantee.

The worker checks a main-thread heartbeat every 100 ms. If the main thread has been absent for more than three seconds, it calls `_exit(70)` on **this process only**; the OS reclaims its windows, event tap and power assertions. The heartbeat is refreshed every 250 ms in common run-loop modes. If release draining lasts over five seconds, input is released with a warning. These bounds are best-effort scheduling thresholds, not real-time deadlines, and neither worker nor UI can run during a whole-process stop or a system freeze.

OS sleep/display-sleep/session-loss notifications disarm the guard. Display discovery failures and zero screens also disarm. Wake/session return never silently rearms. A second process instance is rejected with a per-user `flock` on a cache file rather than installing duplicate taps and shortcuts. The lock file contains no input history.

Recovery is Ctrl+1 or double Escape, then release all controls. From a separate existing Terminal/SSH session, `killall PawsOff` targets only this utility. Any OS lock must be unlocked normally; this is not an authentication bypass.

## 6. Rendering, cursor and display changes

Every active `NSScreen` gets a `CurtainWindow`. It uses the exact full `screen.frame`, not `visibleFrame`, and overrides frame constraining so the Dock/menu-bar strips are not intentionally left exposed. The collection behaviors are `.canJoinAllSpaces`, `.fullScreenAuxiliary` and `.ignoresCycle`. There is no call to macOS fullscreen mode, workspace switching or app hiding.

The view stack is: live `NSVisualEffectView` behind-window material; independent black tint layer; compact status badge; small cursor-location ring. Blur alpha is percent/100, not a blur-radius API [S5]. Tint alpha is percent/100 × 0.82. The code uses a light appearance for the frost material and disables frost when Reduce Transparency is active. That setting must not turn into an opaque black “blur” layer. The alpha cap controls the tint layer; it cannot guarantee a silhouette when the underlying content itself is black or an OS material behaves differently, which is why visual verification is required.

Cursor restoration uses `setHiddenUntilMouseMoves(false)` and the arrow cursor. A synchronous, balanced PawsOff-owned hide/unhide pair brackets window arrangement; it never repeatedly decrements a foreign hide count. Apple's cursor API requires balanced calls [S6]. The visible locator is a fallback for a native cursor hidden by another app; it adds no key-window activation. Its timer is active only while guarding and updates layer position only when necessary.

Display/Space notifications create or resize needed windows before retiring obsolete ones. The input tap remains global across the update. A newly attached display cannot be visually covered before macOS reports it; a hotplug frame gap is possible. Real monitors, mirrored/extended modes, negative coordinate origins, scaled Retina displays, Stage Manager and fullscreen Spaces are host admission cases, not emulated test passes.

## 7. Workload, sleep and capture boundaries

There is no `loginwindow`, screen-lock API, OS sleep call, shell launch, process priority change or persistent power-setting write in the shipped app. It acquires `PreventUserIdleSystemSleep` and `PreventUserIdleDisplaySleep` assertions while active and releases them on lift/failure/exit. Forced sleep and OS policy are different from idle sleep [S3]. An independently configured screensaver or automatic lock remains in force. Power assertions do not authorize disabling organizational security settings.

PawsOff's own `NSProcessInfo` activity and bundle setting keep its guard responsive; they are not a global opt-out for other apps. Apple documents App Nap as dependent on activity and foreground/visibility factors [S4]. Even a focus-preserving translucent overlay has compositing cost. Lab daemons may continue normally while a GUI app makes its own visibility-dependent choice. The honest acceptance criterion is measured throughput/focus continuity on the actual lab, not an unmeasured “100% speed” guarantee.

ScreenCaptureKit supports excluding specified applications/windows [S7, S8]. PawsOff supplies a stable bundle ID and a capture probe that uses this supported filter. Whole-display capture without an exclusion will include the curtain. Window-specific capture should be tested for its specific target. Existing third-party capture clients cannot have their filters rewritten from this app. `NSWindow.sharingType = .none` is deliberately not used as a promise of universal capture invisibility.

The app requests no Screen Recording authorization for its own operation. Only the optional capture probe needs it, and the probe writes no pixels unless an explicit new snapshot path is supplied. `SCShareableContent` query continuity and correct stream content are separate checks; a successful enumeration query alone does not prove that the underlying desktop remained visible in captured frames.

## 8. Build, install and host admission

Extract the archive. Its top-level `Install_to_Workspace.sh` verifies the workspace SHA-256 manifest and copies into a **new** destination; it refuses to overwrite an existing workspace. Default destination matches the commission. This delivery was staged in the authoring container; the installer has not run on Leon's Mac.

Run `make bundle` in the host workspace. It builds the native executable, stages the standard `.app` layout and Info.plist, signs locally and verifies the signature before replacing a prior bundle. It refuses a running PawsOff process and preserves the old bundle until staging succeeds. A rollback path protects a failed final move; this is not a transactional guarantee over a power failure during a local rename.

The bundle is an LSUIElement accessory with identifier `com.leonidmajbits.pawsoff`. No app sandbox entitlement is asserted. Ad-hoc signing is a local development choice, not notarization. Authorize that exact bundle for Accessibility after first launch, then relaunch. Inspect Input Monitoring only when the host requires it or the mask gate fails. A changed ad-hoc binary can invalidate prior authorization; do not hide that fact with an insecure fallback.

Run `make verify` to compile/link and save non-overwriting host build logs. Run `make probes` and `Docs/VERIFICATION.md` for physical input, focus, hotplug/fullscreen, failure and capture/workload checks. A passed build is not a passed runtime matrix. Keep new native evidence separate from `Validation/RESULTS.json`, which records only this delivery's actual Linux checks. Do not edit the original evidence to make it appear as if the host runs happened here.

## 9. Packaging and custody

The source ZIP is `PawsOff_v1.0.0_Source_Bundle.zip`; its external `.sha256` file verifies the archive. The workspace `MANIFEST.sha256` covers source, docs and recorded validation files, excluding itself and build caches. The root manifest also covers the installer and workspace. Neither manifest is a developer signature.

`01_PawsOff_Architecture_and_Build_Guide.md` is a standalone reading copy of this file. `01_Delivery_Receipt.json` is outside the ZIP to avoid a circular archive-hash dependency. The receipt records final artifact hashes, known limitations, environment, Drive IDs and the actually completed readback checks. It does not contain keys, credentials or machine secrets. The destination remains private; no public link-sharing permission is added.

## 10. Primary-source ledger

Retrieved September 24–25, 2026. API availability is bounded by the macOS 13 minimum; current SDK/runtime behavior is still subject to native admission.

- **S1 — Apple, Monitoring Events.** Global observers versus local event filtering. https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/MonitoringEvents/MonitoringEvents.html
- **S2 — Apple, CGEventTapCreate.** Filter/listener distinction, permission-dependent mask removal, callback run-loop ownership. https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)?language=objc
- **S3 — Apple QA1340, Preventing Sleep.** Idle assertions versus forced sleep and assertion release. https://developer.apple.com/library/archive/qa/qa1340/_index.html
- **S4 — Apple, Energy Efficiency Guide: App Nap.** Other-process performance cannot be inferred from a guard's own assertion. https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html
- **S5 — Apple, NSVisualEffectView.** Native visual-effect material, blending and active state. https://developer.apple.com/documentation/appkit/nsvisualeffectview
- **S6 — Apple, NSCursor.unhide.** Balance each unhide with an owned hide. https://developer.apple.com/documentation/appkit/nscursor/unhide()?language=objc
- **S7 — Apple, SCContentFilter.** Capture inclusion/exclusion by applications and windows. https://developer.apple.com/documentation/screencapturekit/sccontentfilter
- **S8 — Apple WWDC22, Meet ScreenCaptureKit.** Official application-exclusion and capture-stream examples. https://developer.apple.com/videos/play/wwdc2022/10156/
- **S9 — Apple WWDC22, Take ScreenCaptureKit to the next level.** Display-filter rules, including new/child windows of filtered apps. https://developer.apple.com/videos/play/wwdc2022/10155/
- **S10 — Apple, NSWindow.orderFrontRegardless.** Ordering an overlay separately from making it key. https://developer.apple.com/documentation/appkit/nswindow/orderfrontregardless()

These references support API decisions. They are not substitutes for build logs or empirical proof of this implementation.
