// Draws App Sales Overview's icon: nine app tiles in a 3x3 grid, filled from the bottom right like a bar chart
// (all your apps at a glance), silver on black. 1024 px PNG.
// Usage: swift scripts/make-icon.swift <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

// Top-left origin.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: alpha)
}

// Ground: black, lifted a little towards the top.
let ground = CGGradient(colorsSpace: space, colors: [color(0x1b1b1e), color(0x000000)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(ground, startCenter: CGPoint(x: 512, y: 358), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 358), endRadius: 820, options: [.drawsAfterEndLocation])

// The grid: columns and rows at 232, 432, 632; tiles 160 wide with a 40 radius.
let starts: [CGFloat] = [232, 432, 632]
let metal = CGGradient(colorsSpace: space, colors: [color(0xf4f4f6), color(0x9a9aa0)] as CFArray, locations: [0, 1])!

func tile(column: Int, row: Int) -> CGPath {
    CGPath(roundedRect: CGRect(x: starts[column], y: starts[row], width: 160, height: 160), cornerWidth: 40, cornerHeight: 40, transform: nil)
}

// Filled: the bottom row, two in the middle row, one at the top right. The rest are outlines.
let filled: Set<[Int]> = [[0, 2], [1, 2], [2, 2], [1, 1], [2, 1], [2, 0]]
for column in 0..<3 {
    for row in 0..<3 where !filled.contains([column, row]) {
        let inset = CGPath(roundedRect: CGRect(x: starts[column] + 6, y: starts[row] + 6, width: 148, height: 148),
                           cornerWidth: 36, cornerHeight: 36, transform: nil)
        ctx.addPath(inset)
        ctx.setStrokeColor(color(0x3a3a3f))
        ctx.setLineWidth(12)
        ctx.strokePath()
    }
}
for cell in filled {
    ctx.saveGState()
    ctx.addPath(tile(column: cell[0], row: cell[1]))
    ctx.clip()
    ctx.setAlpha(cell == [2, 0] ? 1 : 0.9)
    ctx.drawLinearGradient(metal, start: CGPoint(x: 0, y: 212), end: CGPoint(x: 0, y: 772), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

let destination = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
CGImageDestinationFinalize(destination)
