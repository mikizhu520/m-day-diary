import AppKit
import CoreGraphics
import ImageIO
import Foundation
import UniformTypeIdentifiers

// MARK: - 生成应用图标
//
// 设计原则：够看、够小、够清楚。
// 上一版是「暖色渐变底板 + 白纸 + 三行字」。
//
// 这一版按用户要求改成 **白色底**：
// 白底板铺下去之后，原来那张白纸会当场消失（白纸落在白底上等于没画），
// 所以把关系反过来 —— 纸用品牌色（#C85A37），纸上的字用白色。
// 全图只剩两样东西：一块白底板、一个暖色的本子。没有渐变、没有高光、没有投影叠加。
//
// 白底还有一个副作用要处理：图标落在浅色壁纸/浅色界面上时边界会糊掉。
// 所以外面补两样极轻的东西：一条发丝级的暖灰描边，加一层很淡的投影。
// 两者都刻意压到「近看才有」，不然小尺寸下会显脏。

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

// 品牌色，和 Theme.swift 里的 `accentDefault`（#C85A37）保持一致 ——
// 图标和界面里的强调色必须同一个，否则放在一起像两个产品。
let brand = rgb(200, 90, 55)

// MARK: 底板（白色）

let inset: CGFloat = 76
let bg = CGRect(x: inset, y: inset, width: S - inset * 2, height: S - inset * 2)
let corner = bg.width * 0.2265
let bgPath = CGPath(roundedRect: bg, cornerWidth: corner, cornerHeight: corner, transform: nil)

// 淡投影：给白底一点「放在桌面上」的厚度，alpha 压到 0.10 才不至于脏
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: S * 0.006),
              blur: S * 0.018,
              color: rgb(0, 0, 0, 0.10))
ctx.addPath(bgPath)
ctx.setFillColor(rgb(255, 255, 255))
ctx.fillPath()
ctx.restoreGState()

// 发丝描边：白底白墙时的最后一道边界
ctx.saveGState()
ctx.addPath(bgPath)
ctx.setStrokeColor(rgb(226, 217, 211))
ctx.setLineWidth(S * 0.005)
ctx.strokePath()
ctx.restoreGState()

// MARK: 本子（品牌色）

// 白底板比原来的暖色底板「空」得多，本子就得更占地方一点，
// 否则缩到 32×32 只看见一块白板上糊了个小色块。
let pageW = bg.width * 0.515
let pageH = bg.height * 0.635
let page = CGRect(x: bg.midX - pageW / 2,
                  y: bg.midY - pageH / 2,
                  width: pageW, height: pageH)
let pagePath = CGPath(roundedRect: page,
                      cornerWidth: pageW * 0.155, cornerHeight: pageW * 0.155,
                      transform: nil)

ctx.saveGState()
ctx.addPath(pagePath)
ctx.setFillColor(brand)
ctx.fillPath()
ctx.restoreGState()

// MARK: 纸上的三行

let lineX = page.minX + pageW * 0.20
let lineW = pageW * 0.60
let thinH: CGFloat = pageH * 0.062

func bar(_ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ alpha: CGFloat) {
    let r = CGRect(x: lineX, y: y, width: w, height: h)
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: h / 2, cornerHeight: h / 2, transform: nil))
    ctx.setFillColor(rgb(255, 255, 255, alpha))
    ctx.fillPath()
}

// 第一行是「今天写下的那一行」—— 满不透明，长一点；
// 后面两行退到 0.55，做出「还在写」的层次，但不要弱到看不见。
// 三行整体压在纸的中间，行距一起调，否则会头重脚轻。
let step = pageH * 0.195
var y = page.minY + pageH * 0.265
bar(y, lineW, thinH, 1.0)
y += step
bar(y, lineW * 0.92, thinH, 0.55)
y += step
bar(y, lineW * 0.60, thinH, 0.55)

// MARK: 输出

guard let image = ctx.makeImage() else { exit(1) }
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
if !CGImageDestinationFinalize(dest) { exit(1) }
print("icon written: \(outPath)")
