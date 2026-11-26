#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Spaces"
LEGACY_EXECUTABLE="SpaceSwitcher"
PROD_BUNDLE_ID="com.spaceswitcher.Spaces"
DEST="/Applications/$APP_NAME.app"

# No per-Mac setup required. Sign each local build ad hoc by default.
# Developers who already have a reusable signing identity may optionally
# specify SPACES_SIGNING_IDENTITY. macOS can require new Accessibility approval
# after code changes to an ad-hoc signed app.
SIGNING_IDENTITY="${SPACES_SIGNING_IDENTITY:-}"

echo "Building Spaces..."
# Xcode produces Spaces.app directly; there is no separate development app.
xcodebuild -project SpaceSwitcher.xcodeproj -scheme Spaces \
    -configuration Debug CODE_SIGNING_ALLOWED=NO build -quiet

BUILD_DIR=$(xcodebuild -project SpaceSwitcher.xcodeproj -scheme Spaces \
    -configuration Debug CODE_SIGNING_ALLOWED=NO -showBuildSettings 2>/dev/null |
    awk '$1 == "BUILT_PRODUCTS_DIR" { print $3; exit }')
BUILT_APP="$BUILD_DIR/$APP_NAME.app"
if [[ ! -d "$BUILT_APP" ]]; then
    echo "Built app not found: $BUILT_APP" >&2
    exit 1
fi

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/spaces-install.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT
TEMP_APP="$TEMP_DIR/$APP_NAME.app"
cp -R "$BUILT_APP" "$TEMP_APP"

# Confirm the sole Spaces.app has the intended identity; never patch it.
PLIST="$TEMP_APP/Contents/Info.plist"
BUILT_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST")
BUILT_EXEC=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$PLIST")
if [[ "$BUILT_ID" != "$PROD_BUNDLE_ID" || "$BUILT_EXEC" != "$APP_NAME" ]]; then
    echo "ERROR: unexpected build identity ($BUILT_ID / $BUILT_EXEC)" >&2
    exit 1
fi

if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "Signing production Spaces with: $SIGNING_IDENTITY"
    codesign --force --sign "$SIGNING_IDENTITY" "$TEMP_APP"
else
    echo "Using ad-hoc signing (no certificate setup). Accessibility may need reapproval after updates."
    codesign --force --sign - "$TEMP_APP"
fi
codesign --verify --deep --strict "$TEMP_APP"
codesign --display -r- "$TEMP_APP" 2>&1 | grep "designated =>" || true

# Stop current Spaces, including the legacy process during this migration.
# Graceful termination restores the system Cmd+Tab interception state.
echo "Stopping running Spaces..."
pkill -x "$APP_NAME" 2>/dev/null || true
pkill -x "$LEGACY_EXECUTABLE" 2>/dev/null || true
for i in 1 2 3 4 5 6 7 8 9 10; do
    if ! pgrep -x "$APP_NAME" >/dev/null && ! pgrep -x "$LEGACY_EXECUTABLE" >/dev/null; then
        break
    fi
    sleep 0.5
done
if pgrep -x "$APP_NAME" >/dev/null || pgrep -x "$LEGACY_EXECUTABLE" >/dev/null; then
    echo "ERROR: Spaces is still running. Installation aborted." >&2
    exit 1
fi

echo "Installing to $DEST..."
rm -rf "$DEST"
mv "$TEMP_APP" "$DEST"
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f "$DEST"

echo "Installed Spaces. Open /Applications/Spaces.app to start it."
