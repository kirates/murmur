import AppKit
import CoreGraphics
import Foundation

let size = 1024.0
let inset = 92.0
let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                          bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("could not create bitmap context")
}

let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let squircle = CGPath(roundedRect: plate, cornerWidth: 200, cornerHeight: 200, transform: nil)

ctx.saveGState()
ctx.addPath(squircle)
ctx.clip()
let gradient = CGGradient(colorsSpace: colorSpace, colors: [
    CGColor(red: 0.35, green: 0.29, blue: 0.85, alpha: 1),
    CGColor(red: 0.16, green: 0.44, blue: 0.86, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: plate.minX, y: plate.maxY),
                       end: CGPoint(x: plate.maxX, y: plate.minY),
                       options: [])
ctx.restoreGState()

ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.setLineCap(.round)

// Microphone capsule.
let capsule = CGRect(x: size / 2 - 70, y: 470, width: 140, height: 268)
ctx.addPath(CGPath(roundedRect: capsule, cornerWidth: 70, cornerHeight: 70, transform: nil))
ctx.fillPath()

// Cradle: the lower half of a circle wrapping under the capsule.
ctx.setLineWidth(36)
ctx.addArc(center: CGPoint(x: size / 2, y: 540), radius: 168,
           startAngle: .pi, endAngle: 0, clockwise: false)
ctx.strokePath()

// Stand and base.
ctx.move(to: CGPoint(x: size / 2, y: 372))
ctx.addLine(to: CGPoint(x: size / 2, y: 300))
ctx.strokePath()

ctx.move(to: CGPoint(x: size / 2 - 92, y: 300))
ctx.addLine(to: CGPoint(x: size / 2 + 92, y: 300))
ctx.strokePath()

// Waveform flanking the mic.
ctx.setLineWidth(32)
for (index, offset) in [286.0, 372.0].enumerated() {
    let height = index == 0 ? 132.0 : 72.0
    for side in [-1.0, 1.0] {
        let x = size / 2 + side * offset
        ctx.move(to: CGPoint(x: x, y: 560 - height))
        ctx.addLine(to: CGPoint(x: x, y: 560 + height))
    }
}
ctx.strokePath()

guard let image = ctx.makeImage() else { fatalError("could not render icon") }
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let rep = NSBitmapImageRep(cgImage: image)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not encode png")
}
try png.write(to: out)
