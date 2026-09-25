#!/usr/bin/env python3
"""Finite source-contract checks; NOT an AppKit compiler or an integration test."""
from pathlib import Path
import json
import re
import sys

import hashlib

root = Path(__file__).resolve().parents[1]
sources = {p.name: p.read_text(encoding='utf-8') for p in (root / 'Sources/PawsOff').glob('*.swift')}
all_native = '\n'.join(sources.values())
checks = {}
def check(name: str, condition: bool) -> None:
    checks[name] = bool(condition)

# 1. Required Swift source modules
for name in ('main.swift','AppDelegate.swift','CurtainController.swift','CurtainWindow.swift',
             'ShieldView.swift','MenuBarController.swift','HotkeyManager.swift','SettingsManager.swift'):
    check('required_' + name, name in sources)

# 2. Safety & runtime constraints
check('no_app_activation_or_key_window_calls', not re.search(r'(?:NSApp\.activate|NSApplication\.shared\.activate|\.(?:makeKeyAndOrderFront|makeKey|makeMain))\s*\(', all_native))
check('no_lock_sleep_shell_or_power_policy_calls', not re.search(
    r'\b(?:SACLockScreenImmediate|IOPMSleepSystem|CGSession|pmset|caffeinate|system|execv|posix_spawn)\s*\(', all_native))
check('no_network_imports', not re.search(r'^import\s+(?:Network|NetworkExtension|FoundationNetworking)\b', all_native, re.M))
check('tint_cap_literal', 'maximumTintOpacity = 0.82' in (root/'Sources/PawsOffCore/AppearanceSettings.swift').read_text(encoding='utf-8'))
check('active_not_listen_only_tap', 'options: .defaultTap' in sources['InputShield.swift'] and '.listenOnly' not in sources['InputShield.swift'])
check('callback_nil_is_not_coalesced', 'return owner.handle(type, event, token: context.generation)' in sources['InputShield.swift'])
check('mask_is_checked', 'CGGetEventTapList' in sources['InputShield.swift'] and 'entry.eventsOfInterest & requiredMask == requiredMask' in sources['InputShield.swift'])
check('tap_disabled_is_fail_open', 'type == .tapDisabledByTimeout || type == .tapDisabledByUserInput' in sources['InputShield.swift'])
check('global_shortcut_registered', 'RegisterEventHotKey(' in sources['HotkeyManager.swift'])
check('no_key_or_main_curtain', 'canBecomeKey: Bool { false }' in sources['CurtainWindow.swift'] and 'canBecomeMain: Bool { false }' in sources['CurtainWindow.swift'])
check('required_window_behaviors', all(x in sources['CurtainWindow.swift'] for x in ['.canJoinAllSpaces','.fullScreenAuxiliary','.ignoresCycle','.screenSaver','.borderless']))
check('hotplug_observer', 'NSApplication.didChangeScreenParametersNotification' in sources['CurtainController.swift'])
check('balanced_cursor_calls', all_native.count('NSCursor.hide()') == all_native.count('NSCursor.unhide()') == 1)
check('pointer_locator_fallback', 'updatePointerLocator' in sources['ShieldView.swift'])
check('no_capture_exclusion_false_promise', 'sharingType = .none' not in all_native)
check('no_hide_foreign_apps', not re.search(r'NSRunningApplication.*\bhide\(', all_native))
for method in ['keyDown','keyUp','mouseDown','mouseUp','mouseDragged','rightMouseDown','rightMouseUp',
               'otherMouseDown','otherMouseUp','scrollWheel']:
    check('responder_' + method, f'override func {method}(with event: NSEvent)' in sources['ShieldView.swift'])

# 3. Manifest Custody & Cryptographic Integrity
manifest_file = root / 'MANIFEST.sha256'
check('manifest_exists', manifest_file.is_file())

manifest_entries = {}
if manifest_file.is_file():
    for line in manifest_file.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = line.split('  ', 1)
        if len(parts) == 2:
            manifest_entries[parts[1]] = parts[0]

manifest_hashes_valid = True
for rel_path, expected_hash in manifest_entries.items():
    file_p = root / rel_path
    if not file_p.is_file():
        manifest_hashes_valid = False
        break
    h = hashlib.sha256(file_p.read_bytes()).hexdigest()
    if h != expected_hash:
        manifest_hashes_valid = False
        break
check('manifest_hashes_match', manifest_hashes_valid and len(manifest_entries) > 0)

# 4. Inventory Equality (No unmanifested surprise/private files)
ignored_roots = {'.git', '.build', 'dist', 'Validation', '__pycache__', '.pytest_cache'}
scanned_files = set()
for p in root.rglob('*'):
    if p.is_file():
        parts = p.relative_to(root).parts
        if any(part in ignored_roots for part in parts):
            continue
        if parts[0].startswith('.'):
            # allow .gitignore, .github
            if parts[0] not in ('.gitignore', '.github'):
                continue
        rel = p.relative_to(root).as_posix()
        if rel != 'MANIFEST.sha256':
            scanned_files.add(rel)

check('no_unmanifested_payloads', scanned_files == set(manifest_entries.keys()))

# 5. Strict Privacy & Brand Hygiene
privacy_clean = True
forbidden_patterns = [
    re.compile(r'[a-zA-Z0-9._%+-]+@gmail\.com'),
    re.compile(r'/Users/[a-zA-Z0-9_-]+'),
    re.compile(r'Free\s*' + r'Life\s*AI', re.I),
    re.compile(r'free' + r'life', re.I),
    re.compile(r'[\U0001F300-\U0001F9FF]')  # Emojis/pictographs
]

for rel_path in manifest_entries.keys():
    file_p = root / rel_path
    try:
        content = file_p.read_text(encoding='utf-8')
        for pat in forbidden_patterns:
            if pat.search(content):
                privacy_clean = False
                break
    except Exception:
        pass
    if not privacy_clean:
        break

check('privacy_and_brand_hygiene_clean', privacy_clean)

print(json.dumps({'scope':'static source-contract & manifest integrity checks','passed':sum(checks.values()),
                  'total':len(checks),'checks':checks}, indent=2))
sys.exit(0 if all(checks.values()) else 1)
