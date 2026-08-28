# Security

## Reporting a vulnerability

Open a [security advisory](https://github.com/markstrom/mac-touchscreen-mapper/security/advisories/new)
rather than a public issue.

## What this tool has access to

It requires the two most far-reaching permissions macOS grants, so it is worth
being precise about what they are used for. The README section
[What this tool does not do](README.md#what-this-tool-does-not-do) covers this for
users; the summary for reviewers:

| Permission | Used for | Not used for |
|---|---|---|
| Input Monitoring | Opening and seizing one USB HID device, matched by vendor and product ID | Keyboards, the trackpad, or any other input device |
| Accessibility | Posting mouse and scroll events derived from touches on that panel | Reading other applications, or any input not originating from the panel |

The binary links no networking framework. Verify with `otool -L`.

## Things a reviewer should look at

Being honest about where the sharp edges are:

- **Device selection.** `findTouchDevices()` requires `Transport == "USB"`
  specifically so the built-in trackpad, which is also a digitizer with usage
  `0x04`, can never be seized. Weakening that filter could take out a user's
  pointing device.
- **Seizing.** The tool takes exclusive control of the matched device. A bug in
  matching means some other device stops working for as long as it runs.
- **Event synthesis.** Every posted event should trace back to a touch on the
  panel. There is no code path that generates input from anything else, and there
  should not be.
- **No signature.** The binary is unsigned, so TCC grants bind to its cdhash.
  Anything that replaces the binary at `/usr/local/bin/touchmap` inherits nothing
  — the grants lapse and must be re-issued by the user in System Settings. That is
  a safety property, but it also means a user who re-grants without checking is
  approving whatever now sits at that path.

## Supported versions

The latest commit on `master`. This is a single-file tool with no release
branches; fixes land there.
