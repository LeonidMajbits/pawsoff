#!/usr/bin/env python3
"""Stage 4 finite source-contract and passkey security checks."""
from pathlib import Path
import json
import re
import sys

root = Path(__file__).resolve().parents[1]
sources = {p.name: p.read_text() for p in (root / 'Sources/PawsOff').glob('*.swift')}
all_native = '\n'.join(sources.values())
core_sources = {p.name: p.read_text() for p in (root / 'Sources/PawsOffCore').glob('*.swift')}
checks = {}
def check(name: str, condition: bool) -> None:
    checks[name] = bool(condition)

for name in ('main.swift','AppDelegate.swift','CurtainController.swift','CurtainWindow.swift',
             'ShieldView.swift','MenuBarController.swift','HotkeyManager.swift','SettingsManager.swift'):
    check('required_' + name, name in sources)

check('focus_restoration_on_lift', 'prev.activate' in sources['CurtainController.swift'] or 'previousApp?.activate' in sources['CurtainController.swift'])
check('no_rogue_system_sleep_calls', not re.search(
    r'\b(?:IOPMSleepSystem|CGSession|caffeinate|system|execv|posix_spawn)\s*\(', all_native))
check('no_network_imports', not re.search(r'^import\s+(?:Network|NetworkExtension|FoundationNetworking)\b', all_native, re.M))
check('tint_cap_literal', 'maximumTintOpacity = 0.82' in core_sources['AppearanceSettings.swift'])
check('active_not_listen_only_tap', 'options: .defaultTap' in sources['InputShield.swift'] and '.listenOnly' not in sources['InputShield.swift'])
check('callback_nil_is_not_coalesced', 'return owner.handle(type, event, token: context.generation)' in sources['InputShield.swift'])
check('mask_is_checked', 'CGGetEventTapList' in sources['InputShield.swift'] and 'entry.eventsOfInterest & requiredMask == requiredMask' in sources['InputShield.swift'])
check('tap_disabled_is_fail_open', 'type == .tapDisabledByTimeout || type == .tapDisabledByUserInput' in sources['InputShield.swift'])
check('global_shortcut_registered', 'RegisterEventHotKey(' in sources['HotkeyManager.swift'])
check('controlled_key_or_main_curtain', 'override var canBecomeKey: Bool { true }' in sources['CurtainWindow.swift'] and 'override var canBecomeMain: Bool { true }' in sources['CurtainWindow.swift'])
check('required_window_behaviors', all(x in sources['CurtainWindow.swift'] for x in ['.canJoinAllSpaces','.fullScreenAuxiliary','.ignoresCycle','.screenSaver','.borderless']))
check('hotplug_observer', 'NSApplication.didChangeScreenParametersNotification' in sources['CurtainController.swift'])
check('balanced_cursor_calls', all_native.count('NSCursor.hide()') == all_native.count('NSCursor.unhide()') == 1)
check('pointer_locator_fallback', 'updatePointerLocator' in sources['ShieldView.swift'])
check('no_capture_exclusion_false_promise', 'sharingType = .none' not in all_native)
check('no_hide_foreign_apps', not re.search(r'NSRunningApplication.*\bhide\(', all_native))
for method in ['keyDown','keyUp','mouseDown','mouseUp','mouseDragged','rightMouseDown','rightMouseUp',
               'otherMouseDown','otherMouseUp','scrollWheel']:
    check('responder_' + method, f'override func {method}(with event: NSEvent)' in sources['ShieldView.swift'])

# Stage 4 Enterprise Passkey & Fail-Safe Invariants
check('passkey_core_engine_present', 'PasskeyManager.swift' in core_sources)
check('sac_lock_fail_safe_supported', 'SACLockScreenImmediate' in core_sources.get('PasskeyManager.swift', ''))
check('passkey_salted_sha256', 'SHA256.hash' in core_sources.get('PasskeyManager.swift', ''))
check('passkey_manager_integrated', 'let passkey = PasskeyManager()' in sources['SettingsManager.swift'])
check('awaiting_passkey_tap_bypass', 'if locked({ awaitingPasskey })' in sources['InputShield.swift'])
check('emergency_lockdown_wired', 'PasskeyManager.triggerNativeMacLockScreen()' in sources['CurtainController.swift'])
check('enterprise_shield_docs_present', (root / 'Docs/02_Enterprise_Office_Shield_Passkey_Architecture.md').exists())

print(json.dumps({'scope':'Stage 4 Enterprise Shield source-contract checks','passed':sum(checks.values()),
                  'total':len(checks),'checks':checks}, indent=2))
sys.exit(0 if all(checks.values()) else 1)
