#!/bin/bash
# App Store screenshot capture for iPhone 14 Plus (1284x2778, the 6.7" slot).
#
#   Tools/capture-screenshots.sh <output-dir> [device-udid]
#
# Drives the app with ScreenshotDriver's launch arguments (DEBUG only) rather
# than by tapping, so it needs no UI automation. Points at the public Jellyfin
# demo server so nobody's real library ends up in a listing.
#
# If a screenshot comes back with an "Open in Cove?" system alert on it, some
# earlier `simctl openurl` left it behind: it survives app reinstalls, so
# shut the device down and boot it again before re-running.
# Two of these come back as empty states, and that is the tool's limit rather
# than a bug: entering a search query and starting a download both need a tap,
# and ScreenshotDriver can only sign in, pick a tab, or push an item. If you
# want Search-with-results or Downloads-in-progress for a listing, either drive
# those two by hand or teach the driver a -screenshotQuery / -screenshotDownload
# argument. Downloads is a headline feature in the App Store copy, so an empty
# shot of it undersells the app.
#
# There is deliberately no Music shot: FeatureFlags.musicEnabled is false, so
# the tab does not exist. Re-add one here if music is ever turned back on.

set -euo pipefail

OUT="${1:?usage: capture-screenshots.sh <output-dir> [device-udid]}"
DEV="${2:-Cove-14Plus}"
APP_ID="com.nikolajjsj.cove"
SERVER="https://demo.jellyfin.org/stable"
USER_NAME="demo"
SETTLE="${SETTLE:-26}"   # seconds to wait for network + artwork before capturing

mkdir -p "$OUT"

xcrun simctl status_bar "$DEV" override \
    --time "9:41" --batteryState charged --batteryLevel 100 \
    --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3

shoot() {
    local name="$1"; shift
    xcrun simctl terminate "$DEV" "$APP_ID" 2>/dev/null || true
    sleep 2
    xcrun simctl launch "$DEV" "$APP_ID" \
        -screenshotServer "$SERVER" -screenshotUser "$USER_NAME" "$@" >/dev/null
    sleep "$SETTLE"
    xcrun simctl io "$DEV" screenshot "$OUT/$name.png" >/dev/null 2>&1
    echo "captured $name"
}

shoot 01-home      -screenshotTab home
shoot 02-detail    -screenshotItem 5e6e8380563c5211106652362c5c6843
shoot 03-movies    -screenshotTab movies
shoot 04-search    -screenshotTab search
shoot 05-downloads -screenshotTab downloads

echo "done -> $OUT"
