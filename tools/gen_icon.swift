import AppKit
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

// MARK: - 生成应用图标
//
// 设计原则：够看、够小、够清楚。
// 上一版堆了渐变、高光、投影、黄点、书签…… 在小尺寸下一团糊。
// 这一版只留三样东西：一块暖色底板、一页白纸、纸上的三行字。
// 第一行用品牌色 —— 那是「今天写下的那一行」。

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let S: CGFloat = 1024

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S),
                          bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    exit(1)
}
ctx.setAllowsAntialiasing(true)
ctx.interpolationQuality = .high

// 以左上角为原点作图
ctx.translateBy(x: 0, y: S)
ctx.scaleBy(x: 1, y: -1)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

// MARK: 底板

let inset: CGFloat = 76
let bg = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let corner = bg.width * 0.2265
let bgPath = CGPath(roundedRect: bg, cornerWidth: corner, cornerHeight: corner, transform: nil)

ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
// 两色就够了：上面亮一点，下面沉一点，干净
let grad = CGGradient(colorsSpace: cs,
                      colors: [rgb(240, 138, 95), rgb(211, 82, 44)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad,
                       start: CGPoint(x: bg.midX, y: bg.minY),
                       end: CGPoint(x: bg.midX, y: bg.maxY),
                       options: [])
ctx.restoreGState()

// MARK: 白纸

let pageW = bg.width * 0.515
let pageH = bg.height * 0.60
let page = CGRect(x: bg.midX - pageW / 2,
                  y: bg.midY - pageH / 2,
                  width: pageW, height: pageH)
let pagePath = CGPath(roundedRect: page,
                      cornerWidth: pageW * 0.115, cornerHeight: pageW * 0.115,
                      transform: nil)

ctx.saveGState()
ctx.addPath(pagePath)
ctx.setFillColor(rgb(255, 253, 251))
ctx.fillPath()
ctx.restoreGState()

// MARK: 纸上的三行

let lineX = page.minX + pageW * 0.185
let lineW = pageW * 0.63
let thinH: CGFloat = pageH * 0.055

func bar(_ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: CGColor) {
    let r = CGRect(x: lineX, y: y, width: w, height: h)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
    ctx.setFillColor(color)
    ctx.fillPath()
}

// 第一行是「今天写的」—— 品牌色，粗一点
let accent = rgb(201, 73, 31)
let faint = rgb(219, 210, 203)

// 三行整体要落在纸的中间 —— 起始位置和行距一起调，
// 否则字全挤在上半张，看着头重脚轻。
let step = pageH * 0.185
var y = page.minY + pageH * 0.27
bar(y, lineW, thinH * 1.25, accent)
y += step
bar(y, lineW * 0.9, thinH, faint)
y += step
bar(y, lineW * 0.62, thinH, faint)

// MARK: 输出

guard let image = ctx.makeImage() else { exit(1) }
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
if !CGImageDestinationFinalize(dest) { exit(1) }
print("icon written: \(outPath)")
