import AppKit
import Foundation

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

func png(_ name: String, width: Int, height: Int, draw: () -> Void) throws {
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    draw()
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(cgImage: image.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name))
}

try png("table.png", width: 1200, height: 700) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 36), .foregroundColor: NSColor.black]
    let table = [["Product", "Quantity", "Amount"], ["Apples", "3", "12.50"], ["Tea", "2", "9.00"], ["Bread", "1", "4.50"]]
    for (r, row) in table.enumerated() {
        for (c, text) in row.enumerated() {
            (text as NSString).draw(at: NSPoint(x: 90 + c * 350, y: 505 - r * 115), withAttributes: attributes)
        }
    }
    NSColor.black.setStroke()
    let grid = NSBezierPath(); grid.lineWidth = 2
    for r in 0...4 { grid.move(to: NSPoint(x: 60, y: 570 - r * 115)); grid.line(to: NSPoint(x: 1110, y: 570 - r * 115)) }
    for c in 0...3 { grid.move(to: NSPoint(x: 60 + c * 350, y: 110)); grid.line(to: NSPoint(x: 60 + c * 350, y: 570)) }
    grid.stroke()
}

try png("subject.png", width: 1000, height: 800) {
    NSColor(calibratedRed: 0.85, green: 0.92, blue: 0.98, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 1000, height: 800).fill()
    NSColor(calibratedRed: 0.95, green: 0.36, blue: 0.1, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 320, y: 190, width: 320, height: 390), xRadius: 45, yRadius: 45).fill()
    let handle = NSBezierPath(ovalIn: NSRect(x: 560, y: 270, width: 190, height: 220))
    handle.lineWidth = 44
    NSColor(calibratedRed: 0.95, green: 0.36, blue: 0.1, alpha: 1).setStroke(); handle.stroke()
    NSColor.brown.setFill(); NSBezierPath(ovalIn: NSRect(x: 340, y: 535, width: 280, height: 50)).fill()
    NSColor(calibratedRed: 0.2, green: 0.6, blue: 0.25, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 70, y: 150, width: 140, height: 140)).fill()
}

try "Invoice Number: INV-2048\nVendor: Orchard Design\nTotal Due: AUD 1,284.50\nDue Date: 14 October 2026\n".write(to: destination.appendingPathComponent("invoice.txt"), atomically: true, encoding: .utf8)
try "Hello, welcome to our store.\nThank you for your order.\n".write(to: destination.appendingPathComponent("translate.txt"), atomically: true, encoding: .utf8)
try "{\"welcome\":\"Hello, {name}!\",\"count\":\"You have %d items.\"}".write(to: destination.appendingPathComponent("strings.json"), atomically: true, encoding: .utf8)
