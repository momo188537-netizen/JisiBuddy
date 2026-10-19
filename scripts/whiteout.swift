// 白底照片 → 透明 PNG：从四边泛洪，min(R,G,B) >= 235 且和边缘连通的像素设为透明，
// alpha 腐蚀 1px 去白边，再对边缘做一次 3×3 轻微模糊。主体 alpha 保持 255。
// 用法：swift scripts/whiteout.swift 输入 输出.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count == 3,
      let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("用法: swift whiteout.swift 输入 输出.png"); exit(1)
}
let w = image.width, h = image.height
var px = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

func isWhite(_ i: Int) -> Bool { min(px[i * 4], px[i * 4 + 1], px[i * 4 + 2]) >= 235 }

// 泛洪
var bg = [Bool](repeating: false, count: w * h)
var stack: [Int] = []
for x in 0..<w { stack.append(x); stack.append((h - 1) * w + x) }
for y in 0..<h { stack.append(y * w); stack.append(y * w + w - 1) }
while let i = stack.popLast() {
    if bg[i] || !isWhite(i) { continue }
    bg[i] = true
    let x = i % w, y = i / w
    if x > 0 { stack.append(i - 1) }
    if x < w - 1 { stack.append(i + 1) }
    if y > 0 { stack.append(i - w) }
    if y < h - 1 { stack.append(i + w) }
}

var alpha = bg.map { $0 ? 0.0 : 1.0 }
// 腐蚀 1px
var eroded = alpha
for y in 0..<h { for x in 0..<w where alpha[y * w + x] > 0 {
    var edge = false
    for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1)] {
        let nx = x + dx, ny = y + dy
        if nx < 0 || ny < 0 || nx >= w || ny >= h || alpha[ny * w + nx] == 0 { edge = true; break }
    }
    if edge { eroded[y * w + x] = 0 }
}}
// 轻微模糊：只动边缘附近，主体仍是 255
var soft = eroded
for y in 1..<(h - 1) { for x in 1..<(w - 1) {
    var sum = 0.0
    for dy in -1...1 { for dx in -1...1 { sum += eroded[(y + dy) * w + x + dx] } }
    let avg = sum / 9
    if avg > 0 && avg < 1 { soft[y * w + x] = eroded[y * w + x] > 0 ? max(avg, 0.5) : avg * 0.6 }
}}

// 写回（预乘 alpha）
for i in 0..<(w * h) {
    let a0 = Double(px[i * 4 + 3]) / 255, na = soft[i]
    for c in 0..<3 {
        let straight = a0 > 0 ? Double(px[i * 4 + c]) / a0 : 0
        px[i * 4 + c] = UInt8(min(255, (straight * na).rounded()))
    }
    px[i * 4 + 3] = UInt8((na * 255).rounded())
}
let out = ctx.makeImage()!
let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dst, out, nil)
CGImageDestinationFinalize(dst)
print("ok \(w)x\(h)")
