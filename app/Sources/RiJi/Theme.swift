import SwiftUI
import AppKit

// MARK: - 界面字号缩放

/// 全局界面缩放。改这里一处，整个 App 的字号一起变。
enum UIScale {
    static let key = "rj.uiScale"

    /// 没设置过时的默认档（比原来的 1.15 大一档，解决「字太小」）
    static let defaultFactor: CGFloat = 1.30

    /// 预设档位
    static let presets: [(name: String, value: Double)] = [
        ("紧凑", 1.00),
        ("标准", 1.15),
        ("大", 1.30),
        ("特大", 1.46)
    ]

    static var factor: CGFloat = {
        let v = UserDefaults.standard.double(forKey: key)
        return v > 0 ? CGFloat(v) : defaultFactor
    }()

    static var doubleValue: Double { Double(factor) }

    static func label(for value: Double) -> String {
        presets.first { abs($0.value - value) < 0.001 }?.name ?? "自定义"
    }

    static func set(_ v: Double) {
        UserDefaults.standard.set(v, forKey: key)
        factor = CGFloat(v)
    }
}

extension Font {
    /// 带全局缩放的系统字体。参数与 `Font.system(size:weight:design:)` 完全一致。
    static func rj(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size * UIScale.factor, weight: weight, design: design)
    }
}

// MARK: - 栏背景
//
// 顶栏 / 底栏原来铺的是 `.ultraThinMaterial` —— 浅色模式下会透出一层灰，
// 跟中间的内容区割裂成「上灰下灰中间白」三段。
// 现在统一成「浅色模式纯白、深色模式比窗口底色略亮」，
// 让每一块面板的顶部和底部跟内容连成一片。
//
// 注意：只用在**栏**上（顶栏 / 底栏 / 表头），不要拿去铺整栏背景，
// 那样会把侧边栏、中栏的层次感一起抹平。

extension Color {
    static var rjBar: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.15, alpha: 1)
                : NSColor.white
        })
    }
}

// MARK: - 颜色

extension Color {
    init(hex: String) {
        var s = hex.trimmed
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        } else {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// 品牌主色：暖赤陶。随明暗自动调整亮度，永远不用系统蓝。
    static let rjAccent = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0.902, green: 0.494, blue: 0.376, alpha: 1)   // #E67E60
            : NSColor(srgbRed: 0.784, green: 0.353, blue: 0.216, alpha: 1)   // #C85A37
    })

    /// 卡片表面
    static let rjCard = Color(nsColor: .controlBackgroundColor)
    /// 发丝线
    static let rjHairline = Color(nsColor: .separatorColor).opacity(0.55)
    /// 悬停高亮
    static let rjHover = Color.primary.opacity(0.07)
    /// 选中底色
    static let rjSelect = Color.primary.opacity(0.10)
}

enum RJ {
    static let accentDefault = "#C85A37"

    static let cardRadius: CGFloat = 12
    static let panelRadius: CGFloat = 16
    static let rowRadius: CGFloat = 8
    /// 图标按钮的命中尺寸
    static let tapSize: CGFloat = 30
}

// MARK: - 按压反馈（所有按钮共用）

/// 按下时轻微缩小 + 回弹。给任何按钮带来「按下去有反应」的手感。
struct PressableStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.94
    var pressedOpacity: Double = 0.78

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

// MARK: - 主按钮（唯一保留填充色的 CTA）

struct RJPrimaryButtonStyle: ButtonStyle {
    var tint: Color = .rjAccent

    func makeBody(configuration: Configuration) -> some View {
        RJPrimaryLabel(configuration: configuration, tint: tint)
    }

    struct RJPrimaryLabel: View {
        let configuration: ButtonStyle.Configuration
        let tint: Color
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(configuration.isPressed ? 0.82 : 1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(hovering ? 0.28 : 0.14), lineWidth: 1)
                )
                .shadow(color: tint.opacity(hovering ? 0.32 : 0.20),
                        radius: hovering ? 12 : 7, x: 0, y: hovering ? 4 : 2)
                .scaleEffect(configuration.isPressed ? 0.965 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.16), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - 次要按钮（浅底 + 描边，无蓝）

struct RJSubtleButtonStyle: ButtonStyle {
    var tint: Color = .rjAccent

    func makeBody(configuration: Configuration) -> some View {
        RJSubtleLabel(configuration: configuration, tint: tint)
    }

    struct RJSubtleLabel: View {
        let configuration: ButtonStyle.Configuration
        let tint: Color
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(tint)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.opacity(configuration.isPressed ? 0.20 : (hovering ? 0.14 : 0.09)))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(tint.opacity(hovering ? 0.45 : 0.25), lineWidth: 1)
                )
                .scaleEffect(configuration.isPressed ? 0.965 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.55), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.16), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

// MARK: - 纯文字按钮（弱化，用于「取消」「关闭」）

struct RJPlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

// MARK: - 图标按钮（替代所有蓝色按钮的主力）

struct IconButton: View {
    var symbol: String
    var help: String = ""
    var active: Bool = false
    var tint: Color? = nil
    var size: CGFloat = RJ.tapSize
    var iconSize: CGFloat = 13
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.rj(iconSize, weight: .medium))
                .frame(width: size, height: size)
                .foregroundStyle(foreground)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(background)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        if active { return tint ?? .rjAccent }
        if let tint { return hovering ? tint : tint.opacity(0.85) }
        return Color.primary.opacity(hovering ? 0.95 : 0.68)
    }

    private var background: Color {
        if active { return (tint ?? .rjAccent).opacity(0.15) }
        return hovering ? Color.primary.opacity(0.08) : .clear
    }
}

// MARK: - 图标菜单（带悬停反馈的 Menu）

struct MenuIcon<Content: View>: View {
    var symbol: String
    var help: String = ""
    var active: Bool = false
    var tint: Color? = nil
    var size: CGFloat = RJ.tapSize
    var iconSize: CGFloat = 13
    @ViewBuilder var content: () -> Content

    @State private var hovering = false

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: symbol)
                .font(.rj(iconSize, weight: .medium))
                .frame(width: size, height: size)
                .foregroundStyle(active ? (tint ?? .rjAccent) : Color.primary.opacity(hovering ? 0.95 : 0.68))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(active ? (tint ?? .rjAccent).opacity(0.15)
                              : (hovering ? Color.primary.opacity(0.08) : .clear))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
        .onHover { hovering = $0 }
    }
}

// MARK: - 图标 + 文字胶囊菜单（带悬停反馈）

struct MenuPill<Content: View>: View {
    var symbol: String
    var title: String
    var help: String = ""
    var tint: Color = .rjAccent
    @ViewBuilder var content: () -> Content

    @State private var hovering = false

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.rj(12, weight: .semibold))
                Text(title).font(.rj(12.5, weight: .semibold))
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5.5)
            .background(Capsule().fill(tint.opacity(hovering ? 0.20 : 0.13)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help)
        .onHover { hovering = $0 }
    }
}

// MARK: - 图标分段控件（替代系统蓝色 segmented）

struct SegmentOption<T: Hashable>: Identifiable {
    var value: T
    var symbol: String
    var label: String
    var id: T { value }
}

struct IconSegmented<T: Hashable>: View {
    var options: [SegmentOption<T>]
    @Binding var selection: T
    var cellWidth: CGFloat = 36

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options) { opt in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { selection = opt.value }
                } label: {
                    Image(systemName: opt.symbol)
                        .font(.rj(12, weight: .medium))
                        .frame(width: cellWidth, height: 26)
                        .foregroundStyle(selection == opt.value ? Color.rjAccent : Color.secondary)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selection == opt.value ? Color.rjAccent.opacity(0.15) : .clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(PressableStyle(pressedScale: 0.90))
                .help(opt.label)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
    }
}

// MARK: - 可复用外观

struct CardBackground: ViewModifier {
    var selected: Bool = false
    var accent: Color = .rjAccent
    var interactive: Bool = true

    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: RJ.cardRadius, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    RoundedRectangle(cornerRadius: RJ.cardRadius, style: .continuous)
                        .fill(accent.opacity(selected ? 0.13 : 0))
                    RoundedRectangle(cornerRadius: RJ.cardRadius, style: .continuous)
                        .fill(Color.primary.opacity(hovering && !selected ? 0.045 : 0))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: RJ.cardRadius, style: .continuous)
                    .strokeBorder(selected ? accent.opacity(0.5)
                                  : Color(nsColor: .separatorColor).opacity(hovering ? 0.85 : 0.5),
                                  lineWidth: selected ? 1.4 : 1)
            }
            .shadow(color: .black.opacity(hovering && !selected ? 0.07 : 0.02), radius: 7, x: 0, y: 2)
            .animation(.easeOut(duration: 0.16), value: hovering)
            .animation(.easeOut(duration: 0.18), value: selected)
            .onHover { if interactive { hovering = $0 } }
    }
}

extension View {
    func card(selected: Bool = false, accent: Color = .rjAccent, interactive: Bool = true) -> some View {
        modifier(CardBackground(selected: selected, accent: accent, interactive: interactive))
    }

    func softShadow() -> some View {
        shadow(color: Color.black.opacity(0.07), radius: 10, x: 0, y: 3)
    }
}

// MARK: - 小组件

/// 数字 / 文字胶囊
struct Pill: View {
    var text: String
    var symbol: String? = nil
    var color: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.rj(10.5, weight: .semibold)) }
            Text(text).font(.rj(12.5, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(Capsule().fill(color.opacity(0.13)))
    }
}

/// 日记本色点
struct JournalDot: View {
    var color: Color
    var size: CGFloat = 9

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: [color, color.opacity(0.6)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
    }
}

/// 日记本图标：彩色圆角方块 + 白色 SF Symbol。
///
/// 侧边栏、编辑弹窗、列表标题都用它，保证同一个日记本在哪儿长一个样。
/// 尺寸一律是外框边长，内部字号按比例取（跟着 UIScale 一起缩放）。
struct JournalIconBadge: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 20
    /// 圆角，不传就按边长取
    var corner: CGFloat? = nil
    /// 选中态（比如被选中的日记本）会把底色压暗一点，白色图标才够清楚
    var dimmed: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner ?? max(3, size * 0.29), style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(dimmed ? 1 : 0.96),
                                              color.opacity(dimmed ? 0.82 : 0.74)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: symbol)
                .font(.system(size: size * 0.5 * UIScale.factor, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}

/// 空状态
struct EmptyHint: View {
    var symbol: String
    var title: String
    var subtitle: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.05))
                    .frame(width: 62, height: 62)
                Image(systemName: symbol)
                    .font(.rj(24, weight: .light))
                    .foregroundStyle(.tertiary)
            }
            VStack(spacing: 6) {
                Text(title).font(.rj(16, weight: .semibold))
                Text(subtitle)
                    .font(.rj(13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle).font(.rj(13.5, weight: .semibold))
                }
                .buttonStyle(RJSubtleButtonStyle())
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 区块标题
struct SectionLabel: View {
    var text: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.rj(10.5, weight: .bold)) }
            Text(text.uppercased())
                .font(.rj(11, weight: .bold))
                .tracking(0.7)
        }
        .foregroundStyle(.tertiary)
    }
}

// MARK: - 像素级毛玻璃分隔

struct HairLine: View {
    var vertical: Bool = false
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.55))
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}

// MARK: - 自动换行的横向排列

/// 一排标签/胶囊按钮，放不下就自动折到下一行。
/// AI 面板最窄只有 320pt，横向滚动会把最后一颗胶囊截一半，看着像坏了。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, used: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                used = max(used, x - spacing)
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        used = max(used, x - spacing)
        return CGSize(width: min(max(used, 0), maxWidth), height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for sv in subviews {
            let size = sv.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            sv.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - 图片加载（本地附件）

enum ImageCache {
    private static var cache = NSCache<NSString, NSImage>()

    static func image(at url: URL) -> NSImage? {
        let key = url.path as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let img = NSImage(contentsOf: url) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    @MainActor
    static func image(named name: String, store: Store, entry: Entry?) -> NSImage? {
        guard let url = store.resolveAttachment(name, entry: entry) else { return nil }
        return image(at: url)
    }
}
