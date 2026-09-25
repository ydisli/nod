# Contributing to Nod

Thank you for helping. Nod exists for people who depend on it, so reliability and clarity
matter more than features.

## Before you start

- Open an issue first for anything bigger than a small fix, so we can agree on the approach.
- If you use a head or eye pointer every day, your experience is the most valuable input there is.
  Issues that describe how Nod feels in real use are as welcome as code.

## Working on the code

```bash
make test    # NodCore unit tests, must pass
make run     # build build/Nod.app and launch it
```

- Tracking maths belongs in `Sources/NodCore` and comes with tests. It must not import AppKit,
  AVFoundation or Vision, so it stays fast to test and easy to reason about.
- The app target (`Sources/Nod`) is Swift 6 with strict concurrency. Camera frames, Vision and the
  pointer engine run on one serial queue; the UI lives on the main actor.
- New behaviour needs a test that fails without it. A passing test that was never seen failing
  proves nothing.
- Keep the resource budget: measure CPU with `top -pid` before and after anything that touches
  the frame loop, and put the numbers in the pull request.

## Reporting tracking problems

Please include your Mac model, camera, macOS version, the input and motion mode, and the file
`~/Library/Application Support/Nod/last-calibration-v1.json` if you calibrated. It holds only
landmark-derived numbers, never images.

## Style

Match the surrounding code. User-facing text is plain and short, and speaks to the person using
Nod, not about them.
