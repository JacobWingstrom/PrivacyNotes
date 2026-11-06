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
for s in home all notes tasks boards habits calendar journals drawings vault files contacts bookmarks; do
  shot "$s" -startSection "$s"
done
shot drawer -startSection notes -demoOpenDrawer YES
shot settings -startSection notes -demoOpenSettings YES
shot light-notes -startSection notes -theme light
shot note-editor -startSection notes -demoOpenNote YES
shot monokai-notes -startSection notes -theme spectrum -accentHex FF6188 -fontStyle jetbrainsMono
shot monokai-editor -startSection notes -demoOpenNote YES -theme spectrum -accentHex FF6188 -fontStyle jetbrainsMono
shot dracula-home -startSection home -theme vampire -accentHex BD93F9 -fontStyle firaCode
shot latte-habits -startSection habits -theme latte -accentHex 8839EF -fontStyle inter
shot lock -startSection home -demoLock YES
shot home-edit -startSection home -demoHomeEdit YES
shot journal-mood -startSection journals
shot lab-overview -startSection homelab -labTab overview
shot lab-devices -startSection homelab -labTab devices
shot lab-diagram -startSection homelab -labTab diagrams -demoOpenDiagram YES
shot lab-network -startSection homelab -labTab network
shot lab-services -startSection homelab -labTab services
shot board-open -startSection boards -demoOpenBoard YES
shot lab-proxmox -startSection homelab -labTab proxmox
shot lab-stacks -startSection homelab -labTab stacks
shot notes-graph -startSection notes -demoGraph YES
shot calendar-day -startSection calendar -calendarDayView YES
shot habit-detail -startSection habits -demoOpenHabit YES
