// 用系统 Vision 把照片主体抠出来（白底 → 透明），输出 PNG。
// 用法：swift scripts/cutout.swift 输入.jpg 输出.png
import AppKit
import CoreImage
import Vision

let args = CommandLine.arguments
guard args.count == 3, let input = CIImage(contentsOf: URL(fileURLWithPath: args[1])) else {
    print("用法: swift cutout.swift 输入 输出.png"); exit(1)
}
let handler = VNImageRequestHandler(ciImage: input)
let request = VNGenerateForegroundInstanceMaskRequest()
try handler.perform([request])
guard let result = request.results?.first else { print("没识别到主体"); exit(1) }
let masked = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: false)
let ci = CIImage(cvPixelBuffer: masked)
let ctx = CIContext()
try ctx.writePNGRepresentation(of: ci, to: URL(fileURLWithPath: args[2]), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
print("ok")
