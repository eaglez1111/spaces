#!/bin/bash
set -e

cd "$(dirname "$0")"

APP_NAME="SpaceSwitcher"
PROD_NAME="Spaces"
PROD_BUNDLE_ID="com.spaceswitcher.Spaces"
DEST="/Applications/$PROD_NAME.app"

# IMPORTANT: The .app bundle is renamed to Spaces, but its binary retains
# the Xcode PRODUCT_NAME 'SpaceSwitcher'. Terminate BOTH names before building.
# Otherwise, an old process can continue handling global keyboard/mouse events.
echo "Stopping any running Spaces/SpaceSwitcher instances..."
pkill -x "$APP_NAME" 2>/dev/null || true
pkill -x "$PROD_NAME" 2>/dev/null || true

# Do not overwrite a still-running bundle. Never force-kill automatically.
for i in 1 2 3 4 5 6 7 8 9 10; do
    if ! pgrep -x "$APP_NAME" >/dev/null && ! pgrep -x "$PROD_NAME" >/dev/null; then
        break
    fi
    sleep 0.5
done
if pgrep -x "$APP_NAME" >/dev/null || pgrep -x "$PROD_NAME" >/dev/null; then
    echo "ERROR: Spaces process is still running. Installation aborted." >&2
    exit 1
fi

# Build release
echo "Building $PROD_NAME..."
xcodebuild -project SpaceSwitcher.xcodeproj -scheme SpaceSwitcher -configuration Debug build -quiet

# Find the built app
BUILD_DIR=$(xcodebuild -project SpaceSwitcher.xcodeproj -scheme SpaceSwitcher -configuration Debug -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $3}')
BUILT_APP="$BUILD_DIR/$APP_NAME.app"

# Copy to a temp location for renaming
TEMP_APP="/tmp/$PROD_NAME.app"
rm -rf "$TEMP_APP"
cp -R "$BUILT_APP" "$TEMP_APP"

# Patch bundle ID and display name
PLIST="$TEMP_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $PROD_BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $PROD_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $PROD_NAME" "$PLIST"

# Re-sign after modifying the plist
codesign --force --sign - "$TEMP_APP"

# Install to /Applications
echo "Installing to $DEST..."
rm -rf "$DEST"
mv "$TEMP_APP" "$DEST"

# Register the installed bundle, without restarting the Dock or resetting
# Accessibility permissions. The user can explicitly launch the app later.
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f "$DEST"

echo "Installed Spaces. It was NOT launched."
echo "Accessibility permissions may need to be renewed after this ad-hoc re-sign."
echo "If permission is missing, re-add /Applications/Spaces.app in Privacy & Security > Accessibility."
echo "Cmd+Tab and Dock lock settings are saved across relaunches."\necho "If Cmd+Tab remains native, check the diagnostic status and Input Monitoring permission."
