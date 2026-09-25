import SwiftUI
import AppKit

// MARK: - 纸张底纹

/// 写作区的底纹。
///
/// 编辑区（NSTextView）本来就是透明的，所以只要在它外面铺一层，
/// 纸纹就能透到文字底下 —— 不用去改绘图层。
enum PaperStyle: String, CaseIterable, Identifiable {
    case plain
    case lined
    case grid
    case dots
    case cream
    case blush

    var id: String { rawValue }

    var name: String {
        switch self {
        case .plain: return "纯白"
        case .lined: return "横线"
        case .grid:  return "方格"
        case .dots:  return "点阵"
        case .cream: return "米黄"
        case .blush: return "樱粉"
        }
    }

    var hint: String {
        switch self {
        case .plain: return "什么都不铺，最干净"
        case .lined: return "像信纸，一条一条的横线"
        case .grid:  return "像本子，写代码和清单都合适"
        case .dots:  return "点阵，比方格轻一些"
        case .cream: return "暖米色，长时间看不累眼"
        case .blush: return "很淡的樱粉，偏软"
        }
    }

    var symbol: String {
        switch self {
        case .plain: return "doc"
        case .lined: return "list.dash"
        case .grid:  return "square.grid.3x3"
        case .dots:  return "circle.grid.3x3"
        case .cream: return "cup.and.saucer"
        case .blush: return "heart"
        }
    }

    /// 有没有纹路要画。
    ///
    /// 只有横线 / 方格 / 点阵三种需要跑 Canvas ——
    /// 米黄和樱粉的区别只在底色，没有纹路，不必白白建一层空画布。
    var hasPattern: Bool {
        switch self {
        case .lined, .grid, .dots: return true
        case .plain, .cream, .blush: return false
        }
    }

    static func from(_ raw: String) -> PaperStyle { PaperStyle(rawValue: raw) ?? .plain }

    // MARK: 配色

    /// 底色
    var base: Color {
        switch self {
        case .plain, .lined, .grid, .dots:
            // 这几档底色一样，区别只在纹路。跟着系统明暗走。
            return PaperStyle.dynamic(light: .white, dark: NSColor(calibratedWhite: 0.15, alpha: 1))
        case .cream:
            return PaperStyle.dynamic(light: NSColor(calibratedRed: 0.984, green: 0.965, blue: 0.925, alpha: 1),
                                      dark: NSColor(calibratedRed: 0.16, green: 0.152, blue: 0.135, alpha: 1))
        case .blush:
            return PaperStyle.dynamic(light: NSColor(calibratedRed: 0.996, green: 0.965, blue: 0.965, alpha: 1),
                                      dark: NSColor(calibratedRed: 0.17, green: 0.152, blue: 0.155, alpha: 1))
        }
    }

    /// 纹路的颜色。深色模式下要反过来「提亮」，否则线会沉进底色里。
    var ink: Color {
        let dark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        switch self {
        case .lined:
            return Color.primary.opacity(dark ? 0.11 : 0.075)
        case .grid:
            return Color.primary.opacity(dark ? 0.09 : 0.06)
        case .dots:
            return Color.primary.opacity(dark ? 0.16 : 0.11)
        default:
            return .clear
        }
    }

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

// MARK: - 画底纹

/// 铺满整块的纸。放在编辑器 / 预览的下层。
struct PaperBackground: View {
    var style: PaperStyle

    /// 横线的间距。跟正文行高无关 —— 对齐行高要精确到文字的基线，
    /// 差一点反而更显脏，不如老老实实当「背景纸」。
    private let lineStep: CGFloat = 30
    private let dotStep: CGFloat = 22

    var body: some View {
        style.base
            .overlay {
                if style.hasPattern {
                    Canvas { ctx, size in
                        let ink = style.ink
                        switch style {
                        case .lined:
                            var y = lineStep
                            while y < size.height {
                                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                                         with: .color(ink))
                                y += lineStep
                            }
                        case .grid:
                            var y = lineStep
                            while y < size.height {
                                ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                                         with: .color(ink))
                                y += lineStep
                            }
                            var x = lineStep
                            while x < size.width {
                                ctx.fill(Path(CGRect(x: x, y: 0, width: 1, height: size.height)),
                                         with: .color(ink))
                                x += lineStep
                            }
                        case .dots:
                            var y = dotStep
                            while y < size.height {
                                var x = dotStep
                                while x < size.width {
                                    ctx.fill(Path(ellipseIn: CGRect(x: x - 0.9, y: y - 0.9,
                                                                    width: 1.8, height: 1.8)),
                                             with: .color(ink))
                                    x += dotStep
                                }
                                y += dotStep
                            }
                        default:
                            break
                        }
                    }
                    .allowsHitTesting(false)
                }
            }
    }
}
