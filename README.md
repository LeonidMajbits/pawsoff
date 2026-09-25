# PawsOff: Zero-Interruption macOS Cat Guard & Screen Curtain

> "Engineered under the Triadic Sovereign Development Architecture: Leonid Majbits (Vision & Invariants) · Gemini Operator Lab (ZION Chassis Execution & Verification) · Frontier Systems Models (Synthesis & Stress-Testing)."

**A native macOS menu-bar cat guard, not an OS screen lock.** Drops an interactive frosted, dimmed curtain across active displays to block stray keystrokes, trackpad bumps, clicks, drags, and scrolling without making curtain windows key or stealing focus. Return instantly with **Ctrl+1** or **two distinct Escape presses within 650 ms**. No password required.

Unlike standard macOS lock screens (`Cmd+Ctrl+Q`) or sleep modes, PawsOff **holds user-space power assertions to prevent idle display and system sleep without locking credentials, keeping active daemons, compilation loops, and background processes unhindered by idle sleep interrupts**.

---

## Key Capabilities

- **Zero-Disruption Architecture**: Acquires `kIOPMAssertPreventUserIdleDisplaySleep` and `kIOPMAssertPreventUserIdleSystemSleep` assertions so background daemons, compilers, and inference engines continue running without idle sleep interruptions.
- **Input Shielding via Active Session Tap**: Installs an active `CGEvent.tapCreate` at `.cgSessionEventTap` to filter routine keyboard, mouse, click, drag, and scroll events before target-application delivery.
- **Visual Frosted Curtain**: Spans all active displays (`NSScreen.screens`) with borderless `.screenSaver`-level windows that remain non-key and non-main.
- **Adjustable Blur & Tint**:
  * **Blur Slider** (0–100%): Adjusts `NSVisualEffectView` frosted glass material opacity.
  * **Tint Slider** (0–100%): Linearly adjusts darkening from $0.0$ to $0.82$. Strictly capped at $82\%$ black so mouse cursor position and display silhouette remain comfortably visible.
- **Stealth Mode HUD**: Optional setting in menu popover to suppress on-screen unlock cards for a completely unobtrusive, frosted backdrop.
- **Multi-Monitor Dynamic Re-Anchoring**: Automatically handles display connect/disconnect events and Spaces transitions.
- **Fail-Open Safety & Dual Recovery**:
  * **Global Hotkey**: Carbon-registered `Ctrl+1` chord instantly toggles the shield.
  * **Double-Tap Escape**: Two discrete Escape key presses within 650 ms immediately dismiss the curtain.
  * **Fail-Open Policy**: If Secure Event Input activates or event tap permissions are revoked, PawsOff fails open and removes the curtain rather than trapping the operator.
- **Zero Third-Party Dependencies**: Pure Swift 5.9+ standard library, AppKit, Carbon, CoreGraphics, ApplicationServices, and IOKit.

---

## Quick Start & Installation

Requires macOS 13.0+ (Ventura, Sonoma, Sequoia) on Apple Silicon or Intel, with Xcode Command Line Tools installed.

### 1. Build and Bundle Locally

```bash
# Clone repository
git clone https://github.com/LeonidMajbits/pawsoff.git
cd pawsoff

# Compile release binary and assemble PawsOff.app bundle
make bundle

# Launch the app
open -g dist/PawsOff.app
```

### 2. Grant Accessibility Permission

1. Click the **PawsOff** menu-bar icon in your macOS status bar.
2. Select **Grant Accessibility…**.
3. Authorize `PawsOff.app` in **System Settings → Privacy & Security → Accessibility**.
4. Quit and relaunch PawsOff once authorized.

---

## Make Commands

| Command | Action |
| :--- | :--- |
| `make build` | Compiles native release executable via `swift build -c release` |
| `make bundle` | Compiles release binary, creates `dist/PawsOff.app`, and applies ad-hoc codesign |
| `make run` | Builds bundle and opens `dist/PawsOff.app` in background |
| `make test` | Runs core policy and preference unit tests via `swift test` |
| `make verify` | Runs native macOS verification suite and logs host evidence |
| `make probes` | Compiles optional focus, input, and ScreenCaptureKit verification probes |
| `make clean` | Removes `.build` and `dist` build directories |

---

## Operating Boundaries & Scope

1. **Cat Guard & Physical Input Shield**: PawsOff is designed to prevent physical accidents (cats walking across mechanical keyboards, stray elbow bumps, accidental trackpad brushes). It is **not** a cryptographically secure kiosk or password-protected security boundary. Anyone who knows the `Ctrl+1` or double-Esc shortcut can dismiss it.
2. **ScreenCaptureKit Cooperation**: PawsOff does not stop ScreenCaptureKit capture streams. Cooperating recording clients should exclude `com.leonidmajbits.pawsoff` using `SCContentFilter`. See [`Docs/SCREEN_CAPTURE.md`](Docs/SCREEN_CAPTURE.md) for details.
3. **Hardware & Power Keys**: System-level power keys, Touch ID sensors, and OS-reserved system gestures operate below user-space event taps and remain under kernel control.
4. **Privacy & Telemetry**: Zero network calls, zero analytics, zero keystroke recording. Only numerical pressed-key codes and modifier states are tracked in volatile RAM during active curtain sessions to safely drain stuck modifier states on exit; zero typed text is stored or logged.

---

## Provenance & License

- **Authorship**: Leonid Majbits & Gemini Operator Lab (ZION Chassis). See [`NOTICE.md`](NOTICE.md) for full Triadic Sovereign Provenance details.
- **License**: MIT License. See [`LICENSE`](LICENSE) for complete terms.
