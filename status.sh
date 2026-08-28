#!/bin/bash
# Report exactly where the installation stands and what the next step is.
BIN=/usr/local/bin/touchmap
LABEL=io.github.markstrom.touchmap
AGENT="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG=/tmp/touchmap.log
SRC="$(cd "$(dirname "$0")" && pwd)/touchmap"

ok()  { printf '  \033[32mok\033[0m   %s\n' "$1"; }
bad() { printf '  \033[31mfail\033[0m %s\n' "$1"; }

echo "touchmap status"
echo

[ -x "$BIN" ]   && ok "binary installed: $BIN" || bad "binary missing from /usr/local/bin"
[ -f "$AGENT" ] && ok "LaunchAgent installed"  || bad "LaunchAgent missing"

if pgrep -x touchmap >/dev/null; then
    ok "running (pid $(pgrep -x touchmap | tr '\n' ' '))"
else
    bad "not running"
fi

if [ -x "$BIN" ] && [ -x "$SRC" ]; then
    if [ "$(shasum -a 256 "$BIN" | cut -d' ' -f1)" = "$(shasum -a 256 "$SRC" | cut -d' ' -f1)" ]; then
        ok "installed binary matches the build"
    else
        bad "installed binary differs from the build — run ./install.sh"
    fi
fi

# Seize status from the MOST RECENT startup. Each run's first line begins with
# "device:", which delimits runs from one another.
LAST=$(grep -n "^device:" "$LOG" 2>/dev/null | tail -1 | cut -d: -f1)
if [ -n "$LAST" ]; then
    BLOCK=$(tail -n "+$LAST" "$LOG")

    # Test the failure first: "could not take exclusive control" contains the
    # success string as a substring. Hence the ^ anchor on the success test.
    if echo "$BLOCK" | grep -q "0xE00002E2"; then
        bad "seize denied (0xE00002E2) — Input Monitoring missing"
        echo
        echo "  1. open \"x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent\""
        echo "  2. Remove any existing touchmap row with the minus button."
        echo "     A replaced binary has a new cdhash; the old row looks fine but is void."
        echo "  3. Click +, press Cmd-Shift-G, enter: $BIN"
        echo "  4. Enable the toggle"
        echo "  5. launchctl kickstart -k gui/\$UID/$LABEL"
        exit 1

    elif echo "$BLOCK" | grep -q "0xE00002C5"; then
        bad "device held by another process"
        echo
        echo "  Run: pkill -x touchmap && launchctl kickstart -k gui/\$UID/$LABEL"
        exit 1

    elif echo "$BLOCK" | grep -q "^exclusive control"; then
        ok "exclusive control of the panel (Input Monitoring granted)"
        echo
        echo "Touch the panel. The cursor should land where your finger is."
        echo "Hold still for half a second, then drag, to scroll."
        echo
        echo "NOTHING HAPPENS AT ALL? Then the SECOND permission is missing."
        echo "  Reading the panel needs Input Monitoring (granted)."
        echo "  Posting mouse events needs Accessibility."
        echo
        echo "  1. open \"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility\""
        echo "  2. Click +, press Cmd-Shift-G, enter: $BIN"
        echo "  3. Enable the toggle"
        echo "  4. launchctl kickstart -k gui/\$UID/$LABEL"
        exit 0
    fi
fi

bad "could not read seize status from $LOG"
exit 1
