import AppKit

let sizes: [(String, CGFloat, CGFloat)] = [
    ("icon_16x16.png", 16, 1.0),
    ("icon_16x16@2x.png", 16, 2.0),
    ("icon_32x32.png", 32, 1.0),
    ("icon_32x32@2x.png", 32, 2.0),
    ("icon_128x128.png", 128, 1.0),
    ("icon_128x128@2x.png", 128, 2.0),
    ("icon_256x256.png", 256, 1.0),
    ("icon_256x256@2x.png", 256, 2.0),
    ("icon_512x512.png", 512, 1.0),
    ("icon_512x512@2x.png", 512, 2.0)
]

let iconsetDir = URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

for (filename, points, scale) in sizes {
    let px = points * scale
    let size = CGSize(width: px, height: px)
    let image = NSImage(size: size)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { continue }
    
    // Squircle radius and inset proportionally
    let inset = px * (40.0 / 512.0)
    let corner = px * (96.0 / 512.0)
    let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
    let path = CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)
    
    // Gradient Background (Deep dark slate/midnight)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let colors = [
        NSColor(red: 0.16, green: 0.17, blue: 0.22, alpha: 1.0).cgColor,
        NSColor(red: 0.08, green: 0.09, blue: 0.12, alpha: 1.0).cgColor
    ] as CFArray
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient, start: CGPoint(x: px/2, y: px - inset), end: CGPoint(x: px/2, y: inset), options: [])
    }
    ctx.restoreGState()
    
    // Subtle border
    ctx.addPath(path)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.15).cgColor)
    ctx.setLineWidth(max(1.0, px * (3.0 / 512.0)))
    ctx.strokePath()
    
    // Paw Symbol
    ctx.saveGState()
    if px >= 32 {
        ctx.setShadow(offset: CGSize(width: 0, height: -px * (6.0 / 512.0)),
                      blur: px * (12.0 / 512.0),
                      color: NSColor(white: 0.0, alpha: 0.5).cgColor)
    }
    
    if let pawSymbol = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil) {
        let symSize = px * (250.0 / 512.0)
        let config = NSImage.SymbolConfiguration(pointSize: symSize * 0.88, weight: .semibold)
        if let configured = pawSymbol.withSymbolConfiguration(config) {
            let tinted = NSImage(size: configured.size)
            tinted.lockFocus()
            NSColor(red: 0.95, green: 0.96, blue: 0.98, alpha: 1.0).setFill()
            NSRect(origin: .zero, size: configured.size).fill()
            configured.draw(in: NSRect(origin: .zero, size: configured.size), from: .zero, operation: .destinationIn, fraction: 1.0)
            tinted.unlockFocus()
            
            let symRect = CGRect(x: (px - symSize) / 2, y: (px - symSize) / 2 - (px * (4.0 / 512.0)), width: symSize, height: symSize)
            tinted.draw(in: symRect, from: .zero, operation: .sourceOver, fraction: 1.0)
        }
    }
    ctx.restoreGState()
    image.unlockFocus()
    
    if let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        let outURL = iconsetDir.appendingPathComponent(filename)
        try! png.write(to: outURL)
    }
}
print("Iconset generated successfully.")
