---
name: My touch panel does not work
about: Touch is not landing correctly, or nothing happens at all
title: ''
labels: ''
assignees: ''
---

<!--
Almost every question about this tool comes down to what your specific panel
reports. The three commands below answer that, and with them an issue is usually
solvable in one reply instead of five.
-->

## What happens

<!-- e.g. "touch still clicks on the laptop screen", "nothing happens at all",
     "the cursor lands about 100 px too far left" -->

## Status

<!-- Paste the full output. It shows both permissions, the panel and the display. -->

```
$ touchmap --status

```

## Devices

```
$ touchmap --list-devices

```

```
$ touchmap --list-displays

```

## What the panel reports

<!--
Stop the agent, run in the foreground, touch the panel a few times near each
corner, then press Ctrl-C and paste 20-30 lines. This shows the report ID, the
byte layout and the coordinate range your controller uses.

  launchctl bootout gui/$UID/io.github.markstrom.touchmap
  /usr/local/bin/touchmap --debug

Start it again afterwards:

  launchctl bootstrap gui/$UID ~/Library/LaunchAgents/io.github.markstrom.touchmap.plist
-->

```

```

## System

- macOS version:
- Mac model:
- Monitor make and model:
- touchmap version: <!-- touchmap --version -->
