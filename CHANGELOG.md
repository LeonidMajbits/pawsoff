# Changelog

## 1.2.0 — Enterprise Office Shield & Zero-Latency Focus Restoration

- **Complete Physical Input Freeze**: `CurtainWindow` accepts key focus on drop; AppKit window hierarchy and `ShieldView` swallow 100% of routine keyboard events, clicks, drags, and scrolls natively without keystroke leakage to background applications.
- **Seamless Focus Restoration**: PawsOff records frontmost application on curtain drop and automatically restores focus upon unlock (`previousApp?.activate`).
- **Enterprise Passkey Mode**: Optional 4–8 digit PIN protection for shared office environments, salted and hashed via Apple `CryptoKit` (SHA-256).
- **The "Never-Trapped" Fail-Safe**: Three consecutive wrong PIN attempts or clicking "Forgot Passkey (Use Mac Password)" dynamically invokes `SACLockScreenImmediate()`, dropping machine safely to native macOS login window without killing background AI loops.
- **Harmonized Menu Bar HUD**: Full-width 32pt hero button (`Drop Curtain Now`), balanced 50/50 secondary row (`📖 Quick Guide` + `Quit PawsOff`), and rounded passkey configuration accessory.
- **Quick Guide HUD Card**: 500pt dark floating card explaining core shortcuts and features with persistent launch suppression.
- **Stable TCC Codesign Requirement**: `bundle.sh` signs with designated requirement `-r='designated => identifier "com.leonidmajbits.pawsoff"'` to preserve macOS Accessibility permissions across rebuilds.
- **Standalone CLT Test Runner**: `run_core_tests.sh` executes all 63 pure Swift core unit tests without requiring full Xcode.app `XCTest`.
- **41 Finite Source Contract Checks**: Full coverage across security invariants, memory isolation, and window behaviors.

## 1.1.0 — Visual Polish & Dynamic Presets

- Dynamic Monogram status bar icon and dark slate/midnight app icon.
- Sliders capped strictly at 82% tint to guarantee cursor silhouette visibility.
- Improved multi-monitor hotplug observer and Spaces transition handling.

## 1.0.0 — Initial Release

- Native AppKit menu/curtain, guarded percentage preferences, global Carbon shortcut (`Ctrl+1`), active session input filter, display reconciliation, scoped power assertions, paired-release drain, failure recovery, local bundle generation, and verification probes.
