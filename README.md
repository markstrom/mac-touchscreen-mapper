# mac-touchscreen-mapper

Make an external USB touchscreen work on macOS: touches land on the panel you
actually touched, instead of the corresponding spot on your laptop screen.

Jump to [Installation](#installation) for step-by-step instructions. It takes
about five minutes and assumes no prior command line experience.

## The problem

macOS has no touchscreen support at all. A USB touch panel enumerates as a HID
device reporting *absolute* coordinates, and macOS maps those coordinates onto
whichever display currently holds the cursor. Touch the external panel and the
click lands on your built-in screen instead — at the matching relative position,
which makes it look like a calibration bug rather than a mapping one.

The giveaway: touch works correctly *if the cursor already happens to be on the
touch panel*, and goes somewhere else if it isn't.

There is no macOS setting that fixes this. Making the panel the main display does
not help, because the mapping follows the cursor, not the main display.

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

Check yours:

```bash
./touchmap --list-devices
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
launchctl kickstart -k gui/$UID/io.github.markstrom.touchmap && ./status.sh
```

You want to see:

```
ok   exclusive control of the panel (Input Monitoring granted)
```

Now touch your external screen. The cursor should land exactly where your finger
is. **You're done** — it starts by itself every time you log in, and needs no
admin rights to run.

If something is off, `./status.sh` names the missing piece and prints the command
that fixes it. Run it any time.

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
there.

## Usage

```
touchmap [options]

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

Start here. It checks the binary, the agent, the hash and the seize state, and
prints the exact command for whatever is missing:

```bash
./status.sh
```

| Symptom | Cause | Fix |
|---|---|---|
| Touch still clicks on the laptop screen | The tool isn't running, or Input Monitoring is missing | `./status.sh` |
| Touch does **nothing at all** | Accessibility missing — the tool reads the panel but its clicks go nowhere | [Step 4](#step-4--grant-accessibility) |
| Worked before, stopped after rebuilding | New cdhash voided both grants | Remove and re-add `touchmap` in both permission lists |
| `device is already held exclusively` | An older copy is still running | `pkill -x touchmap` then `./status.sh` |
| `no touchscreen found` | Panel not detected as a HID digitizer | `./touchmap --list-devices` |
| Cursor lands on the wrong external screen | Wrong display picked | `./touchmap --list-displays`, then add `--display <uuid>` to the agent plist |
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

Display geometry is re-read automatically when displays are connected,
disconnected, or change resolution.

### Where the data actually comes from

A panel typically exposes three HID collections: Mouse, TouchScreen digitizer,
and something vendor-specific. On macOS the digitizer is usually **silent**.
Windows touch panels start in mouse-emulation mode and only begin sending
multitouch reports once the host writes to the `Device Configuration` feature
report (report ID 33, Device Mode usage `0x52`). macOS never does this.

So the data arrives on the Mouse collection instead, as absolute coordinates:

```
07 01 00 35 7C 0E 00
│  │  └─X──┘ └─Y──┘ └ wheel
│  └ buttons (bit 0 = finger down)
└ report ID
```

Logical maxima are read from the HID elements themselves, so scaling is correct
without hardcoding. Verified on the reference panel: a touch 5 px from the left
edge produces an X fraction of 0.3 %, and all four corners map within one pixel.

### Root is not required

An earlier version installed a LaunchDaemon in `/Library/LaunchDaemons`. That runs
as root outside the login session, where read-only CoreGraphics calls work
(`CGDisplayBounds` returns correct values) but `CGEvent.post` does **not** — events
never reach the desktop. The symptom is deceptive: seize succeeds, macOS's wrong
mapping disappears, and touch stops doing anything whatsoever.

Seizing needs Input Monitoring, not root privileges. A LaunchAgent in the user
session gets both halves working and needs no admin rights at runtime.

## Requirements

macOS 13 or later, Xcode command line tools. Built and verified on macOS 26
(Apple Silicon).

## License

MIT
