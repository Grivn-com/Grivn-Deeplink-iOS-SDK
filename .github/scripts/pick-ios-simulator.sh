#!/usr/bin/env bash
# Prints the UDID of an available iPhone simulator on the newest iOS runtime,
# creating one if that runtime has no iPhone yet.
#
# Why not `-destination name=iPhone 16`: some hosted macOS runners start with
# no usable simulator, and xcodebuild then lists only the "Any iOS Simulator
# Device" placeholder (seen 2026-11-06 on two images). So wait for a runtime
# instead of naming a device, and print the runtime state if none turns up.
set -euo pipefail

wait_seconds=${WAIT_SECONDS:-300}
deadline=$((SECONDS + wait_seconds))

newest_ios_runtime() {
  xcrun simctl list runtimes available -j |
    jq -r '[.runtimes[] | select(.platform == "iOS")]
           | sort_by(.version | split(".") | map(tonumber))
           | last | .identifier // empty'
}

until runtime=$(newest_ios_runtime) && [ -n "$runtime" ]; do
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo "No available iOS simulator runtime after ${wait_seconds}s." >&2
    xcrun simctl runtime list >&2 || true
    xcrun simctl list runtimes >&2 || true
    exit 1
  fi
  echo "Waiting for an iOS simulator runtime..." >&2
  sleep 15
done

udid=$(xcrun simctl list devices available -j |
  jq -r --arg rt "$runtime" '.devices[$rt] // []
                             | map(select(.name | startswith("iPhone")))
                             | first | .udid // empty')

if [ -z "$udid" ]; then
  device_type=$(xcrun simctl list runtimes -j |
    jq -r --arg rt "$runtime" '.runtimes[] | select(.identifier == $rt)
                               | .supportedDeviceTypes
                               | map(select(.productFamily == "iPhone"))
                               | first | .identifier // empty')
  if [ -z "$device_type" ]; then
    echo "Runtime $runtime supports no iPhone device type." >&2
    exit 1
  fi
  echo "No iPhone on $runtime, creating a $device_type." >&2
  udid=$(xcrun simctl create "CI iPhone" "$device_type" "$runtime")
fi

echo "Using simulator $udid on $runtime." >&2
echo "$udid"
