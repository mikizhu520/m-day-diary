import AppKit

// MARK: - 即时渲染主题
//
// 具体数值全部来自 MDType / MDInk（见 MDType.swift），这里只负责把它翻成
// NSTextView 能吃的属性字典。

struct MDLiveTheme {
    var baseSize: CGFloat
    /// 设置页里选的写作区样式（行高 / 段间距 / 标题字号 / 装饰开关）
    var style: MDStyle = .default

    var type: MDType { MDType(base: baseSize, style: style) }
    var ink: MDInk { .current }

    static func current(baseSize: CGFloat, style: MDStyle = .default) -> MDLiveTheme {
        MDLiveTheme(baseSize: baseSize, style: style)
    }

    /// 正文基准属性
    func baseAttributes() -> [NSAttributedString.Key: Any] {
        let t = type
        return [
            .font: NSFont.systemFont(ofSize: baseSize, weight: .regular),
            .foregroundColor: ink.body,
            .paragraphStyle: paragraph(line: t.bodyLine, size: baseSize, after: t.paraAfter * baseSize),
            .ligature: 0
        ]
    }

    /// - Parameter line: 行高倍数（相对 size），直接落到 minimumLineHeight 上，
    ///   这样行高是精确的；用 lineSpacing 只能加「额外」间距，算不准。
    func paragraph(line: CGFloat,
                   size: CGFloat,
                   before: CGFloat = 0,
                   after: CGFloat = 0,
                   indent: CGFloat = 0,
                   align: NSTextAlignment = .natural) -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.minimumLineHeight = size * line
        p.paragraphSpacingBefore = before
        p.paragraphSpacing = after
        p.firstLineHeadIndent = indent
        p.headIndent = indent
        p.alignment = align
        return p
    }
}

// MARK: - 解析产物

struct MDInline {
    enum Kind { case bold, italic, strike, code, link, highlight }
    var kind: Kind
    var content: NSRange      // 被修饰的文字
    var markers: [NSRange]    // 需要隐藏的语法标记
    var url: String?
}

struct MDLine {
    enum Block: Equatable {
        case paragraph
        case heading(Int)
        case quote
        case bullet
        case numbered
        case task(done: Bool)
        case codeFence
        case codeBody
        case divider
        case tableRow
        case tableSeparator
    }
    var block: Block
    var full: NSRange      // 含行尾换行
    var line: NSRange      // 不含换行
    var marker: NSRange    // 块级标记（可能 length 为 0）
    var content: NSRange   // 标记之后的正文
    var inlines: [MDInline]
    var lead: Int          // 行首空格数（用于列表嵌套缩进）
}

extension MDLine.Block {
    /// 同一族 = 视觉上属于同一个块（连续多行引用、整个列表、整个代码块……）。
    /// 排版时靠它判断「这一行是不是块的开始/结束」，好决定段前段后留白。
    var family: Int {
        switch self {
        case .paragraph:                return 0
        case .heading(let l):           return 100 + l
        case .quote:                    return 2
        case .bullet:                   return 3
        case .numbered:                 return 4
        case .task:                     return 5
        // 围栏单独一族：这样代码正文的第一行才算「块首」，
        // 圆角底的上面两个角、块前留白才会落在正确的位置
        case .codeFence:                return 61
        case .codeBody:                 return 6
        case .divider:                  return 7
        case .tableRow, .tableSeparator: return 8
        }
    }
}

// MARK: - 即时渲染引擎

enum LiveMarkdown {

    /// 标记被隐藏时的字号：小到几乎不占宽度，等于「真隐藏」；光标回到该行再显示出来。
    private static let hiddenSize: CGFloat = 0.1

    // MARK: 扫描（纯函数，便于自检）

    static func scan(_ text: NSString) -> [MDLine] {
        var out: [MDLine] = []
        var cursor = 0
        var inFence = false

        while cursor < text.length {
            let full = text.lineRange(for: NSRange(location: cursor, length: 0))
            guard full.length > 0 else { break }

            var line = full
            while line.length > 0 {
                let c = text.character(at: line.location + line.length - 1)
                if c == 10 || c == 13 { line.length -= 1 } else { break }
            }

            let raw = text.substring(with: line)
            let lead = raw.prefix(while: { $0 == " " || $0 == "\t" }).count
            let body = String(raw.dropFirst(lead))
            let start = line.location

            var block: MDLine.Block = .paragraph
            var marker = NSRange(location: start, length: lead)
            var content = line

            if inFence {
                if body.hasPrefix("```") {
                    inFence = false
                    block = .codeFence
                    marker = line
                    content = NSRange(location: start + line.length, length: 0)
                } else {
                    block = .codeBody
                    marker = NSRange(location: start, length: 0)
                }
            } else if body.hasPrefix("```") {
                inFence = true
                block = .codeFence
                marker = line
                content = NSRange(location: start + line.length, length: 0)
            } else if isDivider(body) {
                block = .divider
                marker = line
                content = NSRange(location: start + line.length, length: 0)
            } else if let (level, len) = headingMarker(body) {
                block = .heading(level)
                let total = min(lead + len, line.length)
                marker = NSRange(location: start, length: total)
                content = NSRange(location: start + total, length: max(0, line.length - total))
            } else if body.hasPrefix(">") {
                let second = body.count > 1 ? body[body.index(body.startIndex, offsetBy: 1)] : " "
                let total = min(lead + 1 + ((second == " " || second == "\t") ? 1 : 0), line.length)
                block = .quote
                marker = NSRange(location: start, length: total)
                content = NSRange(location: start + total, length: max(0, line.length - total))
            } else if let mlen = prefixMatch(body, "^[-*+]\\s+\\[[ xX]\\]\\s+") {
                let total = min(lead + mlen, line.length)
                let done = body.range(of: "\\[([xX])\\]", options: .regularExpression) != nil
                block = .task(done: done)
                marker = NSRange(location: start, length: total)
                content = NSRange(location: start + total, length: max(0, line.length - total))
            } else if let mlen = prefixMatch(body, "^(?:\\d+)[.)]\\s+") {
                let total = min(lead + mlen, line.length)
                block = .numbered
                marker = NSRange(location: start, length: total)
                content = NSRange(location: start + total, length: max(0, line.length - total))
            } else if let mlen = prefixMatch(body, "^[-*+]\\s+") {
                let total = min(lead + mlen, line.length)
                block = .bullet
                marker = NSRange(location: start, length: total)
                content = NSRange(location: start + total, length: max(0, line.length - total))
            } else if body.hasPrefix("|") {
                if isTableSeparator(body) {
                    block = .tableSeparator
                    marker = line
                    content = NSRange(location: start + line.length, length: 0)
                } else {
                    block = .tableRow
                    marker = NSRange(location: start, length: 0)
                }
            }

            var inlines: [MDInline] = []
            switch block {
            case .codeBody, .codeFence, .tableSeparator, .divider:
                break
            default:
                if content.length > 0 { inlines = scanInline(text, in: content) }
            }

            out.append(MDLine(block: block,
                              full: full,
                              line: line,
                              marker: marker,
                              content: content,
                              inlines: inlines,
                              lead: lead))

            cursor = full.location + full.length
        }
        return out
    }

    // MARK: 行内扫描

    private static let inlineRules: [(pattern: String, kind: MDInline.Kind)] = [
        ("(?<!\\\\)\\*\\*(?=\\S)(.+?\\S)\\*\\*", .bold),
        ("(?<!\\\\)__(?=\\S)(.+?\\S)__", .bold),
        ("(?<!\\\\)~~(?=\\S)(.+?\\S)~~", .strike),
        ("(?<!\\\\)`([^`\n]+)`", .code),
        ("(?<!\\\\)\\[([^\\]]*)\\]\\(([^)\\s]*)\\)", .link),
        ("(?<!\\\\)==(?=\\S)(.+?\\S)==", .highlight),
        ("(?<![*\\\\\\w])\\*(?=\\S)(.+?\\S)\\*(?![*\\w])", .italic),
        ("(?<![_\\\\\\w])_(?=\\S)(.+?\\S)_(?![_\\w])", .italic)
    ]

    static func scanInline(_ text: NSString, in range: NSRange) -> [MDInline] {
        guard range.length > 0 else { return [] }
        var out: [MDInline] = []
        var taken = [Bool](repeating: false, count: range.length)
        let source = text as String

        for rule in inlineRules {
            guard let re = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            re.enumerateMatches(in: source, options: [], range: range) { match, _, _ in
                guard let m = match else { return }
                let whole = m.range
                guard whole.length > 0,
                      whole.location >= range.location,
                      whole.location + whole.length <= range.location + range.length,
                      m.numberOfRanges > 1 else { return }

                let content = m.range(at: 1)
                guard content.location != NSNotFound, content.length > 0 else { return }

                let rel = whole.location - range.location
                guard rel >= 0, rel + whole.length <= taken.count else { return }
                guard !(rel..<(rel + whole.length)).contains(where: { taken[$0] }) else { return }
                for i in rel..<(rel + whole.length) { taken[i] = true }

                var markers: [NSRange] = []
                var url: String?
                let tailStart = content.location + content.length
                let tailLen = whole.location + whole.length - tailStart
                if rule.kind == .link, m.numberOfRanges > 2 {
                    let g2 = m.range(at: 2)
                    if g2.location != NSNotFound { url = text.substring(with: g2) }
                }
                if content.location > whole.location {
                    markers.append(NSRange(location: whole.location, length: content.location - whole.location))
                }
                if tailLen > 0 {
                    markers.append(NSRange(location: tailStart, length: tailLen))
                }
                out.append(MDInline(kind: rule.kind, content: content, markers: markers, url: url))
            }
        }
        return out
    }

    // MARK: 应用属性

    /// - Parameter style: 设置页里选的写作区样式。不传时用默认规格
    ///   （就是按 GitHub / Tailwind / Solarized 换算出来的那一套），
    ///   所以自检里可以直接 `render(storage, baseSize: 16, caretLine: nil)` 拿到稳定结果。
    static func render(_ storage: NSTextStorage,
                       baseSize: CGFloat,
                       caretLine: NSRange?,
                       style: MDStyle = .default) {
        let theme = MDLiveTheme.current(baseSize: baseSize, style: style)
        let text = storage.string as NSString
        let lines = scan(text)

        storage.beginEditing()
        storage.setAttributes(theme.baseAttributes(), range: NSRange(location: 0, length: text.length))

        // 表格的隔行底色要在「同一个表格内部」计数，跨表格要归零
        var tableRun = 0
        // 多行块（引用、代码）共用一个组号，绘制层靠它把几行合成一个矩形再整块画
        var groupCounter = 0
        var groupFamily = -1

        for (i, line) in lines.enumerated() {
            let prev = i > 0 ? lines[i - 1] : nil
            let next = i + 1 < lines.count ? lines[i + 1] : nil
            let first = prev == nil || prev!.block.family != line.block.family
            let last = next == nil || next!.block.family != line.block.family

            if line.block.family != groupFamily {
                groupFamily = line.block.family
                groupCounter += 1
            }

            let isTable = line.block.family == 8
            if isTable { tableRun = first ? 0 : tableRun + 1 } else { tableRun = 0 }

            // Markdown 表格的表头 = 紧接着分隔行的那一行
            let isTableHeader = isTable && next?.block == .tableSeparator

            // 按「行首位置」判定光标在哪一行：换成位置区间判断会在换行符处串行
            let active = caretLine.map { $0.location == line.line.location } ?? false
            apply(line, to: storage, theme: theme, active: active, text: text,
                  first: first, last: last, isTableHeader: isTableHeader,
                  tableRun: tableRun, group: groupCounter)
        }
        storage.endEditing()
    }

    private static func apply(_ l: MDLine,
                              to storage: NSTextStorage,
                              theme: MDLiveTheme,
                              active: Bool,
                              text: NSString,
                              first: Bool,
                              last: Bool,
                              isTableHeader: Bool,
                              tableRun: Int,
                              group: Int) {
        let t = theme.type
        let ink = theme.ink
        let base = t.base

        /// 嵌套缩进：行首每多两个空格，多让出一点位置
        func nesting(_ baseIndent: CGFloat) -> CGFloat {
            baseIndent + CGFloat(l.lead / 2) * base * 0.55
        }

        /// 隐藏标记；光标所在行则改为浅色显示，方便回头修改
        func conceal(_ r: NSRange) {
            guard r.length > 0 else { return }
            if active {
                storage.addAttribute(.foregroundColor, value: ink.faint, range: r)
            } else {
                storage.addAttributes([.font: NSFont.systemFont(ofSize: hiddenSize),
                                       .foregroundColor: NSColor.clear], range: r)
            }
        }

        /// 把标记染成装饰色（列表序号等）
        func decorate(_ r: NSRange, _ color: NSColor, weight: NSFont.Weight = .semibold, scale: CGFloat = 1) {
            guard r.length > 0 else { return }
            let current = storage.attribute(.font, at: r.location, effectiveRange: nil) as? NSFont
            let size = (current?.pointSize ?? base) * scale
            storage.addAttributes([.foregroundColor: color,
                                   .font: NSFont.systemFont(ofSize: max(size, base * 0.6), weight: weight)],
                                  range: r)
        }

        /// 交给 RJTextView 在 drawRect 里画——整段底边线、左侧竖条、圆角块这些
        /// 效果字符属性表达不了，只能自绘。
        func deco(_ kind: MDDeco.Kind, _ r: NSRange, group g: Int = 0) {
            guard r.length > 0 else { return }
            storage.addAttribute(.mdDeco, value: MDDeco(kind, base: base, group: g), range: r)
        }

        func setParagraph(_ style: NSParagraphStyle, _ r: NSRange) {
            storage.addAttribute(.paragraphStyle, value: style, range: r)
        }

        switch l.block {
        case .paragraph:
            // 段落是最常见的一类，行内的 **粗体**、`代码`、链接全靠这一步
            setParagraph(theme.paragraph(line: t.bodyLine, size: base,
                                         after: t.paraAfter * base), l.full)
            inlineApply(l, to: storage, theme: theme, active: active, size: base, weight: .regular)

        case .heading(let level):
            let size = t.headingSize(level)
            let weight = t.headingWeight(level)
            storage.addAttributes([.font: NSFont.systemFont(ofSize: size, weight: weight),
                                   .foregroundColor: ink.heading],
                                  range: l.line)
            setParagraph(theme.paragraph(line: t.headingLine(level), size: size,
                                         // 上留白大于下留白，标题才「贴着」它带的那段内容
                                         before: first ? t.headingBefore(level) * base : 0,
                                         after: t.headingAfter(level) * base),
                         l.full)
            // GitHub 的招牌做法：一二三级标题压一条底边线，章节感立刻出来
            // （设置里可以关掉，有人嫌标题下面那条线太抢）
            if level <= 2 && t.style.headingRule { deco(.headingRule(level), l.full) }
            conceal(l.marker)
            inlineApply(l, to: storage, theme: theme, active: active, size: size, weight: weight)

        case .quote:
            setParagraph(theme.paragraph(line: t.bodyLine, size: base,
                                         before: first ? t.quoteBlockBefore * base : 0,
                                         after: (last ? t.quoteBlockAfter : t.quoteLineAfter) * base,
                                         indent: t.quoteIndent),
                         l.full)
            storage.addAttribute(.foregroundColor, value: ink.secondary, range: l.line)
            deco(.quote, l.full, group: group)
            conceal(l.marker)
            inlineApply(l, to: storage, theme: theme, active: active, size: base, weight: .regular)

        case .bullet:
            setParagraph(theme.paragraph(line: t.tightLine, size: base,
                                         before: first ? t.listBlockBefore * base : 0,
                                         after: (last ? t.listBlockAfter : t.listItemAfter) * base,
                                         indent: nesting(t.listIndent)),
                         l.full)
            // 圆点交给绘制层画，比打一个「-」出来精致得多
            deco(.bullet(depth: l.lead / 2), l.full)
            conceal(l.marker)
            inlineApply(l, to: storage, theme: theme, active: active, size: base, weight: .regular)

        case .numbered:
            setParagraph(theme.paragraph(line: t.tightLine, size: base,
                                         before: first ? t.listBlockBefore * base : 0,
                                         after: (last ? t.listBlockAfter : t.listItemAfter) * base,
                                         indent: nesting(t.listIndent)),
                         l.full)
            decorate(l.marker, ink.secondary, weight: .medium, scale: 0.96)
            inlineApply(l, to: storage, theme: theme, active: active, size: base, weight: .regular)

        case .task(let done):
            setParagraph(theme.paragraph(line: t.tightLine, size: base,
                                         before: first ? t.listBlockBefore * base : 0,
                                         after: (last ? t.listBlockAfter : t.listItemAfter) * base,
                                         indent: nesting(t.listIndent)),
                         l.full)
            deco(.checkbox(done: done), l.full)
            conceal(l.marker)
            if done, l.content.length > 0 {
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                       .strikethroughColor: ink.secondary,
                                       .foregroundColor: ink.secondary],
                                      range: l.content)
            }
            inlineApply(l, to: storage, theme: theme, active: active, size: base, weight: .regular)

        case .codeFence:
            // 围栏行收成一条缝：代码块看起来是一个整体，不留 ``` 的空位
            conceal(l.line)
            setParagraph(theme.paragraph(line: 0.12, size: base), l.full)

        case .codeBody:
            let mono = NSFont.monospacedSystemFont(ofSize: t.codeSize, weight: .regular)
            storage.addAttributes([.font: mono,
                                   .foregroundColor: ink.body],
                                  range: l.line)
            // 底色和圆角由绘制层画，这里只把文字让出内边距
            setParagraph(theme.paragraph(line: t.codeLine, size: t.codeSize,
                                         before: first ? t.codeBlockBefore * base : 0,
                                         after: last ? t.codeBlockAfter * base : 0,
                                         indent: t.codePadH),
                         l.full)
            deco(.code, l.full, group: group)

        case .divider:
            // 隐藏 --- 本身，留出一条矮行给绘制层画居中的横线
            conceal(l.line)
            setParagraph(theme.paragraph(line: 0.30, size: base,
                                         before: t.dividerBefore * base,
                                         after: t.dividerAfter * base,
                                         align: .center),
                         l.full)
            deco(.divider, l.full)

        case .tableRow:
            setParagraph(theme.paragraph(line: t.tightLine, size: t.tableSize), l.full)
            // 表格里的 | 收成浅灰，当网格线用
            var i = l.line.location
            let end = l.line.location + l.line.length
            while i < end {
                if text.character(at: i) == 124 {   // "|"
                    storage.addAttribute(.foregroundColor, value: ink.faint,
                                         range: NSRange(location: i, length: 1))
                }
                i += 1
            }
            if isTableHeader {
                deco(.tableHeader, l.full)
            } else {
                // 斑马纹可以在设置里关掉
                deco(.tableRow(alt: t.style.tableStripe && tableRun % 2 == 1, last: last), l.full)
            }
            inlineApply(l, to: storage, theme: theme, active: active,
                        size: t.tableSize, weight: isTableHeader ? .semibold : .regular)

        case .tableSeparator:
            conceal(l.line)
            setParagraph(theme.paragraph(line: 0.12, size: base), l.full)
        }
    }

    private static func inlineApply(_ l: MDLine,
                                    to storage: NSTextStorage,
                                    theme: MDLiveTheme,
                                    active: Bool,
                                    size: CGFloat,
                                    weight: NSFont.Weight) {
        guard !l.inlines.isEmpty else { return }
        let ink = theme.ink
        for tok in l.inlines {
            switch tok.kind {
            case .bold:
                let heavier: NSFont.Weight = (weight == .semibold || weight == .bold) ? .heavy : .bold
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: size, weight: heavier),
                                     range: tok.content)
            case .italic:
                storage.addAttribute(.obliqueness, value: 0.14, range: tok.content)
            case .strike:
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                       .strikethroughColor: ink.secondary,
                                       .foregroundColor: ink.secondary],
                                      range: tok.content)
            case .code:
                storage.addAttributes([.font: NSFont.monospacedSystemFont(ofSize: size * 0.90, weight: .regular),
                                       .backgroundColor: ink.inlineCodeBG,
                                       .foregroundColor: ink.inlineCodeText],
                                      range: tok.content)
            case .link:
                // GitHub / Tailwind 都是「悬停才出下划线」，这里保留一条很淡的下划线，
                // 好跟行内代码区分开（两者都是强调色）
                storage.addAttributes([.foregroundColor: ink.accent,
                                       .underlineStyle: NSUnderlineStyle.single.rawValue,
                                       .underlineColor: ink.accent.withAlphaComponent(0.35)],
                                      range: tok.content)
            case .highlight:
                storage.addAttribute(.backgroundColor, value: ink.highlightBG, range: tok.content)
            }
            for m in tok.markers where m.length > 0 {
                if active {
                    storage.addAttribute(.foregroundColor, value: ink.faint, range: m)
                } else {
                    storage.addAttributes([.font: NSFont.systemFont(ofSize: hiddenSize),
                                           .foregroundColor: NSColor.clear], range: m)
                }
            }
        }
    }

    // MARK: 小工具

    private static func headingMarker(_ body: String) -> (Int, Int)? {
        var n = 0
        for ch in body {
            if ch == "#" { n += 1 } else { break }
        }
        guard (1...6).contains(n), body.count > n else { return nil }
        let after = body[body.index(body.startIndex, offsetBy: n)]
        guard after == " " || after == "\t" else { return nil }
        var len = n
        for ch in body.dropFirst(n) {
            if ch == " " || ch == "\t" { len += 1 } else { break }
        }
        return (n, len)
    }

    private static func isDivider(_ body: String) -> Bool {
        let t = body.trimmed
        guard t.count >= 3, let first = t.first, "-*_".contains(first) else { return false }
        return t.allSatisfy { $0 == first }
    }

    private static func isTableSeparator(_ body: String) -> Bool {
        let t = body.trimmed
        guard t.contains("-") else { return false }
        return t.allSatisfy { $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " }
    }

    private static func prefixMatch(_ s: String, _ pattern: String) -> Int? {
        guard let r = s.range(of: pattern, options: .regularExpression),
              r.lowerBound == s.startIndex else { return nil }
        return s.distance(from: s.startIndex, to: r.upperBound)
    }
}
