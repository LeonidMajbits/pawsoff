# PawsOff Enterprise Office Shield: Passkey Architecture & Native macOS Lock Fail-Safe (v1.2.0)

## 1. Executive Summary & Purpose
In corporate enterprise environments, information security policies strictly mandate that workstations must not be left unattended with an active, visible desktop. However, using the traditional macOS Lock Screen (`Cmd + Ctrl + Q` or system sleep) has catastrophic consequences for local AI developers:
1. **Window Server Disconnection**: The graphics display context is suspended, causing ScreenCaptureKit GPU pipelines and window-relative accessibility probes (`AXUIElement`) to stall.
2. **Aggressive System Sleep (App Nap / MDM)**: Enterprise management software (e.g. Jamf, Microsoft Intune) automatically enforces low-power sleep after 2–5 minutes of lock screen inactivity, halting long-running local LLM inference, Claude Code worker loops, and heavy compilation tasks.
3. **Visual Data Leakage**: Colleagues walking past can read confidential proprietary prompts, customer data, or active architectural designs on the display.

**PawsOff v1.2.0 Enterprise Office Shield** solves this fundamental dilemma by providing a secure, lightweight passkey curtain that shields the screen and blocks hardware input while keeping the macOS user session, GPU compositor, and background AI engines running at 100% capacity.

---

## 2. Threat Model & Security Architecture

### 2.1 The Two Competing Security Failures
Existing desktop locking utilities invariably commit one of two fatal errors:
1. **The Trapped-User Failure**: The third-party utility implements its own password field without a system fallback. If the user forgets their custom PIN, encounters an app freeze, or typos their code, they are permanently locked out of their workstation and forced to hard-power-cycle the hardware, losing unsaved work.
2. **The Insecure Bypass Failure**: The app can be easily bypassed by clicking a cancel button, force-quitting the app via keyboard shortcuts, or unplugging peripherals, allowing an unauthorized intruder to gain unrestricted access to the unlocked user account.

### 2.2 The PawsOff Triadic Security Guarantee
PawsOff resolves this through a three-tier fail-safe architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                 PawsOff Shield Active                       │
│  - kCGHIDEventTap blocks all hardware keys & mouse clicks   │
│  - kIOPMAssertionPreventUserIdleSystemSleep keeps AI awake   │
│  - Visual Curtain covers monitors (Adjustable Blur/Tint)    │
└──────────────────────────────┬──────────────────────────────┘
                               │ User Attempts Unlock (Ctrl+1 / Escape / Click)
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                   Passkey Entry Dialog                      │
│            "Enter Passkey to Lift Shield"                   │
│         [ • • • • ]  (Stored as Salted SHA-256)             │
│                                                             │
│   [ Submit (Enter) ]   [ Forgot Passkey / Mac Password ]    │
└──────────────┬──────────────────────────────┬───────────────┘
               │                              │
     Correct Passkey            3 Incorrect Attempts OR
               │              "Forgot Passkey" Clicked
               ▼                              ▼
┌─────────────────────────────┐ ┌─────────────────────────────┐
│       Shield Lifted         │ │  Fail-Safe System Handoff   │
│ - Input taps unhooked       │ │ - PawsOff cleans up taps    │
│ - Windows dismissed         │ │ - Calls SACLockScreenImmediate│
│ - Desktop instantly restored│ │ - Native macOS Login Screen │
│ - 0ms AI interruption       │ │ - Requires System Password  │
└─────────────────────────────┘ └─────────────────────────────┘
```

1. **Happy Path (Legitimate User)**: The user returns to their desk, types their quick 4-digit PIN (e.g., `1234`), and hits Enter. PawsOff verifies the salted hash and immediately lifts the shield in under 100 milliseconds. No loginwindow transition, no process sleep, zero interruption to background models.
2. **Attacker Path (Unauthorized Intruder)**: An intruder attempts to bypass PawsOff. Because standard keyboard events and hotkeys are swallowed by `kCGHIDEventTap`, they cannot access the dock or switch apps. If they attempt to guess the PIN, three failed attempts immediately trigger `SACLockScreenImmediate()`, dropping the machine into the encrypted Apple macOS system lock screen. The intruder is completely blocked.
3. **Emergency Fallback (Legitimate User Forgets PIN)**: The user clicks *"Forgot Passkey / Use Mac Password"*. PawsOff gracefully releases its input hooks and invokes `SACLockScreenImmediate()`. The user logs back into their Mac using their official macOS system password or Touch ID, opening PawsOff preferences to reset their PIN. The user is **never trapped**.

---

## 3. Technical Implementation Details

### 3.1 Salted Cryptographic Storage (`PasskeyManager.swift`)
Passkeys are never stored in plaintext. They are salted with a machine-specific UUID and hashed using standard SHA-256:
```swift
let saltedString = "\(salt):\(passkey)"
let digest = SHA256.hash(data: Data(saltedString.utf8))
let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()
```
The salt and hash are persisted in `UserDefaults` (`PreferenceStore`).

### 3.2 Native Lock Screen Trigger (`SACLockScreenImmediate`)
To guarantee that PawsOff never requires root/sudo privileges or fragile AppleScript hacks, it dynamically resolves the private C function `SACLockScreenImmediate` exported by Apple's `login.framework`:
```swift
typealias SACLockScreenImmediateFunc = @convention(c) () -> Void

public static func triggerNativeMacLockScreen() {
    guard let bundle = CFBundleCreate(
        kCFAllocatorDefault,
        NSURL(fileURLWithPath: "/System/Library/PrivateFrameworks/login.framework")
    ) else {
        NSLog("[PawsOff] Error: Unable to locate login.framework")
        return
    }
    guard let funcPtr = CFBundleGetFunctionPointerForName(
        bundle,
        "SACLockScreenImmediate" as CFString
    ) else {
        NSLog("[PawsOff] Error: SACLockScreenImmediate symbol not found")
        return
    }
    let lockImmediate = unsafeBitCast(funcPtr, to: SACLockScreenImmediateFunc.self)
    lockImmediate()
}
```

### 3.3 Dynamic PIN Entry HUD (`ShieldView.swift`)
When passkey protection is enabled in `SettingsManager`:
* The standard HUD ("🐾 PawsOff Active • Press Ctrl+1 to exit") is replaced upon user interaction by a clean, secure PIN entry card.
* Displays a masked secure input field, a strike indicator ("Attempts remaining: X"), and a discrete button: *"Forgot Passkey (Use Mac Password)"*.
* When 3 strikes are reached, the card displays *"Locking macOS..."* and executes `triggerNativeMacLockScreen()`.

---

## 4. Operational Invariants & Verification Checklist
- [x] **AI Continuity**: `kIOPMAssertionTypePreventUserIdleSystemSleep` holds continuously while shielded.
- [x] **Zero Hardware Bypass**: `NX_SYSDEFINED` audio/brightness keys and standard input events remain trapped.
- [x] **Fail-Safe Integrity**: `SACLockScreenImmediate()` reliably transitions to native login window.
- [x] **Zero Plaintext Persistence**: Passkeys are strictly salted and hashed.
- [x] **User Choice**: Passkey enforcement is strictly optional via menu bar preferences.
