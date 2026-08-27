# Rephraze

Fix a clumsy sentence by double-tapping ⌥ (Option).

Type something, **double-tap the Option key**, and a floating note shows a
better version. Tap ⌥ once more to swap your words for it. `esc` cancels.

```
click into a typing box   (highlighting words is optional)
   │
 ⌥ ⌥ ──► reads your words ──► note pops up, better version streams in
   │
   ├─ ⌥    while streaming ──► swaps as soon as it finishes
   ├─ ⌥    after it's done  ──► swaps now
   └─ esc                   ──► never mind, nothing changes
```

Double-tap is deliberate: people tap a modifier alone by accident all the time,
but rarely twice in a row. And ⌥ on its own does nothing in any app, so if the
listener ever hiccups, nothing happens — instead of a half-finished message
getting sent.

**Why not ⌘⌘?** macOS binds "press either Command key twice" to Siri. ⌥ has no
system binding, so nothing to turn off.

## Where it works

Anywhere you can type: search bars, comment boxes, Slack messages, `<textarea>`
on a website.

Not whole documents — Word pages, Excel grids, PowerPoint slides and Google Docs
are canvases, not typing boxes, so it skips them. Typing boxes *inside* those
apps still work.

## Setup

```sh
make cert      # once -- see "Why the certificate" below
make install   # build, copy to /Applications, launch
```

Then one thing macOS needs:

**Grant Accessibility access.** Click the menu bar icon > "Grant Accessibility
access…". Without it the app cannot read your text or see the keyboard.

That's the only system setting. (Earlier designs used `fn`, which collides with
the emoji picker and Dictation, and ⌘⌘, which collides with Siri. ⌥⌥ is free.)

## Why the certificate

macOS remembers Accessibility permission by recognising an app's code signature.
Ad-hoc signing produces a *different* identity every build, so macOS sees each
rebuild as a new app and drops the permission — you would re-grant access after
every code change.

`make cert` creates a stable self-signed identity so the grant sticks. It asks
before touching your keychain, and prints how to undo it.

Builds work fine without it, just with that friction.

## Commands

| | |
|---|---|
| `make` | build `build/Rephraze.app` |
| `make run` | build and launch from `build/` |
| `make install` | build, copy to `/Applications`, launch |
| `make test` | run unit tests |
| `make status` | show signing identity and permission state |
| `make cert` | one-time signing identity setup |
| `make uninstall` | remove from `/Applications` |

## Notes

- Your text is sent to OpenAI. Password fields are refused, and specific apps can
  be blocked, but rewritten text does leave your machine.
- Slack `@mentions` come back as plain text, not clickable mentions.
- Cannot ship on the Mac App Store — the sandbox forbids reading other apps'
  content, which is the whole job.
