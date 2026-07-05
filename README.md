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

- 🖥️ **Full-screen capture** — one hotkey, instantly copied to the clipboard and saved.
- 📋 **Copy & save at once** — PNGs land in `~/Pictures/SnapKeep`.
- 🎨 **Beautiful menu-bar UI** — translucent, spring-animated, light & dark mode.
- 🔒 **Private by design** — no network calls, no telemetry.

> 🚧 In active development — region select, annotation toolbar, window capture,
> scrolling capture, OCR, recording, and beautify framing are on the roadmap.

## 📦 Install

### Option A — Download (recommended)
Grab the latest notarized `SnapKeep.dmg` from the
[**Releases**](https://github.com/ebnsina/aperi/releases) page, open it, and
drag SnapKeep to Applications.

### Option B — Build from source
Requires **Xcode 26+** and [`xcodegen`](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```bash
git clone git@github.com:ebnsina/aperi.git
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
