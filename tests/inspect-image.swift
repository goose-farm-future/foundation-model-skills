import AppKit
import Foundation

let url = URL(fileURLWithPath: CommandLine.arguments[1])
let bitmap = NSBitmapImageRep(data: try Data(contentsOf: url))!
func alpha(_ x: Double, _ y: Double) -> Double {
    Double(bitmap.colorAt(x: Int(Double(bitmap.pixelsWide) * x), y: Int(Double(bitmap.pixelsHigh) * y))!.alphaComponent)
}
let result: [String: Any] = ["width": bitmap.pixelsWide, "height": bitmap.pixelsHigh, "has_alpha": bitmap.hasAlpha, "center_alpha": alpha(0.48, 0.5), "corner_alpha": alpha(0.04, 0.04)]
print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
