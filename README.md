<div align="center">

# 📸 SnapKeep

**A beautiful, native screenshot tool for Apple Silicon.**

Capture · Annotate · Keep — fast, private, and 100% local.

</div>

---

SnapKeep is a modern macOS screenshot app in the spirit of Lightshot, rebuilt
natively for Apple Silicon with **ScreenCaptureKit**, **SwiftUI**, and a
gorgeous, fluid interface. Everything runs on-device — no accounts, no cloud, no cost.

## ✨ Features

- 🖱️ **Region capture** — `⌘⇧5` freezes the screen; drag to select any area with live
  pixel dimensions, crosshair guides, and an 8× magnifier loupe.
- ✏️ **Annotation editor** — mark up captures with pen, marker, line, arrow, rectangle,
  ellipse, and text, in any color and stroke width, with full undo/redo.
- 🖥️ **Full-screen capture** — `⌘⇧4`, instantly copied to the clipboard and saved.
- ⌨️ **System-wide hotkeys** — capture without opening the menu.
- 📋 **Copy & save at once** — PNGs land in `~/Pictures/SnapKeep`.
- 🎨 **Beautiful menu-bar UI** — translucent, spring-animated, light & dark mode.
- 🔒 **Private by design** — no network calls, no telemetry.

> 🚧 On the roadmap — window & scrolling capture, delayed capture, OCR, screen
> recording, and beautify framing.

## 📦 Install

### Option A — Download (recommended)
Grab the latest notarized `SnapKeep.dmg` from the
[**Releases**](https://github.com/ebnsina/SnapKeep/releases) page, open it, and
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

## 🔐 Permissions

On first launch, macOS asks for **Screen Recording** permission (required by
ScreenCaptureKit). Grant it in **System Settings → Privacy & Security → Screen
Recording**, then relaunch SnapKeep.

## 🛠️ Tech

Swift 6 · SwiftUI + AppKit · ScreenCaptureKit · Metal/Core Image · macOS 14+ ·
Apple Silicon (arm64).

## 📄 License

[MIT](LICENSE) © ebnsina
