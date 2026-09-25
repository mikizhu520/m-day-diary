import SwiftUI
import AppKit

// MARK: - Markdown 块

struct MDBlock: Identifiable {
    enum Kind {
        case heading(Int, String)
        case paragraph(String)
        case quote(String)
        case list([ListItem], ordered: Bool)
        case task(String, Bool)
        case code(String, String)
        case divider
        case image(String, String)
        case table([[String]])
    }
    struct ListItem {
        var indent: Int
        var text: String
    }
    var id = UUID()
    var kind: Kind
}

// MARK: - 解析器

enum MDParser {

    static func parse(_ text: String) -> [MDBlock] {
        var blocks: [MDBlock] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var paragraph: [String] = []

        func flushParagraph() {
            let joined = paragraph.joined(separator: "\n").trimmed
            if !joined.isEmpty { blocks.append(MDBlock(kind: .paragraph(joined))) }
            paragraph.removeAll()
        }

        while i < lines.count {
            let raw = lines[i]
            let line = raw.trimmed

            // 代码块
            if line.hasPrefix("```") {
                flushParagraph()
                let lang = String(line.dropFirst(3)).trimmed
                var code: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmed.hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                i += 1
                blocks.append(MDBlock(kind: .code(lang, code.joined(separator: "\n"))))
                continue
            }

            // 空行
            if line.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // 分割线
            if line == "---" || line == "***" || line == "___" {
                flushParagraph()
                blocks.append(MDBlock(kind: .divider))
                i += 1
                continue
            }

            // 标题
            if let m = firstMatch("^(#{1,6})\\s+(.*)$", line), m.count == 2 {
                flushParagraph()
                blocks.append(MDBlock(kind: .heading(m[0].count, m[1])))
                i += 1
                continue
            }

            // 引用
            if line.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while i < lines.count && lines[i].trimmed.hasPrefix(">") {
                    quote.append(lines[i].trimmed.replacingOccurrences(of: "^>\\s?", with: "", options: .regularExpression))
                    i += 1
                }
                blocks.append(MDBlock(kind: .quote(quote.joined(separator: "\n"))))
                continue
            }

            // 表格
            if line.hasPrefix("|"), i + 1 < lines.count, lines[i + 1].trimmed.hasPrefix("|"),
               lines[i + 1].contains("---") {
                flushParagraph()
                var rows: [[String]] = []
                while i < lines.count && lines[i].trimmed.hasPrefix("|") {
                    let cells = lines[i].trimmed
                        .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                        .components(separatedBy: "|")
                        .map { $0.trimmed }
                    if !cells.allSatisfy({ $0.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "").isEmpty }) {
                        rows.append(cells)
                    }
                    i += 1
                }
                if !rows.isEmpty { blocks.append(MDBlock(kind: .table(rows))) }
                continue
            }

            // 任务
            if let m = firstMatch("^[-\\*]\\s+\\[([ xX])\\]\\s+(.*)$", line), m.count == 2 {
                flushParagraph()
                blocks.append(MDBlock(kind: .task(m[1], m[0].lowercased() == "x")))
                i += 1
                continue
            }

            // 图片独占一行
            if let m = firstMatch("^!\\[([^\\]]*)\\]\\(([^)]+)\\)\\s*$", line), m.count == 2 {
                flushParagraph()
                blocks.append(MDBlock(kind: .image(m[0], m[1])))
                i += 1
                continue
            }

            // 有序 / 无序列表
            if let _ = firstMatch("^\\s*([-\\*\\+])\\s+", raw), !line.hasPrefix("- [") {
                flushParagraph()
                var items: [MDBlock.ListItem] = []
                // 任务行（`- [ ]` / `- [x]`）必须留给上面的「任务」分支。
                // 原先这个循环只看 `[-*+]`，会把紧跟在列表后面的待办行一起吞进来，
                // 渲染成「圆点 + 字面 [ ]」—— 设置页预览里就是这么露馅的。
                while i < lines.count,
                      let im = firstMatch("^(\\s*)[-\\*\\+]\\s+(.*)$", lines[i]),
                      firstMatch("^\\s*[-\\*]\\s+\\[[ xX]\\]\\s+", lines[i]) == nil {
                    items.append(.init(indent: im[0].count / 2, text: im[1]))
                    i += 1
                }
                blocks.append(MDBlock(kind: .list(items, ordered: false)))
                continue
            }

            if let _ = firstMatch("^\\s*\\d+[.)]\\s+", raw) {
                flushParagraph()
                var items: [MDBlock.ListItem] = []
                while i < lines.count, let im = firstMatch("^(\\s*)\\d+[.)]\\s+(.*)$", lines[i]) {
                    items.append(.init(indent: im[0].count / 2, text: im[1]))
                    i += 1
                }
                blocks.append(MDBlock(kind: .list(items, ordered: true)))
                continue
            }

            paragraph.append(raw)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    private static func firstMatch(_ pattern: String, _ string: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let m = re.firstMatch(in: string, range: range) else { return nil }
        var out: [String] = []
        for g in 1..<m.numberOfRanges {
            if let r = Range(m.range(at: g), in: string) { out.append(String(string[r])) }
            else { out.append("") }
        }
        return out
    }

    /// 行内样式 → AttributedString
    ///
    /// - Parameters:
    ///   - scaled: 传 true 时字号会再乘一遍界面缩放系数。
    ///     预览侧统一传 false —— 那边算出来的 size 已经是最终点数了，
    ///     再用 .rj() 会缩放两次。
    ///   - color: 不传就跟着上层环境色（正文/标题各有各的色）
    static func inline(_ text: String,
                       size: CGFloat,
                       baseWeight: Font.Weight = .regular,
                       scaled: Bool = false,
                       color: Color? = nil) -> AttributedString {
        var attr: AttributedString
        if let parsed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            attr = parsed
        } else {
            attr = AttributedString(text)
        }
        attr.font = scaled ? .rj(size, weight: baseWeight) : .system(size: size, weight: baseWeight)
        attr.foregroundColor = color ?? .primary
        return attr
    }
}

// MARK: - 渲染

struct MarkdownPreview: View {
    var text: String
    @ObservedObject var store: Store
    var entry: Entry?
    var fontSize: Double = 15
    /// 写作区样式，跟编辑器的即时渲染读同一份，两处观感才一致
    var style: MDStyle = .default

    var body: some View {
        let blocks = MDParser.parse(text)
        VStack(alignment: .leading, spacing: 0) {
            if blocks.isEmpty {
                Text("还没有内容，点上面的「编辑」开始写吧。")
                    .font(.rj(fontSize))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            } else {
                ForEach(blocks) { block in
                    MDBlockView(block: block, store: store, entry: entry,
                                fontSize: fontSize, style: style)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .textSelection(.enabled)
    }
}

struct MDBlockView: View {
    var block: MDBlock
    @ObservedObject var store: Store
    var entry: Entry?
    var fontSize: Double
    var style: MDStyle = .default

    /// 预览侧的正文字号（已经乘过界面缩放），后面所有尺寸都从它按比例推，
    /// 这样跟编辑器里的即时渲染用的是同一套比例，两处观感一致。
    private var base: CGFloat { CGFloat(fontSize) * UIScale.factor }
    /// ⚠️ 量纲别搞混（2026-09-25 踩过一次，整个预览区变一片空白）：
    ///   · `t.paraAfter` / `t.listBlockBefore` / `t.headingBefore(_)` 等**块间距** —— `MDType`
    ///     里已经乘过 `base` 了，直接当点数用，**不要再乘 base**。再乘一次会变成
    ///     base² 量级（一个段落垫出 160pt 空白），整篇被推到看不见的地方。
    ///   · `t.bodyLine` / `t.tightLine` / `t.codeLine` 是**行高倍率**，要配合
    ///     `leading(size, multiple)` 用。
    ///   · `t.bulletDot` / `t.checkBox` / `t.listIndent` 等**装饰尺寸**也是点数。
    private var t: MDType { MDType(base: base, style: style) }
    private var ink: MDInk { .current }

    private func c(_ color: NSColor) -> Color { Color(nsColor: color) }

    /// SwiftUI 的 Text 行高大约就是 1.2 倍字号，这里补足到目标倍率
    private func leading(_ size: CGFloat, _ multiple: CGFloat) -> CGFloat {
        max(0, size * (multiple - 1.20))
    }

    var body: some View {
        switch block.kind {
        case .heading(let level, let text):
            VStack(alignment: .leading, spacing: 0) {
                Text(MDParser.inline(text, size: t.headingSize(level),
                                     baseWeight: level <= 2 ? .bold : .semibold,
                                     color: c(ink.heading)))
                    .lineSpacing(leading(t.headingSize(level), t.headingLine(level)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, level <= 2 ? base * 0.24 : base * 0.16)
                // GitHub 的招牌做法：一级二级标题压一条底边线（可在设置里关掉）
                if level <= 2 && style.headingRule {
                    Rectangle()
                        .fill(level == 1 ? c(ink.rule) : c(ink.rule.withAlphaComponent(0.65)))
                        .frame(height: t.headingRuleWidth(level))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, t.headingBefore(level) * (level <= 2 ? 0.85 : 0.7))

        case .paragraph(let text):
            Text(MDParser.inline(text, size: base, color: c(ink.body)))
                .lineSpacing(leading(base, t.bodyLine))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, t.paraAfter * 0.8)

        case .quote(let text):
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: t.quoteBarWidth / 2)
                    .fill(c(ink.quoteBar))
                    .frame(width: t.quoteBarWidth)
                Text(MDParser.inline(text, size: base * 0.98, color: c(ink.secondary)))
                    .lineSpacing(leading(base, t.bodyLine))
                    .padding(.leading, t.quoteBarGap)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, base * 0.36)
            .padding(.horizontal, base * 0.12)
            // 底纹可以关掉只留竖条，所以用透明度控制而不是条件分支
            .background(RoundedRectangle(cornerRadius: 7)
                .fill(c(ink.quoteBG))
                .opacity(style.quoteTint ? 1 : 0))
            .padding(.vertical, t.quoteBlockBefore * 0.62)

        case .list(let items, let ordered):
            VStack(alignment: .leading, spacing: t.listItemAfter) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .top, spacing: 0) {
                        Group {
                            if ordered {
                                Text("\(idx + 1).")
                                    .font(.system(size: base * 0.94, weight: .medium))
                                    .foregroundStyle(c(ink.secondary))
                            } else {
                                // 一级实心、二级以上空心，跟编辑器里画的一致
                                Circle()
                                    .fill(item.indent == 0 ? c(ink.accent) : .clear)
                                    .overlay(Circle().strokeBorder(
                                        c(ink.accent.withAlphaComponent(0.6)),
                                        lineWidth: item.indent == 0 ? 0 : 1))
                                    .frame(width: t.bulletDot, height: t.bulletDot)
                                    .padding(.top, base * 0.46)
                            }
                        }
                        .frame(width: t.listIndent * 0.78, alignment: .leading)

                        Text(MDParser.inline(item.text, size: base, color: c(ink.body)))
                            .lineSpacing(leading(base, t.tightLine))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, t.listIndent * 0.25 + CGFloat(item.indent) * base * 0.55)
                }
            }
            .padding(.vertical, t.listBlockBefore * 0.85)

        case .task(let text, let done):
            HStack(alignment: .top, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: t.checkBox * 0.32)
                        .fill(done ? c(ink.accent) : Color(nsColor: .controlBackgroundColor))
                    RoundedRectangle(cornerRadius: t.checkBox * 0.32)
                        .strokeBorder(c(ink.secondary.withAlphaComponent(done ? 0 : 0.5)),
                                      lineWidth: done ? 0 : 1)
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: t.checkBox * 0.58, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: t.checkBox, height: t.checkBox)
                .padding(.top, base * 0.22)

                Text(MDParser.inline(text, size: base, color: c(done ? ink.secondary : ink.body)))
                    .strikethrough(done, color: c(ink.secondary))
                    .lineSpacing(leading(base, t.tightLine))
                    .padding(.leading, t.listIndent * 0.52)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, t.listIndent * 0.25)
            .padding(.bottom, t.listItemAfter)

        case .code(let lang, let code):
            VStack(alignment: .leading, spacing: 0) {
                if !lang.isEmpty {
                    Text(lang.lowercased())
                        .font(.system(size: t.codeSize * 0.76, weight: .semibold))
                        .foregroundStyle(c(ink.secondary.withAlphaComponent(0.9)))
                        .padding(.horizontal, t.codePadH)
                        .padding(.top, t.codePadV * 0.9)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(code)
                        .font(.system(size: t.codeSize, design: .monospaced))
                        .foregroundStyle(c(ink.body))
                        .lineSpacing(leading(t.codeSize, t.codeLine))
                        .textSelection(.enabled)
                        .padding(.horizontal, t.codePadH)
                        .padding(.vertical, t.codePadV)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9).fill(c(ink.codeBG)))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(c(ink.codeEdge), lineWidth: 1))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.25)
                    .fill(c(ink.accent.withAlphaComponent(0.55)))
                    .frame(width: 2.5)
                    .padding(.vertical, 4)
                    .padding(.leading, 2)
            }
            .padding(.vertical, t.codeBlockBefore * 0.55)

        case .divider:
            Rectangle()
                .fill(c(ink.rule))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, t.dividerBefore * 0.85)

        case .image(let alt, let path):
            VStack(alignment: .leading, spacing: 4) {
                if let img = ImageCache.image(named: path, store: store, entry: entry) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 520)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .softShadow()
                        .padding(.vertical, 4)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "photo").foregroundStyle(.tertiary)
                        Text(alt.isEmpty ? path : alt)
                            .font(.system(size: base * 0.86))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
                }
            }
            .padding(.vertical, base * 0.3)

        case .table(let rows):
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { rIdx, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { cIdx, cell in
                            Text(MDParser.inline(cell, size: t.tableSize,
                                                 baseWeight: rIdx == 0 ? .semibold : .regular,
                                                 color: c(rIdx == 0 ? ink.heading : ink.body)))
                                .lineSpacing(leading(t.tableSize, t.tightLine))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                // GitHub 的单元格内边距是 6px × 13px，这里按字号等比换算
                                .padding(.horizontal, t.tableSize * 0.85)
                                .padding(.vertical, t.tableSize * 0.42)
                                .overlay(alignment: .trailing) {
                                    if cIdx < row.count - 1 {
                                        Rectangle()
                                            .fill(c(ink.tableLine))
                                            .frame(width: t.tableLineWidth)
                                    }
                                }
                        }
                    }
                    .background(rowTint(rIdx))
                    .overlay(alignment: .bottom) {
                        if rIdx < rows.count - 1 {
                            Rectangle()
                                .fill(c(ink.tableLine))
                                .frame(height: t.tableLineWidth)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(c(ink.tableLine), lineWidth: t.tableLineWidth))
            .padding(.vertical, t.tableBlockBefore * 0.6)
        }
    }

    /// 表头浅底 + 隔行斑马纹，跟 GitHub 的表格一个路数（斑马纹可在设置里关掉）
    private func rowTint(_ index: Int) -> Color {
        if index == 0 { return c(ink.tableHeaderBG) }
        guard style.tableStripe else { return .clear }
        return index % 2 == 1 ? c(ink.tableAltBG) : .clear
    }
}
