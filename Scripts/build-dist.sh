#!/usr/bin/env bash
#
# Build, Developer ID sign, notarize, staple, and verify dist/Reflex.dmg.
#
# Required:
#   - A valid "Developer ID Application: ..." certificate in the keychain.
#   - Notary credentials, provided either as:
#       NOTARY_KEYCHAIN_PROFILE=profile-name
#     or:
#       APPLE_ID=you@example.com APPLE_TEAM_ID=TEAMID APPLE_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx
#
# Optional:
#   SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
#   APPLE_TEAM_ID=TEAMID

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

APP_NAME="Reflex"
PROJECT_PATH="$ROOT/Reflex.xcodeproj"
DERIVED_DATA_PATH="$ROOT/.build/xcode-dist"
APP_BUNDLE="$DERIVED_DATA_PATH/Build/Products/Release/$APP_NAME.app"
DIST_DIR="$ROOT/dist"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"

cd "$ROOT"

if [ -f ".env" ]; then
    set -a
    # shellcheck disable=SC1091
    . ./.env
    set +a
fi

if [ -z "${SPOTIFY_CLIENT_ID:-}" ]; then
    echo "==> Warning: SPOTIFY_CLIENT_ID not set. Spotify search/playback will be unavailable."
fi

if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="$(
        security find-identity -v -p codesigning |
        sed -n 's/.*"\(Developer ID Application: .*([^)]*)\)".*/\1/p' |
        head -n 1
    )"
fi

if [ -z "${SIGN_IDENTITY:-}" ]; then
    echo "error: no Developer ID Application signing identity found in this keychain." >&2
    echo "Run: security find-identity -v -p codesigning" >&2
    exit 1
fi

if [ -z "${APPLE_TEAM_ID:-}" ]; then
    APPLE_TEAM_ID="$(
        printf '%s\n' "$SIGN_IDENTITY" |
        sed -n 's/.*(\([A-Z0-9][A-Z0-9]*\)).*/\1/p'
    )"
fi

if [ -z "${APPLE_TEAM_ID:-}" ]; then
    echo "error: APPLE_TEAM_ID is required when it cannot be inferred from SIGN_IDENTITY." >&2
    exit 1
fi

echo "==> Using signing identity: $SIGN_IDENTITY"
echo "==> Using Apple team id: $APPLE_TEAM_ID"

echo "==> Generating SpotifySecrets.swift..."
"$SCRIPT_DIR/generate-spotify-secrets.sh"

echo "==> Building Release app with Xcode..."
rm -rf "$DERIVED_DATA_PATH"
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    build

if [ ! -d "$APP_BUNDLE" ]; then
    echo "error: built app not found at $APP_BUNDLE" >&2
    exit 1
fi

echo "==> Verifying app signature..."
codesign --verify --strict --verbose=2 "$APP_BUNDLE"

echo "==> Creating DMG..."
APP_BUNDLE="$APP_BUNDLE" DIST_DIR="$DIST_DIR" "$SCRIPT_DIR/package-dmg.sh"

echo "==> Signing DMG..."
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

echo "==> Submitting DMG for notarization..."
if [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --password "$APPLE_APP_PASSWORD" \
        --wait
else
    echo "error: notarization credentials are missing." >&2
    echo "Set NOTARY_KEYCHAIN_PROFILE, or APPLE_ID + APPLE_TEAM_ID + APPLE_APP_PASSWORD." >&2
    exit 1
fi

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

echo "==> Verifying Gatekeeper acceptance..."
if ! spctl -a -vv --type open --context context:primary-signature "$DMG_PATH"; then
    echo "==> Warning: spctl DMG assessment failed. The DMG is still signed, notarized, and stapled."
fi
if ! spctl -a -vv --type exec "$APP_BUNDLE"; then
    echo "==> Warning: spctl app assessment failed. The app signature was already verified with codesign."
fi

echo "==> Done: $DMG_PATH"
