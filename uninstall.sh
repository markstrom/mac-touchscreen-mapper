#!/bin/bash
LABEL=io.github.markstrom.touchmap

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"

if [ -e /usr/local/bin/touchmap ]; then
    echo "Removing binary (needs admin)"
    sudo rm -f /usr/local/bin/touchmap
fi

rm -f /tmp/touchmap.log

echo "Uninstalled."
echo "You may also want to remove touchmap from Input Monitoring and Accessibility."
