#!/bin/bash
# Builds Hush for the iOS Simulator and captures a screenshot of each screen.
set -euo pipefail
xcodebuild -project Hush.xcodeproj -target Hush -configuration Debug -sdk iphonesimulator -arch arm64 \
  SYMROOT="$PWD/simbuild" CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO \
  build > sim.log 2>&1 || { grep -E "error:" sim.log | sort -u; tail -n 30 sim.log; exit 1; }
APP="simbuild/Debug-iphonesimulator/Hush.app"
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]
c=[x for k,v in d.items() if "iOS" in k for x in v if x["name"].startswith("iPhone") and "Pro" in x["name"] and "Max" not in x["name"]]
print(c[-1]["udid"])')
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl ui "$UDID" appearance dark
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryLevel 100 --batteryState charged || true
xcrun simctl install "$UDID" "$APP"
BID=com.jacobwingstrom.hush
mkdir -p shots
shot() {
  local name=$1; shift
  xcrun simctl terminate "$UDID" "$BID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BID" -demoSeed YES "$@" >/dev/null
  sleep 5
  xcrun simctl io "$UDID" screenshot "shots/$name.png" >/dev/null
  echo "captured $name"
}
for s in home all notes tasks calendar journals drawings vault files contacts bookmarks; do
  shot "$s" -startSection "$s"
done
shot drawer -startSection notes -demoOpenDrawer YES
shot settings -startSection notes -demoOpenSettings YES
shot light-notes -startSection notes -theme light
