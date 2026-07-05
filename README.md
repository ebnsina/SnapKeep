<div align="center">

# SnapKeep

**A beautiful, native screenshot tool for Apple Silicon.**

Capture, annotate, keep — fast, private, and 100% local.

</div>

---

SnapKeep is a modern macOS screenshot app in the spirit of Lightshot, rebuilt
natively for Apple Silicon with **ScreenCaptureKit**, **SwiftUI**, and a
gorgeous, fluid interface. Everything runs on-device — no accounts, no cloud, no cost.

## Features

- **Region capture** — `⌘⇧9` freezes the screen; drag to select any area with live
  pixel dimensions, crosshair guides, and an 8x magnifier loupe.
- **Window capture** — `⌘⇧8`; hover to highlight a window, click to grab it.
- **Full-screen capture** — `⌘⇧4`, instantly copied to the clipboard and saved.
- **Recapture last region** — `⌘⇧7` re-shoots the exact previous area.
- **Screen recording** — `⌘⇧6` records to MP4 or animated GIF with a floating
  timer/stop control; recordings land in your history.
- **Annotation editor** — pen, marker, line, arrow, rectangle, ellipse, text,
  numbered step badges, and pixelate/redact, in any color and stroke, with undo/redo.
- **Beautify** — drop a capture onto a gradient backdrop with padding, rounded
  corners, and a soft shadow for a polished share.
- **OCR** — extract text from any capture on-device (Copy Text) via the Vision framework.
- **Pin to desktop** — float a capture always-on-top while you work.
- **History grid** — recent captures in the menu bar; click to copy, drag into any
  app, or right-click to pin, reveal, share, or delete.
- **Native sharing** — AirDrop, Messages, Mail, Notes. No accounts, no uploads.
- **Settings** — image format, capture delay, save location, shutter sound, auto-copy.
- **System-wide hotkeys**, delayed capture, light and dark mode.
- **Private by design** — no network calls, no telemetry, no cost.

On the roadmap: scrolling capture, recording audio, and move/resize of annotations.

## Install

### Option A — Download (recommended)

Grab the latest notarized `SnapKeep.dmg` from the
[Releases](https://github.com/ebnsina/SnapKeep/releases) page, open it, and
drag SnapKeep to Applications.

### Option B — Build from source

Requires **Xcode 26+** and [`xcodegen`](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
git clone git@github.com:ebnsina/SnapKeep.git
cd SnapKeep
./scripts/bootstrap.sh      # generates the project and builds a release .app
open build/SnapKeep.app
```

Or open it in Xcode:

```bash
xcodegen generate
open SnapKeep.xcodeproj
```

## Permissions

On first launch, macOS asks for **Screen Recording** permission (required by
ScreenCaptureKit). Grant it in **System Settings, Privacy & Security, Screen
Recording**, then relaunch SnapKeep.

## Tech

Swift 6, SwiftUI + AppKit, ScreenCaptureKit, Metal/Core Image, macOS 14+,
Apple Silicon (arm64).

## License

[MIT](LICENSE) © ebnsina
