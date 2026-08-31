#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=$(tr -d '[:space:]' < "$ROOT/VERSION")
ARCH=${ARCH:-$(uname -m)}
BUILD_NUMBER=${BUILD_NUMBER:-1}
IDENTITY=${SIGNING_IDENTITY:-"Developer ID Application: FATIH MEHMET BABACAN (SBGX8T7DZN)"}
DIST=${DIST_DIR:-"$ROOT/dist/$ARCH"}
APP="$DIST/PortHarbor.app"
ARCHIVE="$DIST/PortHarbor-$VERSION-$ARCH.zip"

rm -rf "$DIST"
mkdir -p "$DIST"

PACKAGE_ONLY=1 ARCH="$ARCH" BUILD_NUMBER="$BUILD_NUMBER" "$ROOT/scripts/package-local-app.sh" >/dev/null
cp -R "$ROOT/.build/PortHarbor.app" "$APP"

/usr/bin/codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ARCHIVE"

if test "${SKIP_NOTARIZATION:-0}" != "1"; then
    if test -n "${APPLE_ID:-}" && test -n "${APPLE_TEAM_ID:-}" && test -n "${APP_SPECIFIC_PASSWORD:-}"; then
        xcrun notarytool submit "$ARCHIVE" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APP_SPECIFIC_PASSWORD" --wait
    else
        : "${NOTARYTOOL_PROFILE:?NOTARYTOOL_PROFILE or Apple ID credentials are required}"
        xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
    fi

    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    /usr/sbin/spctl --assess --type execute --verbose=4 "$APP"
    rm -f "$ARCHIVE"
    /usr/bin/ditto -c -k --keepParent "$APP" "$ARCHIVE"
fi

/usr/bin/shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
printf '%s\n' "$ARCHIVE"
