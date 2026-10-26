import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func icon(size: Int) -> Data {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let scale = CGFloat(size) / 1024
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: scale, y: scale)
    let background = NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 200, yRadius: 200)
    NSColor(calibratedRed: 0.09, green: 0.15, blue: 0.24, alpha: 1).setFill()
    background.fill()
    context.setStrokeColor(NSColor(calibratedRed: 0.39, green: 0.91, blue: 0.72, alpha: 1).cgColor)
    context.setLineWidth(35)
    context.setLineCap(.round)
    for (from, to) in [
        (CGPoint(x: 619, y: 738), CGPoint(x: 676, y: 813)),
        (CGPoint(x: 688, y: 654), CGPoint(x: 783, y: 686)),
        (CGPoint(x: 518, y: 786), CGPoint(x: 530, y: 878))
    ] {
        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()
    }
    let cursor = NSBezierPath()
    cursor.move(to: NSPoint(x: 300, y: 766))
    cursor.line(to: NSPoint(x: 319, y: 260))
    cursor.line(to: NSPoint(x: 433, y: 376))
    cursor.line(to: NSPoint(x: 542, y: 178))
    cursor.line(to: NSPoint(x: 637, y: 231))
    cursor.line(to: NSPoint(x: 527, y: 429))
    cursor.line(to: NSPoint(x: 691, y: 464))
    cursor.close()
    NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
    cursor.fill()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return bitmap.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    for retina in [false, true] {
        let size = base * (retina ? 2 : 1)
        let name = "icon_\(base)x\(base)\(retina ? "@2x" : "").png"
        try icon(size: size).write(to: output.appendingPathComponent(name))
    }
}
