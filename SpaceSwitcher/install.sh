#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="SpaceSwitcher"
PROD_NAME="Spaces"
PROD_BUNDLE_ID="com.spaceswitcher.Spaces"
DEST="/Applications/$PROD_NAME.app"

# An ad-hoc signature identifies the exact build hash, so old Accessibility
# grants stop matching after a rebuild. Decide how to sign before replacing
# or stopping the existing, potentially working app.
SIGNING_IDENTITY="${SPACES_SIGNING_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
    LOGIN_KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
    if security find-certificate -c "Spaces Local Signing" -p "$LOGIN_KEYCHAIN" 2>/dev/null |
            grep -q "BEGIN CERTIFICATE"; then
        SIGNING_IDENTITY="Spaces Local Signing"
    fi
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
    CANDIDATES=$(security find-identity -v -p codesigning 2>/dev/null |
        grep -E '"(Apple Development:|Developer ID Application:)' |
        awk '{print $2}' || true)
    if [[ $(printf '%s\n' "$CANDIDATES" | sed '/^$/d' | wc -l | tr -d ' ') == "1" ]]; then
        SIGNING_IDENTITY="$CANDIDATES"
    fi
fi
if [[ -z "$SIGNING_IDENTITY" && "${SPACES_ALLOW_ADHOC:-0}" != "1" ]]; then
    cat >&2 <<'MESSAGE'
No reusable code-signing identity found. Your installed Spaces was NOT changed.
Ad-hoc signing would make macOS forget Accessibility permission on rebuild.

One-time setup:
  In Keychain Access > Certificate Assistant > Create a Certificate:
  Name: Spaces Local Signing
  Identity Type: Self Signed Root
  Certificate Type: Code Signing
  Keep the identity in your login keychain and trust it for Code Signing.
  Then rerun ./install.sh and grant Accessibility to Spaces once.

Or specify an existing certificate:
  SPACES_SIGNING_IDENTITY="certificate name or SHA-1" ./install.sh

Temporary bypass (will likely require Accessibility reapproval):
  SPACES_ALLOW_ADHOC=1 ./install.sh
MESSAGE
    exit 1
fi

echo "Building Spaces..."
# The intermediate SpaceSwitcher build is never signed or launched by the
# installer. Only /Applications/Spaces.app gets the stable production identity.
xcodebuild -project SpaceSwitcher.xcodeproj -scheme SpaceSwitcher \
    -configuration Debug CODE_SIGNING_ALLOWED=NO build -quiet

BUILD_DIR=$(xcodebuild -project SpaceSwitcher.xcodeproj -scheme SpaceSwitcher \
    -configuration Debug CODE_SIGNING_ALLOWED=NO -showBuildSettings 2>/dev/null |
    awk '$1 == "BUILT_PRODUCTS_DIR" { print $3; exit }')
BUILT_APP="$BUILD_DIR/$APP_NAME.app"
if [[ ! -d "$BUILT_APP" ]]; then
    echo "Built app not found: $BUILT_APP" >&2
    exit 1
fi

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/spaces-install.XXXXXX")
trap 'rm -rf "$TEMP_DIR"' EXIT
TEMP_APP="$TEMP_DIR/$PROD_NAME.app"
cp -R "$BUILT_APP" "$TEMP_APP"

PLIST="$TEMP_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $PROD_BUNDLE_ID" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName $PROD_NAME" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleName $PROD_NAME" "$PLIST"

if [[ -n "$SIGNING_IDENTITY" ]]; then
    echo "Signing production Spaces with: $SIGNING_IDENTITY"
    codesign --force --sign "$SIGNING_IDENTITY" "$TEMP_APP"
else
    echo "WARNING: Explicit ad-hoc signing chosen; macOS may require reapproval."
    codesign --force --sign - "$TEMP_APP"
fi
codesign --verify --deep --strict "$TEMP_APP"
codesign --display -r- "$TEMP_APP" 2>&1 | grep "designated =>" || true

# Stop the actual SpaceSwitcher executable only after a good build exists.
# Graceful termination restores the system Cmd+Tab interception state.
echo "Stopping running Spaces / SpaceSwitcher..."
pkill -x "$APP_NAME" 2>/dev/null || true
pkill -x "$PROD_NAME" 2>/dev/null || true
for i in 1 2 3 4 5 6 7 8 9 10; do
    if ! pgrep -x "$APP_NAME" >/dev/null && ! pgrep -x "$PROD_NAME" >/dev/null; then
        break
    fi
    sleep 0.5
done
if pgrep -x "$APP_NAME" >/dev/null || pgrep -x "$PROD_NAME" >/dev/null; then
    echo "ERROR: Spaces is still running. Installation aborted." >&2
    exit 1
fi

echo "Installing to $DEST..."
rm -rf "$DEST"
mv "$TEMP_APP" "$DEST"
/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f "$DEST"

echo "Installed Spaces. Open /Applications/Spaces.app to start it."
