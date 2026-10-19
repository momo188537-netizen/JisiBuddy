// 生成锁屏单色（vibrant）模式用的高对比度灰度头像：去色、提对比、锐化，保留透明背景。
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import UniformTypeIdentifiers
// 用法：swift scripts/mono-face.swift 输入.png 输出.png 像素
let a = CommandLine.arguments
let px = CGFloat(Double(a[3])!)
var img = CIImage(contentsOf: URL(fileURLWithPath: a[1]))!
let scale = px / img.extent.width
let lanczos = CIFilter.lanczosScaleTransform(); lanczos.inputImage = img; lanczos.scale = Float(scale); img = lanczos.outputImage!
let mono = CIFilter.colorControls(); mono.inputImage = img; mono.saturation = 0; mono.contrast = 1.7; mono.brightness = 0.05; img = mono.outputImage!
let gamma = CIFilter.gammaAdjust(); gamma.inputImage = img; gamma.power = 1.4; img = gamma.outputImage!
let sharp = CIFilter.unsharpMask(); sharp.inputImage = img; sharp.radius = 1.5; sharp.intensity = 0.8; img = sharp.outputImage!
let ctx = CIContext()
let cg = ctx.createCGImage(img, from: CGRect(x: 0, y: 0, width: px, height: px), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
let dst = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[2]) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dst, cg, nil); CGImageDestinationFinalize(dst)
