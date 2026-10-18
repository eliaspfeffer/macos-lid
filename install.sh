#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
build_dir=$(mktemp -d)
trap 'rm -rf "$build_dir"' EXIT
swiftc -O LidBrightness.swift -o "$build_dir/lid-brightness" -framework CoreGraphics -framework IOKit
"$build_dir/lid-brightness" --self-test
codesign --force --sign - "$build_dir/lid-brightness"
mkdir -p "$HOME/.local/bin" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
install -m 755 "$build_dir/lid-brightness" "$HOME/.local/bin/lid-brightness"
plist="$build_dir/com.eliaspfeffer.lid-brightness.plist"
/usr/bin/plutil -create xml1 "$plist"
/usr/bin/plutil -insert Label -string com.eliaspfeffer.lid-brightness "$plist"
/usr/bin/plutil -insert ProgramArguments -json '[]' "$plist"
/usr/bin/plutil -insert ProgramArguments.0 -string "$HOME/.local/bin/lid-brightness" "$plist"
/usr/bin/plutil -insert RunAtLoad -bool true "$plist"
/usr/bin/plutil -insert KeepAlive -bool true "$plist"
/usr/bin/plutil -insert ThrottleInterval -integer 5 "$plist"
/usr/bin/plutil -insert ProcessType -string Background "$plist"
/usr/bin/plutil -insert StandardOutPath -string "$HOME/Library/Logs/lid-brightness.log" "$plist"
/usr/bin/plutil -insert StandardErrorPath -string "$HOME/Library/Logs/lid-brightness.log" "$plist"
label=com.eliaspfeffer.lid-brightness
domain="gui/$(id -u)"
if launchctl print "$domain/$label" >/dev/null 2>&1; then
    launchctl bootout "$domain/$label"
fi
install -m 644 "$plist" "$HOME/Library/LaunchAgents/$label.plist"
# launchd can briefly retain a service after bootout completes.
for attempt in 1 2 3 4 5; do
    if launchctl bootstrap "$domain" "$HOME/Library/LaunchAgents/$label.plist"; then
        break
    fi
    if [[ "$attempt" == 5 ]]; then
        echo "Could not start the brightness service." >&2
        exit 1
    fi
    sleep 1
done
launchctl kickstart "$domain/$label"
"$HOME/.local/bin/lid-brightness" --status
