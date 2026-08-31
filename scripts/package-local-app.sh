#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD_DIR="$ROOT/.build"
VERSION=$(tr -d '[:space:]' < "$ROOT/VERSION")
BUILD_NUMBER=${BUILD_NUMBER:-1}
SPARKLE_PUBLIC_KEY=${SPARKLE_PUBLIC_KEY:-"YL33FrdCjDXEfkZXNKVFzBf+lqjKcCwFRKB3KHecEZA="}
SPARKLE_FEED_URL=${SPARKLE_FEED_URL:-"https://raw.githubusercontent.com/fmbabacan/PortHarbor/main/appcast.xml"}
APP_DIR="$BUILD_DIR/PortHarbor.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
ICONSET_DIR="$BUILD_DIR/PortHarbor.iconset"
ICON_SOURCE="$ROOT/Sources/PortHarborApp/Resources/Assets.xcassets/AppIcon.appiconset"
INSTALL_DIR=${INSTALL_DIR:-"$HOME/Applications"}
INSTALLED_APP="$INSTALL_DIR/PortHarbor.app"

if test -n "${ARCH:-}"; then
    swift build -c release --arch "$ARCH" --package-path "$ROOT"
else
    swift build -c release --package-path "$ROOT"
fi

rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR" "$ICONSET_DIR"

cp "$ICON_SOURCE/icon_16x16.png" "$ICONSET_DIR/icon_16x16.png"
cp "$ICON_SOURCE/icon_32x32.png" "$ICONSET_DIR/icon_16x16@2x.png"
cp "$ICON_SOURCE/icon_32x32.png" "$ICONSET_DIR/icon_32x32.png"
cp "$ICON_SOURCE/icon_64x64.png" "$ICONSET_DIR/icon_32x32@2x.png"
cp "$ICON_SOURCE/icon_128x128.png" "$ICONSET_DIR/icon_128x128.png"
cp "$ICON_SOURCE/icon_256x256.png" "$ICONSET_DIR/icon_128x128@2x.png"
cp "$ICON_SOURCE/icon_256x256.png" "$ICONSET_DIR/icon_256x256.png"
cp "$ICON_SOURCE/icon_512x512.png" "$ICONSET_DIR/icon_256x256@2x.png"
cp "$ICON_SOURCE/icon_512x512.png" "$ICONSET_DIR/icon_512x512.png"
cp "$ICON_SOURCE/icon_1024x1024.png" "$ICONSET_DIR/icon_512x512@2x.png"
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/PortHarbor.icns"

cp "$BUILD_DIR/release/PortHarbor" "$MACOS_DIR/PortHarbor"
chmod 755 "$MACOS_DIR/PortHarbor"

SPARKLE_FRAMEWORK=$(find "$BUILD_DIR" -path '*/release/Sparkle.framework' -type d -print -quit)
: "${SPARKLE_FRAMEWORK:?Sparkle.framework was not produced by Swift Package Manager}"
cp -R "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/Sparkle.framework"

/usr/libexec/PlistBuddy -c "Add :CFBundleDevelopmentRegion string en" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string PortHarbor" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string PortHarbor" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string PortHarbor" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.fmbabacan.PortHarbor" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleInfoDictionaryVersion string 6.0" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string PortHarbor" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundlePackageType string APPL" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $VERSION" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $BUILD_NUMBER" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :LSMinimumSystemVersion string 15.0" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSHighResolutionCapable bool true" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :NSSupportsAutomaticGraphicsSwitching bool true" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SPARKLE_FEED_URL" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$CONTENTS_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SUAutomaticallyUpdate bool false" "$CONTENTS_DIR/Info.plist"

cp "$ROOT/Sources/PortHarborApp/Resources/Localizable.xcstrings" "$RESOURCES_DIR/Localizable.xcstrings"

/usr/bin/plutil -convert binary1 "$CONTENTS_DIR/Info.plist"
/usr/bin/xattr -cr "$APP_DIR"
/usr/bin/codesign --force --deep --sign - "$APP_DIR"

if test "${PACKAGE_ONLY:-0}" = "1"; then
    printf '%s\n' "$APP_DIR"
    exit 0
fi

mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP"
cp -R "$APP_DIR" "$INSTALLED_APP"
/usr/bin/xattr -cr "$INSTALLED_APP"
/usr/bin/codesign --force --deep --sign - "$INSTALLED_APP"

printf '%s\n' "$INSTALLED_APP"
