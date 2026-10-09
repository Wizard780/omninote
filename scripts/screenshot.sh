#!/bin/sh
# Screenshot the first on-screen window owned by an app, without needing Accessibility access.
# usage: scripts/screenshot.sh <AppName> <out.png>
set -e
APP="${1:-omninote}"; OUT="${2:-/tmp/$APP.png}"
WID="$(cd "$(dirname "$0")/.." && pwd)/build/wid"  # repo-local, not /tmp: never execute a world-writable path
mkdir -p "$(dirname "$WID")"
if [ ! -x "$WID" ]; then
  TMP=$(mktemp -d)
  cat > "$TMP/wid.swift" <<'EOF'
import CoreGraphics
import Foundation
let app = CommandLine.arguments[1]
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
// Largest window owned by the app (any layer, so a pinned/floating window still counts).
let mine = list.filter { ($0["kCGWindowOwnerName"] as? String) == app }
let best = mine.max { a, b in
    func area(_ w: [String: Any]) -> Double { let b = w["kCGWindowBounds"] as! [String: Double]; return b["Width"]! * b["Height"]! }
    return area(a) < area(b)
}
if let best { print(best["kCGWindowNumber"]!) }
EOF
  swiftc -O -o "$WID" "$TMP/wid.swift" 2>/dev/null
fi
ID=$("$WID" "$APP")
[ -n "$ID" ] || { echo "no window for $APP" >&2; exit 1; }
screencapture -x -o -l "$ID" "$OUT"
echo "$OUT"
