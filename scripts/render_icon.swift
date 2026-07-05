import AppKit

// Renders the SnapKeep app icon: a solid Honolulu-blue rounded square with a white
// camera-viewfinder glyph. Outputs a 1024×1024 PNG to the path given as argv[1].

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/icon1024.png"
let size: CGFloat = 1024

func whiteSymbol(_ name: String, point: CGFloat) -> NSImage? {
    let cfg = NSImage.SymbolConfiguration(pointSize: point, weight: .medium)
    guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else { return nil }
    let s = base.size
    let out = NSImage(size: s)
    out.lockFocus()
    base.draw(in: CGRect(origin: .zero, size: s))
    NSColor.white.set()
    CGRect(origin: .zero, size: s).fill(using: .sourceAtop) // tint only the glyph
    out.unlockFocus()
    return out
}

let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()

// Rounded-square background with a little transparent margin (macOS icon style).
let inset: CGFloat = 84
let rect = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let path = NSBezierPath(roundedRect: rect, xRadius: 190, yRadius: 190)
NSColor(red: 0.0, green: 0.463, blue: 0.714, alpha: 1).setFill()
path.fill()

// Centered white viewfinder glyph.
if let glyph = whiteSymbol("camera.viewfinder", point: 560) {
    let gs = glyph.size
    glyph.draw(in: CGRect(x: (size - gs.width) / 2, y: (size - gs.height) / 2,
                          width: gs.width, height: gs.height))
}

img.unlockFocus()

guard let tiff = img.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("failed to render icon\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
