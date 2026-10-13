# PPT Clicker

**Turn any mouse into a presentation clicker.**

No dongle, no extra hardware, no vendor driver. While your slideshow is running,
PPT Clicker makes your ordinary mouse (or trackpad buttons) behave like a
presentation remote — and gets out of the way the rest of the time.

![icon](Resources/preview.png)

```
left click      -> next slide          (sends →)
wheel down      -> next slide          (sends →)
right click     -> previous slide      (sends ←)
wheel up        -> previous slide      (sends ←)
```

Works with **Keynote, Microsoft PowerPoint, WPS Office, LibreOffice Impress,
Preview, Adobe Acrobat** and anything else that responds to arrow keys —
including browser-based decks such as Google Slides.

---

## Features

| | |
| --- | --- |
| **Any mouse** | Bluetooth, 2.4G, USB, trackpad buttons — if macOS sees the clicks, PPT Clicker can remap them |
| **Four ways to toggle** | global shortcut (default `⌃⌥⌘P`), double-click the wheel button, `ESC`, or click the indicator dot |
| **Corner indicator dot** | a small always-on-top dot: green = remapping active, grey ring = idle. Click to toggle, drag to move |
| **Remaps only what you choose** | left / right / middle / side buttons / wheel up-down-left-right → next, prev, Page Up/Down, space, Esc, black, white, swallow, or pass through |
| **Auto scroll direction** | follows your macOS *Natural scrolling* setting, so wheel-down is *next slide* on every machine |
| **Remembers nothing about you** | no network, no telemetry, no keyboard logging. The event tap subscribes to mouse events only (plus a read-only ESC listener when you enable ESC-to-disable) |
| **Zero dependencies** | plain Swift + AppKit, ~1.5k lines, no package manager, no Xcode project |

## Install

### 1. Download

Grab `PPT-Clicker-<version>.zip` (or `.dmg`) from
[Releases](https://github.com/<owner>/ppt-clicker/releases), unzip and drag
**PPTClicker.app** into `/Applications`.

### 2. Bypass Gatekeeper once

The app is not notarized (that requires a paid Apple Developer account), so
macOS will refuse the first launch. Either:

- Right-click the app → **Open** → **Open** again, or
- run once:

  ```bash
  xattr -dr com.apple.quarantine "/Applications/PPTClicker.app"
  ```

### 3. Grant permissions

| Permission | Why | Required? |
| --- | --- | --- |
| **Accessibility** | intercept and replace mouse events | **yes** |
| **Input Monitoring** | read-only listener for the `ESC` key | only if you want ESC-to-disable |

System Settings → Privacy & Security → Accessibility / Input Monitoring → enable
**PPT Clicker**. The app opens the right pane for you on first launch and shows
its own status in the menu.

> Rebuilding the app invalidates the grant on macOS (the permission is bound to
> the binary's code signature), so you have to toggle it again after each local
> rebuild.

### Homebrew

```bash
brew install --cask ./packaging/homebrew/ppt-clicker.rb   # local file, after cloning
```

A cask template lives in [`packaging/homebrew/`](packaging/homebrew/ppt-clicker.rb);
use it with your own tap once you publish a release.

## Usage

1. Start your slideshow.
2. Turn the clicker on — **double-click the mouse wheel button** (or press `⌃⌥⌘P`).
   The corner dot turns **green**.
3. Left click / wheel down = next slide. Right click / wheel up = previous slide.
4. Turn it off — press `ESC`, double-click the wheel again, press `⌃⌥⌘P`, or click
   the dot.

The dot lives at the **top-right corner, just below the menu bar**. Drag it
anywhere (position is remembered); right-click it for the full menu. There is
also a regular menu bar item with the same menu.

> By default the remapping is **global**: while the dot is green, clicks and
> wheel events are replaced everywhere, not only in your slideshow app. That is
> the most predictable behaviour (and works for web decks too). If you would
> rather scope it to presentation apps, enable *"Only inside presentation apps"*
> in the menu or set `"scope": "apps"` in the config.

## Configuration

```
~/Library/Application Support/PPTClicker/config.json
```

Menu → *Open config file…*, edit, then *Reload config*. A fully commented
example ships as [`config.example.json`](config.example.json).

### Events you can bind

`leftClick`, `rightClick`, `middleClick`, `backButton`, `forwardButton`,
`scrollUp`, `scrollDown`, `scrollLeft`, `scrollRight`

### Actions

| Value | Meaning |
| --- | --- |
| `next` / `prev` | send `→` / `←` |
| `pageDown` / `pageUp` | send Page Down / Page Up |
| `space` / `escape` | send Space / Esc |
| `black` / `white` | Keynote black/white screen (`b` / `w`) |
| `none` | swallow the event, do nothing |
| `pass` | do not intercept — keep the system behaviour |

### Other fields

| Field | Default | Notes |
| --- | --- | --- |
| `hotkey` | `⌃⌥⌘P` | `key`: a–z, 0–9, f1–f12, space, escape, arrows…; `modifiers`: `control`, `option`, `shift`, `command` (keep at least one) |
| `escapeDisables` | `true` | `ESC` also turns the clicker off (read-only listener, so your slideshow still exits on ESC) |
| `middleDoubleClickToggles` | `true` | double-click the wheel button to toggle |
| `showIndicator` | `true` | show the corner dot |
| `scrollDirection` | `auto` | `auto` follows macOS *Natural scrolling*; force with `normal` / `inverted` |
| `throttleMs` | `300` | minimum gap between two wheel-triggered page turns |
| `scope` | `global` | `global` = everywhere, `apps` = only when the frontmost app is listed |
| `apps` | Keynote, PowerPoint, WPS, Impress, Preview, Acrobat, Chrome, Safari, Edge | whitelist used by `scope: apps` |
| `startEnabled` | `false` | start with remapping already on |
| `debugLog` / `logPath` | `true` / `~/Library/Logs/PPTClicker.log` | lifecycle log |
| `debugEvents` | `false` | log every raw mouse event + every interception (troubleshooting) |

Adding your own app: `osascript -e 'id of app "Microsoft PowerPoint"'` prints the
bundle identifier to put in `apps`.

## Troubleshooting

**The dot is grey even after double-clicking the wheel.**
Accessibility permission is missing — the dot turns green as soon as the event
tap is installed. Check the menu item *Accessibility: …*.

**ESC does not turn it off.**
Grant *Input Monitoring* and restart the app.

**Nothing happens, the dot is green but slides do not advance.**
The dot means "remapping active" — the arrow keys still have to reach your
slideshow. Make sure the slideshow window is focused. Enable `"debugEvents": true`
and check `~/Library/Logs/PPTClicker.log`: a working setup logs
`左键 → next（keyCode 124）` for every click.

**Wheel goes the wrong way.**
Set `"scrollDirection": "inverted"` (or `"normal"`), reload the config.

**One wheel flick skips several slides.**
Increase `throttleMs` (e.g. 500).

**I cannot find the indicator dot.**
Maybe it was dragged off-screen (e.g. after unplugging a display) or hidden.
Re-enable *"Show corner indicator dot"* in the menu — it snaps back to the
corner.

**Left click stopped working on links inside the slideshow.**
Set `"bindings": { "leftClick": "pass" }` and use the wheel only.

**Uninstall.** Menu → *Quit*, disable *Launch at login* if you enabled it, delete
the app, then remove `~/Library/Application Support/PPTClicker`, the log, and the
Accessibility/Input Monitoring entries.

## How it works

```
Sources/
  main.swift         entry point + hidden CLI flags (--selftest, --print-default-config, …)
  AppDelegate.swift  menu bar item, permissions, indicator dot, config reload, login item
  EventTap.swift     CGEventTap at the HID layer: intercept, swallow, synthesize keys
  Mapping.swift      pure logic: actions, key codes, scroll-direction resolution (unit tested)
  Config.swift       lenient JSON config + default template
  Indicator.swift    the corner dot (borderless always-on-top panel)
  Localization.swift tiny zh/en string table
  Log.swift          file logger
  SelfTest.swift     89 headless assertions
```

- The tap is inserted at the **head of the HID event stream**, so mouse events
  are seen before any app (including your slideshow). Mapped events are swallowed
  and replaced by synthesized arrow keys posted back into the HID stream.
- Synthesized key events are tagged with a marker in `eventSourceUserData` so the
  tap never processes its own output.
- Momentum/continuous scrolling is swallowed without triggering, and repeated
  events are merged by a throttle; a direction change bypasses the throttle so
  you can flick back and forth.
- Double-click detection on the wheel button has a cooldown, so mashing the wheel
  cannot toggle twice.
- The global shortcut uses `RegisterEventHotKey` (no permissions at all). Only if
  that fails does it fall back to watching keys in the event tap.
- At launch the app synthesizes a tagged click over the indicator dot and checks
  whether its own tap saw it — a self-test of the whole interception path that
  needs no user interaction.
- Menu-bar clicks, the open menu itself and system settings windows are always
  passed through, so the app can never make its own UI unclickable.

## Development

Requirements: macOS 13+, Xcode Command Line Tools (or Xcode).

```bash
git clone https://github.com/<owner>/ppt-clicker.git
cd ppt-clicker
./build.sh                 # host arch + runs the self-test suite
./build.sh --universal     # arm64 + x86_64
./release.sh               # universal + zip + dmg + SHA256SUMS.txt
```

`./build.sh` runs 89 assertions covering actions, key codes, scroll direction
resolution, throttling, double-click detection and config parsing. CI runs the
same command on every push (see `.github/workflows/ci.yml`).

See [CONTRIBUTING.md](CONTRIBUTING.md) for the layout and testing notes.

## Limitations

- **Mouse only.** If you switch to a trackpad mid-presentation, two-finger
  swipes are treated as `scrollUp` / `scrollDown`.
- The `escape` *action* cannot leave a Keynote slideshow (use your own ESC key
  for that — which the app lets through untouched).
- Remapping left click to `→` means **links and buttons inside a slide are no
  longer clickable**; bind `leftClick` to `pass` if you need them.
- The indicator dot occupies a 16×16 pt region in the corner of your screen;
  clicks there hit the dot (move it or hide it if that bothers you).
- The app is not notarized, so the first launch needs the Gatekeeper step above.
- Moving the app folder breaks the Accessibility grant and the login item.

## License

[MIT](LICENSE)
