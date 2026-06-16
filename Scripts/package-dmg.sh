#!/bin/sh
set -eu

APP_NAME="${APP_NAME:-${PRODUCT_NAME:-Reflex}}"
SRCROOT="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CONFIGURATION_BUILD_DIR="${CONFIGURATION_BUILD_DIR:-${BUILT_PRODUCTS_DIR:-}}"
APP_BUNDLE="${APP_BUNDLE:-}"

if [ -z "$APP_BUNDLE" ]; then
  if [ -n "$CONFIGURATION_BUILD_DIR" ] && [ -d "$CONFIGURATION_BUILD_DIR/$APP_NAME.app" ]; then
    APP_BUNDLE="$CONFIGURATION_BUILD_DIR/$APP_NAME.app"
  elif [ -n "${BUILT_PRODUCTS_DIR:-}" ] && [ -d "$BUILT_PRODUCTS_DIR/$APP_NAME.app" ]; then
    APP_BUNDLE="$BUILT_PRODUCTS_DIR/$APP_NAME.app"
  elif [ -d "$SRCROOT/build/$APP_NAME.app" ]; then
    APP_BUNDLE="$SRCROOT/build/$APP_NAME.app"
  else
    echo "error: Could not find $APP_NAME.app. Build the Reflex target first or set APP_BUNDLE." >&2
    exit 1
  fi
fi

DIST_DIR="${DIST_DIR:-$SRCROOT/dist}"
STAGING_DIR="${STAGING_DIR:-$SRCROOT/.build/dmg-staging}"
DMG_PATH="${DMG_PATH:-$DIST_DIR/$APP_NAME.dmg}"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
echo "Created $DMG_PATH"
