# Contributing

The most valuable contribution to this project is **a report from a panel I do not
own**. Everything here was measured on one 16" USB-C monitor with a `wch.cn`
controller. Whether other panels behave the same is genuinely unknown.

## Reporting a panel

Whether it works or not, this is useful:

```bash
touchmap --list-devices
touchmap --status
```

Then the interesting part — what your controller actually sends:

```bash
launchctl bootout gui/$UID/io.github.markstrom.touchmap
/usr/local/bin/touchmap --debug
```

Touch near each corner, press Ctrl-C, and include 20–30 lines. Restart the agent
afterwards:

```bash
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/io.github.markstrom.touchmap.plist
```

Three things make a report especially worth having:

- **A panel that honours the mode switch.** Run `sudo touchmap --probe-modes`. If
  the readback tracks what is written and report ID 13 starts appearing, that
  panel does real multitouch — the code path exists but has never run on hardware.
- **A panel using a report ID other than 7**, or a different byte layout.
- **A panel that does not use its full logical range.** The transform assumes it
  does. If your corners do not reach the declared maxima, calibration is needed
  and the code has no support for it yet.

## Building

One file, no dependencies, no build system:

```bash
swiftc -O -o touchmap TouchMap.swift
```

`./install.sh` does the same and sets up the LaunchAgent.

**Rebuilding invalidates both TCC grants.** They are bound to the binary's cdhash,
and the rows left in System Settings look fine while granting nothing. After
changing the code, remove `touchmap` from Input Monitoring and Accessibility and
add it back. `touchmap --status` will tell you which one is missing.

## Testing a change

There are no unit tests. The state machine is driven by hardware and the
permissions are per-binary, so almost nothing meaningful can be tested off the
device. What CI checks is that it compiles and that argument handling behaves.

Test by hand:

```bash
launchctl bootout gui/$UID/io.github.markstrom.touchmap
./touchmap -v
```

Then verify each gesture deliberately:

| Gesture | Expected log |
|---|---|
| Tap | `down` then `up` at the same point |
| Tap a button in an app | it actually activates — a click needs real duration |
| Drag | `down`, `drag`, `up` |
| Hold still 0.5 s, then drag | `scroll mode`, then `scroll` lines |
| Touch each corner | mapped coordinates within a pixel or two of the display bounds |

The corner check is the one that catches coordinate regressions. Compare against
`touchmap --list-displays`.

## Style

Match what is there. Comments explain *why*, particularly where the obvious
approach fails — several of those failures cost hours to find and the notes are
the record of them.

`docs/INTERNALS.md` documents measured behaviour. If you change what the code does
with the hardware, update it, and say what you measured rather than what you
expect.
