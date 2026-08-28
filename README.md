# mac-touchscreen-mapper

## You connected an external touchscreen to your Mac. The picture works. The touch doesn't.

You tap a button on the touch panel and nothing happens there — instead something
gets clicked over on your laptop screen, in roughly the same spot. Drag a finger
and you select text in a window you weren't even looking at. The panel works fine
on a Windows machine, and the shop said it was plug-and-play.

Sound familiar? That is what this tool fixes. Touches land where your finger
actually is.

It is not a broken panel, a bad cable, or a calibration you forgot to run. And
there is no setting hidden in System Settings that turns it on — macOS has no
touchscreen support at all, so there is nothing to switch on.

Jump to [Installation](#installation) for step-by-step instructions. It takes
about five minutes and assumes no prior command line experience. Want to know
first whether your screen is the right kind?
[Check before installing anything](#will-my-screen-work-check-before-installing-anything).

## Why it happens

macOS has never supported touchscreens. It has no concept of "this panel is a
touch surface located over there" — the notion does not exist in the system.

What it does have is support for *absolute pointing devices*, the category
graphics tablets fall into. A USB touch panel enumerates as one of those: it
reports "finger at 41% across, 11% down" rather than "cursor moved 3 pixels left".
macOS accepts those coordinates but has to decide which screen they refer to, and
it picks **whichever display the cursor happens to be on at that moment**.

Hence the behaviour that makes it look like a calibration fault rather than a
mapping one: the position is right, the screen is wrong.

The clearest way to recognise it: **touch works correctly whenever the cursor
already happens to be sitting on the touch panel**, and goes somewhere else the
rest of the time. If you have caught yourself nudging the cursor over to the touch
screen first so that tapping works, this is your bug.

Two things that seem like they should help, and don't:

- **Making the panel the main display.** The mapping follows the cursor, not the
  main display, so this changes nothing.
- **Installing a driver from the monitor's maker.** These are almost always
  Windows-only. The panel already speaks a standard protocol; nothing is missing
  at the hardware end.

This tool takes exclusive control of the panel so macOS stops guessing, then
converts the coordinates against the target display's real position on your
desktop and clicks there itself.

## Which displays this works with

Any **USB HID digitizer** — in Windows Device Manager these appear as
"HID-compliant touch screen".

| | |
|---|---|
| Transport | USB HID |
| Usage Page | `0x0D` (Digitizers) |
| Usage | `0x04` (Touch Screen) |
| Also exposes | A Mouse collection with absolute X/Y |

That is the standard touch panels have been built against for Windows Touch since
Windows 7, so it covers most of the market:

- Portable USB-C touch monitors (Nomad, Uperfect, Arzopa, Espresso, Duex, …)
- Point-of-sale and industrial touch panels
- USB touch overlays fitted to ordinary displays

Common controllers — WCH, ILITEK, Goodix, eGalax, SiS, Weida — all speak the same
HID protocol. The tool auto-detects the panel; nothing is hardcoded.

**Not supported:** panels requiring a vendor driver, or touch delivered over
anything other than USB HID.

### Will my screen work? Check before installing anything

Paste this into Terminal. It uses only tools already on your Mac — nothing to
download, nothing to build:

```bash
ioreg -r -c IOHIDDevice -d 1 | awk 'BEGIN{RS="\\+-o"} /"PrimaryUsagePage" = 13/ && /"PrimaryUsage" = 4\n/ && /"Transport" = "USB"/ {n="unnamed"; if (match($0,/"Product" = "[^"]*"/)) n=substr($0,RSTART+13,RLENGTH-14); print "compatible touchscreen: " n}'
```

With the panel plugged in, a compatible screen prints something like:

```
compatible touchscreen: TouchScreen
```

No output means macOS does not see a USB HID touchscreen. Check that the panel's
USB cable is connected — on many portable monitors the touch signal travels over a
*different* cable than the video, so the picture can work while touch does not.

The `"Transport" = "USB"` filter matters: a MacBook's built-in trackpad is also a
digitizer with usage `0x04`, but it is reached over SPI. Without that filter the
check reports the trackpad and gives a false positive.

After installing you can use the tool's own version, which also shows vendor and
product IDs:

```bash
touchmap --list-devices
```

## Installation

Five steps, about five minutes. Everything happens in the Terminal app and in
System Settings. You can copy each command and paste it into Terminal.

**Open Terminal:** press ⌘ + Space, type `Terminal`, press Return.

### Before you start: are you allowed to install things?

You need administrator rights for two moments during setup. On a personal Mac you
almost certainly have them. On a **work Mac**, they are often switched off — see
[Work Macs](#work-macs-when-admin-rights-are-locked) below before continuing.

Check by running this:

```bash
sudo -v
```

- Asks for your password and then returns silently → you're fine, continue.
- Says **`is not in the sudoers file`** → your admin rights are locked. Read
  [Work Macs](#work-macs-when-admin-rights-are-locked) first.

### Step 1 — Install Apple's build tools

The tool is compiled on your machine, which needs Apple's compiler. It ships free
with macOS but is not installed by default:

```bash
xcode-select --install
```

A dialog appears — click **Install** and wait for it to finish. If you get
`command line tools are already installed`, you already have it. Move on.

### Step 2 — Download and build

```bash
git clone https://github.com/markstrom/mac-touchscreen-mapper
cd mac-touchscreen-mapper
./install.sh
```

This compiles the tool, copies it to `/usr/local/bin/touchmap`, and sets it up to
start automatically at every login.

**It will ask for your password once.** That's macOS asking permission to place a
file in a system folder. Nothing is typed on screen while you type your password —
no dots, no stars. That's normal. Type it and press Return.

At the end it prints a status report. It will say a permission is missing. That's
expected — the next two steps fix it.

### Step 3 — Grant Input Monitoring

This lets the tool read the touch panel.

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
```

System Settings opens on the right page. Then:

1. Click the **`+`** button below the list
2. A file picker appears. Press **⌘ + Shift + G** — a small text box opens
3. Paste `/usr/local/bin/touchmap` and press Return, then click **Open**
4. Make sure the switch next to `touchmap` is **on** (blue)

macOS asks for your password or Touch ID to change this list. It will ask again in
step 4, and then never again.

### Step 4 — Grant Accessibility

This lets the tool move the cursor and click. It is a **separate** permission from
step 3 and both are required — this is the step people miss.

```bash
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

Same procedure: **`+`** → **⌘ + Shift + G** → `/usr/local/bin/touchmap` → Open →
switch **on**.

### Step 5 — Restart and verify

```bash
launchctl kickstart -k gui/$UID/io.github.markstrom.touchmap && touchmap --status
```

Every line should say `ok`:

```
touchmap status

  ok   binary installed: /usr/local/bin/touchmap
  ok   starts automatically at login
  ok   running (pid 20732)
  ok   Input Monitoring granted — can read the panel
  ok   Accessibility granted — can move the cursor and click
  ok   touchscreen: TouchScreen (vendor 0x27C0, product 0x0859)
  ok   target display: 1920x1080 @ (-1920,0)
```

Now touch your external screen. The cursor should land exactly where your finger
is. **You're done** — it starts by itself every time you log in, and needs no
admin rights to run.

If something is off, `touchmap --status` names the missing piece and prints the
command that fixes it. Run it any time, from any folder.

### Work Macs: when admin rights are locked

Many company Macs let you *temporarily* unlock administrator rights through a
tool your IT department installed — often a menu bar item named **Privileges**,
**Make Me Admin**, or something similar, sometimes a self-service portal.

The confusing part is that `sudo` can fail with:

```
yourname is not in the sudoers file.  This incident has been reported.
```

even while you appear to be an administrator. Check with:

```bash
id -Gn | tr ' ' '\n' | grep -x admin
```

If that prints `admin`, you are in the administrators group and IT has simply
removed that group from the `sudo` configuration. Unlocking through their tool
restores it. Do that, then run `sudo -v` again to confirm before continuing.

You need the unlock for **two moments only**:

| Moment | Admin needed |
|---|---|
| `./install.sh` copying the binary into `/usr/local/bin` | yes, once |
| Adding the tool to Input Monitoring and Accessibility | yes, once |
| Everyday use, and every restart afterwards | **no** |

Once installed, the tool keeps working even after your admin rights are taken
away again. It is a LaunchAgent in your own home folder and needs no elevated
privileges to run — that is deliberate, precisely so a temporary unlock is enough.

If your organisation blocks these permissions entirely by policy, no workaround
exists in this tool and you will need IT to approve it.

## Permissions reference

`/usr/local/bin/touchmap` must appear in **both** lists under
System Settings → Privacy & Security:

| Permission | Needed for | Symptom when missing |
|---|---|---|
| **Input Monitoring** | Reading the panel, taking exclusive control | `0xE00002E2` in the log; macOS's wrong mapping persists |
| **Accessibility** | Posting mouse events to the desktop | Seize succeeds, panel goes silent — touch does *nothing at all* |

The second one is easy to miss. Run the tool from Terminal and it inherits
Terminal's Accessibility grant, so everything works. Started by launchd it stands
on its own and has none — it then reads the panel perfectly and posts events that
nobody receives.

Both grants are bound to the binary's cdhash. Rebuilding invalidates them, so
`install.sh` rebuilds only when the source changed and copies only when the
contents differ. If you do rebuild, remove the old `touchmap` row from both lists
and add it again — the stale row looks correct but grants nothing.

## What this tool does not do

Input Monitoring and Accessibility are the two most far-reaching permissions macOS
grants. Between them they describe a keylogger. You should be suspicious of
anything asking for both, including this — so here is exactly what it does with
them, and how to check rather than take my word for it.

**It does not touch the network.** No telemetry, no update check, no crash
reporting. Nothing leaves your machine — and you do not have to trust that
sentence, because it is checkable two ways.

The binary does not link a single networking framework. No `CFNetwork`, no
`Network.framework`, nothing that could open a socket:

```bash
otool -L /usr/local/bin/touchmap
```

You will see IOKit, CoreGraphics, ColorSync, ApplicationServices, Foundation and
the Swift runtime. That is the complete list.

And it holds no connections while running:

```bash
lsof -i -a -p "$(pgrep -x touchmap)"
```

That prints nothing. Not "nothing interesting" — no rows at all.

**It does not read your keyboard.** Input Monitoring is what macOS requires to open
*any* HID device. This one opens exactly one: the USB touch panel it matched by
vendor and product ID. It never enumerates keyboards, never opens the built-in
trackpad — which it explicitly excludes — and never installs a keyboard event tap.

**It does not record what you do.** The log holds startup messages. Coordinates
appear only when you pass `-v`, and raw HID reports only with `--debug`, both of
which are diagnostic flags you invoke deliberately. Nothing is written anywhere
else, ever.

**It does not run as root.** It runs as you, from a LaunchAgent in your own home
folder. It cannot modify the system even if it wanted to.

**What it does do with Accessibility** is the honest part to be uneasy about: it
synthesises mouse events, which land system-wide like any other click. That
capability is the whole point of the tool, and there is no smaller permission that
provides it. Every event it posts originates from a touch you made on the panel.

**How to check for yourself:** it is one Swift file, no dependencies, no build
system, no vendored code. The entire program is
[`TouchMap.swift`](TouchMap.swift) — small enough to read end to end in a sitting,
and `docs/INTERNALS.md` explains what every part of it is for. Compare the binary
you installed against a build of your own:

```bash
shasum -a 256 /usr/local/bin/touchmap touchmap
```

Two identical hashes mean the running binary is exactly what the source compiles
to.

## Gestures

| Gesture | Events | Result |
|---|---|---|
| Touch and lift | `down` … `up` | Click |
| Two quick taps | `clickState` 2 | Double-click |
| Touch and drag | `down`, `dragged` …, `up` | Drag |
| **Hold still 0.5 s, then drag** | `down`, `up`, scroll … | **Scroll** |

`leftMouseDown` is posted on touch-down, not on lift. Posting both on lift
produced a zero-duration click that applications silently ignored — the cursor
moved correctly but nothing happened.

A consequence is that a long press emits a click before scrolling begins. In
practice this is harmless: it sets focus. Scroll mode releases the button when
the hold expires, so no button press is left hanging.

Tune with `--hold-time 0.3`, `--scroll-scale 1.5`, `--invert-scroll`.

### Why not two-finger scroll

The reference panel never reports more than one contact. Its `Device Mode`
feature report acknowledges every write with `kIOReturnSuccess` but stores
nothing: reading back returns the same constant bytes `161,1,33,3,0,0,8,0`
whether you write 0, 1, 2 or 3 — and those bytes are fragments of a HID
descriptor, not a mode value. The panel keeps sending report ID 7 only.

Check your own panel:

```bash
sudo ./touchmap --probe-modes --debug
```

If yours does honour the mode switch and starts sending report ID 13, two-finger
scroll works: the code path for two or more simultaneous contacts is already
there. [The full probe output and what it means](docs/INTERNALS.md#why-the-digitizer-stays-silent).

## Usage

```
touchmap [options]

SETUP
  --status            Check installation, permissions and hardware, then exit
  --version           Print the version and exit

DEVICE
  --list-devices      List touchscreen-capable HID devices and exit
  --vendor <id>       Vendor ID (decimal or 0x hex). Default: auto-detect
  --product <id>      Product ID. Default: auto-detect

DISPLAY
  --list-displays     List connected displays and exit
  --display <uuid>    Target display UUID. Default: first external display

GESTURES
  --hold-time <sec>   Hold duration before a press becomes scroll (0.5)
  --scroll-scale <n>  Scroll speed multiplier (1.0)
  --invert-scroll     Reverse scroll direction

DIAGNOSTICS
  -v, --verbose       Log interpreted gestures
  --debug             Log every HID report and element
  --no-seize          Do not take exclusive control of the device
  --multitouch        Try to switch the panel into multitouch mode
  --probe-modes       Write every Device Mode value and read each back
```

## Troubleshooting

Start here. It asks the system directly about every prerequisite — installation,
both permissions, the panel, the display — and prints the exact command for
whatever is missing:

```bash
touchmap --status
```

Before installing, run it from the project folder as `./touchmap --status`. Note
that permissions are granted per binary: a copy in your Downloads folder and the
installed one at `/usr/local/bin/touchmap` have separate grants, and the check
reports on whichever copy you ran. It tells you when those differ.

| Symptom | Cause | Fix |
|---|---|---|
| Touch still clicks on the laptop screen | The tool isn't running, or Input Monitoring is missing | `touchmap --status` |
| Touch does **nothing at all** | Accessibility missing — the tool reads the panel but its clicks go nowhere | [Step 4](#step-4--grant-accessibility) |
| Worked before, stopped after rebuilding | New cdhash voided both grants | Remove and re-add `touchmap` in both permission lists |
| `device is already held exclusively` | An older copy is still running | `pkill -x touchmap` then `touchmap --status` |
| `no touchscreen found` | Panel not detected as a HID digitizer | `./touchmap --list-devices` |
| Cursor lands on the wrong external screen | Wrong display picked | `touchmap --list-displays`, then add `--display <uuid>` to the agent plist — see [Pinning a display](#pinning-a-display) |
| `is not in the sudoers file` | Admin rights locked | [Work Macs](#work-macs-when-admin-rights-are-locked) |

Full log: `/tmp/touchmap.log`. To watch gestures as you make them, stop the agent
and run it in the foreground:

```bash
launchctl bootout gui/$UID/io.github.markstrom.touchmap
/usr/local/bin/touchmap -v
```

Press Ctrl-C to stop, then start the agent again:

```bash
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/io.github.markstrom.touchmap.plist
```

## What it cannot do

- **Unlock the Mac.** The panel is seized while the tool runs, so the lock screen
  never sees touch. Use the keyboard or trackpad to log back in.
- **Serve a second user.** The tool belongs to one login session and keeps the
  panel while that session is switched away, so another user gets nothing from it.
- **Two-finger gestures**, on panels that ignore the mode switch — which is most of
  them. Hold-and-drag replaces scrolling. No pinch, no rotate.
- **Hover.** The panel reports nothing until you touch it, so the cursor jumps
  rather than tracking an approaching finger.
- **Right-click.** Nothing is mapped to a secondary button; a long press is taken
  by the scroll gesture.
- **Rotated displays.** The mapping assumes an unrotated target. Mirroring is
  untested.

## Pinning a display

With one external screen, auto-detection is right and there is nothing to do. With
two or more, the tool takes the first external display it finds, which may not be
the touch panel.

Find the right UUID:

```bash
touchmap --list-displays
```

Then edit the agent and add the flag inside `ProgramArguments`:

```bash
open -e ~/Library/LaunchAgents/io.github.markstrom.touchmap.plist
```

```xml
<key>ProgramArguments</key>
<array>
    <string>/usr/local/bin/touchmap</string>
    <string>--display</string>
    <string>F8025F1D-72E2-462F-8530-0F16BAC7BC1D</string>
</array>
```

Each flag and each value is its own `<string>`. Then restart it:

```bash
launchctl kickstart -k gui/$UID/io.github.markstrom.touchmap
```

`install.sh` will not overwrite an agent you have edited — it keeps your version
and says so. Use `./install.sh --reset-agent` if you want the default back.

The same place is where you would add `--invert-scroll`, `--hold-time 0.3`, or
`--scroll-scale 1.5` to make them permanent.

## Uninstalling

```bash
./uninstall.sh
```

Removes the agent and the binary. Also remove `touchmap` from Input Monitoring and
Accessibility if you want to clean up completely.

## How it works

1. Finds a HID device whose primary usage is Touch Screen (`0x0D`/`0x04`)
2. Seizes every collection on that device, so macOS stops mapping it wrongly
3. Rescales the absolute coordinates against the target display's real global
   bounds, read from CoreGraphics
4. Posts its own mouse and scroll events there

The display's position is read fresh on every touch, so rearranging your screens
takes effect immediately — no restart, no reconfiguration. Put the panel to the
left, right, above or below; all four are verified.

One detail worth knowing even if you never read the code: the touch data does
**not** arrive on the digitizer collection. That one is silent on macOS. It comes
in on the panel's mouse-emulation collection as absolute coordinates:

```
07 01 00 35 7C 0E 00
│  │  └─X──┘ └─Y──┘ └ wheel
│  └ buttons (bit 0 = finger down)
└ report ID
```

### Going deeper

**[docs/INTERNALS.md](docs/INTERNALS.md)** documents the whole mechanism, measured
rather than assumed:

- The three HID collections, every report ID, and the exact byte layout
- Why the digitizer never speaks, and how to test whether yours does
- The three IOKit details that cost real debugging time — per-element callbacks,
  collection cookies, relative-axis filtering
- The coordinate transform, verified corner by corner
- What seizing does, and what breaks without it
- Why a click needs duration, and how `clickState` drives double-clicks
- The gesture state machine, as a diagram
- The two TCC services, how grants bind to a binary's cdhash, and why running from
  Terminal hides a missing one
- Why a LaunchDaemon cannot work, in detail
- The two error codes you will actually hit
- A step-by-step guide to porting this to another panel
- Known limitations

## Contributing

The most useful thing anyone can contribute is **a report from a panel I do not
own** — everything here was measured on a single monitor. See
[CONTRIBUTING.md](CONTRIBUTING.md) for what to capture, and
[SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## Requirements

Xcode command line tools, to compile the single source file.

Developed and verified on **macOS 26, Apple Silicon**. The APIs it uses
(`IOHIDCheckAccess`, `AXIsProcessTrusted`, `CGEvent`, the IOKit HID manager) have
been available since macOS 10.15, so macOS 13 and later should work — but that is
reasoning, not testing. If you run it on something older, a note in an issue would
be genuinely useful.

## License

MIT
