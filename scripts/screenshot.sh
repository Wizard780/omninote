#!/bin/sh
# Screenshot the first on-screen window owned by an app, without needing Accessibility access.
# usage: scripts/screenshot.sh <AppName> <out.png>
set -e
APP="${1:-omninote}"; OUT="${2:-/tmp/$APP.png}"
TMP=$(mktemp -d)
cat > "$TMP/wid.swift" <<'EOF'
import CoreGraphics
import Foundation
let app = CommandLine.arguments[1]
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
for w in list where (w["kCGWindowOwnerName"] as? String) == app && (w["kCGWindowLayer"] as? Int) == 0 {
    print(w["kCGWindowNumber"]!); break
}
EOF
swiftc -O -o "$TMP/wid" "$TMP/wid.swift" 2>/dev/null
ID=$("$TMP/wid" "$APP")
[ -n "$ID" ] || { echo "no window for $APP" >&2; exit 1; }
screencapture -x -o -l "$ID" "$OUT"
echo "$OUT"
