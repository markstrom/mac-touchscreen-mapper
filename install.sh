#!/bin/bash
# Install touchmap as a LaunchAgent in your own login session.
#
# Agent, not daemon: a root LaunchDaemon runs outside the login session and its
# CGEvent.post never reaches the desktop. Seizing the device does not require
# root — only Input Monitoring on the binary.
set -e
cd "$(dirname "$0")"

BIN=/usr/local/bin/touchmap
LABEL=io.github.markstrom.touchmap
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"

# Only rebuild when the source actually changed. A needless rebuild produces a new
# cdhash, which silently invalidates both TCC grants.
if [ ! -x touchmap ] || [ TouchMap.swift -nt touchmap ]; then
    echo "==> Building"
    swiftc -O -o touchmap TouchMap.swift
else
    echo "==> Source unchanged, not rebuilding"
fi

if [ -x "$BIN" ] && \
   [ "$(shasum -a 256 "$BIN" | cut -d' ' -f1)" = "$(shasum -a 256 touchmap | cut -d' ' -f1)" ]; then
    echo "==> Binary already current, skipping copy"
else
    echo "==> Installing binary (needs admin)"
    sudo install -m 755 touchmap "$BIN"
    echo
    echo "    The binary changed, so BOTH permissions must be re-granted:"
    echo "      System Settings > Privacy & Security > Input Monitoring"
    echo "      System Settings > Privacy & Security > Accessibility"
    echo "    Remove any existing touchmap row, then add $BIN again."
    echo
fi

echo "==> Installing LaunchAgent"
mkdir -p "$HOME/Library/LaunchAgents"
cp "$LABEL.plist" "$AGENT"

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$AGENT"

echo "==> Done. Log: /tmp/touchmap.log"
echo
"$BIN" --status || true
