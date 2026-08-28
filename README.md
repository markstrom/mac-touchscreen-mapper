# mac-touchscreen-mapper

Make an external USB touchscreen work on macOS: touches land on the panel you
actually touched, instead of the corresponding spot on your laptop screen.

```bash
git clone https://github.com/markstrom/mac-touchscreen-mapper
cd mac-touchscreen-mapper
./install.sh
```

Then grant two permissions (see [Permissions](#permissions)). That's it — the
panel works from every login onward.

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

## Permissions

`/usr/local/bin/touchmap` must be added to **both** lists under
System Settings → Privacy & Security (`+` → ⌘⇧G → paste the path):

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
contents differ.

### Root is not required

An earlier version installed a LaunchDaemon in `/Library/LaunchDaemons`. That runs
as root outside the login session, where read-only CoreGraphics calls work
(`CGDisplayBounds` returns correct values) but `CGEvent.post` does **not** — events
never reach the desktop. The symptom is deceptive: seize succeeds, macOS's wrong
mapping disappears, and touch stops doing anything whatsoever.

Seizing needs Input Monitoring, not root privileges. A LaunchAgent in the user
session gets both halves working and needs no admin rights at runtime.

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

```bash
./status.sh
```

Checks the binary, the agent, the hash and the seize state, and prints the exact
command for whatever is missing. Log: `/tmp/touchmap.log`.

## Requirements

macOS 13 or later, Xcode command line tools. Built and verified on macOS 26
(Apple Silicon).

## License

MIT
