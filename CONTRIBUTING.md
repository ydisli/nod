# Contributing to Nod

Thank you for helping. Nod exists for people who depend on it, so reliability and clarity
matter more than features.

## Before you start

- Open an issue first for anything bigger than a small fix, so we can agree on the approach.
- If you use a head pointer every day, your experience is the most valuable input there is.
  Issues that describe how Nod feels in real use are as welcome as code.

## Working on the code

```bash
make test    # NodCore unit tests, must pass
make run     # build build/Nod.app and launch it
```

- Tracking maths belongs in `Sources/NodCore` and comes with tests. It must not import AppKit or
  CoreMotion, so it stays fast to test and easy to reason about.
- The app target (`Sources/Nod`) is Swift 6 with strict concurrency. Head poses and the pointer
  engine run on one serial queue; the UI lives on the main actor.
- New behaviour needs a test that fails without it. A passing test that was never seen failing
  proves nothing.
- Keep the resource budget: under 1% of one core while tracking with no window open. Measure
  with simulated head motion and a pretend cursor, before and after, and put the numbers in the
  pull request:

  ```bash
  open --env NOD_DEV=1 --env NOD_SIMULATE_HEAD=1 --env NOD_DRY_RUN=1 build/Nod.app
  top -l 6 -s 2 -pid $(pgrep -f build/Nod.app/Contents/MacOS/Nod) -stats cpu
  ```

## Reporting tracking problems

Please include your Mac model, macOS version, which AirPods you use and the motion mode
(Relative, Direct or Joystick).

## Style

Match the surrounding code. User-facing text is plain and short, and speaks to the person using
Nod, not about them.
