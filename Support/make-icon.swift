// Renders the app icon: swift Support/make-icon.swift out.png
import AppKit
let size = 1024.0
let img = NSImage(size: NSSize(width: size, height: size))
img.lockFocus()
let rect = NSRect(x: 100, y: 100, width: 824, height: 824)
let path = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGradient(starting: NSColor(red: 0.16, green: 0.72, blue: 0.47, alpha: 1),
           ending: NSColor(red: 0.05, green: 0.38, blue: 0.30, alpha: 1))!.draw(in: path, angle: -90)
let para = NSMutableParagraphStyle(); para.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 520, weight: .semibold),
    .foregroundColor: NSColor.white, .paragraphStyle: para,
]
("=" as NSString).draw(in: NSRect(x: 100, y: 190, width: 824, height: 640), withAttributes: attrs)
let small: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedDigitSystemFont(ofSize: 150, weight: .medium),
    .foregroundColor: NSColor.white.withAlphaComponent(0.75), .paragraphStyle: para,
]
("1 + 2" as NSString).draw(in: NSRect(x: 100, y: 650, width: 824, height: 200), withAttributes: small)
img.unlockFocus()
let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
