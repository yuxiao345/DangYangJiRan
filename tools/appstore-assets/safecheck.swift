// 安全区自查图生成器
//
// 把「安全区之外」压暗、并给安全区描一圈黄框，用来肉眼复核成品有没有把
// 品牌文案放到会被裁掉的位置。验收标准：**文案必须整块落在黄框内**，
// 手机这类装饰性内容允许出框（出血）。
//
// 用法（安全区参数取自 make_banner.swift 的 FORMATS，单位是画布宽/高的分数）：
//
//   swift tools/appstore-assets/safecheck.swift \
//     output/header-21x9-zh-dark.png diag/自查-header-21x9.png \
//     0.285677 0.712760 0.299514 0.701093
//
// ⚠️ 这四个数是**从 make_banner.swift 的 FORMATS 抄过来的**，不是单一真相来源。
// Apple 若改了模板，两处都要改（FORMATS 里是 `1097.0 / 3840` 这种写法，除一下即得）。
// 之所以不做成 `--safecheck` 开关去复用 FORMATS，是因为这个脚本要能在
// 成品图已经生成、甚至 make_banner.swift 跑不起来时独立运行。

import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 7 else {
    print("usage: safecheck <in.png> <out.png> <safeL> <safeR> <safeT> <safeB>")
    print("       安全区参数为 0–1 的分数，原点在左上（与 SwiftUI 一致）")
    exit(2)
}
let pathIn = args[1], pathOut = args[2]
guard let L = Double(args[3]), let R = Double(args[4]),
      let T = Double(args[5]), let B = Double(args[6]),
      L >= 0, T >= 0, R <= 1, B <= 1, L < R, T < B else {
    print("✗ 安全区参数非法：需要 0 ≤ L < R ≤ 1、0 ≤ T < B ≤ 1")
    exit(2)
}

guard let src = NSImage(contentsOfFile: pathIn),
      let tiff = src.tiffRepresentation,
      let bmp = NSBitmapImageRep(data: tiff) else {
    print("✗ 读不出 \(pathIn)")
    exit(1)
}

let W = CGFloat(bmp.pixelsWide), H = CGFloat(bmp.pixelsHigh)

// CGContext 的原点在左下，而安全区参数原点在左上，所以纵向要翻一下
let rect = CGRect(x: CGFloat(L) * W,
                  y: H - CGFloat(B) * H,
                  width: CGFloat(R - L) * W,
                  height: CGFloat(B - T) * H)

let canvas = NSImage(size: NSSize(width: W, height: H))
canvas.lockFocus()
src.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
let ctx = NSGraphicsContext.current!.cgContext

// 四条边带压暗。不用 destinationOut 挖洞——那条路会连底图的 alpha 一起改掉，
// 而 App Store 明令禁止素材带 alpha 通道。
ctx.setFillColor(NSColor.black.withAlphaComponent(0.62).cgColor)
for band in [CGRect(x: 0, y: 0, width: W, height: rect.minY),
             CGRect(x: 0, y: rect.maxY, width: W, height: H - rect.maxY),
             CGRect(x: 0, y: 0, width: rect.minX, height: H),
             CGRect(x: rect.maxX, y: 0, width: W - rect.maxX, height: H)] {
    ctx.fill(band)
}

ctx.setStrokeColor(NSColor.systemYellow.cgColor)
ctx.setLineWidth(max(4, W * 0.0022))
ctx.stroke(rect)
canvas.unlockFocus()

guard let outTIFF = canvas.tiffRepresentation,
      let outRep = NSBitmapImageRep(data: outTIFF),
      let png = outRep.representation(using: .png, properties: [:]) else {
    print("✗ 编码 PNG 失败")
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: pathOut))
} catch {
    print("✗ 写入 \(pathOut) 失败：\(error.localizedDescription)")
    exit(1)
}
print("✓ \(pathOut)  \(Int(W))x\(Int(H))  (暗区 = 安全区之外，黄框内必须装下全部品牌文案)")
