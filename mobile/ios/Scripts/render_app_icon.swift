import AppKit
import Foundation

let outputPath = CommandLine.arguments.dropFirst().first
    ?? "LingHui/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)

image.lockFocus()
NSColor(
    calibratedRed: 21.0 / 255.0,
    green: 34.0 / 255.0,
    blue: 56.0 / 255.0,
    alpha: 1
).setFill()
NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 224, yRadius: 224).fill()

func strokePath(
    _ configure: (NSBezierPath) -> Void,
    color: NSColor,
    width: CGFloat
) {
    let path = NSBezierPath()
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    configure(path)
    color.setStroke()
    path.stroke()
}

let mist = NSColor(
    calibratedRed: 245.0 / 255.0,
    green: 247.0 / 255.0,
    blue: 244.0 / 255.0,
    alpha: 1
)
let blue = NSColor(
    calibratedRed: 61.0 / 255.0,
    green: 99.0 / 255.0,
    blue: 1,
    alpha: 1
)
let coral = NSColor(
    calibratedRed: 1,
    green: 107.0 / 255.0,
    blue: 94.0 / 255.0,
    alpha: 1
)

strokePath({ path in
    path.move(to: NSPoint(x: 254, y: 702))
    path.curve(
        to: NSPoint(x: 770, y: 504),
        controlPoint1: NSPoint(x: 370, y: 802),
        controlPoint2: NSPoint(x: 654, y: 798)
    )
    path.curve(
        to: NSPoint(x: 254, y: 320),
        controlPoint1: NSPoint(x: 830, y: 448),
        controlPoint2: NSPoint(x: 372, y: 426)
    )
}, color: mist, width: 116)

strokePath({ path in
    path.move(to: NSPoint(x: 258, y: 320))
    path.curve(
        to: NSPoint(x: 766, y: 310),
        controlPoint1: NSPoint(x: 380, y: 414),
        controlPoint2: NSPoint(x: 640, y: 406)
    )
}, color: mist, width: 116)

strokePath({ path in
    path.move(to: NSPoint(x: 276, y: 326))
    path.curve(
        to: NSPoint(x: 750, y: 320),
        controlPoint1: NSPoint(x: 390, y: 412),
        controlPoint2: NSPoint(x: 636, y: 406)
    )
}, color: blue, width: 30)

coral.setFill()
NSBezierPath(ovalIn: NSRect(x: 720, y: 284, width: 72, height: 72)).fill()
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Unable to render AppIcon PNG")
}
try png.write(to: URL(fileURLWithPath: outputPath))
