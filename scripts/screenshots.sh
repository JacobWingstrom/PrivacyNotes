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

# End-to-end sync test against a real hush-server on this Mac (started by CI with HUSH_SYNC_TOKEN).
if [ -n "${HUSH_SYNC_TOKEN:-}" ]; then
  SPEC="http://localhost:8080|${HUSH_SYNC_TOKEN}|correct horse battery staple"
  stats() { curl -fsS -H "Authorization: Bearer ${HUSH_SYNC_TOKEN}" http://localhost:8080/v1/stats; }
  shot sync-setup -startSection notes -demoOpenSync YES
  # 1. This iPhone (with demo data) creates the passphrase and uploads everything.
  xcrun simctl terminate "$UDID" "$BID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BID" -demoSeed YES -startSection notes -demoOpenSync YES -syncTest "$SPEC" >/dev/null
  for i in $(seq 1 30); do
    n=$(stats | python3 -c 'import json,sys; print(json.load(sys.stdin)["records"])')
    [ "$n" -ge 20 ] && break; sleep 2
  done
  sleep 4
  xcrun simctl io "$UDID" screenshot shots/sync-status.png >/dev/null
  echo "server after upload: $(stats)"
  [ "$n" -ge 20 ] || { echo "sync upload failed: only $n records on the server"; exit 1; }
  curl -fsS -H "Authorization: Bearer ${HUSH_SYNC_TOKEN}" "http://localhost:8080/v1/pull?limit=1000" > pulled.json
  if grep -q "Homelab notes\|Trip ideas" pulled.json; then echo "PLAINTEXT FOUND ON SERVER"; exit 1; fi
  echo "server copy is encrypted (no note text visible)"
  # 2. A fresh install joins with the passphrase and gets everything back.
  xcrun simctl terminate "$UDID" "$BID" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$UDID" "$BID"
  xcrun simctl install "$UDID" "$APP"
  before=$(stats)
  xcrun simctl launch "$UDID" "$BID" -startSection notes -syncTest "$SPEC" >/dev/null
  sleep 25
  xcrun simctl io "$UDID" screenshot shots/sync-restored.png >/dev/null
  xcrun simctl terminate "$UDID" "$BID" >/dev/null 2>&1 || true
  xcrun simctl launch "$UDID" "$BID" -startSection homelab -labTab devices >/dev/null
  sleep 6
  xcrun simctl io "$UDID" screenshot shots/sync-restored-lab.png >/dev/null
  echo "server before restore: $before"
  echo "server after restore:  $(stats)"
  echo "captured sync shots"
fi
