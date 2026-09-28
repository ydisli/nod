<p align="center">
  <img src="docs/icon.png" width="128" alt="Nod app icon: a face drawn as landmark points, with the pointer's tip on the nose">
</p>

<h1 align="center">Nod</h1>
<p align="center"><b>Your head is the mouse.</b><br>
Hands-free pointer control for macOS, through the AirPods you already wear.</p>

<p align="center"><a href="https://github.com/ydisli/nod/releases/latest"><b>Download Nod</b></a>
· free · macOS 14 or later · Apple silicon · AirPods with head tracking</p>

<p align="center">
  <img src="docs/screens/onboarding-0.jpg" width="720" alt="Nod's welcome screen">
</p>

Nod moves the pointer as you turn your head, using the motion sensors in AirPods with head
tracking (AirPods Pro, AirPods Max and others that support spatial audio head tracking). Click
with a key, a lean of the head, or by resting on a spot. It lives in the menu bar, runs entirely
on your Mac, uses no camera, and is free and open source.

It is built for people who cannot use a mouse or trackpad comfortably, whether because of a
disability, an injury or RSI, and for anyone who wants their hands free.

## What it does

**Three ways to move**

- **Relative**. Feels like a mouse: small head turns for fine control, quick ones travel far.
- **Direct**. Your head aims at a spot on the screen. Look at the middle and press Recentre to
  line it up, no calibration.
- **Joystick**. Turn away from centre and the pointer glides. The least neck movement.

**Clicking**

| Way | Does |
| --- | --- |
| Tap right ⌘, or your own shortcut | Click. Tap twice to double click |
| Tap right ⌥, or your own shortcut | Right click |
| Tap a drag key you pick | Pick up; move your head; tap again to drop |
| Lean your head left | Click, keep leaning to drag |
| Lean your head right | Right click |
| Nod | Off at first (double click), since glancing at the keyboard looks similar |
| Rest on a spot | Dwell click, with a palette for right click, double click, drag and scroll |

A key press never moves your head, so key clicks land exactly where you aimed. Any modifier key
on either side can click (⌘ ⌥ ⌃ ⇧, left or right; the right-hand ones are the default). It counts
only when tapped on its own, and holding it never presses the button, so shortcuts, typing and
⌘-clicks keep working. Nod never records what you type. Each click can also take any shortcut you
record, such as F5 or ⌃⌥Space; those are taken system wide only while Nod is on, and a recorded
click key can be held to drag. Settings has a Help page.

Leaning does not steer the pointer, so a lean can be held while you turn. While a lean forms, the
pointer holds still so the click lands where you aimed, and a nod clicks where the pointer was
before your head went down.

**The rest.** Scroll mode, pause, recentre, multi-display support, global shortcuts, launch at
login, and it steps aside the moment a helper touches the real mouse.

<p align="center">
  <img src="docs/screens/menu.png" width="300" alt="Menu bar panel with the live head dial, tilt meters and quick controls">
  &nbsp;
  <img src="docs/screens/palette.png" width="80" alt="Dwell palette with click, right, double, drag, scroll and pause">
  &nbsp;
  <img src="docs/screens/halo.png" width="140" alt="The halo around the pointer: dwell ring and action hint">
</p>

<p align="center">
  <img src="docs/screens/settings-clicking.png" width="720" alt="Clicking settings: click keys and recorded shortcuts, and lean gestures with live meters">
</p>

## Light on your Mac

The AirPods fuse their own gyroscope and accelerometer and send a finished orientation about 50
times a second. Nod turns those few numbers into pointer movement; there is no image to analyse.

Measured on a MacBook Pro (Apple M5) with simulated head motion at 50 updates a second:

| State | CPU |
| --- | --- |
| Tracking, no Nod window open | under 1% of one core |
| Tracking with the menu panel or live meters open | 3 to 5% |
| Tracking off | 0% |

The pointer clock runs at 60 Hz only while head motion arrives (4 Hz when your AirPods are out),
and the screen hears about live data only while a window shows it, at most ten times a second.

## Private by design

- Nod makes no network connections. No account, no analytics.
- It reads head orientation from your AirPods and nothing else. No camera, no microphone.
- Only your settings are saved.

## Install

No Terminal, no developer tools. Nod is one app you download.

**What you need**

- A Mac with Apple silicon (M1 or newer), running macOS 14 Sonoma or later. Apple offers AirPods
  head tracking on Macs with Apple silicon.
- AirPods with head tracking: AirPods 3, AirPods 4, any AirPods Pro, or AirPods Max
  ([Apple's list](https://support.apple.com/guide/airpods/control-spatial-audio-and-head-tracking-dev00eb7e0a3/web)).

**Steps**

1. Download **Nod.dmg** from the [latest release](https://github.com/ydisli/nod/releases/latest).
2. Open the downloaded file and drag **Nod** onto the **Applications** folder next to it.
3. Open Nod from your Applications folder. macOS says it cannot verify the app, because Nod is not
   yet signed with a paid Apple developer certificate. Click **Done**. This happens only once.
4. Open the Apple menu, choose **System Settings**, then **Privacy & Security**. Scroll down to
   **Security**, where it mentions Nod, and click **Open Anyway**. Enter your Mac password. (The
   button stays there for about an hour after step 3.
   [Apple explains this here](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac).)
5. Nod opens with a short welcome tour, and its icon, a small face with a pointer on the nose,
   appears in the menu bar at the top of your screen.
6. **Allow Accessibility.** The tour has a button for it. In the list that opens, switch Nod on.
   This is what lets Nod move the pointer and click.
7. **Put in your AirPods.** The first time, macOS asks whether Nod may use motion data. Click
   **Allow**.
8. Press **⌃⌥N** (Control, Option and N together) to start. Look at the middle of the screen and
   press **⌃⌥C** to centre the pointer. Turn your head, and it follows.

Settings has a **Help** page, and the **?** in the menu bar panel opens it.

**Updating.** Download the new Nod.dmg and drag Nod to Applications again, replacing the old one.
Your settings and permissions stay.

**Removing Nod.** Quit it from its menu bar panel, then drag Nod from Applications to the Bin (Trash). To
tidy up, remove it from System Settings, Privacy & Security, Accessibility.

**If something is off**

- *Nothing moves.* Open the menu bar panel. It says what is missing: Accessibility, or your
  AirPods. Check that they are in your ears and connected to this Mac.
- *Accessibility is on, but Nod still asks for it.* Select Nod in the Accessibility list, remove
  it with **−**, then allow it again.
- *The pointer drifts from where you look.* Look at the middle of the screen and press ⌃⌥C.
  **Direct** motion (in the panel) keeps the two lined up best.
- *It moves the wrong way.* Settings, Pointer, Reverse left and right, or up and down.
- *You want your mouse back.* Just move it; Nod steps aside. ⌃⌥N switches Nod off completely.

## Using it

| Shortcut | Does |
| --- | --- |
| ⌃⌥N | Start or stop Nod, your safety switch |
| ⌃⌥C | Recentre the pointer |

Both can be changed or cleared in Settings, Shortcuts. Right click the menu bar icon for a quick
menu.

## How it works

```
AirPods (orientation, about 50 per second, via CMHeadphoneMotionManager)
  → HeadPose: yaw, pitch and roll in screen terms
  → 1€ filter: steady when still, no lag when moving
  → PointerEngine: relative / direct / joystick, leans and nods, click keys, dwell, scroll
  → CGEvent mouse events, glided at 60 Hz
```

All the logic lives in `NodCore`, a dependency-free Swift module with unit tests: the filter, the
pointer engine, and the head gesture, click key and dwell state machines. The app target adds
CoreMotion, event posting and SwiftUI.

```
Sources/NodCore     pointer logic, fully tested
Sources/Nod         menu bar app (AirPods motion, events, UI)
Tests/NodCoreTests  Swift Testing suite
Support             Info.plist, icon
scripts             build and developer tools
```

## Build from source

For developers. Nod has no third-party dependencies; it uses only Apple's frameworks. You need
Apple's command line tools with Swift 6.

1. Open **Terminal** (Applications, Utilities).
2. Install the tools, if you do not have them: run `xcode-select --install` and click **Install**
   in the window that appears. If you already have them, check `swift --version` says 6 or newer;
   Software Update installs newer tools.
3. Get the code and build the app:

```bash
git clone https://github.com/ydisli/nod.git
cd nod
make app          # builds build/Nod.app
make install      # copies it to /Applications
```

`make dmg` makes the same Nod.dmg as the releases. A build you make yourself opens without the
security warning, because your Mac made it.

## Development

```bash
make test                     # unit tests
make run                      # build and launch
.build/debug/Nod --render-screens /tmp/shots   # render every screen with demo data
```

Launch with `open --env NOD_DEV=1 build/Nod.app` and `scripts/devctl.swift` can open screens,
toggle tracking, print live stats (`status`) and capture Nod's own windows (`snapshot DIR`). Add
`--env NOD_SIMULATE_HEAD=1 --env NOD_DRY_RUN=1` to run on made-up head motion with a pretend
cursor, which is how the CPU numbers above were measured.

## Honest limits

- AirPods measure orientation relative to where they started, and it drifts slowly. Recentre
  when the pointer and your gaze no longer line up.
- Only AirPods with head tracking report motion to the Mac.

## Contributing

Issues and pull requests are welcome, especially from people who use head pointers every day.
See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. See [LICENSE](LICENSE). Made by Yusuf Disli, [yusufdisli.com](https://yusufdisli.com).
Smoothing by the 1€ filter of Géry Casiez, Nicolas Roussel and Daniel Vogel (CHI 2012).
