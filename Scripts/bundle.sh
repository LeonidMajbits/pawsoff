#!/bin/bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$ROOT"
[[ "$(uname -s)" == Darwin ]] || { echo 'Bundling requires macOS.' >&2; exit 2; }
if pgrep -x PawsOff >/dev/null; then
  echo 'Quit PawsOff before replacing its bundle (TCC identity must remain stable).' >&2; exit 2
fi
BIN="$(xcrun swift build -c release --show-bin-path)/PawsOff"
[[ -x "$BIN" ]] || { echo 'Run make build first.' >&2; exit 2; }
mkdir -p dist
STAGE="$(mktemp -d "$ROOT/dist/.PawsOff-stage.XXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
APP="$STAGE/PawsOff.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PawsOff"
chmod 755 "$APP/Contents/MacOS/PawsOff"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleExecutable</key><string>PawsOff</string>
<key>CFBundleIdentifier</key><string>com.leonidmajbits.pawsoff</string>
<key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
<key>CFBundleName</key><string>PawsOff</string>
<key>CFBundleDisplayName</key><string>PawsOff</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>CFBundleVersion</key><string>1.1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppSleepDisabled</key><true/>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"
IDENTITY="${CODE_SIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" --identifier com.leonidmajbits.pawsoff "$APP"
codesign --verify --strict --verbose=2 "$APP"
# Never delete the previous bundle until the staged binary and signature have passed.
# Roll back if the final move fails. This is a local replacement, not distribution notarization.
PREVIOUS="$ROOT/dist/.PawsOff-previous.app"
if [[ -e "$PREVIOUS" ]]; then
  echo "Inspect/remove the existing recovery bundle before retrying: $PREVIOUS" >&2; exit 2
fi
if [[ -e "$ROOT/dist/PawsOff.app" ]]; then mv "$ROOT/dist/PawsOff.app" "$PREVIOUS"; fi
if ! mv "$APP" "$ROOT/dist/PawsOff.app"; then
  [[ ! -e "$PREVIOUS" ]] || mv "$PREVIOUS" "$ROOT/dist/PawsOff.app"
  exit 1
fi
rm -rf -- "$PREVIOUS"
echo "Created: $ROOT/dist/PawsOff.app"
echo 'Default signing is ad-hoc. No Developer ID signature or notarization is claimed.'
