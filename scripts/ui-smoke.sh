#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PACKAGE_ONLY=1 "$ROOT/scripts/package-local-app.sh" > /tmp/portharbor-ui-package.txt
APP=$(tail -n 1 /tmp/portharbor-ui-package.txt)

open -n "$APP"
sleep 3
pgrep -x PortHarbor > /dev/null

WINDOW_COUNT=$(swift -e 'import CoreGraphics; let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]; let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []; let count = windows.filter { ($0[kCGWindowOwnerName as String] as? String) == "PortHarbor" && (($0[kCGWindowBounds as String] as? [String: Any])?["Width"] as? Double ?? 0) > 0 }.count; print(count)')
test "$WINDOW_COUNT" -gt 0

pkill -x PortHarbor
printf 'PortHarbor UI smoke passed with %s visible window(s).\n' "$WINDOW_COUNT"
