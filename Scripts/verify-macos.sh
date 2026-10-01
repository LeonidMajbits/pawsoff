#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Darwin ]] || { echo 'This is the native macOS build gate.' >&2; exit 2; }
REPORT="$(mktemp -d "$ROOT/Validation/host-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
exec > >(tee "$REPORT/build.log") 2>&1
sw_vers
xcrun swift --version
uname -m
./Scripts/run_core_tests.sh
python3 Scripts/audit_source.py
make bundle
plutil -lint dist/PawsOff.app/Contents/Info.plist
codesign --verify --strict --verbose=2 dist/PawsOff.app
shasum -a 256 dist/PawsOff.app/Contents/MacOS/PawsOff > "$REPORT/native-binary.sha256"
printf '%s\n' '{"native_build":"passed","signature_verification":"passed","manual_runtime_matrix":"not_run","screen_capture_probe":"not_run"}' > "$REPORT/result.json"
echo "Build gate complete: $REPORT"
echo 'This does not certify event delivery, focus, Spaces, capture, or workload performance. Run Docs/VERIFICATION.md.'
