import AppKit
import SwiftUI

// MARK: - 写作区样式（用户可在设置里调）
//
// MDType 管的是「渲染成什么样」的绝对规格，MDStyle 管的是「用户想让它偏哪一边」。
// 所有可调项都做成倍率 / 开关，落进 MDType 里，所以调整只影响观感，不会破坏排版结构。
//
// 三个量控制整体呼吸感：行高、段间距、标题字号。三段预设只是这三者的组合，
// 用户可以在此基础上继续微调；装饰类（标题底线 / 斑马纹 / 引用底纹）单独开关，
// 切预设时不会被悄悄改掉。

struct MDStyle: Equatable, Codable {
    /// 当前预设的标识（只用来在设置页里高亮那一档，改滑块后会变成「自定义」）
    var preset: String = MDStyle.Preset.relaxed.rawValue

    /// 正文行高倍数。GitHub 1.5 / Tailwind 1.75 / Solarized 1.8，中文取中间偏松
    var lineHeight: Double = 1.72
    /// 段落之间的留白（相对正文字号的倍数）。其余所有块间距都按它等比换算，
    /// 所以调这一个值，整篇的呼吸感是整体变化的，不会出现「段落紧了但列表还松着」
    var paraSpacing: Double = 0.64
    /// 标题字号整体缩放。中文标题笔画多，倍率太大反而笨重，所以默认 1.0
    var headingScale: Double = 1.0

    /// 一级 / 二级标题压一条底部横线（github-markdown-css 的招牌做法）
    var headingRule: Bool = true
    /// 表格隔行底色（斑马纹）
    var tableStripe: Bool = true
    /// 引用块的淡底纹（关掉只留左侧竖条）
    var quoteTint: Bool = true

    /// 版心宽度（pt）。0 = 撑满编辑区。
    /// 一行太长眼睛回行会串行，所以给一个「收窄到舒适宽度」的选项。
    var contentWidth: Double = 0

    static let `default` = MDStyle()

    enum Preset: String, CaseIterable, Identifiable {
        case compact, relaxed, magazine

        var id: String { rawValue }

        var name: String {
            switch self {
            case .compact: return "紧凑"
            case .relaxed: return "舒展"
            case .magazine: return "杂志"
            }
        }

        /// 设置页里的说明，顺带写清它像谁
        var desc: String {
            switch self {
            case .compact: return "行距紧、段间距小，一屏能看更多字（近 GitHub）"
            case .relaxed: return "行高 1.72，长文最耐读（默认）"
            case .magazine: return "大标题 + 大留白，适合随笔和长文（近 Typora）"
            }
        }

        /// 该预设对应的三项数值
        var values: (lineHeight: Double, paraSpacing: Double, headingScale: Double) {
            switch self {
            case .compact:  return (1.50, 0.46, 0.94)
            case .relaxed:  return (1.72, 0.64, 1.00)
            case .magazine: return (1.90, 0.90, 1.14)
            }
        }

        /// 把预设套到当前样式上（保留用户的装饰开关与版心设置）
        func apply(to style: MDStyle) -> MDStyle {
            var s = style
            s.preset = rawValue
            s.lineHeight = values.lineHeight
            s.paraSpacing = values.paraSpacing
            s.headingScale = values.headingScale
            return s
        }
    }

    /// 当前数值是否正好等于某个预设
    var matchedPreset: Preset? {
        Preset.allCases.first {
            abs($0.values.lineHeight - lineHeight) < 0.001
                && abs($0.values.paraSpacing - paraSpacing) < 0.001
                && abs($0.values.headingScale - headingScale) < 0.001
        }
    }

    /// 给设置页用：改了三项数值后同步 preset 标识，让「自定义」状态能被认出来
    mutating func syncPreset() {
        preset = matchedPreset?.rawValue ?? "custom"
    }

    /// 滑块用得到的安全区间，避免配置文件被手改坏后整篇排版散架
    var isSane: Bool {
        (1.2...2.4).contains(lineHeight)
            && (0.1...1.6).contains(paraSpacing)
            && (0.7...1.5).contains(headingScale)
    }
}

// MARK: - 写作区样式的容错解码
//
// 和 AppSettings 一个道理：Swift 合成的 Decodable 遇到缺字段会直接抛错，
// 而这个结构体是嵌在整份配置里的 —— 一旦抛错，`try?` 会把整个样式退回默认
// （以后加字段就等于把别人的设置清零）。所以这里也逐字段解码。

extension MDStyle {
    enum CodingKeys: String, CodingKey {
        case preset, lineHeight, paraSpacing, headingScale
        case headingRule, tableStripe, quoteTint, contentWidth
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            guard let v = try? c.decodeIfPresent(T.self, forKey: key) else { return fallback }
            return v
        }
        let d = MDStyle()
        preset = value(.preset, d.preset)
        lineHeight = value(.lineHeight, d.lineHeight)
        paraSpacing = value(.paraSpacing, d.paraSpacing)
        headingScale = value(.headingScale, d.headingScale)
        headingRule = value(.headingRule, d.headingRule)
        tableStripe = value(.tableStripe, d.tableStripe)
        quoteTint = value(.quoteTint, d.quoteTint)
        contentWidth = value(.contentWidth, d.contentWidth)
    }
}

// MARK: - Markdown 排版规格
//
// 全应用「渲染出来的内容长什么样」只在这里定义一次：编辑器里的即时渲染、右侧预览、
// AI 回复里的 Markdown、导出用的渲染，全部读这一份，保证三处观感一致。
//
// 数值参照三个开源项目（都是 MIT）的实际规则换算成「相对正文字号的倍率」，
// 这样设置里改一次正文字号，整套阶梯跟着等比变化，不会散架：
//
// · github-markdown-css  https://github.com/sindresorhus/github-markdown-css
//     h1 = 2em / 600 字重 + 底部横线，h2 = 1.5em / 600 + 底部横线，h3 = 1.25em，h4 = 1em，
//     标题上留白 24px / 下留白 16px（≈ 上 1.5em、下 1em），正文行高 1.5，
//     表格单元格内边距 6px × 13px + 表头底色 + 隔行斑马纹，
//     行内代码 85% 字号 + 浅底 + 圆角，引用 = 左侧竖框 + 弱化文字
//
// · @tailwindcss/typography  https://github.com/tailwindlabs/tailwindcss-typography
//     正文行高 1.75（比 GitHub 松，长文更耐读），
//     标题颜色比正文更深（#111827 vs #374151）—— 层级不只是靠字号，更靠深浅，
//     标题「上留白大于下留白」（h2 为 mt 1.6em / mb 1em），让标题紧贴它带的那段内容，
//     strong 600 字重，hr 上下各 0.5em 起
//
// · typora-solarized  https://github.com/belenos/typora-solarized
//     长文正文行高提到 1.8，代码块加细边框，引用加底纹
//
// 另外几处是照中文排版习惯做的调整（中文没有西文那种小写字母重心，
// 单纯照搬会显得字小了、行挤了）：字号倍率整体比 GitHub 略收，行高比 Tailwind 再松一点。

struct MDType {
    /// 正文字号（已含界面缩放系数）
    var base: CGFloat

    /// 用户在设置里选的写作区样式。默认值 = 上面那套参照 GitHub / Tailwind / Solarized
    /// 换算出来的原始规格，所以不传 style 时行为和以前完全一致。
    var style: MDStyle = .default

    // MARK: 字号阶梯

    /// GitHub 是 2 / 1.5 / 1.25 / 1 / 0.875 / 0.85，这里收窄一点：
    /// 中文标题笔画多，倍率太大反而显得笨重。
    func headingSize(_ level: Int) -> CGFloat {
        let steps: [CGFloat] = [1.58, 1.32, 1.15, 1.05, 0.97, 0.92]
        return base * steps[max(1, min(6, level)) - 1] * style.headingScale
    }

    /// 前两级用 bold 撑住分量，其余 semibold 就够（GitHub 全是 600，但中文要更狠一点）
    func headingWeight(_ level: Int) -> NSFont.Weight {
        level <= 2 ? .bold : .semibold
    }

    /// 行内代码 0.9em（GitHub 是 0.85em，中文缩太多会小得看不清）
    var inlineCodeSize: CGFloat { base * 0.90 }
    /// 代码块 0.88em
    var codeSize: CGFloat { base * 0.88 }
    /// 表格 0.94em（单元格本来就挤，不敢缩太多）
    var tableSize: CGFloat { base * 0.94 }

    // MARK: 行高（相对各自字号的倍数）
    //
    // Tailwind 给出 1.75、Solarized 给出 1.8，都明显比 GitHub 的 1.5 松。
    // 默认取 1.72 —— 中文方块字视觉密度比西文高，再松会显得散。

    /// 正文行高，由 MDStyle 决定
    var bodyLine: CGFloat { CGFloat(style.lineHeight) }
    /// 列表项之间要紧凑，不能跟着正文一起松，按正文行高的比例走
    var tightLine: CGFloat { bodyLine * 0.86 }
    var codeLine: CGFloat { bodyLine * 0.93 }
    func headingLine(_ level: Int) -> CGFloat { level <= 2 ? 1.32 : 1.38 }

    // MARK: 留白（相对正文字号的倍数）
    //
    // NSTextView 里 paragraphSpacing 与 paragraphSpacingBefore 是直接相加的，
    // 不像 CSS 的 margin 会自动折叠，所以这里只用「段后 + 块前」两个量来控制，
    // 换算出来的实际距离已在注释里写清楚。
    //
    // 下面每个值都是「段间距的固定倍数」—— 比例取自最初按开源样式表定下的那套绝对值，
    // 这样设置里拖动段间距时，整篇的块间呼吸是一起等比变化的。

    /// 段落之间。基准值 0.64em，可由设置调整
    var paraAfter: CGFloat { base * CGFloat(style.paraSpacing) }
    /// 列表项之间（0.64 的 0.28 倍 ≈ 0.18em）
    var listItemAfter: CGFloat { paraAfter * 0.28 }
    /// 列表块整体上下（0.53 / 0.66 倍 ≈ 0.34em / 0.42em）
    var listBlockBefore: CGFloat { paraAfter * 0.53 }
    var listBlockAfter: CGFloat { paraAfter * 0.66 }
    /// 代码块整体上下（1.09 倍 ≈ 0.70em）
    var codeBlockBefore: CGFloat { paraAfter * 1.09 }
    var codeBlockAfter: CGFloat { paraAfter * 1.09 }
    /// 引用块整体上下（0.81 倍 ≈ 0.52em）；引用内部行之间 0.125 倍 ≈ 0.08em
    var quoteBlockBefore: CGFloat { paraAfter * 0.81 }
    var quoteBlockAfter: CGFloat { paraAfter * 0.81 }
    var quoteLineAfter: CGFloat { paraAfter * 0.125 }
    /// 表格整体上下（1.03 倍 ≈ 0.66em）
    var tableBlockBefore: CGFloat { paraAfter * 1.03 }
    var tableBlockAfter: CGFloat { paraAfter * 1.03 }
    /// 分割线上下（1.44 倍 ≈ 0.92em）
    var dividerBefore: CGFloat { paraAfter * 1.44 }
    var dividerAfter: CGFloat { paraAfter * 1.44 }

    /// 标题前留白（1.64 倍，一级 1.875 倍），叠上前一段的 paraAfter ≈ Tailwind 的 mt 1.6em
    func headingBefore(_ level: Int) -> CGFloat { paraAfter * (level == 1 ? 1.875 : 1.64) }
    /// 标题后留白要比前面小，标题才「贴着」自己的内容（Tailwind mb 1em，这里更收）
    func headingAfter(_ level: Int) -> CGFloat { paraAfter * (level <= 2 ? 0.66 : 0.50) }

    // MARK: 缩进（相对正文字号）

    /// 列表文字的左缩进，给项目符号让出位置
    var listIndent: CGFloat { base * 1.15 }
    /// 引用文字的左缩进，给竖条让出位置
    var quoteIndent: CGFloat { base * 1.00 }
    /// 代码块文字的左缩进（代码块底色自带左右内边距）
    var codeIndent: CGFloat { base * 0.55 }
    /// 代码块上下内边距（绘制圆角底时用）
    var codePadV: CGFloat { base * 0.38 }
    /// 代码块左右内边距（绘制圆角底时用）
    var codePadH: CGFloat { base * 0.95 }
    /// 源码模式下代码块的普通段落缩进
    var sourceCodePad: CGFloat { base * 0.35 }

    // MARK: 装饰尺寸

    /// 引用左侧竖条宽度
    var quoteBarWidth: CGFloat { max(2.5, base * 0.16) }
    /// 引用竖条相对文字左边再往外的距离
    var quoteBarGap: CGFloat { base * 0.42 }
    /// 项目符号圆点直径
    var bulletDot: CGFloat { base * 0.26 }
    /// 待办勾选框边长
    var checkBox: CGFloat { base * 0.86 }
    /// 标题底部横线粗细：一级更实，二级更淡
    func headingRuleWidth(_ level: Int) -> CGFloat { level == 1 ? 1.2 : 0.9 }
    /// 表格行分隔线 / 表格外框
    var tableLineWidth: CGFloat { 0.8 }
}

// MARK: - 颜色
//
// 全部做成随系统明暗自动切换的动态色。取色思路：
// 正文不是纯黑（纯黑在暖色界面上发死），标题才是最深的一档 —— 层级靠深浅拉开；
// 代码块用「比正文底色再低一层」的暖灰，而不是冷灰，免得跟赤陶色打架。

struct MDInk {
    var body: NSColor
    var heading: NSColor
    var secondary: NSColor
    var faint: NSColor
    var accent: NSColor
    var rule: NSColor
    var inlineCodeBG: NSColor
    var codeBG: NSColor
    var codeEdge: NSColor
    var quoteBG: NSColor
    var quoteBar: NSColor
    var tableHeaderBG: NSColor
    var tableAltBG: NSColor
    var tableLine: NSColor
    var highlightBG: NSColor

    static let current = MDInk(
        // 暖调近黑，跟 rjAccent 的赤陶同色系
        body: NSColor(name: nil) { a in
            a.rjIsDark
                ? NSColor(srgbRed: InkLevel.bodyDark, green: 0.902, blue: 0.898, alpha: 1)
                : NSColor(srgbRed: InkLevel.bodyLight, green: 0.137, blue: 0.133, alpha: 1)
        },
        heading: NSColor(name: nil) { a in
            a.rjIsDark
                ? NSColor(srgbRed: 0.984, green: 0.980, blue: 0.976, alpha: 1)
                : NSColor(srgbRed: 0.075, green: 0.067, blue: 0.063, alpha: 1)
        },
        secondary: NSColor(name: nil) { a in
            a.rjIsDark
                ? NSColor(white: 1, alpha: 0.62)
                : NSColor(srgbRed: 0.373, green: 0.353, blue: 0.345, alpha: 1)
        },
        faint: NSColor(name: nil) { a in
            a.rjIsDark ? NSColor(white: 1, alpha: 0.30) : NSColor(white: 0.25, alpha: 0.38)
        },
        accent: NSColor(name: nil) { a in
            a.rjIsDark
                ? NSColor(srgbRed: 0.902, green: 0.494, blue: 0.376, alpha: 1)   // #E67E60
                : NSColor(srgbRed: 0.784, green: 0.353, blue: 0.216, alpha: 1)   // #C85A37
        },
        // 注意：这里必须是「不透明」的灰。
        // NSColor.withAlphaComponent 是直接设定透明度而不是叠加，
        // 如果本身带着 0.11 的 alpha，再调 withAlphaComponent(0.65) 会变成 0.65 → 一条深黑粗线。
        rule: NSColor(name: nil) { a in
            a.rjIsDark
                ? NSColor(srgbRed: 0.239, green: 0.231, blue: 0.224, alpha: 1)   // #3D3B39
                : NSColor(srgbRed: 0.867, green: 0.855, blue: 0.847, alpha: 1)   // #DDDAD8
        },
        inlineCodeBG: NSColor(name: nil) { a in
            a.rjIsDark ? NSColor(white: 1, alpha: 0.11) : NSColor(white: 0.36, alpha: 0.085)
        },
        codeBG: NSColor(name: nil) { a in
            a.rjIsDark
                ? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.062)
                : NSColor(srgbRed: 0.945, green: 0.929, blue: 0.918, alpha: 1)
        },
        codeEdge: NSColor(name: nil) { a in
            a.rjIsDark
                ? NSColor(white: 1, alpha: 0.10)
                : NSColor(white: 0, alpha: 0.075)
        },
        quoteBG: NSColor(name: nil) { a in
            a.rjIsDark
                ? NSColor(srgbRed: 0.902, green: 0.494, blue: 0.376, alpha: 0.075)
                : NSColor(srgbRed: 0.784, green: 0.353, blue: 0.216, alpha: 0.048)
        },
        quoteBar: NSColor(name: nil) { a in
            a.rjIsDark
                ? NSColor(srgbRed: 0.902, green: 0.494, blue: 0.376, alpha: 0.85)
                : NSColor(srgbRed: 0.784, green: 0.353, blue: 0.216, alpha: 0.72)
        },
        tableHeaderBG: NSColor(name: nil) { a in
            a.rjIsDark ? NSColor(white: 1, alpha: 0.085) : NSColor(white: 0.34, alpha: 0.075)
        },
        tableAltBG: NSColor(name: nil) { a in
            a.rjIsDark ? NSColor(white: 1, alpha: 0.035) : NSColor(white: 0.34, alpha: 0.032)
        },
        tableLine: NSColor(name: nil) { a in
            a.rjIsDark
                ? NSColor(srgbRed: 0.290, green: 0.282, blue: 0.275, alpha: 1)
                : NSColor(srgbRed: 0.835, green: 0.824, blue: 0.816, alpha: 1)
        },
        highlightBG: NSColor(name: nil) { a in
            a.rjIsDark
                ? NSColor(srgbRed: 1, green: 0.84, blue: 0.35, alpha: 0.26)
                : NSColor(srgbRed: 1, green: 0.85, blue: 0.36, alpha: 0.42)
        }
    )

    /// 浅一档的正文色，给 AI 回答这类「整段都是机器写的字」用。
    ///
    /// 日记正文是自己的字，越清楚越好（用 `body`）；但小迹一口气吐出十几行
    /// 全黑的字，压在灰底气泡上像一整块墨，读起来累。这里把明度提上来，
    /// 让它看着像「参考资料」而不是「正文」，也不至于淡到看不清。
    var bodySoft: NSColor {
        NSColor(name: nil) { a in
            a.rjIsDark
                ? NSColor(srgbRed: InkLevel.bodySoftDark, green: 0.776, blue: 0.769, alpha: 1)   // #C8C6C4
                : NSColor(srgbRed: InkLevel.bodySoftLight, green: 0.302, blue: 0.294, alpha: 1)  // #514D4B
        }
    }

    /// 行内代码的字色：比正文暖一档，跟赤陶呼应，又不至于像链接
    var inlineCodeText: NSColor {
        NSColor(name: nil) { a in
            a.rjIsDark
                ? NSColor(srgbRed: 0.945, green: 0.612, blue: 0.494, alpha: 1)
                : NSColor(srgbRed: 0.678, green: 0.286, blue: 0.161, alpha: 1)
        }
    }
}

extension NSAppearance {
    var rjIsDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

/// 正文字色的明度刻度。
///
/// 单独拎出来是为了能自检。动态 `NSColor` 在无窗口的命令行里解不出确定的分量，
/// 「AI 回答用的字确实比正文浅」这条断言就没法验证 —— 而它恰恰是这次改动的全部意义。
/// 放在这里当常量，自检直接比数字。
enum InkLevel {
    /// 日记正文（浅色模式）—— 近黑，越清楚越好
    static let bodyLight = 0.145
    /// AI 回答（浅色模式）—— 提亮一档，读整段机器写的字不费劲
    static let bodySoftLight = 0.318
    /// 日记正文（深色模式）
    static let bodyDark = 0.906
    /// AI 回答（深色模式）—— 压暗一档，道理同上
    static let bodySoftDark = 0.784
}

// MARK: - 排版装饰（交给 NSTextView 自绘，字符属性做不出来）
//
// 这些效果在 CSS 里就是一行 border / background，但 NSTextView 的字符属性只能表达
// 字体、颜色、下划线、背景色，做不到「整段底部横线」「左侧竖条」「圆角块」。
// 所以这里把「这一段要画什么」作为属性挂在文本上，由 RJTextView 在 drawRect 里绘制。

final class MDDeco: NSObject {
    enum Kind: Equatable {
        /// 标题底部横线，参数是标题级别
        case headingRule(Int)
        /// 列表项目符号（画一个小圆点代替被隐藏的连字符），参数是缩进层级
        case bullet(depth: Int)
        /// 待办勾选框，参数是已完成状态
        case checkbox(done: Bool)
        /// 引用块：整块绘制（左侧圆头竖条 + 淡底纹）
        case quote
        /// 代码块：整块绘制（圆角底 + 细描边 + 左强调条）
        case code
        /// 分割线
        case divider
        /// 表格：表头带底色 + 下线；数据行隔行底色；末行收口
        case tableHeader
        case tableRow(alt: Bool, last: Bool)
    }

    let kind: Kind
    /// 绘制尺度基准（正文字号）
    let base: CGFloat
    /// 大于 0 表示「这一行属于某个多行块」，绘制层会把同一个编号的几行先合成一个矩形，
    /// 再整块画一次 —— 这样圆角才是完整的，而不是每行各圆各的。
    let group: Int

    init(_ kind: Kind, base: CGFloat, group: Int = 0) {
        self.kind = kind
        self.base = base
        self.group = group
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? MDDeco else { return false }
        return other.kind == kind && other.base == base && other.group == group
    }
    override var hash: Int { "\(kind)-\(base)-\(group)".hashValue }
}

extension NSAttributedString.Key {
    /// 值类型是 MDDeco
    static let mdDeco = NSAttributedString.Key("rj.mdDeco")
}
